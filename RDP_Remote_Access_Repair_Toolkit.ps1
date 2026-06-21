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

function Write-Log([string]$Message) {
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $Message" | Tee-Object -FilePath $logPath -Append
}
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
function Test-MemberPresent([object[]]$Members,[string]$RequestedMember) {
    foreach ($entry in $Members) {
        $name = [string]$entry.Name
        if ($name -ieq $RequestedMember -or $name -ilike "*\$RequestedMember") { return $true }
        if ($entry.SID -and ([string]$entry.SID -ieq $RequestedMember)) { return $true }
    }
    return $false
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

$beforeState = Get-RepairState
$beforeState | ConvertTo-Json -Depth 8 | Set-Content $beforePath -Encoding UTF8

if (-not $DryRun) {
    & reg.exe export 'HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server' (Join-Path $backupPath 'TerminalServer.reg') /y | Out-Null
    if ($LASTEXITCODE -ne 0) { Write-Error 'Could not back up Terminal Server registry settings.'; exit 20 }
    & reg.exe export 'HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' (Join-Path $backupPath 'RDP-Tcp.reg') /y | Out-Null
    if ($LASTEXITCODE -ne 0) { Write-Error 'Could not back up RDP-Tcp registry settings.'; exit 20 }
    Get-NetFirewallRule -Name 'RemoteDesktop*' -ErrorAction SilentlyContinue | Export-Clixml (Join-Path $backupPath 'rdp-firewall-rules.xml')
    if (Get-Command Get-LocalGroup -ErrorAction SilentlyContinue) {
        try { Get-LocalGroupMember -Group (Get-RdpGroup).Name | Export-Clixml (Join-Path $backupPath 'remote-desktop-users.xml') } catch { Write-Log "WARNING: could not export group membership evidence - $($_.Exception.Message)" }
    }
    Write-Log "Saved pre-change backups to $backupPath"
}

if (-not $DryRun -and -not $Yes) {
    if ((Read-Host 'Apply the selected RDP repairs? Type YES') -cne 'YES') { Write-Log 'Repair cancelled.'; exit 10 }
}

if ($EnableRdp) {
    Invoke-RepairAction 'Enabling Remote Desktop connections' {
        New-ItemProperty -Path $terminalServerPath -Name fDenyTSConnections -PropertyType DWord -Value 0 -Force | Out-Null
    }
}
if ($RequireNla) {
    Invoke-RepairAction 'Requiring Network Level Authentication' {
        New-ItemProperty -Path $rdpTcpPath -Name UserAuthentication -PropertyType DWord -Value 1 -Force | Out-Null
    }
}
if ($RepairFirewall) {
    Invoke-RepairAction 'Enabling built-in Remote Desktop firewall rules' {
        $rules = @(Get-NetFirewallRule -Name 'RemoteDesktop*' -ErrorAction Stop)
        if (-not $rules) { throw 'No built-in Remote Desktop firewall rules were found.' }
        $rules | Enable-NetFirewallRule
    }
}
if ($RestartTermService) {
    Invoke-RepairAction 'Restarting Remote Desktop Services' {
        Restart-Service TermService -Force
        (Get-Service TermService).WaitForStatus('Running',[TimeSpan]::FromSeconds(30))
    }
}
if ($AddUser) {
    Invoke-RepairAction "Adding $AddUser to Remote Desktop Users" {
        $group = Get-RdpGroup
        $members = @(Get-LocalGroupMember -Group $group.Name -ErrorAction SilentlyContinue)
        if (-not (Test-MemberPresent -Members $members -RequestedMember $AddUser)) { Add-LocalGroupMember -Group $group.Name -Member $AddUser }
    }
}

if (-not $DryRun) { Start-Sleep -Seconds 2 }
$afterState = Get-RepairState
$afterState | ConvertTo-Json -Depth 8 | Set-Content $afterPath -Encoding UTF8

if (-not $DryRun) {
    if ($EnableRdp -and -not $afterState.RdpEnabled) { $script:VerificationFailures++; Write-Log 'VERIFY FAILED: RDP remains disabled.' }
    if ($RequireNla -and -not $afterState.NlaRequired) { $script:VerificationFailures++; Write-Log 'VERIFY FAILED: NLA is not required.' }
    if ($RepairFirewall -and @($afterState.FirewallRules | Where-Object Enabled -ne 'True').Count -gt 0) { $script:VerificationFailures++; Write-Log 'VERIFY FAILED: one or more RDP firewall rules remain disabled.' }
    if ($RestartTermService -and $afterState.Service.Status -ne 'Running') { $script:VerificationFailures++; Write-Log 'VERIFY FAILED: TermService is not running.' }
    if ($AddUser -and -not (Test-MemberPresent -Members $afterState.RemoteDesktopUsers -RequestedMember $AddUser)) { $script:VerificationFailures++; Write-Log 'VERIFY FAILED: requested user is not a Remote Desktop Users member.' }
}

if ($script:Failures -gt 0) { exit 20 }
if ($script:VerificationFailures -gt 0) { exit 30 }
Write-Log "Workflow completed. Actions: $script:Actions; DryRun: $DryRun"
exit 0
