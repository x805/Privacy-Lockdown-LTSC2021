# Changelog

All notable changes to `Privacy-Lockdown-LTSC2021` are documented in this file.


---

### Fixed

* **Rollback redirection syntax:** Added missing escape characters before `>nul` in three rollback-generation lines within `EnsureKeyBackedUp`/`SetReg`.
* **Batch execution hijack defense:** Replaced `echo.` with `echo/` across 26 sites to defend against execution hijacking from files named `echo.exe`/`echo.bat` on the `PATH`.

### Added

* **Rollback warning notice:** Added an explicit `REM` warning directly into `rollback_privacy.bat` noting that `HKCU` entries restore to whichever user account originally executed the script.
* **Last-run registry marker:** Added writing of `LastRunVersion`, `LastRunDate`, and `LastRunResult` to `HKLM\SOFTWARE\Privacy-Lockdown-LTSC2021` upon successful completion.

### Notes

* **Final standalone release:** The lockdown-only script line ends here, with future development moving to the v1.7 unified toolkit.
* No changes were made to hardening rules; all settings, services, scheduled tasks, and per-user changes are identical to v1.6.2.
* Orphaned `HKU\TempHive_*` hive cleanup was reviewed during this release and confirmed to already exist correctly in 1.6.2 - not a v1.6.3 change.

---

## [1.6.2]

### Fixed

* **`:StopDisableSvc` localization bug:** Replaced parsing of localized `sc qc` console output with direct `REG_DWORD` reads from `HKLM\SYSTEM\CurrentControlSet\Services\<SvcName>`.
* **Active user profile target miss:** Enumerated mounted user hives directly under `HKU` by SID to apply per-user settings immediately to active standard users when elevated under secondary administrator credentials.
* **Rollback path portability:** Replaced hardcoded working directory paths with `%~dp0` in `rollback_privacy.bat`.
* **Rollback correctness for per-user hives:** Added automatic `reg load` and `reg unload` calls for `NTUSER.DAT` files during rollback script execution.
* **Hardened profile-folder parsing:** Refactored `%SystemDrive%\Users\*` folder loop into a subroutine using `%~nx1` argument substitution to prevent string corruption from delayed expansion variables containing exclamation marks.
* **Unquoted registry data in `:SetReg`:** Enclosed `/d "%~4"` in quotes within `reg add` calls to support registry values containing spaces.

### Changed

* **`:DisableTask` performance:** Replaced per-task PowerShell invocations with native `schtasks /query /tn "%~1" /fo CSV /nh` calls.

### Added

* **Cloud Clipboard:** Added `AllowCrossDeviceClipboard = 0` under `HKLM\SOFTWARE\Policies\Microsoft\Windows\System`.
* **News and Interests / Widgets:** Added `AllowNewsAndInterests = 0` under `HKLM\SOFTWARE\Policies\Microsoft\Dsh`.
* **Edge Update tasks:** Added `EdgeUpdateTaskMachineCore` and `EdgeUpdateTaskMachineUA` to the scheduled-task disable list.

---

## [1.6.1]

### Changed
* **Windows Error Reporting:** Permanently disabled Windows Error Reporting across the board with no user option to leave it active.

---

## [1.6.0]

### Added
* **Incremental rollback generation:** Rebuilt `rollback_privacy.bat` creation to append revert actions incrementally as changes occur, ensuring usable rollbacks even if execution is interrupted mid-run.
* **Rollback integrity check:** Validates at the end of a run that `rollback_privacy.bat` exists, is non-empty, wasn't truncated mid-write, and reports total revert actions.
* **Per-action logging timestamps:** Added individual `[date time]` entries for every `SetReg`, `StopDisableSvc`, and `DisableTask` call.

### Notes
* Closed out applicable suggestions from an independent review of v1.5.2.

---

> **Historical Note:** Versions 1.5.2 and older were developed and published in a previous repository. Their release history is preserved below for continuity, but their source code and binary assets are not hosted in this current repository tree.


---

## [1.5.2]

