; Inno Setup script for the Windows installer. Build on Windows after
; `flutter build windows --release` with Inno Setup 6:
;   iscc /DAppVersion=1.0.0 packaging\postbox.iss
; The release workflow does this on every version tag. Not yet run on a clean
; machine; the installer is unsigned (SmartScreen will warn).
#define AppName "PostBox"
#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif
#define RepoUrl "https://github.com/ghaderi0x/PostBox"
#define Publisher "Uniqueone"
#define BuildDir "..\build\windows\x64\runner\Release"

[Setup]
AppId={{B6A1B4E2-5C2B-4C77-9E1A-6D5B1F0C7A10}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#Publisher}
AppPublisherURL={#RepoUrl}
AppSupportURL={#RepoUrl}/issues
AppUpdatesURL={#RepoUrl}/releases
CloseApplications=yes
RestartApplications=no
PrivilegesRequiredOverridesAllowed=dialog
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
OutputDir=..\build\installer
OutputBaseFilename=PostBox-{#AppVersion}-windows-setup
Compression=lzma2
SolidCompression=yes
ArchitecturesInstallIn64BitMode=x64compatible
LicenseFile=..\LICENSE
SetupIconFile=..\assets\branding\app_icon.ico
UninstallDisplayIcon={app}\postbox.exe
PrivilegesRequired=lowest
WizardStyle=modern

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Shortcuts:"

[Files]
Source: "{#BuildDir}\*"; DestDir: "{app}"; Flags: recursesubdirs ignoreversion

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\postbox.exe"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\postbox.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\postbox.exe"; Description: "Launch {#AppName}"; Flags: nowait postinstall skipifsilent
