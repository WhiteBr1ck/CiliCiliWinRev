# Private key storage is outside the repository and encrypted for this Windows user.
Add-Type -AssemblyName System.Security
function Get-UpdateKeyPath {
    Join-Path $env:LOCALAPPDATA 'CiliCiliWinRevPublisher\update-signing-key.dpapi'
}
function Invoke-WithUpdateKey([string]$Tool, [scriptblock]$Action) {
    $keyPath = Get-UpdateKeyPath
    if (-not (Test-Path -LiteralPath $keyPath)) { throw 'Run tools/initialize_update_signing.ps1 once on the publishing host.' }
    $folder = Split-Path -Parent $keyPath
    $temporary = Join-Path $folder ([Guid]::NewGuid().ToString('N') + '.pem')
    $plain = [Security.Cryptography.ProtectedData]::Unprotect([IO.File]::ReadAllBytes($keyPath), $null, [Security.Cryptography.DataProtectionScope]::CurrentUser)
    try {
        [IO.File]::WriteAllBytes($temporary, $plain)
        & $Action $Tool $temporary
    } finally {
        [Array]::Clear($plain, 0, $plain.Length)
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
    }
}
