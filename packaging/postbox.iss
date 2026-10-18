; Inno Setup script for the Windows installer. Unverified: build it on Windows
; after `flutter build windows --release`, with Inno Setup 6 installed.
#define AppName "PostBox"
#define AppVersion "0.2.0"
#define Publisher "Uniqueone"
#define BuildDir "..\build\windows\x64\runner\Release"

[Setup]
AppId={{B6A1B4E2-5C2B-4C77-9E1A-6D5B1F0C7A10}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#Publisher}
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
OutputDir=..\build\installer
OutputBaseFilename=PostBox-{#AppVersion}-windows-setup
Compression=lzma2
SolidCompression=yes
ArchitecturesInstallIn64BitMode=x64compatible
LicenseFile=..\LICENSE
PrivilegesRequired=lowest

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
