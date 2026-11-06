# Detection Engine

Metadata-based malicious request detection. No TLS decryption required.

## Data model

Replace the browser `LogRecord` (`lib/models.dart`) with:

```text
NetworkEvent {
  id, timestamp, direction (outbound|inbound|loopback),
  pid, processName, processPath,
  protocol (tcp|udp|dns|icmp), state,
  localIp, localPort, remoteIp, remotePort,
  domain, tlsSni, httpMethod, httpHost, httpPath,
  bytesSent, bytesReceived, durationMs,
  riskScore (0-100), severity, reasons[]
}
```

SQLite tables (`lib/log_database.dart`):

| Table | Purpose |
|---|---|
| `events` | Normalized flows, indexed on remote_ip, domain, process_name, timestamp |
| `alerts` | Events above the risk threshold + reasons |
| `allowlist` | User-confirmed safe domains/IPs/processes |
| `blocklist` | Known-bad domains/IPs (bundled snapshot + updates) |
| `process_cache` | PID -> name/path resolution cache |

## Signals / heuristics

| Signal | Weight | Notes |
|---|---|---|
| Destination matches blocklist | critical | domain or IP |
| Raw-IP destination, no DNS name | medium | common in malware C2 |
| First-seen domain within session | low | novelty |
| DGA-like domain | high | entropy, length, consonant runs |
| DNS tunneling pattern | high | many long unique subdomains, TXT, high rate |
| Beaconing | high | regular intervals, small repeated payloads |
| Non-standard port | low/medium | e.g. 443-like traffic on 8443/4444 |
| Unsigned or temp-dir process | medium | outbound from `%TEMP%`, no signature |
| High fan-out | medium | one process to many distinct remotes |
| Inbound from blocklisted source | high | inbound direction only |

Each signal contributes points and a human-readable reason string.

## Scoring

- Weighted sum -> `riskScore` 0-100.
- Severity bands: `info` (<20), `low` (20-39), `medium` (40-59),
  `high` (60-79), `critical` (80+).
- Allowlisted domain/IP/process forces score to 0.
- Blocklist hit forces `critical`.

## Blocklists

- Bundled snapshot at build time (abuse.ch / StevenBlack-style feeds).
- Optional updater in Phase 5 with a signed/validated manifest.
- Store parsed sets in `blocklist` with a `source` and `updated_at` column.

## UI

- **Alerts** view: severity-sorted list, each row shows process, remote, and
  the top reasons.
- Details panel: full reason list, DNS, process path, remote IP, timeline.
- Actions: "Allowlist this domain/IP/process" (writes to `allowlist`).
- Filters: severity, direction, process, domain.

## Testing

- Pure-Dart unit tests for each heuristic (no capture needed).
- Fixtures: DGA names, known-bad domains, beacon interval samples, tunneling
  query bursts, benign traffic.
- Integration: run capture, generate traffic with `curl`/browser, assert
  events and expected scores.
