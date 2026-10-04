param([string]$Compiler = '', [string]$CMake = 'C:/Program Files/Microsoft Visual Studio/2022/Community/Common7/IDE/CommonExtensions/Microsoft/CMake/CMake/bin/cmake.exe')
$ErrorActionPreference = 'Stop'
$taskWorkspace = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
if (-not $Compiler) { $Compiler = Join-Path $taskWorkspace '.research/tooling/InnoSetup/ISCC.exe' }
if (-not (Test-Path -LiteralPath $Compiler)) { throw 'Pass -Compiler with the Inno Setup 7 ISCC.exe path.' }
& $CMake -S $PSScriptRoot -B (Join-Path $taskWorkspace '.research/update-native-new') -A x64
if ($LASTEXITCODE -ne 0) { throw 'Fixture configuration failed.' }
& $CMake --build (Join-Path $taskWorkspace '.research/update-native-new') --config Release
if ($LASTEXITCODE -ne 0) { throw 'Fixture build failed.' }
$taskPackage = Join-Path $taskWorkspace '.research/helper-qa-package'
$taskResearch = [IO.Path]::GetFullPath((Join-Path $taskWorkspace '.research')) + [IO.Path]::DirectorySeparatorChar
if (-not [IO.Path]::GetFullPath($taskPackage).StartsWith($taskResearch,[StringComparison]::OrdinalIgnoreCase)) { throw 'Fixture package path is outside research.' }
if (Test-Path -LiteralPath $taskPackage) { Remove-Item -LiteralPath $taskPackage -Recurse -Force }
Copy-Item -LiteralPath (Join-Path $taskWorkspace 'dist/CiliCiliWinRev-0.7.0-windows-x64') -Destination $taskPackage -Recurse
Copy-Item -LiteralPath (Join-Path $taskWorkspace '.research/update-native-new/Release/CiliCiliWinRev.exe') -Destination (Join-Path $taskPackage 'CiliCiliWinRev.exe') -Force
$taskSource = Get-Content -LiteralPath (Join-Path $taskWorkspace 'tools/windows_installer.iss') -Raw
$taskSource = $taskSource.Replace('35D7C36E-596C-4DF5-95E3-C528CD74A04B','45685E6E-62BA-4C30-90E7-B1F8D77EE247').Replace('DefaultGroupName=CiliCiliWinRev','DefaultGroupName=CiliCiliWinRev Installer Verification')
$taskScript = Join-Path $taskWorkspace '.research/windows_installer-qa.iss'
[IO.File]::WriteAllText($taskScript,$taskSource)
& $Compiler /DAppVersion=0.7.0 "/DPackageDir=$taskPackage" "/DOutputDir=$taskWorkspace/.research/helper-qa-build" $taskScript
if ($LASTEXITCODE -ne 0) { throw 'Fixture installer compilation failed.' }
# If the earlier real QA package is unavailable, create an explicit fixture
# baseline. It tests registry/directory handoff; it is not the original 0.6.1 app.
$taskOldSetup = Join-Path $taskWorkspace '.research/installer-qa-build/CiliCiliWinRev-0.6.1-windows-x64-setup.exe'
if (-not (Test-Path -LiteralPath $taskOldSetup)) {
    & $Compiler /DAppVersion=0.6.1 "/DPackageDir=$taskPackage" "/DOutputDir=$taskWorkspace/.research/installer-qa-build" $taskScript
    if ($LASTEXITCODE -ne 0) { throw 'Fixture baseline compilation failed.' }
}
