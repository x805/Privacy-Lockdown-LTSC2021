@echo off
:: =====================================================================
:: Windows10-IoT-LTSC-Privacy-Baseline
:: https://github.com/x805/Windows10-IoT-LTSC-Privacy-Baseline
:: Copyright (c) 2026 x805 - SPDX-License-Identifier: MIT
:: Full license text: LICENSE file in this repository.
::
:: Privacy hardening for Windows 10 IoT Enterprise LTSC 2021. Creates a
:: System Restore point and per-key registry backups before any change,
:: and generates rollback_privacy.bat to revert everything (including
:: each service's actual original start type, not a hardcoded guess).
:: Covers telemetry, Windows Error Reporting (permanently disabled), Edge
:: and Office (auto-detected, skipped cleanly if absent), OneDrive sync,
:: and related scheduled tasks - applied machine-wide (HKLM) and per-user
:: (HKCU, every local profile plus the Default template for future
:: accounts). Leaves Defender cloud protection, Location Services,
:: SysMain, WSearch, and Windows Update delivery (BITS/wuauserv)
:: untouched by design - see README.md for the full list and rationale.
::
:: Full feature list, usage instructions, and version history:
:: README.md and CHANGELOG.md in this repository.
::
:: This script makes system-level changes (services, scheduled tasks, and
:: the registry). Review it before running. Use at your own risk.
:: =====================================================================
setlocal EnableDelayedExpansion
set "SCRIPT_VERSION=1.6.1"

:: Windows Error Reporting is fully and permanently disabled below - no
:: crash dumps of any kind, local or sent to Microsoft. There is no
:: user-configurable option for this as of 1.6.1 (see CHANGELOG.md).
title Windows 10 IoT LTSC 2021 - Privacy Lockdown v%SCRIPT_VERSION%

:: ---------------------- Command-line options ----------------------------
:: /quiet suppresses both "press any key" pauses, for unattended deployment
:: via SCCM/MDT. Everything still logs normally either way.
set "QUIET="
if /I "%~1"=="/quiet" set "QUIET=1"

:: ---------------------- Admin check -----------------------------------
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo Please run this script as an Administrator!
    if not defined QUIET pause
    exit /b 1
)

:: ---------------------- Setup -------------------------------------------
:: Timestamp via PowerShell Get-Date with an explicit format string - this
:: avoids the locale-dependent parsing problems of %DATE%/%TIME%, which
:: use whatever short-date/time format the OS regional settings define
:: (not guaranteed to be MM/DD/YYYY, so substring-slicing them is fragile).
for /f %%i in ('powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-Date -Format yyyyMMdd_HHmmss"') do set "STAMP=%%i"
if not defined STAMP set "STAMP=fallback_%RANDOM%%RANDOM%"
set "WORKDIR=%~dp0PrivacyLockdown_%STAMP%"
set "LOGFILE=%WORKDIR%\log.txt"
set "REGBACKUP=%WORKDIR%\registry_backup"
set "ROLLBACK_BAT=%WORKDIR%\rollback_privacy.bat"
set "OK=0"
set "FAIL=0"
set "SKIP=0"

mkdir "%WORKDIR%" >nul 2>&1
mkdir "%REGBACKUP%" >nul 2>&1

echo Privacy Lockdown run started %date% %time% > "%LOGFILE%"
echo Script version: %SCRIPT_VERSION% >> "%LOGFILE%"
echo Privacy Lockdown v%SCRIPT_VERSION%
echo Log and registry backups are being written to:
echo   %WORKDIR%
echo.

:: Initialize rollback script
echo @echo off > "%ROLLBACK_BAT%"
echo title Privacy Lockdown - Rollback >> "%ROLLBACK_BAT%"
echo net session ^>nul 2^>^&1 >> "%ROLLBACK_BAT%"
echo if %%errorLevel%% neq 0 ^(echo Please run as Administrator! ^& pause ^& exit /b 1^) >> "%ROLLBACK_BAT%"
echo echo Rolling back privacy changes... >> "%ROLLBACK_BAT%"
echo echo. >> "%ROLLBACK_BAT%"

:: ---------------------- System Restore point -----------------------------
:: NOTE: on some Windows 10 IoT Enterprise LTSC images, OEMs strip or
:: disable Volume Shadow Copy/System Restore entirely to reduce writes to
:: flash storage. If that's the case here, the block below will fail by
:: design (not a bug) - it's already handled as a non-fatal warning.
echo === Creating System Restore point ===
echo [%DATE% %TIME%] === Creating System Restore point === >> "%LOGFILE%"
powershell -NoProfile -ExecutionPolicy Bypass -Command "try { Enable-ComputerRestore -Drive '%SystemDrive%\' -ErrorAction Stop } catch {}; try { Checkpoint-Computer -Description 'Pre-PrivacyLockdown' -RestorePointType MODIFY_SETTINGS -ErrorAction Stop; exit 0 } catch { Write-Output $_.Exception.Message; exit 1 }" >> "%LOGFILE%" 2>&1
if errorlevel 1 (
    echo   [WARN] Restore point creation failed or was skipped ^(Windows only allows ^
one automatic restore point per 24h - this is often normal^). Continuing.
    echo   [WARN] Restore point may have failed - see log >> "%LOGFILE%"
) else (
    echo   [OK] Restore point created.
)
echo.

:: ================================================================
:: Helper subroutines (called below - do not run this section directly)
:: ================================================================
goto :MAIN

:EnsureKeyBackedUp
:: %1 = full key path
:: Runs ONCE per key per run, at the very first value touched under that
:: key - regardless of whether that first touch happens to be a brand-new
:: value or a pre-existing one. This matters because the old design only
:: backed a key up when the FIRST value processed under it already
:: existed; if a NEW value was added first (no backup needed then) and a
:: LATER call touched an EXISTING value in that same key, the backup taken
:: at that later point would already include the value just added earlier
:: in this run - permanently corrupting what "original" meant for rollback.
set "SAFEBK=%~1"
set "SAFEBK=%SAFEBK::=_%"
set "SAFEBK=%SAFEBK:\=_%"
set "KEY_PREEXISTED=0"
if exist "%REGBACKUP%\%SAFEBK%.done" (
    if exist "%REGBACKUP%\%SAFEBK%.reg" set "KEY_PREEXISTED=1"
    exit /b 0
)
reg query "%~1" >nul 2>&1
if errorlevel 1 (
    :: Key itself doesn't exist yet - deleting the whole key on rollback
    :: is correct and automatically covers every value this run adds to it.
    set "KEY_PREEXISTED=0"
    echo reg delete "%~1" /f >nul 2^>^&1 >> "%ROLLBACK_BAT%"
) else (
    set "KEY_PREEXISTED=1"
    reg export "%~1" "%REGBACKUP%\%SAFEBK%.reg" /y >nul 2>&1
    echo reg import "%REGBACKUP%\%SAFEBK%.reg" >nul 2^>^&1 >> "%ROLLBACK_BAT%"
)
echo done > "%REGBACKUP%\%SAFEBK%.done"
exit /b 0

