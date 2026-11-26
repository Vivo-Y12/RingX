; RingX — Inno Setup installer script (original script, Inno Setup 6).
;
; Built by CI:      iscc installer\RingX.iss    (from the repo root)
; Built by hand:    cd app && flutter build windows --release
;                   python tool\make_icon.py    (icon must exist first)
;                   iscc installer\RingX.iss
;
; Inputs:
;   ..\app\build\windows\x64\runner\Release\*   the built app (required)
;   ..\app\windows\runner\resources\app_icon.ico  generated icon (required)
;   drivers\vJoySetup.exe                        official vJoy 2.1.9.1
;     (optional — CI stages it next to this script; the
;     skipifsourcedoesntexist flag keeps hand builds working without it)

#define MyAppName "RingX"
#define MyAppVersion "0.1.0"
#define MyAppPublisher "RingX Project"
#define MyAppExeName "ringx.exe"
#define MyAppURL "https://github.com/Vivo-Y12/RingX"

[Setup]
AppId={{8F13C7A2-9E4D-4B6A-8C21-5D0E9A73F4B1}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={autopf}\RingX
DefaultGroupName=RingX
DisableProgramGroupPage=yes
LicenseFile=..\app\LICENSE
SetupIconFile=..\app\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
OutputDir=..\dist
OutputBaseFilename=RingX-Setup-{#MyAppVersion}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesInstallIn64BitMode=x64
ArchitecturesAllowed=x64
PrivilegesRequired=admin
MinVersion=10.0

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"
Name: "vjoydriver"; Description: "Also install the vJoy driver (required for RingX to feed the game; the PC reboots when it finishes)"; GroupDescription: "Driver:"; Flags: unchecked

[Files]
Source: "..\app\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs
Source: "drivers\vJoySetup.exe"; DestDir: "{app}\drivers"; Flags: skipifsourcedoesntexist; Tasks: vjoydriver

[Icons]
Name: "{group}\RingX"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\{cm:UninstallProgram,RingX}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\RingX"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,RingX}"; Flags: nowait postinstall skipifdoesntexist
Filename: "{app}\drivers\vJoySetup.exe"; Description: "Run the vJoy driver setup now"; Flags: nowait postinstall skipifdoesntexist; Tasks: vjoydriver