### Fixed
* **System Restore point pathing:** Switched System Restore point creation to `%SystemDrive%\` instead of hardcoded `C:\`.
* **Service rollback queuing:** Suppressed `sc start` queuing during rollback for services that were already disabled prior to running the script.
* **Domain-join detection:** Updated domain-join detection to a proper three-way status check (domain-joined / not domain-joined / inconclusive).

### Added
* **Defender status check:** Added a read-only startup check via `Get-MpComputerStatus` to verify real-time protection status.

---

## [1.5.0]

### Fixed
* **Delayed-auto service rollback:** Updated `:StopDisableSvc` to detect `(DELAYED)` AUTO_START services and restore them with `start= delayed-auto`.
* **WER service state alignment:** Conditionalized `WerSvc` disabling on `WER_MODE` to allow local dumps when set to `LOCAL`.

### Added
* **Portable user-profile path:** Replaced hardcoded `C:\Users` with `%SystemDrive%\Users` across profile loops.
* **Windows edition check:** Added startup check for EditionID to warn if non-Enterprise/Education/IoT builds clamp `AllowTelemetry=0`.
* **`WER_MODE` toggle:** Added a top-level `WER_MODE` variable (`OFF` or `LOCAL`) to drive Windows Error Reporting behavior.
* **Unattended `/quiet` flag:** Added `/quiet` flag to suppress pause prompts for automated SCCM/MDT deployment.
* **Logon notes:** Clarified in the summary that offline `NTUSER.DAT` profile changes take effect at next logon.

---

## [1.4.2]

### Added
* **"Intentionally Left Alone" summary:** Added end-of-run summary detailing components deliberately untouched (e.g., `PcaSvc`, Location Services, `SysMain`, `WSearch`, Defender cloud protection, sync services, BITS/wuauserv).

---

## [1.4.0]

### Fixed
* **Profile hive cleanup whitespace handling:** Updated `reg query HKU` parsing from `tokens=1` to `tokens=*` to handle username folders containing spaces.
* **Default profile template hardening:** Added explicit hardening step for `C:\Users\Default\NTUSER.DAT` so new user accounts inherit hardened settings.

### Added
* **AutoLogger ETW disabling:** Disabled `AutoLogger-Diagtrack-Listener` via registry (`Start=0`).
* **Trace file cleanup:** Added one-time deletion of residual `.etl` trace files.
* **PowerShell execution policy bypass:** Added `-ExecutionPolicy Bypass` to PowerShell invocations.

---

## [1.3.0]

### Added
* **PowerShell 7+ telemetry opt-out:** Configured `POWERSHELL_TELEMETRY_OPTOUT` environment variable via `:SetReg`.
* **Edge policy addition:** Added `HideFirstRunExperience` policy for Microsoft Edge.
* **Quick Verification summary:** Added end-of-run spot-check for `AllowTelemetry` and `DiagTrack` status.

---

## [1.2.0]

### Fixed
* **Rollback corruption fix (High Severity):** Replaced per-value backup triggering with single first-touch-per-key snapshotting (`:EnsureKeyBackedUp`).
* **Scheduled task rollback accuracy:** Updated `:DisableTask` to query initial status before disabling to prevent re-enabling previously disabled tasks.
* **Service detection rewrite:** Refactored `sc qc` parsing to target exact `START_TYPE` lines.
* **Conditional rollback logging:** Restricted rollback entries to write only after `reg add` succeeds.

### Added
* **Orphaned hive cleanup pass:** Added end-of-run cleanup attempt for mounted `HKU\TempHive_*` keys.
* **Domain-join detection:** Added startup warning if machine is domain-joined.

---

## [1.1.1]

### Fixed
* **Timestamp entropy:** Improved timestamp fallback entropy using `%RANDOM%%RANDOM%`.
* **Documentation:** Added MIT license header, copyright notice, and SPDX identifier.

---

## [1.0.1]

### Added
* **Edge policies:** Added `StartupBoostEnabled`, `BackgroundModeEnabled`, `EdgeEnhanceImagesEnabled`, and `WebWidgetAllowed`.
* **Service exclusions:** Explicitly configured low-risk consumer service targeting (`WalletService`, `PushToInstall`) while preserving core OS functionality.

---

## [1.0.0]

### Added
* **Initial public release:** Windows 10 IoT Enterprise LTSC 2021 Privacy Lockdown script.
* **Core system privacy:** Enterprise telemetry reduction, disabling CEIP, WER, Activity History, Advertising ID, Cortana, Bing Search, Game DVR, and Spotlight.
* **App hardening:** Microsoft Edge and Microsoft Office privacy policies, OneDrive GPO sync blocking.
* **Backup & Rollback engine:** Automated restore point creation, registry key backup, and `rollback_privacy.bat` generation.
