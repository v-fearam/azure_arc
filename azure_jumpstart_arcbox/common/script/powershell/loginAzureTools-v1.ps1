#requires -version 2

<#
.SYNOPSIS
  Log the azure command line tools
.PARAMETER <Parameter_Name>
.OUTPUTS
  az cli and az powersell login 
.NOTES
  Version:        1.0
  Author:         Arambarri Federico
  Creation Date:  23/05/20222
  Purpose/Change: Initial script development
  
.EXAMPLE
  Arbox-Login-Azure-Tools
#>
function Arbox-Login-Azure-Tools {
    # Required for azcopy
    Write-Header "Az PowerShell Login"
    $azurePassword = ConvertTo-SecureString $Env:spnClientSecret -AsPlainText -Force
    $psCred = New-Object System.Management.Automation.PSCredential($Env:spnClientID , $azurePassword)
    Connect-AzAccount -Credential $psCred -TenantId $Env:spnTenantId -ServicePrincipal

    # Required for CLI commands
    Write-Header "Az CLI Login"
    az login --service-principal --username $Env:spnClientID --password $Env:spnClientSecret --tenant $Env:spnTenantId
}