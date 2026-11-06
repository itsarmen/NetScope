# Project Plan: NetScope — Network Monitor & Malicious Request Detector

Status: Phase 0 + 1 complete; Phase 2 integrated and runtime-verified (Phase 3 next)
Last updated: 2026-11-06

## Vision

Turn the existing browser-only "NetScope" into a
device-wide network monitor: capture all inbound and outbound network flows on
the PC, attribute them to processes, detect suspicious/malicious behaviour, and
present everything in the same clean Yaru/Flutter desktop UI.

The Firefox extension is removed. Capture is done by a native Windows helper.

## Locked decisions

| Decision | Choice |
|---|---|
| Capture backend (v1) | ETW: `Microsoft-Windows-Kernel-Network` + `Microsoft-Windows-DNS-Client` |
| Fallback | Polling `Get-NetTCPConnection` / `Get-NetUDPEndpoint` + `Get-DnsClientCache` |
| Deep capture | Npcap (packet-level DNS/SNI/JA3/HTTP), Phase 4, optional |
| Elevation | Normal app; `netscope-capture.exe` self-elevates via `ShellExecuteEx("runas")` on demand |
| UI library | Keep Yaru (Flutter) and the existing white/outlined master-detail look |
| Browser extension | Removed entirely |
| Product name | Display: "NetScope — Network Monitor & Malicious Request Detector" |

## What "listen to all requests" means

Full URLs and bodies for every app on Windows require TLS interception (MITM
proxy + root CA) or a kernel driver. That is out of scope for v1.

v1 captures every network **flow** with process attribution:

- 5-tuple: local/remote IP + port, protocol, direction, state
- owning PID -> process name and executable path
- DNS query name (domain visible even when traffic is encrypted)
- byte counts, duration, connection lifecycle
- optional later: TLS SNI, JA3/JA4, HTTP method/host/path via Npcap

HTTPS payload contents stay encrypted and invisible without MITM. This is a
documented limitation, not a bug.

## Non-goals (v1)

- Decrypting arbitrary TLS traffic
- Blocking/terminating connections (monitor only)
- Reading HTTP bodies of non-browser apps
- Replay / "Edit & Run" of captured requests (removed with the extension)

## Roadmap

| Phase | Work | Acceptance |
|---|---|---|
| 0 | ✅ Rebrand, remove extension, strip browser UI/replay/CORS | App builds and opens as an empty monitor under the new name |
| 1 | ✅ `NetworkEvent` model, new SQLite schema, `CaptureService`, polling helper | Live flows with PID/process appear and survive restart |
| 2 | ✅ C++ ETW helper (Kernel-Network + DNS-Client), PID->exe, self-elevation, TCP NDJSON, Dart client + fallback; runtime-verified DNS/HTTP/HTTPS/loopback with correct port order | DNS name + remote IP + process appear within ~1s, inbound included |
| 3 | Detection engine, blocklists, scoring, Alerts view, allowlist | Seeded malicious domains and beacon patterns flagged with reasons |
| 4 | Npcap deep mode (SNI/JA3/HTTP), behind a toggle | Deep metadata visible in details for opted-in users |
| 5 | Installer, elevation UX, blocklist updater, docs | Ship-ready release |

## Phase 0 change map (concrete)

- `flutter-desktop-app/lib/main.dart` — app title, package wiring
- `flutter-desktop-app/pubspec.yaml` — name/description/version
- `flutter-desktop-app/windows/` — window title, BINARY_NAME, runner resources
- `installer/netscope.iss` — product name, exe name, paths, helper, icon
- `README.md`, `branding.md`, `AGREEMENT.md`, `LICENSE` — rename and scope
- Delete `extension/`, `extension/dist`, `extension/build.py`
- `flutter-desktop-app/lib/models.dart` — remove browser `LogRecord`/`RequestBody`
- `flutter-desktop-app/lib/log_server.dart` — drop CORS/browser ingest
- `flutter-desktop-app/lib/app_state.dart` — remove sites/skip/replay logic
- `flutter-desktop-app/lib/ui/` — adapt table/sidebar/details, remove replay editor
- Author headers: "NetScope" -> new product name

## Risks

- HTTPS content is invisible without MITM; detection is metadata-based.
- ETW kernel providers need elevation (UAC prompt when recording starts).
- Polling fallback misses short-lived connections.
- ETW provider event layouts must be validated on Windows 11 (22631).
- Blocklist sourcing/licensing and update cadence.
- False positives; mitigated by an allowlist and reason transparency.

## Environment (verified)

- Windows 11 Pro, build 22631; current shell is NOT admin
- Flutter SDK present (`C:\flutter`)
- MSVC Build Tools 2022 with C++ tools present (native helper buildable)
- Python 3.11; `winget`; built-in `pktmon`
- No Npcap / Wireshark installed; no .NET SDK
