param([string]$FlutterSdk = '')
$ErrorActionPreference = 'Stop'
$workspace = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Set-Location -LiteralPath $workspace
if ($FlutterSdk) {
    $flutterCommand = Join-Path $FlutterSdk 'bin\flutter.bat'
} else {
    $flutterCommand = (Get-Command flutter -ErrorAction Stop).Source
}
& $flutterCommand pub get
if ($LASTEXITCODE -ne 0) { throw 'Dependency resolution failed.' }
& $flutterCommand analyze
if ($LASTEXITCODE -ne 0) { throw 'Static analysis failed.' }
& $flutterCommand test
if ($LASTEXITCODE -ne 0) { throw 'Tests failed.' }
& $flutterCommand build windows --release
if ($LASTEXITCODE -ne 0) { throw 'Windows release build failed.' }
& (Join-Path $PSScriptRoot 'package_windows.ps1')
