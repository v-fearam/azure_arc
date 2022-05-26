#requires -version 2

<#
.SYNOPSIS
  Configure a script to be trigger at log on 
.PARAMETER <Parameter_Name>
    $adminUsername admin username to configure the task
    $taskName name used to register the task
    $script script to be executed
.OUTPUTS
  The $script executes the first time the user log on to the vm
.NOTES
  Version:        1.0
  Author:         Arambarri Federico
  Creation Date:  18/05/20222
  Purpose/Change: Initial script development
  
.EXAMPLE
  Configuring-Logon-Scripts $adminUsername "ArcServersLogonScript" ("$Env:ArcBoxDir\ArcServersLogonScript.ps1")
#>
function Configuring-Logon-Scripts {
    param(
        [string] $adminUsername,
        [string] $taskName,
        [string] $script
    )
    $Trigger = New-ScheduledTaskTrigger -AtLogOn
    $Action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument $script
    Register-ScheduledTask -TaskName $taskName -Trigger $Trigger -User $adminUsername -Action $Action -RunLevel "Highest" -Force
}