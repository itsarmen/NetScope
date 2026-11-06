# Status / Memory Checkpoint

Read this first when resuming work.

Last updated: 2026-11-06

## Current state

- Repository: `E:\Software-Projects\ComputerNetworkLogMonitor` (git re-initialized).
- **Phase 0 complete** - project fully renamed; Firefox extension deleted.
- **Phase 1 complete** - polling capture, `NetworkEvent` model, new SQLite
  schema, new Yaru UI, detection engine, allowlist, JSON export.
- **Phase 2 integrated** - native `netscope-capture.exe` ETW helper built with
  MSVC, bundled next to the app by CMake, shipped by the installer, and wired
  to a Dart client with automatic polling fallback.
- **Hosts editor complete** - GUI list with per-entry enable/disable, add and
  remove, search, reload/discard and apply; right-click a captured event to
  block (`0.0.0.0`), redirect (`127.0.0.1`), open the editor or remove it.
  Writes go through `netscope-capture.exe --apply-hosts`, with backup and DNS
  cache flush.
- Verified after rename: `flutter analyze` clean, `flutter test` 23/23 passing,
  `flutter build windows --debug` produces `netscope.exe` **and**
  `netscope-capture.exe` in `build\windows\x64\runner\Debug\`.
- Verified helper CLI: `--check` reports `elevated:false`, `--help` works,
  `--no-elevate` exits 2 with the admin message.
- **Elevated hosts apply verified:** approved UAC for
  `--apply-hosts`; the marker `0.0.0.0 netscope-hosts-test.invalid` was applied,
  status returned `ok:true`, backup was created, then the original file was
  restored. Live hosts file is back to 1050 bytes with no test marker.
- Automated hosts UI tests cover load/search, add validation, add/remove,
  apply success/failure, and declined-elevation messaging; helper exit code 2
  is tested through an injected process starter.
- Verified the helper is GUI-subsystem (`dumpbin /headers`: `subsystem
  (Windows GUI)`) so it does not flash a console when spawned by the app; it
  attaches to a terminal for diagnostics and preserves redirected output.
- Verified Dart ETW client end-to-end with a fake helper: hello/token
  handshake, flow + DNS parsing, 100 ms batching.
- Verified fallback: `CaptureCoordinator` selects polling when the helper is
  absent and captured ~128 events in 6 s.
- **Runtime ETW verified** on Windows 11 22631 (elevated `--stdout` capture):
  DNS 3008 events for `example.com`, TCP 80 flows, Chrome UDP/443, and a
  loopback listener/accept test all appeared with correct process attribution.
- **Full app path verified:** launched `netscope.exe`, approved UAC for the
  helper, generated `http://example.com` traffic, then queried
  `%LOCALAPPDATA%\NetScope\network.db`. Rows use ETW ids
  (`tcp|...`, `udp|...`, `dns-...`), with correct port 80/443, process names,
  and `example.com` attached to the TCP flow.
- Fixed during runtime verification:
  - ETW `dport`/`sport` are network byte order; they are now converted with
    `ntohs` (80 no longer shows as 20480, 443 as 47873).
  - TCP accept events use source=local server / destination=remote client;
    accept mapping now keeps the server port local and the client port remote.
- Remaining ETW polish: duplicate DNS completion events, occasional empty
  process name on very short-lived acceptors, and no TCP byte aggregation.

## Locked decisions

- Display name: "NetScope — Network Monitor & Malicious Request Detector".
- Short name / exe / package: `NetScope` / `netscope`.
- Remove the Firefox extension entirely (done).
- Keep Flutter + Yaru and the white/outlined master-detail UI (done).
- Capture v1 target: ETW (`Kernel-Network` + `DNS-Client`); polling is the
  working fallback.
- Npcap deep mode deferred to Phase 4.
- App stays unelevated; `netscope-capture.exe` self-elevates through UAC and
  streams NDJSON over loopback TCP.
- Polling runs silently/automatically on launch; sidebar has Stop monitoring.

## Environment (verified)

- Windows 11 Pro 22631; current shell NOT admin.
- Flutter SDK at `C:\flutter`.
- MSVC Build Tools 2022 with C++ tools (CMake + Ninja present under
  `C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools`).
- Python 3.11; `winget`; built-in `pktmon`.
- No Npcap/Wireshark; no .NET SDK.

## Implementation notes

