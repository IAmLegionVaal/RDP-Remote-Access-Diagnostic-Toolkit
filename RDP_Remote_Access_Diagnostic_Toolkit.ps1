#requires -Version 5.1
<#
.SYNOPSIS
    Remote Connectivity Diagnostic Toolkit.
.DESCRIPTION
    Read-only Windows connectivity context reporter for support review.
#>
[CmdletBinding()]
param([string]$OutputPath,[int]$Hours=72)
$RunStamp=Get-Date -Format 'yyyyMMdd_HHmmss'
if([string]::IsNullOrWhiteSpace($OutputPath)){$OutputPath=Join-Path ([Environment]::GetFolderPath('Desktop')) 'Remote_Connectivity_Reports'}
New-Item -Path $OutputPath -ItemType Directory -Force|Out-Null
$services=Get-Service|Where-Object {$_.Name -in @('TermService','UmRdpService','SessionEnv','MpsSvc')}|Select-Object Name,DisplayName,Status,StartType
$services|Export-Csv (Join-Path $OutputPath "services_$RunStamp.csv") -NoTypeInformation -Encoding UTF8
try{Get-NetFirewallProfile|Select-Object Name,Enabled,DefaultInboundAction,DefaultOutboundAction|Export-Csv (Join-Path $OutputPath "firewall_profiles_$RunStamp.csv") -NoTypeInformation -Encoding UTF8}catch{}
try{Get-NetTCPConnection -State Listen|Where-Object {$_.LocalPort -in @(3389,443,80)}|Select-Object LocalAddress,LocalPort,State,OwningProcess|Export-Csv (Join-Path $OutputPath "listeners_$RunStamp.csv") -NoTypeInformation -Encoding UTF8}catch{}
$start=(Get-Date).AddHours(-1*$Hours)
$events=Get-WinEvent -FilterHashtable @{LogName='System';StartTime=$start;Level=1,2,3} -ErrorAction SilentlyContinue|Where-Object{$_.ProviderName -match 'TerminalServices|RemoteDesktop|Service Control Manager'}|Select-Object -First 100 TimeCreated,Id,ProviderName,LevelDisplayName,Message
$events|Export-Csv (Join-Path $OutputPath "remote_connectivity_events_$RunStamp.csv") -NoTypeInformation -Encoding UTF8
$html="<h1>Remote Connectivity Diagnostic - $env:COMPUTERNAME</h1><p>Generated $(Get-Date)</p><h2>Services</h2>$($services|ConvertTo-Html -Fragment)<h2>Recent Events</h2>$($events|ConvertTo-Html -Fragment)"
$html|ConvertTo-Html -Title 'Remote Connectivity Diagnostic'|Set-Content (Join-Path $OutputPath "remote_connectivity_$RunStamp.html") -Encoding UTF8
$services|Format-Table -AutoSize
Write-Host "Reports saved to: $OutputPath" -ForegroundColor Green
Start-Process explorer.exe -ArgumentList "`"$OutputPath`"" -ErrorAction SilentlyContinue
