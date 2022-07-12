#requires -version 2

<#
.SYNOPSIS
  Install Hyper-V
.PARAMETER <Parameter_Name>
   None
.OUTPUTS
  Hyper-V is installed on the VM
.NOTES
  Version:        1.0
  Author:         Arambarri Federico
  Creation Date:  19/05/20222
  Purpose/Change: Initial script development
  
.EXAMPLE
  Installing-Hyper-V-And-Restart
#>
function Installing-Hyper-V-And-Restart {
    Write-Output "Installing Hyper-V and restart"
    Enable-WindowsOptionalFeature -Online -FeatureName Containers -All -NoRestart
    Enable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -NoRestart
    Install-WindowsFeature -Name Hyper-V -IncludeAllSubFeature -IncludeManagementTools -Restart
}