- `native/netscope_capture/main.cpp`:
  - ETW session `NetScope-Etw`; providers `Kernel-Network`
    `{7DD42A49-...}` and `DNS-Client` `{1C95126E-...}`.
  - Kernel events: TCP connect/accept 12/15 (v4), 28/31 (v6); reconnect
    16/32 treated as connect; UDP send/recv 42/43 (v4), 58/59 (v6).
  - DNS event 3008 only; caches `answer IP -> query` and attaches the domain
    to later flows.
  - TDH property lookup by name, so payload layout changes do not need offsets.
  - Ports are decoded with `ntohs` (Kernel-Network uses network byte order).
  - TCP connect/accept both use source=local/destination=remote; UDP receive
    uses source=remote/destination=local.
  - Process attribution via `QueryFullProcessImageNameW`, cached; PID 4/0
    shown as `System`/`System Idle`.
  - Self-elevates with `ShellExecuteExW("runas")`; TCP hello carries a random
    token; the helper stops the session when the app closes the socket.
  - Diagnostics: `--check`, `--help`, `--stdout`, `--no-elevate`.
  - Hosts mode: `--apply-hosts <file> --status <json>` self-elevates, backs up
    the current file to `hosts.netscope.bak`, atomically replaces it and calls
    `DnsFlushResolverCache` dynamically from `dnsapi.dll`.
- `flutter-desktop-app/lib/capture/etw_service.dart`:
  - Binds loopback port 0, launches the helper, verifies the hello token,
    parses NDJSON, batches events every 100 ms.
  - Fails fast when the launcher exits non-zero (UAC declined).
- `flutter-desktop-app/lib/capture/capture_coordinator.dart`:
  - ETW first; polling fallback; re-falls back if ETW disconnects.
  - `NETSCOPE_DISABLE_ETW=1` forces polling for debugging.
- `flutter-desktop-app/lib/app_state.dart` exposes `captureMode` and shows an
  ETW/POLL/OFF badge beside the status text.
- `flutter-desktop-app/windows/CMakeLists.txt` + `runner/CMakeLists.txt`:
  build `netscope_capture`, depend on it, copy it next to the runner, install it.
- `installer/netscope.iss` includes `netscope-capture.exe` and the new icon.
- `flutter-desktop-app/lib/hosts/hosts_file.dart` preserves comments, blank
  lines and line endings; `hosts_service.dart` stages the file under
  `%LOCALAPPDATA%\NetScope` and waits up to 120 s for the elevated helper.
- `flutter-desktop-app/lib/ui/hosts_dialog.dart` is the GUI editor; the table
  context menu is wired through `network_table.dart` and `home_page.dart`.
- `lib/capture/capture_service.dart` remains the polling source:
  `netstat -ano`, `Get-CimInstance Win32_Process`, `Get-DnsClientCache`
  (`Entry`, not `RecordName`; private/loopback answers skipped; cache primed).

## Next action

1. Smoke-test the hosts editor on an interactive desktop, including denying the
   real UAC prompt, then confirm block/redirect/remove from the table menu.
   Automated tests cover the dialog and exit-code paths; the elevated apply
   path is already verified.
2. Proceed to **Phase 3**: alert list, allowlist UX, blocklist update/format,
   and beacon/DGA tuning.
3. Optional Phase 2 polish: dedupe repeated DNS completions, suppress repeated
   TCP connect attempts for the same 5-tuple, accumulate TCP byte counts, emit
   `flow-close`.
4. Later: ETW session cleanup on hard kill; sign the helper.

## Known limitations

- Duplicate DNS completion events (same query/answers) appear in ETW; failed
  DNS completions are stored with an empty remote IP.
- Very short-lived accepting processes can occasionally show an empty name.
- Polling misses short-lived connections.
- HTTPS payloads are invisible without MITM; detection is metadata-based.
- Hosts changes require UAC approval; declining elevates nothing and the app
  reports "Administrator approval was declined".
- Apps using DNS-over-HTTPS or their own resolver may ignore hosts entries.
- The hosts editor lists entry lines; ordinary comments are preserved verbatim
  but are not shown as editable rows.
- Chrome/DoH traffic often has no Windows DNS cache entry, so some public IPs
  show no domain name.
- TCP byte totals are not aggregated yet; UDP records carry datagram size only.
- Flow dedup keys in polling do not expire yet; a reused 5-tuple may be
  suppressed until the 50k safety clear.
- The helper lives in `%LOCALAPPDATA%\NetScope` and self-elevates; for a
  production release, sign it and consider a protected install location.

## Related docs

- `docs/PROJECT-PLAN.md` - scope, decisions, roadmap
- `docs/CAPTURE-ARCHITECTURE.md` - how capture works, helper contract
- `docs/DETECTION-ENGINE.md` - model, heuristics, scoring, blocklists
