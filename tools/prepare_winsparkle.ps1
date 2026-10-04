$ErrorActionPreference = 'Stop'
$workspace = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$cache = Join-Path $workspace '.dart_tool\winsparkle'
$archive = Join-Path $cache 'WinSparkle-0.9.4.zip'
$expected = '6037df37fc263bd1650a1c4949681a9d40ffe991d01f35892a406cb5d103c976'
New-Item -ItemType Directory -Path $cache -Force | Out-Null
if (-not (Test-Path -LiteralPath $archive)) {
    Invoke-WebRequest 'https://github.com/vslavik/winsparkle/releases/download/v0.9.4/WinSparkle-0.9.4.zip' -OutFile $archive
}
if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expected) {
    throw 'WinSparkle archive checksum does not match the pinned official release.'
}
Expand-Archive -LiteralPath $archive -DestinationPath $cache -Force
Write-Output (Join-Path $cache 'WinSparkle-0.9.4')
