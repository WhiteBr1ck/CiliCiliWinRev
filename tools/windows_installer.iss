#ifndef AppVersion
  #error AppVersion is required
#endif
#ifndef PackageDir
  #error PackageDir is required
#endif
#ifndef OutputDir
  #error OutputDir is required
#endif

[Setup]
AppId={{35D7C36E-596C-4DF5-95E3-C528CD74A04B}
AppName=CiliCiliWinRev
AppVersion={#AppVersion}
AppVerName=CiliCiliWinRev {#AppVersion}
AppPublisher=WhiteBr1ck
AppPublisherURL=https://github.com/WhiteBr1ck/CiliCiliWinRev
AppSupportURL=https://github.com/WhiteBr1ck/CiliCiliWinRev/issues
AppUpdatesURL=https://github.com/WhiteBr1ck/CiliCiliWinRev/releases
DefaultDirName={localappdata}\Programs\CiliCiliWinRev
DefaultGroupName=CiliCiliWinRev
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
UninstallDisplayIcon={app}\CiliCiliWinRev.exe
SetupIconFile=..\windows\runner\resources\app_icon.ico
OutputDir={#OutputDir}
OutputBaseFilename=CiliCiliWinRev-{#AppVersion}-windows-x64-setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
DisableProgramGroupPage=yes
UsePreviousAppDir=yes
CloseApplications=yes
RestartApplications=no
Uninstallable=yes
VersionInfoVersion={#AppVersion}

[Languages]
Name: "chinesesimplified"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#PackageDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\CiliCiliWinRev"; Filename: "{app}\CiliCiliWinRev.exe"; WorkingDir: "{app}"
Name: "{autodesktop}\CiliCiliWinRev"; Filename: "{app}\CiliCiliWinRev.exe"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\CiliCiliWinRev.exe"; Description: "{cm:LaunchProgram,CiliCiliWinRev}"; Flags: nowait postinstall skipifsilent
