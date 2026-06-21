# RDP Remote Access Diagnostic Toolkit

A PowerShell toolkit for Windows Remote Desktop connectivity reporting and guarded local RDP repair.

## Scripts

- `RDP_Remote_Access_Diagnostic_Toolkit.ps1` — read-only service, firewall, listener, and event reporting.
- `RDP_Remote_Access_Repair_Toolkit.ps1` — targeted RDP configuration, firewall, service, and local-group repair.

## Repair actions

The repair script can:

- enable Remote Desktop connections with `-EnableRdp`;
- require Network Level Authentication with `-RequireNla`;
- enable the built-in `RemoteDesktop*` Windows Firewall rules with `-RepairFirewall`;
- restart Remote Desktop Services with `-RestartTermService`;
- add one explicit principal to the local Remote Desktop Users group with `-AddUser`.

It does not disable NLA, remove users, create arbitrary firewall rules, configure NAT, or expose TCP 3389 through an upstream firewall or router.

## Examples

Preview an RDP repair without changing the device:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\RDP_Remote_Access_Repair_Toolkit.ps1 `
  -EnableRdp -RequireNla -RepairFirewall -DryRun
```

Apply a guarded repair and add an approved user:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\RDP_Remote_Access_Repair_Toolkit.ps1 `
  -EnableRdp -RequireNla -RepairFirewall -RestartTermService `
  -AddUser "CONTOSO\Support User" -Yes
```

Omit `-Yes` to require typing `YES` before changes are made. Actual changes require an elevated PowerShell session.

## Evidence, backup, and verification

Each run creates a timestamped directory under `%ProgramData%\RDPRemoteAccessRepair` unless `-OutputPath` is supplied. It contains:

- `before.json` and `after.json` with RDP, service, listener, firewall, and membership state;
- `repair.log` with planned actions, results, and verification failures;
- for non-dry runs, registry exports for Terminal Server and RDP-Tcp settings plus exports of matching firewall rules and Remote Desktop Users membership.

Applied changes are verified against the requested RDP state, firewall state, service status, and group membership. `-DryRun` logs planned actions without changing the device, creating configuration backups, or performing post-change verification.

## Exit codes

| Code | Meaning |
|---:|---|
| 0 | Completed successfully, including a successful dry run |
| 2 | Invalid arguments or safety refusal |
| 3 | Unsupported platform or missing required cmdlets |
| 4 | Elevation required |
| 10 | User cancelled |
| 20 | One or more repair actions or required backups failed |
| 30 | Post-repair verification failed |

## Safety

Enabling RDP increases the device's remote-access exposure. Use approved firewall, network, identity, and account controls, and never expose TCP 3389 directly to the public internet without an approved secure access layer.

## Validation status

The scripts were source-reviewed during this update. They were not runtime-tested on a Windows endpoint or server.

## Author

Dewald Pretorius — L2 IT Support Engineer
