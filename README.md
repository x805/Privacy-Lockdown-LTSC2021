# Windows 10 IoT LTSC 2021 – Privacy Baseline

![Version](https://img.shields.io/badge/Version-1.6.1-success.svg)
![License](https://img.shields.io/badge/License-MIT-blue.svg)
![Platform](https://img.shields.io/badge/Platform-Windows%2010%20IoT%20Enterprise%20LTSC%202021-lightgrey.svg)

A single, self-contained batch script that hardens telemetry and data
collection on **Windows 10 IoT Enterprise LTSC 2021** (also applicable to
LTSC 2019/2024 and standard Enterprise/Education editions, with reduced
effect on Pro/Home — see [Compatibility](#compatibility) below).

It's built around three priorities, in this order: **safety first**, **real
privacy gains second**, **never break core functionality third**. Every
change is backed up before it's made, logged as it happens, and reversible
with a single generated script.

## Why this exists

Most "debloat" scripts found online are one-shot, no-rollback, no-backup,
and frequently disable things that have nothing to do with privacy (Windows
Update, BITS, DNS-over-HTTPS) under a "telemetry" label. This script takes
the opposite approach: nothing goes in unless it's a verified, correctly-named
registry policy or task, and nothing that breaks patching, update delivery,
or your active antivirus goes in at all — regardless of how it's framed.

## What it does

- **System Restore point** before any change is made (best-effort; some
  IoT/OEM images strip Volume Shadow Copy entirely — handled as a non-fatal
  warning, not a failure).
- **Per-key registry backups** (`.reg` files) taken before the *first*
  change to each key, and a **`rollback_privacy.bat`** auto-generated
  alongside them that correctly restores original values, deletes anything
  newly created, and restores each modified service's actual original start
  type (including delayed-auto) — not a guess.
- **Rollback script integrity check** — at the end of every run, confirms
  `rollback_privacy.bat` exists, isn't empty, and wasn't truncated
  mid-write, and reports how many revert actions it contains. Catches a
  corrupted rollback file immediately instead of discovering it's broken
  later when you actually need it.
- **Full logging, with a timestamp on every individual action** — not just
  once at the top of the log file. Every registry write, service change,
  and task change gets its own `[date time]` entry, both on-screen (as
  `[OK]` / `[FAIL]` / `[SKIP]`) and in the log, plus a write-back
  verification after every registry change.
- **Startup checks** — Windows edition (warns if `AllowTelemetry=0` won't be
  honored on your edition), domain membership (warns that Group Policy may
  override local settings), and Windows Defender real-time protection status
  (informational only, since this script leaves Defender's cloud protection
  enabled by design).
- **Telemetry & diagnostics**: `DiagTrack`, `dmwappushservice`, Windows Error
  Reporting (permanently disabled as of 1.6.1 - no local dumps, nothing
  sent to Microsoft, no configuration option), `diagsvc`, plus the
  underlying ETW `AutoLogger-Diagtrack-Listener` and its local `.etl` trace
  files (stopping `DiagTrack` alone doesn't stop this — it buffers
  independently, starting earlier in boot than any service).
- **Machine-wide (HKLM) policies**: telemetry level, Cortana/web search,
  advertising ID, Delivery Optimization (LAN-only, not fully off), Activity
  History/Timeline, input personalization, Game DVR, App Compat telemetry,
  Windows Consumer Features/Spotlight, and PowerShell 7+'s telemetry opt-out.
- **Microsoft Edge** (auto-detected, skipped cleanly if not installed):
  usage/crash metrics, site-info sharing, ad personalization, feedback
  prompts, Do Not Track, Shopping Assistant, Collections, Startup Boost,
  Background Mode, first-run onboarding, and two Microsoft-deprecated-but-
  harmless-to-set policies (Enhance Images, the Search bar widget).
- **Microsoft Office 16.0** (covers 2016/2019/2021/2024 LTSC/365, auto-
  detected): telemetry agent, legacy Telemetry Dashboard, feedback surveys,
  Connected Experiences, LinkedIn integration.
- **OneDrive**: sync disabled via policy, plus its auto-start entry removed
  from the Run key for every profile (this does *not* uninstall OneDrive —
  full removal is planned for a future major version, see
  [Roadmap](#roadmap)).
- **Scheduled tasks**: the full set of documented CEIP/Compatibility
  Appraiser/Feedback/WER/Delivery-related telemetry tasks.
- **Per-user settings, applied to every local profile** — not just the
  account running the script. Loads each user's `NTUSER.DAT` offline
  (skipping in-use/locked hives gracefully), including the **Default
  profile template**, so accounts created *after* this script runs also
  inherit hardened defaults.
- **Low-risk consumer services**: Xbox-related services, Wallet, Push To
  Install.

## What it deliberately leaves alone

This script does not treat "reduces data collection" and "safe to disable"
as the same thing. Left untouched, on purpose:

| Item | Why |
|---|---|
| `PcaSvc` | May be needed for legacy app compatibility; its telemetry/notification behavior is disabled via policy instead of stopping the service outright |
| Location Services | Night Light auto-brightness and the Weather app depend on it |
| `SysMain` / `WSearch` | App launch speed / Explorer & Start menu search |
| Defender cloud protection (MAPS/SpyNet) | Assumed to be the only real-time AV on the device — status is checked at startup, not disabled |
| `CDPSvc`, `OneSyncSvc`, `UnistoreSvc`, `UserDataSvc` | Mail/Calendar/People sync, Timeline, clipboard sync, Nearby Sharing, Phone Link |
| `BITS`, `wuauserv` | Windows Update *delivery* — not telemetry. Disabling these blocks security patches, not data collection |
| DNS-over-HTTPS | Encrypted DNS is a privacy *improvement*, not something this script fights |

## Requirements

- Windows 10 IoT Enterprise LTSC 2021 (primary target — see
  [Compatibility](#compatibility))
- Administrator privileges
- PowerShell (present by default on all supported editions; used for
  locale-independent timestamps, the restore point, and a few status checks)

## Usage

1. Download `Privacy-Lockdown-LTSC2021-v1.6.1.bat` from the
   [latest release](../../releases/latest).
2. Right-click → **Run as administrator**.
3. Review the on-screen output as it runs — every action is logged live,
   with its own timestamp.
4. When it finishes, a folder named `PrivacyLockdown_<timestamp>` is created
   next to the script, containing:
   - `log.txt` — full run log
   - `registry_backup\` — one `.reg` file per key touched
   - `rollback_privacy.bat` — reverts everything from this run (its
     integrity is checked automatically at the end of the run — watch for
     a `[WARN]` in the summary if something looks off)
5. **Reboot** to fully apply service and scheduled-task changes.

For unattended/scripted deployment (SCCM, MDT, etc.), pass `/quiet` to
suppress the "press any key" prompts — everything still logs normally:

```bat
Privacy-Lockdown-LTSC2021-v1.6.1.bat /quiet
```

### Rolling back

Run the generated `rollback_privacy.bat` (in the same
`PrivacyLockdown_<timestamp>` folder) as Administrator. One exception: the
AutoLogger `.etl` trace files deleted during the original run cannot be
restored — this is flagged clearly in both the original run's output and
the rollback script itself.

### Windows Error Reporting

As of 1.6.1, WER is permanently and unconditionally disabled — no local
crash dumps, nothing sent to Microsoft, no user-facing crash prompt. There
is no configuration option for this (earlier versions had a `WER_MODE`
toggle for keeping local dumps; it's been removed for simplicity).

### Upgrading from a previous version

Safe to run directly over a machine already hardened by an earlier version
— no need to roll back first. Every run is self-contained and creates its
own timestamped backup/rollback folder without depending on any previous
run. See [CHANGELOG.md](CHANGELOG.md) for version-specific upgrade notes
(e.g. what happens if you'd previously used the now-removed
`WER_MODE=LOCAL` option).

## Compatibility

| Edition | Behavior |
|---|---|
| Windows 10 IoT Enterprise LTSC 2021 | Fully supported, primary target |
| Windows 10/11 Enterprise or Education LTSC | Should work identically — same policy surface |
| Windows 10/11 Pro or Home | Most settings apply, but `AllowTelemetry=0` (the strictest level) is silently clamped to a higher value by Windows itself on these editions — the script detects and warns about this at startup, it isn't a bug in the script |

## Safety notes

- This script makes system-level changes to services, scheduled tasks, and
  the registry. **Review it before running.** Use at your own risk.
- Domain-joined machines: Group Policy may override some of these settings
  on its next refresh cycle — the script detects and warns about this, but
  can't prevent it. Coordinate with your domain administrator if these
  changes need to persist in a managed environment.
- Nothing in this script disables Windows Update, BITS, or your antivirus's
  real-time/cloud protection — see the table above.

## Roadmap

Larger, more invasive changes are being held for a future major version
rather than folded into ongoing 1.x patches:

- Full OneDrive removal (not just disabling auto-start/sync)
- Under consideration: optional config-driven toggles for individual
  settings, rather than editing the script directly

See [CHANGELOG.md](CHANGELOG.md) for the full version history.

## License

MIT — see [LICENSE](LICENSE).

Copyright (c) 2026 x805
