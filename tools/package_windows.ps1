param()
$ErrorActionPreference = 'Stop'
$workspace = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$versionMatch = [regex]::Match((Get-Content -LiteralPath (Join-Path $workspace 'pubspec.yaml') -Raw), '(?m)^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$')
if (-not $versionMatch.Success) { throw 'Cannot read application version.' }
$appVersion = $versionMatch.Groups[1].Value
$buildNumber = $versionMatch.Groups[2].Value
$releasePath = Join-Path $workspace 'build\windows\x64\runner\Release'
$executable = Join-Path $releasePath 'CiliCiliWinRev.exe'
if (-not (Test-Path -LiteralPath $executable)) { throw 'Build the Windows release first.' }
$versionInfo = [Diagnostics.FileVersionInfo]::GetVersionInfo($executable)
$fileVersion = "$($versionInfo.FileMajorPart).$($versionInfo.FileMinorPart).$($versionInfo.FileBuildPart).$($versionInfo.FilePrivatePart)"
if ($fileVersion -ne "$appVersion.$buildNumber") { throw "Release version $fileVersion does not match $appVersion.$buildNumber" }
$packagePath = Join-Path $workspace "dist\CiliCiliWinRev-$appVersion-windows-x64"
New-Item -ItemType Directory -Path $packagePath -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $releasePath 'data') -Destination $packagePath -Recurse -Force
Get-ChildItem -LiteralPath $releasePath -File | Where-Object {$_.Extension -ne '.exe'} | Copy-Item -Destination $packagePath -Force
Copy-Item -LiteralPath $executable -Destination (Join-Path $packagePath 'CiliCiliWinRev.exe') -Force
Copy-Item -LiteralPath (Join-Path $workspace 'README.md') -Destination $packagePath -Force
Copy-Item -LiteralPath (Join-Path $workspace 'docs\THIRD_PARTY_NOTICES.md') -Destination $packagePath -Force
$packageDocs = Join-Path $packagePath 'docs'
New-Item -ItemType Directory -Path $packageDocs -Force | Out-Null
foreach ($document in @('architecture.md', 'verification.md', 'THIRD_PARTY_NOTICES.md', 'updates.md')) {
    Copy-Item -LiteralPath (Join-Path $workspace "docs\$document") -Destination $packageDocs -Force
}
foreach ($required in @('CiliCiliWinRev.exe', 'flutter_windows.dll', 'libmpv-2.dll', 'msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll', 'data\icudtl.dat', 'data\flutter_assets\AssetManifest.bin')) {
    if (-not (Test-Path -LiteralPath (Join-Path $packagePath $required))) { throw "Package is missing $required" }
}
$archivePath = "$packagePath.zip"
Compress-Archive -Path (Join-Path $packagePath '*') -DestinationPath $archivePath -Force
$hash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
"$hash  $([IO.Path]::GetFileName($archivePath))" | Set-Content -LiteralPath "$archivePath.sha256" -Encoding utf8
Write-Output "Ready: $archivePath"
