$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'update_signing.ps1')
$workspace = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$dependency = & (Join-Path $PSScriptRoot 'prepare_winsparkle.ps1')
$tool = Join-Path $dependency 'bin\winsparkle-tool.exe'
$keyPath = Get-UpdateKeyPath
$folder = Split-Path -Parent $keyPath
New-Item -ItemType Directory -Path $folder -Force | Out-Null
$identity = [Security.Principal.WindowsIdentity]::GetCurrent().User
$null = & icacls.exe $folder '/inheritance:r' '/grant:r' ('*' + $identity.Value + ':(OI)(CI)F')
if ($LASTEXITCODE -ne 0) { throw 'Cannot restrict access to the publisher key directory.' }
if (-not (Test-Path -LiteralPath $keyPath)) {
    $temporary = Join-Path $folder ([Guid]::NewGuid().ToString('N') + '.pem')
    try {
        $null = & $tool generate-key --file $temporary
        if ($LASTEXITCODE -ne 0) { throw 'Cannot generate the update signing key.' }
        $plain = [IO.File]::ReadAllBytes($temporary)
        try {
            $protected = [Security.Cryptography.ProtectedData]::Protect($plain, $null, [Security.Cryptography.DataProtectionScope]::CurrentUser)
            [IO.File]::WriteAllBytes($keyPath, $protected)
        } finally { [Array]::Clear($plain, 0, $plain.Length) }
    } finally { if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force } }
}
$public = Invoke-WithUpdateKey $tool { param($toolPath, $privatePath); & $toolPath public-key --private-key-file $privatePath }
if ($LASTEXITCODE -ne 0) { throw 'Cannot read the update public key.' }
$publicMatch = [regex]::Match(($public -join "`n"), 'Public key: ([A-Za-z0-9+/]{43}=)')
if (-not $publicMatch.Success) { throw 'Unexpected public key format.' }
$public = $publicMatch.Groups[1].Value
$header = Join-Path $workspace 'windows\runner\update_public_key.h'
if ((Test-Path -LiteralPath $header) -and (Get-Content -LiteralPath $header -Raw) -notmatch [regex]::Escape($public)) {
    throw 'The existing app public key differs. Do not rotate it without a key migration.'
}
[IO.File]::WriteAllText($header, "#pragma once`ninline constexpr char kUpdatePublicKey[] = `"$public`";`n", [Text.UTF8Encoding]::new($false))
$dartKey = Join-Path $workspace 'lib\services\update_public_key.dart'
[IO.File]::WriteAllText($dartKey, "// Public verification key. The publisher private key is never bundled.`nconst updatePublicKey = '$public';`n", [Text.UTF8Encoding]::new($false))
Write-Output "Public key: $public"
Write-Output "Protected publisher key: $keyPath"
