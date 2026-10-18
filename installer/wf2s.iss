; Windows installer for wf2s (Inno Setup 6). Built by scripts/build-installer.ps1 from the files of the verified release zip,
; so it contains exactly what the zip contains. Per-user install (no administrator rights needed): the app writes its server
; folder, the game and SteamCMD next to itself, which Program Files would not allow.
#ifndef Version
  #define Version "0.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\dist\stage\wf2s"
#endif

[Setup]
AppId={{6B1F3D2E-8C4A-4E57-9D0B-3A7C5E2F9A41}
AppName=Wreckfest 2 Server (wf2s)
AppVersion={#Version}
AppPublisher=gerp93
AppPublisherURL=https://github.com/gerp93/wf2s
AppSupportURL=https://github.com/gerp93/wf2s/issues
DefaultDirName={autopf}\wf2s
DefaultGroupName=Wreckfest 2 Server
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir=..\dist
OutputBaseFilename=wf2s-setup-v{#Version}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
MinVersion=10.0
UninstallDisplayName=Wreckfest 2 Server (wf2s)
CloseApplications=no

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Shortcuts:"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
Name: "{autoprograms}\Wreckfest 2 Server"; Filename: "{app}\Start.cmd"; WorkingDir: "{app}"; Comment: "Set up and run your Wreckfest 2 dedicated server"
Name: "{autodesktop}\Wreckfest 2 Server"; Filename: "{app}\Start.cmd"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\Start.cmd"; WorkingDir: "{app}"; Description: "Set up my server now"; Flags: postinstall nowait skipifsilent shellexec

; The in-app updater adds and removes files the installer does not know about, so the app's own folders are removed as a whole.
; Your server (instances), the game (server) and SteamCMD are handled by the question below.
[UninstallDelete]
Type: filesandordirs; Name: "{app}\scripts"
Type: filesandordirs; Name: "{app}\ui"
Type: filesandordirs; Name: "{app}\defaults"
Type: filesandordirs; Name: "{app}\docs"
Type: filesandordirs; Name: "{app}\.update-backup"
Type: files; Name: "{app}\VERSION"

[Code]
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usUninstall then
  begin
    { A silent uninstall never deletes your data. }
    if not UninstallSilent then
    begin
      if MsgBox('Also delete your server settings and password, the downloaded game server and SteamCMD?' + #13#10 + #13#10 +
                'Choose No to keep them. You can delete the folder by hand later.',
                mbConfirmation, MB_YESNO or MB_DEFBUTTON2) = IDYES then
      begin
        DelTree(ExpandConstant('{app}\instances'), True, True, True);
        DelTree(ExpandConstant('{app}\server'), True, True, True);
        DelTree(ExpandConstant('{app}\steamcmd'), True, True, True);
        DeleteFile(ExpandConstant('{app}\steam-user.local'));
        DeleteFile(ExpandConstant('{app}\latest-build.local'));
        DeleteFile(ExpandConstant('{app}\game-version.local'));
        DeleteFile(ExpandConstant('{app}\app-update-status.local'));
      end;
    end;
  end;
end;
