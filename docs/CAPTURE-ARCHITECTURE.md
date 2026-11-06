# Capture Architecture

How the app listens to inbound and outbound traffic on the PC.

## Layers

```
+---------------------------- Windows ----------------------------+
| ETW providers                                                   |
|   Microsoft-Windows-Kernel-Network -> TCP/UDP + PID + bytes     |
|   Microsoft-Windows-DNS-Client     -> DNS name + PID            |
+-------------------------------+---------------------------------+
                                | realtime ETW (admin)
                    +-----------v------------+
                    | netscope-capture.exe      |  C++ helper (MSVC)
                    | ETW consumer            |
                    +-----------+-------------+
                                | NDJSON over loopback TCP
                    +-----------v-------------+
                    | EtwCaptureService        |  spawn + parse
                    | -> detection engine      |
                    | -> SQLite + Yaru UI      |
                    +--------------------------+
```

## Primary: ETW (Phase 2)

Realtime ETW session subscribing to kernel/network providers. No driver install.
Requires elevation; the helper self-elevates through UAC.

| Provider | GUID (verify on Win11) | Purpose |
|---|---|---|
| `Microsoft-Windows-Kernel-Network` | `{7DD42A49-5329-4832-8DFD-43D979153A88}` | TCP/UDP connect, close, send, recv with PID and byte counts |
| `Microsoft-Windows-DNS-Client` | `{1C95126E-7EEA-49A9-A3FE-A378B03DDB4D}` | DNS query/response names, status, PID |
| `Microsoft-Windows-TCPIP` (optional) | `{2F07E2EE-15DB-40F1-90EF-9D7BA282188A}` | Connection lifecycle detail |

Processing:

1. Kernel-Network: connect/accept 12/15 (IPv4) and 28/31 (IPv6), UDP
   send/recv 42/43 (IPv4) and 58/59 (IPv6). Reconnects 16/32 are treated as
   connects. Data and disconnect events are ignored for now.
2. Resolve PID -> process name/path (`QueryFullProcessImageNameW`, cached).
3. DNS-Client 3008: cache `answer IP -> query` and attach it to later flows.
4. Emit a normalized `flow` on connect/accept. UDP is throttled to one record
   per 5-tuple per 10 s so datagrams do not flood the UI.
5. Write one NDJSON line per event to the loopback socket. The Dart side
   batches UI/DB writes every 100 ms.

Field orientation (verified on Windows 11 22631):

- `daddr`/`saddr` are already network-order bytes; `inet_ntop` is correct.
- `dport`/`sport` are **network byte order**; the helper applies `ntohs`.
- Connect and accept both use source=local, destination=remote. UDP receive
  uses source=remote, destination=local.
- A loopback listener on `127.0.0.1:54321` produced local port 54321 on the
  accept event and the ephemeral client port on the connect event.

## Fallback: polling (Phase 1)

No admin, no driver. Snapshots every 2 s:

- `netstat -ano` — TCP + UDP local/remote addr+port, state, owning PID
- `Get-CimInstance Win32_Process` — PID -> process name + executable path
- `Get-DnsClientCache` — domain -> IP mapping (cache primed at start so old
  entries are not replayed as new DNS events)
- Deduplication by 5-tuple + PID + state; flows are written to SQLite and
  survive restart

Limitation: short-lived connections between snapshots are missed. Use this
only when ETW is unavailable or not elevated.

## Deep mode: Npcap (Phase 4, optional)

`winget install Npcap.Npcap` (admin + driver). Packet-level capture enables:

- DNS names and TLS SNI (domain even for HTTPS)
- JA3/JA4 TLS fingerprints
- HTTP method/host/path for unencrypted HTTP
- loopback via the Npcap loopback adapter

Packaged as an optional toggle; the app degrades gracefully without it.

## Helper contract

The app binds `127.0.0.1:0`, passes `--port <port> --token <token>` to the
helper, and the helper connects back over loopback TCP. The first line is a
hello, then NDJSON. No CORS, no listening port in the app.

```json
{"kind":"hello","token":"<random hex>"}
{"kind":"flow","id":"...","ts":"2026-11-06T12:00:00.000Z","direction":"outbound","pid":1234,"process":"chrome.exe","processPath":"C:\\...\\chrome.exe","protocol":"tcp","state":"attempted","localIp":"192.168.1.10","localPort":51544,"remoteIp":"93.184.216.34","remotePort":443,"domain":"example.com","bytesSent":0,"bytesReceived":0}
{"kind":"dns","id":"...","ts":"...","pid":1234,"process":"chrome.exe","query":"example.com","status":"Success","answers":["93.184.216.34"],"remoteIp":"93.184.216.34"}
```

Rules:

- One JSON object per line, UTF-8, no pretty printing.
- `kind` in `{hello, flow, dns}`.
- Unknown fields are ignored by the parser for forward compatibility.
- `flow-close` and byte aggregation are not implemented yet; UDP records carry
  the datagram size, TCP records carry 0 bytes.

The helper also supports manual diagnostics:

```
netscope-capture.exe --check          # {"elevated":false,"session":"NetScope-Etw"}
netscope-capture.exe --stdout         # run elevated, print NDJSON to console
netscope-capture.exe --no-elevate     # skip UAC (returns 2 when not elevated)
```

The helper is linked as a GUI-subsystem executable so launching it from the
Flutter app never flashes a console window. When started from a terminal it
attaches to that console for `--check`/`--stdout` output; redirected
stdout/stderr are preserved.

## Elevation

- App runs unelevated.
- The helper has no `requireAdministrator` manifest (that would make
  `CreateProcess` fail with error 740 from an unelevated app).
- Instead the helper checks its token: if not elevated it relaunches itself via
  `ShellExecuteExW("runas")` with the same `--port/--token`, then exits. The
  elevated instance connects back to the app.
- If the UAC prompt is declined, the launcher exits with code 2 and the app
  falls back to polling immediately.
- The helper stops the ETW session when the app closes the socket.

## Native project layout

```
native/netscope_capture/
  CMakeLists.txt
  main.cpp            CLI, self-elevation, ETW consumer, DNS/flow parsing,
                      process cache, NDJSON writer
```

Built by Flutter's Windows CMake build with MSVC 2022 and copied next to the
app executable (`netscope-capture.exe`). The Inno Setup installer ships it too.

## Data flow summary

```
ETW/poll -> helper -> NDJSON over TCP -> EtwCaptureService -> NetworkEvent
        -> detection engine -> SQLite (events, alerts) -> Yaru UI
```

