param([string]$Compiler = '')
$ErrorActionPreference = 'Stop'
$workspace = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$versionMatch = [regex]::Match((Get-Content -LiteralPath (Join-Path $workspace 'pubspec.yaml') -Raw), '(?m)^version:\s*(\d+\.\d+\.\d+)\+\d+\s*$')
if (-not $versionMatch.Success) { throw 'Cannot read application version.' }
$appVersion = $versionMatch.Groups[1].Value
if (-not $Compiler) {
    $candidates = @(
        (Join-Path $workspace '.research\tooling\InnoSetup\ISCC.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 7\ISCC.exe'),
        (Join-Path $env:ProgramFiles 'Inno Setup 7\ISCC.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 7\ISCC.exe')
    )
    $Compiler = $candidates | Where-Object {Test-Path -LiteralPath $_} | Select-Object -First 1
}
if (-not $Compiler -or -not (Test-Path -LiteralPath $Compiler)) { throw 'Install Inno Setup 7, or pass -Compiler with the absolute path to ISCC.exe.' }
$packagePath = Join-Path $workspace "dist\CiliCiliWinRev-$appVersion-windows-x64"
if (-not (Test-Path -LiteralPath (Join-Path $packagePath 'CiliCiliWinRev.exe'))) { throw 'Run tools/build_windows.ps1 first.' }
$outputPath = Join-Path $workspace 'dist'
& $Compiler "/DAppVersion=$appVersion" "/DPackageDir=$packagePath" "/DOutputDir=$outputPath" (Join-Path $PSScriptRoot 'windows_installer.iss')
if ($LASTEXITCODE -ne 0) { throw 'Installer compilation failed.' }
$installerPath = Join-Path $outputPath "CiliCiliWinRev-$appVersion-windows-x64-setup.exe"
$hash = (Get-FileHash -LiteralPath $installerPath -Algorithm SHA256).Hash.ToLowerInvariant()
"$hash  $([IO.Path]::GetFileName($installerPath))" | Set-Content -LiteralPath "$installerPath.sha256" -Encoding utf8
Write-Output "Installer: $installerPath"
Write-Output "SHA256: $hash"
