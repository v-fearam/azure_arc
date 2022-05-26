#requires -version 2

<#
.SYNOPSIS
  Downloading RancherK3s Kubeconfig and Install Logs
.PARAMETER <Parameter_Name>
.OUTPUTS
  The files are copy to the VM 
.NOTES
  Version:        1.0
  Author:         Arambarri Federico
  Creation Date:  24/05/20222
  Purpose/Change: Initial script development
  
.EXAMPLE
  Download-RancherK3s-Files
#>

function Download-RancherK3s-Files {
  # Downloading Rancher K3s cluster kubeconfig file
  Write-Header "Downloading K3s Kubeconfig"
  $sourceFile = "https://$Env:stagingStorageAccountName.blob.core.windows.net/staging-k3s/config"
  $context = (Get-AzStorageAccount -ResourceGroupName $Env:resourceGroup).Context
  $sas = New-AzStorageAccountSASToken -Context $context -Service Blob -ResourceType Object -Permission racwdlup
  $sourceFile = $sourceFile + $sas
  azcopy cp --check-md5 FailIfDifferentOrMissing $sourceFile  "C:\Users\$Env:USERNAME\.kube\config-k3s"

  # Downloading 'installK3s.log' log file
  Write-Header "Downloading K3s Install Logs"
  $sourceFile = "https://$Env:stagingStorageAccountName.blob.core.windows.net/staging-k3s/installK3s.log"
  $sourceFile = $sourceFile + $sas
  azcopy cp --check-md5 FailIfDifferentOrMissing $sourceFile  "$Env:ArcBoxLogsDir\installK3s.log"
}
