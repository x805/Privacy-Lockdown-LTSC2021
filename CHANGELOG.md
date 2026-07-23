# Changelog

All notable changes to `Privacy-Lockdown-LTSC2021` are documented here.

## [1.6.2] - 2026-07-23

### Fixed
- **`:StopDisableSvc` localization bug** — service start-type detection previously
  parsed `sc qc` console output for the `START_TYPE` label, which is localized on
  non-English Windows builds and silently broke rollback's ability to restore a
  service's original start type. Now reads the `Start` value directly as a
  `REG_DWORD` from `HKLM\SYSTEM\CurrentControlSet\Services\<SvcName>`
  (0=Boot, 1=System, 2=Automatic, 3=Manual, 4=Disabled), plus `DelayedAutostart`
  for the Automatic (Delayed Start) case. Immune to display-language differences.
- **Active user profile target miss** — when the script is elevated with secondary
  Administrator credentials, `HKCU` targets the admin's own profile, and the
  standard user's `NTUSER.DAT` is locked, so the offline `reg load` path skipped
  them entirely until their next full logon. The script now also enumerates
  already-mounted user hives directly under `HKU` (matched by SID) and applies
  per-user settings to any of them immediately, in addition to the current
  interactive user and the offline profile loop.
- **Rollback path portability** — `rollback_privacy.bat` previously baked in this
  run's absolute `%WORKDIR%`/`%REGBACKUP%` path for every `reg import` line,
  breaking rollback if the `PrivacyLockdown_*` folder was later moved, renamed, or
  copied to another machine. Backup file references now resolve via `%~dp0` at
  rollback time instead.
- **Rollback correctness for per-user hives** — related to the path-portability fix
  above: `reg export`/`reg import` for offline and Default-template profile hives
  targeted a `TempHive_<profile>` mount name that only exists for the duration of
  the run that created it. Rollback now re-`reg load`s each profile's `NTUSER.DAT`
  under that same mount name from inside `rollback_privacy.bat` before replaying
  the recorded commands, then unloads it afterward, so rollback actually reaches
  the real registry data instead of silently writing to a disconnected orphan key.
- **Hardened profile-folder parsing** — the loop over `%SystemDrive%\Users\*`
  round-tripped each folder name through a delayed-expansion variable
  (`!PROFNAME!`), which corrupts if a folder name contains a literal `!`. This
  logic was moved into a `:ProcessOfflineProfile` subroutine that uses `%~nx1`
  argument substitution throughout instead, which isn't subject to that parsing
  hazard.
- **Unquoted registry data in `:SetReg`** — the `reg add` call passed `/d %~4`
  unquoted, which fails for any string value containing spaces. Now `/d "%~4"`.

### Changed
- **`:DisableTask` performance** — replaced a per-task PowerShell
  `Get-ScheduledTask` call with native `schtasks /query /tn "%~1" /fo CSV /nh`,
  removing one PowerShell process spawn per task in the list. Known trade-off:
  unlike `Get-ScheduledTask`'s `.State` enum, the `Status` column `schtasks`
  prints is a localized display string, so on non-English builds this can miss
  detecting an already-disabled task and cause rollback to re-enable it. This
  does not affect the disable action itself, which relies on `schtasks`' exit
  code, not this text.

### Added
- **Cloud Clipboard**: `AllowCrossDeviceClipboard = 0` under
  `HKLM\SOFTWARE\Policies\Microsoft\Windows\System`, disabling cross-device
  clipboard sync/telemetry.
- **News and Interests / Widgets**: `AllowNewsAndInterests = 0` under
  `HKLM\SOFTWARE\Policies\Microsoft\Dsh`, disabling the background content feed.
- **Edge Update tasks**: `\Microsoft\EdgeUpdate\EdgeUpdateTaskMachineCore` and
  `\Microsoft\EdgeUpdate\EdgeUpdateTaskMachineUA` added to the scheduled-task
  disable list.

---

## [1.6.1]

### Changed
- Windows Error Reporting is now **fully and permanently** disabled, with no
  user-configurable option to leave it enabled.

> Note: this entry reflects only what's confirmed by the in-script comments in
> the 1.6.1 source. If 1.6.1 included other changes not documented in the code
> itself, they aren't captured here — let me know if there's a prior
> CHANGELOG.md or commit history to reconcile against.

---

## [1.6.0]

### Added
- Rollback script (`rollback_privacy.bat`) generation switched to **incremental**
  writes — each revert action is appended to the file as its corresponding
  change is made, rather than assembled in memory and written once at the end.
  This keeps rollback usable even if the script is interrupted partway through
  (power loss, forced termination, etc.), since an end-of-run-only write would
  leave the rollback file empty for a partial run.
- **Rollback integrity check** at the end of each run: confirms
  `rollback_privacy.bat` exists, is non-empty, wasn't truncated partway through
  (disk space or antivirus interference), and reports how many revert actions it
  contains.

> Note: same caveat as above — this entry reflects only what's confirmed by the
> in-script comments. There may be earlier or additional 1.6.0 changes not
> captured here.

---

## Architectural constraints maintained across all versions above
- Custom `:EnsureKeyBackedUp` logic for precise, state-accurate rollbacks.
- Incremental `rollback_privacy.bat` generation (crash-safe).
- Intentional exclusions left untouched: `PcaSvc`, Location Services, `SysMain`,
  `WSearch`, Defender cloud protection (MAPS/SpyNet), and Windows Update
  delivery components (BITS/wuauserv).
