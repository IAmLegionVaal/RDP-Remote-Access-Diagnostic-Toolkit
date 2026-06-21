# RDP Remote Access Diagnostic Toolkit

A PowerShell toolkit for Windows Remote Desktop connectivity reporting and guarded local RDP repair.

## Diagnostic script

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\RDP_Remote_Access_Diagnostic_Toolkit.ps1
```

The diagnostic script reports Remote Desktop service, firewall, listener and recent event context without changing the system.

## Repair script

Preview a repair:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\RDP_Remote_Access_Repair_Toolkit.ps1 -EnableRdp -RequireNla -RepairFirewall -DryRun
```

Examples:

```powershell
.\RDP_Remote_Access_Repair_Toolkit.ps1 -EnableRdp -RequireNla -RepairFirewall
.\RDP_Remote_Access_Repair_Toolkit.ps1 -RestartTermService
.\RDP_Remote_Access_Repair_Toolkit.ps1 -AddUser 'CONTOSO\Support User'
```

## Repair behaviour

- Enables Remote Desktop connections when explicitly requested.
- Requires Network Level Authentication when selected.
- Enables the built-in `RemoteDesktop*` Windows Firewall rules.
- Restarts Remote Desktop Services.
- Adds one explicit principal to the local Remote Desktop Users group.
- Exports Terminal Server registry keys, firewall rules and group membership before changes.
- Captures configuration, service, listener, firewall and membership state before and after repair.
- Supports `-DryRun`, confirmation prompts or `-Yes`, administrator checks, logs and verification.

## Safety and exit codes

Enabling RDP increases the device's remote-access exposure. Use approved firewall, network and account policy controls and avoid exposing TCP 3389 directly to the internet. The tool does not disable NLA, remove users, open arbitrary ports or configure port forwarding.

Exit codes: `0` success, `2` invalid arguments, `3` unsupported platform or missing cmdlets, `4` elevation required, `10` cancelled, `20` action failure and `30` verification failure.

## Validation note

The repair script was committed and statically reviewed, but it was not runtime-tested on a Windows endpoint or server.

## Author

Dewald Pretorius — L2 IT Support Engineer
