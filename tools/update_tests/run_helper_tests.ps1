param([string]$Mode = 'success')
$ErrorActionPreference = 'Stop'
$taskWorkspace = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$taskRoot = Join-Path $taskWorkspace ('.research/helper-test-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + $Mode)
$taskRegistry = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\{45685E6E-62BA-4C30-90E7-B1F8D77EE247}_is1'
$taskGroup = 'CiliCiliWinRev Installer Verification'
$taskMenu = Join-Path ([Environment]::GetFolderPath('Programs')) $taskGroup
if ((Test-Path -LiteralPath $taskRegistry) -or (Test-Path -LiteralPath $taskMenu)) { throw 'Existing isolated QA installation must not be replaced.' }
if ($Mode -notin @('success', 'cancel', 'no-commit', 'bad-hash', 'wrong-version', 'install-failure')) { throw 'Unknown test mode.' }
$taskAppDir = Join-Path $taskRoot 'application'
$taskCache = Join-Path $taskRoot 'download'
New-Item -ItemType Directory -Path $taskAppDir,$taskCache -Force | Out-Null
$taskProbe = Join-Path $taskWorkspace '.research/update-native-new/Release/CiliCiliWinRev.exe'
$taskApp = Join-Path $taskAppDir 'CiliCiliWinRev.exe'
Copy-Item -LiteralPath $taskProbe -Destination $taskApp
$taskHelper = Join-Path $taskCache 'CiliCiliWinRevUpdater.exe'
Copy-Item -LiteralPath (Join-Path $taskWorkspace 'dist/CiliCiliWinRev-0.7.0-windows-x64/CiliCiliWinRevUpdater.exe') -Destination $taskHelper
$taskInstaller = Join-Path $taskCache 'setup.exe'
$taskReport = Join-Path $taskRoot 'parent-report.txt'
$taskRestarted = Join-Path $taskAppDir 'restarted.txt'
$taskSettings = Join-Path $taskRoot 'isolated-settings.json'
'{"session":"fixture","accent":"teal","history":[{"position":321}]}' | Set-Content -LiteralPath $taskSettings -Encoding utf8
$taskSettingsHash = (Get-FileHash -LiteralPath $taskSettings).Hash
$taskSummary = [ordered]@{mode=$Mode; root=$taskRoot; ready=$false; restarted=$false; installerDeleted=$false; installerRetained=$false; dataPreserved=$false; helperExit=$null; accountSessionRead=$false}
try {
    if ($Mode -eq 'success') {
        $taskOldSetup = Join-Path $taskWorkspace '.research/installer-qa-build/CiliCiliWinRev-0.6.1-windows-x64-setup.exe'
        $taskOldArgs = @('/SP-', '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/NOCLOSEAPPLICATIONS', '/TASKS=""', ('/DIR="{0}"' -f $taskAppDir), ('/GROUP="{0}"' -f $taskGroup), ('/LOG="{0}"' -f (Join-Path $taskRoot 'old-install.log')))
        $taskOldProcess = Start-Process -FilePath $taskOldSetup -ArgumentList $taskOldArgs -WindowStyle Hidden -Wait -PassThru
        if ($taskOldProcess.ExitCode -ne 0) { throw 'Old QA installation failed.' }
        # Replace only the QA executable, preventing any daily session loading.
        Copy-Item -LiteralPath $taskProbe -Destination $taskApp -Force
        Copy-Item -LiteralPath (Join-Path $taskWorkspace '.research/helper-qa-build/CiliCiliWinRev-0.7.0-windows-x64-setup.exe') -Destination $taskInstaller
    } elseif ($Mode -eq 'install-failure') {
        Copy-Item -LiteralPath $taskProbe -Destination $taskInstaller
    } else {
        Copy-Item -LiteralPath (Join-Path $taskWorkspace 'dist/CiliCiliWinRev-0.7.0-windows-x64-setup.exe') -Destination $taskInstaller
    }
    $taskDigest = (Get-FileHash -LiteralPath $taskInstaller -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($Mode -eq 'bad-hash') { $taskDigest = '0' * 64 }
    $taskVersion = if ($Mode -eq 'wrong-version') {'0.7.1'} else {'0.7.0'}
    $taskAction = if ($Mode -in @('success','install-failure')) {'commit'} elseif ($Mode -eq 'cancel') {'cancel'} else {'no-commit'}
    & $taskApp --helper $taskHelper --installer $taskInstaller --sha256 $taskDigest --version $taskVersion --mode $taskAction --report $taskReport
    $taskDeadline = (Get-Date).AddSeconds(15)
    while (-not (Test-Path -LiteralPath $taskReport) -and (Get-Date) -lt $taskDeadline) { Start-Sleep -Milliseconds 100 }
    if (-not (Test-Path -LiteralPath $taskReport)) { throw 'Parent fixture produced no report.' }
    $taskReportText = Get-Content -LiteralPath $taskReport -Raw
    $taskSummary.ready = $taskReportText -match '(?m)^ready\r?$'
    $taskPid = [int]([regex]::Match($taskReportText,'helperPid=(\d+)').Groups[1].Value)
    $taskHelperProcess = Get-Process -Id $taskPid -ErrorAction SilentlyContinue
    if ($taskHelperProcess) {
        if (-not $taskHelperProcess.WaitForExit(60000)) { throw "Helper still running. Root: $taskRoot" }
        $taskSummary.helperExit = $taskHelperProcess.ExitCode
    }
    if ($Mode -in @('bad-hash','wrong-version')) {
        if ($taskSummary.ready -or -not $taskReportText.Contains('rejected=4')) { throw 'Invalid payload was not rejected before readiness.' }
    } elseif (-not $taskSummary.ready) { throw 'Valid payload never reached readiness.' }
    $taskDeadline = (Get-Date).AddSeconds(10)
    if ($Mode -in @('success','install-failure')) {
        while (-not (Test-Path -LiteralPath $taskRestarted) -and (Get-Date) -lt $taskDeadline) { Start-Sleep -Milliseconds 100 }
        if (-not (Test-Path -LiteralPath $taskRestarted)) { throw 'Application did not restart.' }
        $taskSummary.restarted = $true
    } elseif (Test-Path -LiteralPath $taskRestarted) { throw 'Unexpected application restart.' }
    $taskSummary.installerDeleted = -not (Test-Path -LiteralPath $taskInstaller)
    $taskSummary.installerRetained = Test-Path -LiteralPath $taskInstaller
    if ($Mode -in @('success','cancel','no-commit') -and -not $taskSummary.installerDeleted) { throw 'Installer was not deleted.' }
    if ($Mode -eq 'install-failure' -and -not $taskSummary.installerRetained) { throw 'Failed installer was not retained.' }
    if ($Mode -in @('success','install-failure')) {
        $taskInstallLog = Get-Content -LiteralPath (Join-Path $taskCache 'install.log') -Raw
        $taskExpectedCode = if ($Mode -eq 'success') {'0'} else {'42'}
        if ($taskInstallLog -notmatch "installerLaunched=1 exitCode=$taskExpectedCode(?:\r?\n|$)") { throw 'Installer result log does not match the expected exit code.' }
        $taskSummary.installerExit = [int]$taskExpectedCode
    }
    if ($Mode -eq 'success') {
        $taskEntry = Get-ItemProperty -LiteralPath $taskRegistry
        if ($taskEntry.DisplayVersion -ne '0.7.0' -or $taskEntry.InstallLocation.TrimEnd('\') -ne $taskAppDir) { throw 'Upgrade version/directory incorrect.' }
        $taskPackage = Join-Path $taskWorkspace '.research/helper-qa-package'
        $taskCount = 0
        foreach ($taskFile in (Get-ChildItem -LiteralPath $taskPackage -Recurse -File)) {
            $taskRelative = [IO.Path]::GetRelativePath($taskPackage,$taskFile.FullName)
            if ((Get-FileHash -LiteralPath $taskFile.FullName).Hash -ne (Get-FileHash -LiteralPath (Join-Path $taskAppDir $taskRelative)).Hash) { throw "Installed file mismatch: $taskRelative" }
            $taskCount++
        }
        $taskSummary.filesVerified = $taskCount
    }
} finally {
    $taskUninstaller = Join-Path $taskAppDir 'unins000.exe'
    if (Test-Path -LiteralPath $taskUninstaller) {
        $taskUninstall = Start-Process -FilePath $taskUninstaller -ArgumentList @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART') -WindowStyle Hidden -Wait -PassThru
        if ($taskUninstall.ExitCode -ne 0) { throw 'QA uninstall failed.' }
    }
    $taskSummary.dataPreserved = (Get-FileHash -LiteralPath $taskSettings).Hash -eq $taskSettingsHash
    $taskSummary | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $taskRoot 'result.json') -Encoding utf8
    Write-Output ($taskSummary | ConvertTo-Json -Compress)
}
