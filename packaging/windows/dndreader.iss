; DNDReader — Windows installer (Inno Setup 6.3+). One installer path only; no MSIX.
;
; Built by packaging/windows/build-installer.sh, which supplies:
;   /DAppVersion=<kAppVersion>   /DBundleDir=<flutter windows Release dir>
;   /DOutputDir=<dist dir>       /DBootstrapper=<MicrosoftEdgeWebview2Setup.exe>
;   /DLicensesDir=<dir of third-party licence files>
;
; Installs per-user by default (no admin prompt) and can be installed per-machine
; from the wizard or with /ALLUSERS. No code-signing certificate is required.

#ifndef AppVersion
  #error AppVersion not defined; build with packaging/windows/build-installer.sh
#endif

#define AppName "DNDReader"
#define AppExe "dndreader.exe"
#define ProgId "DNDReader.pdf"
; Microsoft's Evergreen WebView2 Runtime client id (Microsoft distribution docs).
#define WebView2Key "Software\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}"

[Setup]
AppId={{B7F4E0A2-5D3C-4E1A-9C58-6A1D2F0E7B34}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
OutputDir={#OutputDir}
OutputBaseFilename=DNDReader-{#AppVersion}-setup-x64
UninstallDisplayIcon={app}\{#AppExe}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
; Per-user unless the user asks otherwise; the wizard offers the choice.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
; Windows 10 1809 is the minimum: Windows.Graphics.Capture, which the WebView2
; texture path uses, needs it. 64-bit only.
MinVersion=10.0.17763
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
ChangesAssociations=yes

[Files]
Source: "{#BundleDir}\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion
Source: "{#LicensesDir}\*"; DestDir: "{app}\licenses"; Flags: recursesubdirs createallsubdirs ignoreversion
; The ~2 MB Evergreen bootstrapper, only extracted when the Runtime is missing.
Source: "{#Bootstrapper}"; DestDir: "{tmp}"; Flags: deleteafterinstall; Check: WebView2Missing

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{group}\Uninstall {#AppName}"; Filename: "{uninstallexe}"

[Registry]
; Offer DNDReader for .pdf ("Open with"). Does not seize the default: Windows 10+
; leaves the default choice to the user.
Root: HKA; Subkey: "Software\Classes\{#ProgId}"; ValueType: string; ValueData: "PDF document"; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Classes\{#ProgId}\DefaultIcon"; ValueType: string; ValueData: "{app}\{#AppExe},0"
Root: HKA; Subkey: "Software\Classes\{#ProgId}\shell\open\command"; ValueType: string; ValueData: """{app}\{#AppExe}"" ""%1"""
Root: HKA; Subkey: "Software\Classes\.pdf\OpenWithProgids"; ValueType: string; ValueName: "{#ProgId}"; ValueData: ""; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\shell\open\command"; ValueType: string; ValueData: """{app}\{#AppExe}"" ""%1"""; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".pdf"; ValueData: ""

[Run]
; Elevated installs put the Runtime in per-machine, non-elevated per-user.
Filename: "{tmp}\MicrosoftEdgeWebview2Setup.exe"; Parameters: "/silent /install"; StatusMsg: "Installing the Microsoft Edge WebView2 Runtime..."; Flags: waituntilterminated; Check: WebView2Missing
Filename: "{app}\{#AppExe}"; Description: "Launch {#AppName}"; Flags: nowait postinstall skipifsilent

[Code]
// Microsoft's documented detection: the `pv` string value under the Runtime's
// EdgeUpdate client key, per-machine (WOW6432Node on 64-bit Windows) and
// per-user. Absent, empty, or "0.0.0.0" all mean "not installed".
function UsableVersion(const V: String): Boolean;
begin
  Result := (V <> '') and (V <> '0.0.0.0');
end;

function WebView2Missing: Boolean;
var
  V: String;
begin
  Result := True;
  if RegQueryStringValue(HKLM32, '{#WebView2Key}', 'pv', V) and UsableVersion(V) then
    Result := False
  else if RegQueryStringValue(HKCU, '{#WebView2Key}', 'pv', V) and UsableVersion(V) then
    Result := False;
end;