:SetReg
:: %1=hive\path  %2=value name  %3=type  %4=data
echo [%DATE% %TIME%] SetReg: %~1 ^| %~2 = %~4 >> "%LOGFILE%"
call :EnsureKeyBackedUp "%~1"

:: A per-value delete-on-rollback entry is only needed when this specific
:: value is new AND the key itself already existed (if the key itself was
:: newly created, EnsureKeyBackedUp's whole-key delete already covers it).
set "NEED_VALUE_ROLLBACK=0"
if "!KEY_PREEXISTED!"=="1" (
    reg query "%~1" /v "%~2" >nul 2>&1
    if errorlevel 1 set "NEED_VALUE_ROLLBACK=1"
)

reg add "%~1" /v "%~2" /t %~3 /d %~4 /f >> "%LOGFILE%" 2>&1
if errorlevel 1 (
    echo   [FAIL] %~1  ^|  %~2=%~4
    echo   [FAIL] %~1 ^| %~2=%~4 >> "%LOGFILE%"
    set /a FAIL+=1
) else (
    reg query "%~1" /v "%~2" >nul 2>&1
    if errorlevel 1 (
        echo   [WARN] %~1  ^|  %~2 - reg add reported success but value not found on verify
        echo   [WARN] %~1 ^| %~2 - verify read-back failed >> "%LOGFILE%"
        set /a FAIL+=1
    ) else (
        echo   [ OK ] %~1  ^|  %~2=%~4
        set /a OK+=1
        if "!NEED_VALUE_ROLLBACK!"=="1" (
            echo reg delete "%~1" /v "%~2" /f >nul 2^>^&1 >> "%ROLLBACK_BAT%"
        )
    )
)
exit /b 0

:StopDisableSvc
:: %1 = service name
echo [%DATE% %TIME%] StopDisableSvc: %~1 >> "%LOGFILE%"
sc query "%~1" >nul 2>&1
if errorlevel 1060 (
    echo   [SKIP] Service %~1 not present on this system.
    echo   [SKIP] Service %~1 not present >> "%LOGFILE%"
    set /a SKIP+=1
    exit /b 0
)
:: Capture the service's ACTUAL current start type so rollback restores
:: the real prior state instead of guessing "auto" for everything. Query
:: once, filtered to just the START_TYPE line, then exact-match the label
:: (avoids any risk of a substring like "AUTO_START" coincidentally
:: appearing elsewhere in sc qc's output, e.g. in a binary path or name).
set "ORIGSTART_RAW="
set "ORIGSTART_FULLLINE="
for /f "tokens=4" %%a in ('sc qc "%~1" ^| findstr /i "START_TYPE"') do set "ORIGSTART_RAW=%%a"
for /f "delims=" %%a in ('sc qc "%~1" ^| findstr /i "START_TYPE"') do set "ORIGSTART_FULLLINE=%%a"
set "ORIGSTART=demand"
if /I "!ORIGSTART_RAW!"=="AUTO_START" set "ORIGSTART=auto"
if /I "!ORIGSTART_RAW!"=="DEMAND_START" set "ORIGSTART=demand"
if /I "!ORIGSTART_RAW!"=="BOOT_START" set "ORIGSTART=boot"
if /I "!ORIGSTART_RAW!"=="SYSTEM_START" set "ORIGSTART=system"
if /I "!ORIGSTART_RAW!"=="DISABLED" set "ORIGSTART=disabled"
:: A plain Automatic start can additionally be flagged "(DELAYED)" by sc qc
:: (Automatic - Delayed Start). Confirmed via Microsoft's own sc.exe docs:
:: restoring this needs the single distinct value start= delayed-auto, not
:: "auto" plus a separate flag - using plain "auto" would silently lose
:: the delay behavior on rollback.
echo !ORIGSTART_FULLLINE! | findstr /I "DELAYED" >nul
if not errorlevel 1 if /I "!ORIGSTART!"=="auto" set "ORIGSTART=delayed-auto"
sc config "%~1" start= disabled >> "%LOGFILE%" 2>&1
if errorlevel 1 (
    echo   [FAIL] Could not set %~1 to disabled ^(may need reboot or is protected^)
    set /a FAIL+=1
) else (
    echo   [ OK ] %~1 set to disabled ^(was: !ORIGSTART!^)
    set /a OK+=1
    echo sc config "%~1" start= !ORIGSTART! >> "%ROLLBACK_BAT%"
    if /I not "!ORIGSTART!"=="disabled" (
        echo sc start "%~1" ^>nul 2^>^&1 >> "%ROLLBACK_BAT%"
    )
)
sc stop "%~1" >> "%LOGFILE%" 2>&1
exit /b 0

:DisableTask
:: %1 = full task path
echo [%DATE% %TIME%] DisableTask: %~1 >> "%LOGFILE%"
:: Capture whether the task was actually enabled before we touch it, so
:: rollback doesn't re-enable a task that was already disabled beforehand
:: (by the OS, an OEM, or a previous run of this script). Uses PowerShell's
:: Get-ScheduledTask rather than parsing "schtasks /query" console text,
:: because that text is localized on non-English Windows (e.g. "Disabled"
:: becomes "Deaktiviert" on German Windows) - the .State enum value from
:: Get-ScheduledTask is a fixed .NET symbol name, not a display string, so
:: it reads correctly regardless of the OS display language.
set "TASK_WAS_ENABLED=1"
set "TASKSTATE="
for /f "delims=" %%s in ('powershell -NoProfile -ExecutionPolicy Bypass -Command "$n=Split-Path '%~1' -Leaf; $p=(Split-Path '%~1' -Parent)+'\'; (Get-ScheduledTask -TaskName $n -TaskPath $p -ErrorAction SilentlyContinue).State" 2^>nul') do set "TASKSTATE=%%s"
if /I "!TASKSTATE!"=="Disabled" set "TASK_WAS_ENABLED=0"
schtasks /change /tn "%~1" /disable >> "%LOGFILE%" 2>&1
if errorlevel 1 (
    echo   [SKIP] Task not found or already disabled: %~1
    set /a SKIP+=1
) else (
    echo   [ OK ] Disabled task: %~1
    set /a OK+=1
    if "!TASK_WAS_ENABLED!"=="1" (
        echo schtasks /change /tn "%~1" /enable >> "%ROLLBACK_BAT%"
    ) else (
        echo REM "%~1" was already disabled before this script ran - not re-enabling on rollback >> "%ROLLBACK_BAT%"
    )
)
exit /b 0

:CheckRegKeyExists
:: %1 = registry key path. Returns errorlevel 0 if it exists, 1 if not.
reg query "%~1" >nul 2>&1
exit /b %errorlevel%

:: ================================================================
:MAIN

echo === Checking Windows edition ===
:: AllowTelemetry=0 (Security level) is only honored on Enterprise,
:: Education, and IoT Enterprise editions - on Pro/Home, Windows silently
:: clamps it to 1 (Basic) instead. Read via a plain registry value rather
:: than deprecated wmic, consistent with how the rest of this script
:: avoids it.
for /f "tokens=2,*" %%a in ('reg query "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion" /v EditionID 2^>nul ^| findstr /i "EditionID"') do set "WINEDITION=%%b"
echo !WINEDITION! | findstr /I "Enterprise Education IoT" >nul
if errorlevel 1 (
    echo   [WARN] Detected edition: !WINEDITION! - AllowTelemetry=0 ^(the
    echo   [WARN] strictest level this script sets^) is only honored on
    echo   [WARN] Enterprise, Education, and IoT Enterprise editions. On
    echo   [WARN] this edition Windows will likely clamp it to a higher
    echo   [WARN] value instead. Everything else in this script still
    echo   [WARN] applies normally.
    echo   [WARN] Non-Enterprise/Education/IoT edition detected: !WINEDITION! >> "%LOGFILE%"
) else (
    echo   [OK] Detected edition: !WINEDITION! - AllowTelemetry=0 is fully honored.
)
echo.

echo === Checking domain membership ===
set "ISDOMAIN="
for /f %%i in ('powershell -NoProfile -ExecutionPolicy Bypass -Command "(Get-CimInstance Win32_ComputerSystem).PartOfDomain" 2^>nul') do set "ISDOMAIN=%%i"
if /I "!ISDOMAIN!"=="True" (
    echo   [WARN] This machine appears to be domain-joined. Group Policy may
    echo   [WARN] silently override some of these local settings the next
    echo   [WARN] time it refreshes. Check with your domain administrator if
    echo   [WARN] changes don't seem to stick.
    echo   [WARN] Domain-joined machine detected - GPO may override local settings >> "%LOGFILE%"
) else if /I "!ISDOMAIN!"=="False" (
    echo   [OK] Not domain-joined - no Group Policy conflict expected.
) else (
    echo   [WARN] Could not determine domain membership ^(PowerShell check
    echo   [WARN] returned no result^). If this machine is domain-joined,
    echo   [WARN] Group Policy may override some of these local settings.
    echo   [WARN] Domain membership check inconclusive >> "%LOGFILE%"
)
echo.

echo === Checking Windows Defender status ===
:: This script deliberately leaves Defender cloud protection (MAPS/SpyNet)
:: enabled on the assumption there's no other real-time AV on this device.
:: This is just a status readout to confirm that assumption still holds -
:: it changes nothing.
set "DEFENDERRT="
for /f %%i in ('powershell -NoProfile -ExecutionPolicy Bypass -Command "(Get-MpComputerStatus -ErrorAction SilentlyContinue).RealTimeProtectionEnabled" 2^>nul') do set "DEFENDERRT=%%i"
if /I "!DEFENDERRT!"=="True" (
    echo   [OK] Defender real-time protection is active.
) else if /I "!DEFENDERRT!"=="False" (
    echo   [WARN] Defender real-time protection appears to be OFF. This
    echo   [WARN] script leaves Defender cloud protection enabled assuming
    echo   [WARN] it's your active AV - if you're relying on different
    echo   [WARN] software instead, that's fine, just worth knowing this
    echo   [WARN] script didn't verify that other software is present.
    echo   [WARN] Defender real-time protection appears disabled >> "%LOGFILE%"
) else (
    echo   [SKIP] Could not read Defender status ^(module unavailable or
    echo   [SKIP] Defender not installed^).
    set /a SKIP+=1
)
echo.

echo === Checking installed components ===
echo [%DATE% %TIME%] === Component detection === >> "%LOGFILE%"
call :CheckRegKeyExists "HKLM\SOFTWARE\Microsoft\office\16.0\common\InstallRoot"
if errorlevel 1 (
    call :CheckRegKeyExists "HKLM\SOFTWARE\Microsoft\Office\ClickToRun\Configuration"
    if errorlevel 1 (
        set "OFFICE_INSTALLED=0"
        echo   [SKIP] Office 16.0 not detected - Office section will be skipped.
        echo   [SKIP] Office 16.0 not detected. >> "%LOGFILE%"
        set /a SKIP+=1
    ) else ( set "OFFICE_INSTALLED=1" )
) else ( set "OFFICE_INSTALLED=1" )

call :CheckRegKeyExists "HKLM\SOFTWARE\Microsoft\EdgeUpdate\Clients\{56EB18F8-B008-4CBD-B6D2-8C97FE7E9062}"
if errorlevel 1 (
    set "EDGE_INSTALLED=0"
    echo   [SKIP] Microsoft Edge ^(Chromium^) not detected - Edge section will be skipped.
    echo   [SKIP] Microsoft Edge not detected. >> "%LOGFILE%"
    set /a SKIP+=1
) else ( set "EDGE_INSTALLED=1" )
echo.

echo === PowerShell Telemetry ===
echo [%DATE% %TIME%] === PowerShell === >> "%LOGFILE%"
:: Opts PowerShell 7+ (pwsh.exe) out of its Application Insights telemetry.
:: Has no effect on built-in Windows PowerShell 5.1 (powershell.exe), which
:: doesn't use this variable - harmless either way if pwsh isn't installed,
:: and takes effect for it automatically if installed later. Must be a
:: persistent environment variable (not just visible in this session)
:: because PowerShell only reads it at process startup - setx-style machine
:: environment variables live in this registry key, so routing it through
:: the normal :SetReg call gives it the same tested backup/rollback
:: handling as everything else, instead of a separate one-off mechanism.
call :SetReg "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" "POWERSHELL_TELEMETRY_OPTOUT" REG_SZ 1
:: The reg write above doesn't notify already-running sessions of the new
:: variable - Explorer/cmd/PowerShell windows opened before this script ran
:: would otherwise only see it after a reboot. Re-setting it through .NET's
:: SetEnvironmentVariable is a redundant write (same value) but its real
:: purpose here is the WM_SETTINGCHANGE broadcast it performs as a side
:: effect, which lets NEW processes spawned from EXISTING sessions pick it
:: up immediately instead of waiting for the reboot already recommended
:: for the service/task changes.
powershell -NoProfile -ExecutionPolicy Bypass -Command "[System.Environment]::SetEnvironmentVariable('POWERSHELL_TELEMETRY_OPTOUT','1','Machine')" >nul 2>&1
echo.

echo === Disabling Telemetry ^& Diagnostic Services ===
echo [%DATE% %TIME%] === Services === >> "%LOGFILE%"
call :StopDisableSvc DiagTrack
call :StopDisableSvc dmwappushservice
:: WerSvc is always stopped and disabled as of 1.6.1 - WER is permanently off.
call :StopDisableSvc WerSvc
call :StopDisableSvc diagsvc
:: PcaSvc (Program Compatibility Assistant) intentionally left running:
:: some legacy/line-of-business apps rely on it, and it isn't primarily
:: a telemetry channel. The AppCompat policy block below disables its
:: reporting/notification behavior anyway. Disable the service manually
:: later if you don't need it.
echo   [SKIP] PcaSvc left enabled ^(may be needed for legacy app compatibility^).
echo   [SKIP] PcaSvc left enabled by design. >> "%LOGFILE%"
set /a SKIP+=1
:: Xbox-related services - irrelevant on this device, low risk to disable
call :StopDisableSvc XblAuthManager
call :StopDisableSvc XblGameSave
call :StopDisableSvc XboxGipSvc
call :StopDisableSvc XboxNetApiSvc
echo.

echo === Machine-wide (HKLM) Registry Policies ===
echo [%DATE% %TIME%] === HKLM Policies === >> "%LOGFILE%"

:: Telemetry level (0 = Security, valid on Enterprise/IoT Enterprise/LTSC only)
call :SetReg "HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection" "AllowTelemetry" REG_DWORD 0
call :SetReg "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection" "AllowTelemetry" REG_DWORD 0
call :SetReg "HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection" "DoNotShowFeedbackNotifications" REG_DWORD 1
call :SetReg "HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection" "NumberOfSIUFInPeriod" REG_DWORD 0
:: Prevent DiagTrack from falling back to an authenticated proxy to reach
:: telemetry endpoints when a direct connection is blocked
call :SetReg "HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection" "DisableEnterpriseAuthProxy" REG_DWORD 1
:: Largely redundant given AllowTelemetry=0 (Security), but harmless
call :SetReg "HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection" "LimitEnhancedDiagnosticDataWindowsAnalytics" REG_DWORD 0

:: Windows Error Reporting - permanently and fully disabled as of 1.6.1.
:: No local crash dumps, no data sent to Microsoft, no user prompt.
call :SetReg "HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Error Reporting" "Disabled" REG_DWORD 1
call :SetReg "HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Error Reporting" "DontShowUI" REG_DWORD 1
call :SetReg "HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Error Reporting" "DontSendWindowsReports" REG_DWORD 1
call :SetReg "HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Error Reporting" "DontSendHandWritingSamples" REG_DWORD 1

:: Cortana / Search telemetry
call :SetReg "HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Search" "AllowCortana" REG_DWORD 0
call :SetReg "HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Search" "DisableWebSearch" REG_DWORD 1
call :SetReg "HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Search" "ConnectedSearchUseWeb" REG_DWORD 0
call :SetReg "HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Search" "BingSearchEnabled" REG_DWORD 0
call :SetReg "HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Search" "DisableSearchBoxSuggestions" REG_DWORD 1
call :SetReg "HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Search" "DisableSearchSuggestionsFromLocalFiles" REG_DWORD 1

:: Advertising ID (machine-wide default)
call :SetReg "HKLM\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo" "DisabledByGroupPolicy" REG_DWORD 1

:: Delivery Optimization: LAN-only peer sharing (1) rather than fully off (0).
:: Still stops payloads being shared with/from peers over the internet,
:: but keeps the (harmless, opt-in-by-nature) local-network speedup.
call :SetReg "HKLM\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization" "DODownloadMode" REG_DWORD 1

:: Activity History / Timeline upload to Microsoft account
call :SetReg "HKLM\SOFTWARE\Policies\Microsoft\Windows\System" "EnableActivityFeed" REG_DWORD 0
call :SetReg "HKLM\SOFTWARE\Policies\Microsoft\Windows\System" "PublishUserActivities" REG_DWORD 0
call :SetReg "HKLM\SOFTWARE\Policies\Microsoft\Windows\System" "UploadUserActivities" REG_DWORD 0

:: Location services: intentionally left untouched. Disabling this breaks
:: Night Light auto-brightness/sunset timing and the Weather app for every
:: user on the machine - a bigger usability cost than its telemetry value.
:: Uncomment if you don't use either:
:: call :SetReg "HKLM\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors" "DisableLocation" REG_DWORD 1

:: Legacy CEIP switch (some components still check this)
call :SetReg "HKLM\SOFTWARE\Policies\Microsoft\SQMClient\Windows" "CEIPEnable" REG_DWORD 0

:: Suggested apps / consumer features (Start menu ads, "app suggestions")
call :SetReg "HKLM\SOFTWARE\Policies\Microsoft\Windows\CloudContent" "DisableWindowsConsumerFeatures" REG_DWORD 1

:: Windows Spotlight lock-screen slideshow (fetches images/promo content online)
call :SetReg "HKLM\SOFTWARE\Policies\Microsoft\Windows\Personalization" "NoLockScreenSlideshow" REG_DWORD 1

:: Input personalization - stops typing/inking data from being used to
:: improve predictive text and handwriting recognition (the machine-wide
:: switch; per-user implicit-collection settings are applied in
:: :ApplyHKCU below)
call :SetReg "HKLM\SOFTWARE\Policies\Microsoft\InputPersonalization" "AllowInputPersonalization" REG_DWORD 0

:: Game DVR/background recording - irrelevant on this device
call :SetReg "HKLM\SOFTWARE\Policies\Microsoft\Windows\GameDVR" "AllowGameDVR" REG_DWORD 0

:: Application Compatibility telemetry - policy-level equivalent of what the
:: Compatibility Appraiser scheduled task does; complements leaving PcaSvc
:: running (service stays available for legacy shims, but its telemetry/
:: notification behavior is switched off here).
call :SetReg "HKLM\SOFTWARE\Policies\Microsoft\Windows\AppCompat" "AITEnable" REG_DWORD 0
call :SetReg "HKLM\SOFTWARE\Policies\Microsoft\Windows\AppCompat" "DisableInventory" REG_DWORD 1
call :SetReg "HKLM\SOFTWARE\Policies\Microsoft\Windows\AppCompat" "DisablePCA" REG_DWORD 1

:: Stopping DiagTrack blocks the transport of telemetry off this machine,
:: but the Event Tracing for Windows (ETW) infrastructure that FEEDS it
:: keeps buffering data locally regardless - AutoLogger-Diagtrack-Listener
:: starts very early in boot (before services like DiagTrack even start)
:: and keeps writing local .etl trace files. This stops it from
:: autostarting, and removes the historical trace files already on disk.
echo.
echo === AutoLogger / ETW Cleanup ===
echo [%DATE% %TIME%] === AutoLogger === >> "%LOGFILE%"
call :SetReg "HKLM\SYSTEM\CurrentControlSet\Control\WMI\Autologger\AutoLogger-Diagtrack-Listener" "Start" REG_DWORD 0
:: NOTE: unlike everything else in this script, this next line deletes
:: files rather than changing the registry - there is no rollback for it.
:: Comment it out if you'd rather keep the existing trace files.
del /F /Q "%ProgramData%\Microsoft\Diagnosis\ETLLogs\AutoLogger\*.etl" >nul 2>&1
echo   [ OK ] Cleared existing AutoLogger .etl trace files ^(not reversible^)
echo   [ OK ] Cleared existing AutoLogger .etl trace files >> "%LOGFILE%"
echo echo [NOTE] AutoLogger .etl trace files from the original run were permanently deleted and cannot be restored by this rollback. >> "%ROLLBACK_BAT%"
set /a OK+=1

:: NOTE: Windows Defender cloud-delivered protection (MAPS/SpyNet) is
:: intentionally left untouched per your choice, since this device has
:: no other real-time antivirus. Nothing to do here.

echo.
if %EDGE_INSTALLED%==1 (
echo === Microsoft Edge Telemetry ^(machine-wide, all users^) ===
echo [%DATE% %TIME%] === Edge Policies === >> "%LOGFILE%"

REM Disable usage/crash statistics sent to Microsoft
call :SetReg "HKLM\SOFTWARE\Policies\Microsoft\Edge" "MetricsReportingEnabled" REG_DWORD 0
REM Disable "help improve Microsoft products by sending data about the sites you visit"
call :SetReg "HKLM\SOFTWARE\Policies\Microsoft\Edge" "SendSiteInfoToImproveServices" REG_DWORD 0
REM Disable use of diagnostic data for personalized content/ads within Edge
call :SetReg "HKLM\SOFTWARE\Policies\Microsoft\Edge" "PersonalizationReportingEnabled" REG_DWORD 0
REM Disable the built-in feedback/Send a Smile surveys
call :SetReg "HKLM\SOFTWARE\Policies\Microsoft\Edge" "UserFeedbackAllowed" REG_DWORD 0
REM Send the Do Not Track request header on outgoing traffic
call :SetReg "HKLM\SOFTWARE\Policies\Microsoft\Edge" "ConfigureDoNotTrack" REG_DWORD 1
REM Disable Shopping Assistant - price tracking/coupon feature that phones home
call :SetReg "HKLM\SOFTWARE\Policies\Microsoft\Edge" "EdgeShoppingAssistantEnabled" REG_DWORD 0
REM Additional Edge feature toggles, not core telemetry but low risk
call :SetReg "HKLM\SOFTWARE\Policies\Microsoft\Edge" "EdgeCollectionsEnabled" REG_DWORD 0
call :SetReg "HKLM\SOFTWARE\Policies\Microsoft\Edge" "MicrosoftEdgeInsiderPromotionEnabled" REG_DWORD 0
call :SetReg "HKLM\SOFTWARE\Policies\Microsoft\Edge" "EdgeFollowEnabled" REG_DWORD 0
REM Startup Boost keeps an Edge process pre-launched/running in the
REM background even after you close all windows, for faster next-launch -
REM disabling stops that background presence and its network activity
call :SetReg "HKLM\SOFTWARE\Policies\Microsoft\Edge" "StartupBoostEnabled" REG_DWORD 0
REM Background Mode lets installed Edge extensions/PWAs keep running after
REM you close the browser window - disabling stops that too
call :SetReg "HKLM\SOFTWARE\Policies\Microsoft\Edge" "BackgroundModeEnabled" REG_DWORD 0
REM Skips the first-run welcome/import wizard. Note: per Microsoft's own
REM docs, Edge still auto-signs in with an AAD/MSA-type Windows account
REM regardless of this setting - hiding first-run doesn't prevent that,
REM it just skips the prompts, which is why the other Edge policies above
REM (DoNotTrack, PersonalizationReporting, etc.) still apply independently.
call :SetReg "HKLM\SOFTWARE\Policies\Microsoft\Edge" "HideFirstRunExperience" REG_DWORD 1
REM Enhance Images: when on, Edge sends image URLs from pages you visit to
REM Microsoft's servers for AI-based sharpening. Verified real policy, but
REM Microsoft marked it OBSOLETE as of Edge 121/122 - harmless to set, may
REM simply have no effect if your Edge is already past that version.
call :SetReg "HKLM\SOFTWARE\Policies\Microsoft\Edge" "EdgeEnhanceImagesEnabled" REG_DWORD 0
REM Search bar / "Web Widget" floating desktop widget. Verified real policy
REM name is WebWidgetAllowed (not WebWidgetEnabled) - Microsoft's docs mark
REM this one deprecated too, same caveat as above applies.
call :SetReg "HKLM\SOFTWARE\Policies\Microsoft\Edge" "WebWidgetAllowed" REG_DWORD 0
) else (
echo   [SKIP] Microsoft Edge ^(Chromium^) not installed - skipping Edge policies.
echo   [SKIP] Edge not installed. >> "%LOGFILE%"
set /a SKIP+=1
)

echo.
if %OFFICE_INSTALLED%==1 (
echo === Microsoft Office Telemetry ^(machine-wide, all users - Office 16.0^) ===
echo [%DATE% %TIME%] === Office Policies === >> "%LOGFILE%"
echo   NOTE: 16.0 covers Office 2016/2019/2021/2024 LTSC/365. >> "%LOGFILE%"

REM Master telemetry switch used by the Office telemetry agent
call :SetReg "HKLM\SOFTWARE\Policies\Microsoft\office\16.0\common\clienttelemetry" "DisableTelemetry" REG_DWORD 1
REM Legacy Office Telemetry Dashboard agent - stop local logging and upload
call :SetReg "HKLM\SOFTWARE\Policies\Microsoft\office\16.0\osm" "EnableLogging" REG_DWORD 0
call :SetReg "HKLM\SOFTWARE\Policies\Microsoft\office\16.0\osm" "EnableUpload" REG_DWORD 0
REM Disable in-app feedback / Feedback to Microsoft surveys
call :SetReg "HKLM\SOFTWARE\Policies\Microsoft\office\16.0\common\feedback" "Enabled" REG_DWORD 0
REM Disable optional Connected Experiences that analyze your content in the cloud
call :SetReg "HKLM\SOFTWARE\Policies\Microsoft\office\16.0\common\privacy" "UserContentDisabled" REG_DWORD 1
REM Disable optional Connected Experiences that download online content - templates, stock images, etc.
call :SetReg "HKLM\SOFTWARE\Policies\Microsoft\office\16.0\common\privacy" "DownloadContentDisabled" REG_DWORD 1
REM Disable all other optional Connected Experiences - translation, map charts, etc.
call :SetReg "HKLM\SOFTWARE\Policies\Microsoft\office\16.0\common\privacy" "ControllerConnectedServicesEnabled" REG_DWORD 0
REM Disable LinkedIn integration
call :SetReg "HKLM\SOFTWARE\Policies\Microsoft\office\16.0\common" "EnableLinkedIn" REG_DWORD 0
REM NOTE: "DisableAAD" and "DisconnectedState" were deliberately removed here.
REM The real, documented registry values for suppressing Azure AD sign-in in
REM Office are DisableAADWAM / DisableMSAWAM under
REM HKCU\Software\Microsoft\Office\16.0\Common\Identity - an unsupported
REM Microsoft workaround, not a Group Policy setting, and not something to
REM apply blindly since it can break Office activation/sign-in on installs
REM licensed through a work or school account.
) else (
echo   [SKIP] Office 16.0 not installed - skipping Office policies.
echo   [SKIP] Office not installed. >> "%LOGFILE%"
set /a SKIP+=1
)

echo.

:: === OneDrive Blocking ===
echo === OneDrive Blocking ===
echo [%DATE% %TIME%] === OneDrive === >> "%LOGFILE%"
call :SetReg "HKLM\SOFTWARE\Policies\Microsoft\OneDrive" "DisableFileSyncNGSC" REG_DWORD 1
call :SetReg "HKLM\SOFTWARE\Policies\Microsoft\Windows\OneDrive" "DisableFileSyncNGSC" REG_DWORD 1
echo.

:: === Additional Consumer Services ===
:: Kept: Wallet and PushToInstall - low risk, no legitimate use on this device.
:: Deliberately NOT touched: CDPSvc, OneSyncSvc, UnistoreSvc, UserDataSvc.
:: These aren't telemetry channels - they're the plumbing behind Mail/
:: Calendar/People app sync, Timeline/notification history, clipboard sync,
:: Nearby Sharing, and Phone Link. Disable them yourself only if you're
:: certain you don't use any of those features.
:: Also NOT touched: SysMain (app launch speed) and WSearch (Explorer/
:: Start menu search), for the same reason.
echo === Additional Consumer Services ===
echo [%DATE% %TIME%] === Extra Services === >> "%LOGFILE%"
call :StopDisableSvc WalletService
call :StopDisableSvc PushToInstall
echo.

echo === Disabling Telemetry-related Scheduled Tasks ===
echo [%DATE% %TIME%] === Scheduled Tasks === >> "%LOGFILE%"
call :DisableTask "\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser"
call :DisableTask "\Microsoft\Windows\Application Experience\ProgramDataUpdater"
call :DisableTask "\Microsoft\Windows\Autochk\Proxy"
call :DisableTask "\Microsoft\Windows\Customer Experience Improvement Program\Consolidator"
call :DisableTask "\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip"
call :DisableTask "\Microsoft\Windows\Feedback\Siuf\DmClient"
call :DisableTask "\Microsoft\Windows\Feedback\Siuf\DmClientOnScenarioDownload"
call :DisableTask "\Microsoft\Windows\Windows Error Reporting\QueueReporting"
call :DisableTask "\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector"
:: Office LTSC 2021/2024 are Click-to-Run installs; this task runs daily
:: and reports Click-to-Run crash/error logs to Microsoft.
call :DisableTask "\Microsoft\Office\Office ClickToRun Service Monitor"
:: Additional telemetry-related tasks
call :DisableTask "\Microsoft\Windows\Application Experience\StartupAppTask"
call :DisableTask "\Microsoft\Windows\Customer Experience Improvement Program\BthSQM"
:: Note: this last one is a local powercfg /energy-style diagnostic report,
:: not a telemetry uploader - harmless to disable, just not technically
:: "telemetry" in the same sense as the others.
call :DisableTask "\Microsoft\Windows\Power Efficiency Diagnostics\AnalyzeSystem"
:: Background syncing of Windows settings to the cloud via a Microsoft
:: Account - complements the per-user SettingSync\SyncPolicy value set
:: in :ApplyHKCU below with a machine-wide task-level block
call :DisableTask "\Microsoft\Windows\SettingSync\BackgroundUploadTask"
:: Kernel-level CEIP task - gathers hardware/driver telemetry, sibling of
:: the Consolidator/UsbCeip/BthSQM tasks already disabled above
call :DisableTask "\Microsoft\Windows\Customer Experience Improvement Program\KernelCeipTask"
echo.

:: ================================================================
:: Per-user (HKCU) settings - applied to EVERY local profile
:: ================================================================
echo === Applying per-user privacy settings to ALL local profiles ===
echo [%DATE% %TIME%] === Per-user settings === >> "%LOGFILE%"

:: -- current interactive user (already-mounted HKCU) --
:: NOTE: if this script is run via "Run as Administrator" using a
:: different account than the one you're logged in as, HKCU here refers
:: to the ADMIN account's profile, not the standard user's - the standard
:: user's profile still gets covered by the loop below (their NTUSER.DAT
:: is loaded and modified offline), but they won't see the changes take
:: effect until they log out and back in, releasing the registry locks
:: held by their active session.
call :ApplyHKCU "HKCU"

:: -- every other profile on disk: load its hive temporarily --
for /d %%D in ("%SystemDrive%\Users\*") do (
    set "PROFNAME=%%~nxD"
    if /I not "!PROFNAME!"=="Public" if /I not "!PROFNAME!"=="Default" if /I not "!PROFNAME!"=="Default User" if /I not "!PROFNAME!"=="All Users" if /I not "!PROFNAME!"=="%USERNAME%" (
        if exist "%%D\NTUSER.DAT" (
            reg load "HKU\TempHive_!PROFNAME!" "%%D\NTUSER.DAT" >nul 2>&1
            if errorlevel 1 (
                echo   [SKIP] !PROFNAME! - hive is in use ^(user logged in^) or inaccessible.
                echo   [SKIP] !PROFNAME! hive load failed >> "%LOGFILE%"
                set /a SKIP+=1
            ) else (
                echo   Applying settings to profile: !PROFNAME!
                call :ApplyHKCU "HKU\TempHive_!PROFNAME!"
                reg unload "HKU\TempHive_!PROFNAME!" >nul 2>&1
                if errorlevel 1 (
                    echo   [WARN] Could not unload hive for !PROFNAME! cleanly ^(will release on reboot^)
                )
            )
        )
    )
)
echo.

:: Harden the Default user profile template too. Without this, only
:: accounts that already exist get the per-user settings above - anyone
:: who logs into this machine for the first time AFTER this script runs
:: would otherwise inherit Microsoft's un-hardened defaults, since Windows
:: builds every new profile from C:\Users\Default\NTUSER.DAT. Handled as
:: its own step (rather than just removing it from the exclusion list
:: above) so it's clearly logged and isn't double-processed by that loop.
echo   Applying settings to profile: Default ^(template for future accounts^)
reg load "HKU\TempHive_DefaultTemplate" "%SystemDrive%\Users\Default\NTUSER.DAT" >nul 2>&1
if errorlevel 1 (
    echo   [SKIP] Default profile hive is in use or inaccessible.
    echo   [SKIP] Default profile hive load failed >> "%LOGFILE%"
    set /a SKIP+=1
) else (
    call :ApplyHKCU "HKU\TempHive_DefaultTemplate"
    reg unload "HKU\TempHive_DefaultTemplate" >nul 2>&1
    if errorlevel 1 (
        echo   [WARN] Could not unload Default profile hive cleanly ^(will release on reboot^)
    )
)
echo.

:: Final cleanup pass: attempt to unload any TempHive_* hives that may
:: still be mounted from a transient lock earlier in the run (e.g. an
:: antivirus scan briefly holding a handle on the file at load time).
:: tokens=* (not tokens=1) is required here - a username containing a
:: space (e.g. "TempHive_John Doe") would otherwise get truncated at the
:: space by default for/f word-splitting, producing an incomplete key
:: path that reg unload would silently fail to match.
for /f "tokens=*" %%k in ('reg query HKU 2^>nul ^| findstr /i "TempHive_"') do (
    set "LEFTOVER=%%k"
    set "LEFTOVER=!LEFTOVER:HKEY_USERS=HKU!"
    reg unload "!LEFTOVER!" >nul 2>&1
    if not errorlevel 1 (
        echo   [OK] Cleaned up orphaned hive: !LEFTOVER!
        echo   [OK] Cleaned up orphaned hive: !LEFTOVER! >> "%LOGFILE%"
    )
)
echo.

:: Finalize rollback script
echo echo. >> "%ROLLBACK_BAT%"
echo echo Rollback complete. A reboot is recommended. >> "%ROLLBACK_BAT%"
echo pause >> "%ROLLBACK_BAT%"

:: ---------------------- Rollback integrity check -------------------------
:: New in 1.6.0. Rollback entries are written incrementally to
:: %ROLLBACK_BAT% throughout the run (as each change is made), rather than
:: assembled in memory and written once at the end. That design is
:: intentional and is being kept: if this script were ever interrupted
:: partway through (power loss, forced termination, etc.), an
:: end-of-run-only rollback file would contain NOTHING, even for changes
:: already made - whereas the incremental file already on disk always
:: reflects everything done so far. Rewriting this as a single atomic
:: write-at-the-end would trade that crash-safety away for no real benefit.
:: What this block adds instead is a sanity check on the rollback file
:: actually produced: confirms it exists, is non-empty, still ends with
:: the completion lines just written above (i.e. wasn't truncated by a
:: disk-space or antivirus issue partway through the run), and reports how
:: many revert actions it contains relative to the %OK% counter.
set "RB_STATUS=OK"
set "RB_ACTIONCOUNT=0"
if not exist "%ROLLBACK_BAT%" (
    set "RB_STATUS=MISSING"
) else (
    for %%f in ("%ROLLBACK_BAT%") do if %%~zf==0 set "RB_STATUS=EMPTY"
    findstr /C:"Rollback complete" "%ROLLBACK_BAT%" >nul 2>&1
    if errorlevel 1 set "RB_STATUS=TRUNCATED"
    for /f %%c in ('findstr /R /C:"^reg import" /C:"^reg delete" /C:"^sc config" /C:"^schtasks /change" "%ROLLBACK_BAT%" 2^>nul ^| find /c /v ""') do set "RB_ACTIONCOUNT=%%c"
)
if /I "!RB_STATUS!"=="OK" (
    echo   [OK] Rollback script integrity check passed ^(!RB_ACTIONCOUNT! revert actions recorded^).
    echo [%DATE% %TIME%] Rollback integrity check: OK - !RB_ACTIONCOUNT! revert actions recorded >> "%LOGFILE%"
) else (
    echo   [WARN] Rollback script integrity check: !RB_STATUS! - see log. Do NOT rely on
    echo   [WARN] rollback_privacy.bat until this is investigated.
    echo [%DATE% %TIME%] [WARN] Rollback integrity check failed: !RB_STATUS! >> "%LOGFILE%"
    set /a FAIL+=1
)
echo.

echo === Quick Verification ===
echo [%DATE% %TIME%] === Quick Verification === >> "%LOGFILE%"
for /f "tokens=3" %%v in ('reg query "HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection" /v AllowTelemetry 2^>nul ^| findstr /i "AllowTelemetry"') do echo   AllowTelemetry policy is now: %%v
sc query DiagTrack 2>nul | findstr /i "STATE" | findstr /i "STOPPED" >nul
if not errorlevel 1 (echo   DiagTrack service: stopped) else (echo   DiagTrack service: NOT stopped - check log)
echo   ^(Spot-check only - every individual change has its own [OK]/[FAIL] entry above and in the log^)
echo.

echo === Intentionally Left Alone ===
echo   PcaSvc               - may be needed for legacy app compatibility
echo   Location Services    - Night Light and Weather app depend on it
echo   SysMain / WSearch    - app launch speed / Explorer and Start search
echo   Defender cloud (MAPS/SpyNet) - no other real-time AV on this device
echo   CDPSvc / OneSyncSvc / UnistoreSvc / UserDataSvc - Mail/Calendar/People
echo                          sync, Timeline, clipboard sync, Nearby Share, Phone Link
echo   BITS / wuauserv      - Windows Update delivery, not telemetry
echo [%DATE% %TIME%] === Intentionally Left Alone === >> "%LOGFILE%"
echo PcaSvc, Location Services, SysMain, WSearch, Defender cloud protection, >> "%LOGFILE%"
echo CDPSvc, OneSyncSvc, UnistoreSvc, UserDataSvc, BITS, wuauserv >> "%LOGFILE%"
echo.

echo === Privacy Lockdown Complete ^(v%SCRIPT_VERSION%^) ===
echo.
echo   Registry keys backed up to : %REGBACKUP%
echo   Rollback script generated  : %ROLLBACK_BAT% ^(integrity: !RB_STATUS!^)
echo   Full log written to        : %LOGFILE%
echo   Successful changes         : %OK%
echo   Failed changes              : %FAIL%
echo   Skipped ^(not applicable^)  : %SKIP%
echo.
echo A reboot is recommended to fully apply service and scheduled-task changes.
echo Per-user settings for profiles other than the one running this script
echo take effect the next time each of those users logs on - they were
echo applied offline to their NTUSER.DAT and won't show up in an already-open
echo session for them.
echo To undo everything this script did, run "%ROLLBACK_BAT%" as Administrator.
echo [%DATE% %TIME%] === SUMMARY === >> "%LOGFILE%"
echo OK=%OK% FAIL=%FAIL% SKIP=%SKIP% >> "%LOGFILE%"
if not defined QUIET pause
exit /b 0

:: ================================================================
:ApplyHKCU
:: %1 = hive root, either "HKCU" or "HKU\TempHive_<n>"
set "H=%~1"

call :SetReg "%H%\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo" "Enabled" REG_DWORD 0
call :SetReg "%H%\Software\Microsoft\Windows\CurrentVersion\Privacy" "TailoredExperiencesWithDiagnosticDataEnabled" REG_DWORD 0
call :SetReg "%H%\Software\Microsoft\Windows\CurrentVersion\Explorer\Advertising Info" "Enabled" REG_DWORD 0
call :SetReg "%H%\Software\Microsoft\Windows\CurrentVersion\Search" "BingSearchEnabled" REG_DWORD 0
call :SetReg "%H%\Software\Microsoft\Windows\CurrentVersion\Search" "CortanaConsent" REG_DWORD 0
call :SetReg "%H%\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "Start_TrackProgs" REG_DWORD 0
call :SetReg "%H%\Software\Microsoft\Windows\CurrentVersion\SettingSync" "SyncPolicy" REG_DWORD 5
call :SetReg "%H%\Software\Microsoft\Windows\CurrentVersion\Explorer" "ShowSyncProviderNotifications" REG_DWORD 0
call :SetReg "%H%\Software\Policies\Microsoft\Windows\Explorer" "DisableSearchBoxSuggestions" REG_DWORD 1
:: Per-user counterpart to the HKLM AllowInputPersonalization policy - stops
:: "getting to know you" typing/inking data collection for this account
call :SetReg "%H%\Software\Microsoft\InputPersonalization" "RestrictImplicitTextCollection" REG_DWORD 1
call :SetReg "%H%\Software\Microsoft\InputPersonalization" "RestrictImplicitInkCollection" REG_DWORD 1
:: DisableFileSyncNGSC (set machine-wide earlier) stops OneDrive from
:: actually syncing anything, but doesn't stop OneDrive.exe from still
:: trying to auto-launch at every logon via this Run entry - removing it
:: stops the pointless launch attempt. This is narrower than fully
:: uninstalling OneDrive (which was intentionally left out of this script
:: earlier): it only stops auto-start, it doesn't remove the app itself.
:: Reuses EnsureKeyBackedUp on the Run key first, so the existing
:: key-level rollback (reg import of the whole key) restores this value
:: automatically if rollback is ever run - no separate rollback logic
:: needed for this deletion.
call :EnsureKeyBackedUp "%H%\Software\Microsoft\Windows\CurrentVersion\Run"
reg query "%H%\Software\Microsoft\Windows\CurrentVersion\Run" /v "OneDrive" >nul 2>&1
if not errorlevel 1 (
    reg delete "%H%\Software\Microsoft\Windows\CurrentVersion\Run" /v "OneDrive" /f >> "%LOGFILE%" 2>&1
    if errorlevel 1 (
        echo   [FAIL] Could not remove OneDrive auto-start entry
        set /a FAIL+=1
    ) else (
        echo   [ OK ] Removed OneDrive auto-start entry from Run key
        set /a OK+=1
    )
) else (
    echo   [SKIP] No OneDrive auto-start entry found for this profile
    set /a SKIP+=1
)
exit /b 0
