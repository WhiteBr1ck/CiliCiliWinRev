param([Parameter(Mandatory=$true)][string]$Installer, [string]$Version = '', [string]$Output = '')
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'update_signing.ps1')
$workspace = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if (-not $Version) {
    $match = [regex]::Match((Get-Content -LiteralPath (Join-Path $workspace 'pubspec.yaml') -Raw), '(?m)^version:\s*(\d+\.\d+\.\d+)\+')
    if (-not $match.Success) { throw 'Cannot read application version.' }
    $Version = $match.Groups[1].Value
}
if ($Version -notmatch '^\d+\.\d+\.\d+$') { throw 'Only stable numeric versions may be published.' }
$Installer = (Resolve-Path -LiteralPath $Installer).Path
if ([IO.Path]::GetFileName($Installer) -ne "CiliCiliWinRev-$Version-windows-x64-setup.exe") { throw 'Installer name must match the release version.' }
$fileVersion = [Diagnostics.FileVersionInfo]::GetVersionInfo($Installer)
if ("$($fileVersion.FileMajorPart).$($fileVersion.FileMinorPart).$($fileVersion.FileBuildPart)" -ne $Version) { throw 'Installer resource version does not match.' }
$dependency = & (Join-Path $PSScriptRoot 'prepare_winsparkle.ps1')
$tool = Join-Path $dependency 'bin\winsparkle-tool.exe'
$signature = Invoke-WithUpdateKey $tool { param($toolPath, $privatePath); & $toolPath sign --private-key-file $privatePath $Installer }
if ($LASTEXITCODE -ne 0) { throw 'Cannot sign installer.' }
$signature = ($signature -join "`n").Trim()
if ($signature -notmatch '^[A-Za-z0-9+/]{86}==$') { throw 'Unexpected update signature format.' }
$publicMatch = [regex]::Match((Get-Content -LiteralPath (Join-Path $workspace 'lib\services\update_public_key.dart') -Raw), "'([A-Za-z0-9+/]{43}=)'")
if (-not $publicMatch.Success) { throw 'Missing update public key.' }
& $tool verify --public-key $publicMatch.Groups[1].Value --signature $signature $Installer
if ($LASTEXITCODE -ne 0) { throw 'Installer does not verify with the application public key.' }
$manifest = [ordered]@{
    version = $Version
    url = "https://github.com/WhiteBr1ck/CiliCiliWinRev/releases/download/v$Version/CiliCiliWinRev-$Version-windows-x64-setup.exe"
    size = (Get-Item -LiteralPath $Installer).Length
    sha256 = (Get-FileHash -LiteralPath $Installer -Algorithm SHA256).Hash.ToLowerInvariant()
    signature = $signature
}
if (-not $Output) { $Output = Join-Path $workspace "dist\update-$Version.json" }
[IO.File]::WriteAllText([IO.Path]::GetFullPath($Output), ($manifest | ConvertTo-Json) + "`n", [Text.UTF8Encoding]::new($false))
Write-Output "Signed update manifest: $Output"
