; ssh-client — Inno Setup Script
; Produces a single-file .exe installer for Windows x64

#define AppName "ssh-client"
#define AppVersion "0.0.1"
#define AppPublisher "Dinesh Korukonda"
#define AppURL "https://github.com/dineshkorukonda/ssh-client"
#define AppExeName "ssh_client.bat"

[Setup]
AppId={{8F3C4A2B-1D6E-4F9A-B7C5-0E2D8A3F1C4B}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppURL}
AppSupportURL={#AppURL}/issues
AppUpdatesURL={#AppURL}/releases
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
AllowNoIcons=yes
LicenseFile=..\LICENSE
OutputDir=..\installer
OutputBaseFilename=ssh-client-setup-v{#AppVersion}-windows-x64
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayName={#AppName}
UninstallDisplayIcon={app}\bin\erl.exe

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; Ship the entire OTP release tree
Source: "..\_build\prod\rel\ssh_client\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\bin\{#AppExeName}"; WorkingDir: "{app}"
Name: "{group}\{cm:UninstallProgram,{#AppName}}"; Filename: "{uninstallexe}"
Name: "{commondesktop}\{#AppName}"; Filename: "{app}\bin\{#AppExeName}"; Tasks: desktopicon; WorkingDir: "{app}"

[Run]
Filename: "{app}\bin\{#AppExeName}"; Parameters: "start"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent

[UninstallRun]
Filename: "{app}\bin\{#AppExeName}"; Parameters: "stop"; RunOnceId: "StopService"; Flags: nowait

[Code]
// Open browser after install so user sees the GUI
procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then begin
    ShellExec('open', 'http://localhost:4000', '', '', SW_SHOW, ewNoWait, 0);
  end;
end;
