[CmdletBinding()]
param(
    [switch]$EnableRdp,
    [switch]$RequireNla,
    [switch]$RepairFirewall,
    [switch]$RestartTermService,
    [string]$AddUser,
    [switch]$DryRun,
    [switch]$Yes,
    [string]$OutputPath = (Join-Path $env:ProgramData 'RDPRemoteAccessRepair')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:Failures = 0
$script:VerificationFailures = 0
$script:Actions = 0

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if ($env:OS -ne 'Windows_NT') { Write-Error 'This tool requires Windows.'; exit 3 }
if (-not ($EnableRdp -or $RequireNla -or $RepairFirewall -or $RestartTermService -or $AddUser)) { Write-Error 'Choose at least one repair action.'; exit 2 }
if (-not $DryRun -and -not (Test-Administrator)) { Write-Error 'Run from an elevated PowerShell session.'; exit 4 }
if ($AddUser -and -not (Get-Command Get-LocalGroup -ErrorAction SilentlyContinue)) { Write-Error 'LocalAccounts cmdlets are unavailable on this Windows edition or PowerShell host.'; exit 3 }

$terminalServerPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server'
$rdpTcpPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp'
$runPath = Join-Path $OutputPath (Get-Date -Format 'yyyyMMdd_HHmmss')
$backupPath = Join-Path $runPath 'backup'
New-Item -ItemType Directory -Path $backupPath -Force | Out-Null
$logPath = Join-Path $runPath 'repair.log'
$beforePath = Join-Path $runPath 'before.json'
$afterPath = Join-Path $runPath 'after.json'

function Write-Log([string]$Message) { "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $Message" | Tee-Object -FilePath $logPath -Append }
function Invoke-RepairAction([string]$Description,[scriptblock]$Script) {
    $script:Actions++
    Write-Log "ACTION: $Description"
    if ($DryRun) { Write-Log "DRY-RUN: $Description"; return }
    try {
        $result = & $Script 2>&1
        if ($null -ne $result) { $result | Out-String | Add-Content $logPath }
        Write-Log "SUCCESS: $Description"
    } catch {
        $script:Failures++
        Write-Log "FAILED: $Description - $($_.Exception.Message)"
    }
}
function Get-RdpGroup {
    Get-LocalGroup -SID 'S-1-5-32-555' -ErrorAction Stop
}
function Get-RepairState {
    $terminal = Get-ItemProperty $terminalServerPath
    $rdpTcp = Get-ItemProperty $rdpTcpPath
    $members = @()
    if (Get-Command Get-LocalGroup -ErrorAction SilentlyContinue) {
        try { $members = @(Get-LocalGroupMember -Group (Get-RdpGroup).Name -ErrorAction Stop | Select-Object Name,ObjectClass,PrincipalSource,SID) } catch { $members = @() }
    }
    [pscustomobject]@{
        Collected = Get-Date
        RdpEnabled = ($terminal.fDenyTSConnections -eq 0)
        NlaRequired = ($rdpTcp.UserAuthentication -eq 1)
        Service = Get-Service TermService | Select-Object Name,Status,StartType
        FirewallRules = @(Get-NetFirewallRule -Name 'RemoteDesktop*' -ErrorAction SilentlyContinue | Select-Object Name,DisplayName,Enabled,Direction,Action,Profile)
        Listener = @(Get-NetTCPConnection -LocalPort 3389 -State Listen -ErrorAction SilentlyContinue | Select-Object LocalAddress,LocalPort,OwningProcess)
        RemoteDesktopUsers = $members
    }
}

Get-RepairState | ConvertTo-Json -Depth 8 | Set-Content $beforePath -Encoding UTF8
& reg.exe export 'HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server' (Join-Path $backupPath 'TerminalServer.reg') /y | Out-Null
& reg.exe export 'HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' (Join-Path $backupPath 'RDP-Tcp.reg') /y | Out-Null
Get-NetFirewallRule -Name 'RemoteDesktop*' -ErrorAction SilentlyContinue | Export-Clixml (Join-Path $backupPath 'rdp-firewall-rules.xml')
if (Get-Command Get-LocalGroup -ErrorAction SilentlyContinue) {
    try { Get-LocalGroupMember -Group (Get-RdpGroup).Name | Export-Clixml (Join-Path $backupPath 'remote-desktop-users.xml') } catch { }
}

if (-not $DryRun -and -not $Yes) {
    if ((Read-Host 'Apply the selected RDP repairs? Type YES') -cne 'YES') { Write-Log 'Repair cancelled.'; exit 10 }
}

if ($EnableRdp) {
    Invoke-RepairAction 'Enabling Remote Desktop connections' { Set-ItemProperty -Path $terminalServerPath -Name fDenyTSConnections -Type DWord -Value 0 }
}
if ($RequireNla) {
    Invoke-RepairAction 'Requiring Network Level Authentication' { Set-ItemProperty -Path $rdpTcpPath -Name UserAuthentication -Type DWord -Value 1 }
}
if ($RepairFirewall) {
    Invoke-RepairAction 'Enabling built-in Remote Desktop firewall rules' {
        $rules = @(Get-NetFirewallRule -Name 'RemoteDesktop*' -ErrorAction Stop)
        if (-not $rules) { throw 'No built-in Remote Desktop firewall rules were found.' }
        $rules | Enable-NetFirewallRule
    }
}
if ($RestartTermService) {
    Invoke-RepairAction 'Restarting Remote Desktop Services' { Restart-Service TermService -Force; (Get-Service TermService).WaitForStatus('Running',[TimeSpan]::FromSeconds(30)) }
}
if ($AddUser) {
    Invoke-RepairAction "Adding $AddUser to Remote Desktop Users" {
        $group = Get-RdpGroup
        $existing = @(Get-LocalGroupMember -Group $group.Name -ErrorAction SilentlyContinue | Where-Object Name -eq $AddUser)
        if (-not $existing) { Add-LocalGroupMember -Group $group.Name -Member $AddUser }
    }
}

if (-not $DryRun) { Start-Sleep -Seconds 2 }
Get-RepairState | ConvertTo-Json -Depth 8 | Set-Content $afterPath -Encoding UTF8
if ($EnableRdp -and (Get-ItemProperty $terminalServerPath).fDenyTSConnections -ne 0) { $script:VerificationFailures++; Write-Log 'VERIFY FAILED: RDP remains disabled.' }
if ($RequireNla -and (Get-ItemProperty $rdpTcpPath).UserAuthentication -ne 1) { $script:VerificationFailures++; Write-Log 'VERIFY FAILED: NLA is not required.' }
if ($RepairFirewall -and @(Get-NetFirewallRule -Name 'RemoteDesktop*' -ErrorAction SilentlyContinue | Where-Object Enabled -ne 'True').Count -gt 0) { $script:VerificationFailures++; Write-Log 'VERIFY FAILED: one or more RDP firewall rules remain disabled.' }
if ($RestartTermService -and (Get-Service TermService).Status -ne 'Running') { $script:VerificationFailures++; Write-Log 'VERIFY FAILED: TermService is not running.' }
if ($AddUser) {
    $memberNames = @(Get-LocalGroupMember -Group (Get-RdpGroup).Name -ErrorAction SilentlyContinue | ForEach-Object Name)
    if ($AddUser -notin $memberNames) { $script:VerificationFailures++; Write-Log 'VERIFY FAILED: requested user is not a Remote Desktop Users member.' }
}

if ($script:Failures -gt 0) { exit 20 }
if ($script:VerificationFailures -gt 0) { exit 30 }
Write-Log "Repair completed. Actions: $script:Actions"
exit 0
