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
if (-not ([IO.Path]::GetFullPath($packagePath).StartsWith(([IO.Path]::GetFullPath((Join-Path $workspace 'dist')) + [IO.Path]::DirectorySeparatorChar), [StringComparison]::OrdinalIgnoreCase))) { throw 'Package path is outside dist.' }
if (Test-Path -LiteralPath $packagePath) { Remove-Item -LiteralPath $packagePath -Recurse -Force }
New-Item -ItemType Directory -Path $packagePath -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $releasePath 'data') -Destination $packagePath -Recurse -Force
$obsoleteLicense = Join-Path $packagePath 'data\licenses\WinSparkle'
if (Test-Path -LiteralPath $obsoleteLicense) { Remove-Item -LiteralPath $obsoleteLicense -Recurse -Force }
Get-ChildItem -LiteralPath $releasePath -File | Where-Object {$_.Extension -ne '.exe' -and $_.Name -ne 'WinSparkle.dll'} | Copy-Item -Destination $packagePath -Force
Copy-Item -LiteralPath $executable -Destination (Join-Path $packagePath 'CiliCiliWinRev.exe') -Force
Copy-Item -LiteralPath (Join-Path $releasePath 'CiliCiliWinRevUpdater.exe') -Destination $packagePath -Force
Copy-Item -LiteralPath (Join-Path $workspace 'README.md') -Destination $packagePath -Force
Copy-Item -LiteralPath (Join-Path $workspace 'docs\THIRD_PARTY_NOTICES.md') -Destination $packagePath -Force
$packageDocs = Join-Path $packagePath 'docs'
New-Item -ItemType Directory -Path $packageDocs -Force | Out-Null
foreach ($document in @('architecture.md', 'verification.md', 'THIRD_PARTY_NOTICES.md', 'updates.md')) {
    Copy-Item -LiteralPath (Join-Path $workspace "docs\$document") -Destination $packageDocs -Force
}
foreach ($required in @('CiliCiliWinRev.exe', 'CiliCiliWinRevUpdater.exe', 'flutter_windows.dll', 'libmpv-2.dll', 'msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll', 'data\icudtl.dat', 'data\flutter_assets\AssetManifest.bin')) {
    if (-not (Test-Path -LiteralPath (Join-Path $packagePath $required))) { throw "Package is missing $required" }
}
Write-Output "Package directory: $packagePath"
