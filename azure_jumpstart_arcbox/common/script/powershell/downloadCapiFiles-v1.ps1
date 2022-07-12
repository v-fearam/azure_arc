#requires -version 2

<#
.SYNOPSIS
  Downloading CAPI K8s Kubeconfig and Install Logs
.PARAMETER <Parameter_Name>
.OUTPUTS
  The files are copy to the VM 
.NOTES
  Version:        1.0
  Author:         Arambarri Federico
  Creation Date:  24/05/20222
  Purpose/Change: Initial script development
  
.EXAMPLE
  Download-CAPI-Files
#>
function Download-CAPI-Files {
    # Downloading CAPI Kubernetes cluster kubeconfig file
    Write-Header "Downloading CAPI K8s Kubeconfig"
    $sourceFile = "https://$Env:stagingStorageAccountName.blob.core.windows.net/staging-capi/config"
    $context = (Get-AzStorageAccount -ResourceGroupName $Env:resourceGroup).Context
    $sas = New-AzStorageAccountSASToken -Context $context -Service Blob -ResourceType Object -Permission racwdlup
    $sourceFile = $sourceFile + $sas
    azcopy cp --check-md5 FailIfDifferentOrMissing $sourceFile  "C:\Users\$Env:USERNAME\.kube\config"

    # Downloading 'installCAPI.log' log file
    Write-Header "Downloading CAPI Install Logs"
    $sourceFile = "https://$Env:stagingStorageAccountName.blob.core.windows.net/staging-capi/installCAPI.log"
    $sourceFile = $sourceFile + $sas
    azcopy cp --check-md5 FailIfDifferentOrMissing $sourceFile  "$Env:ArcBoxLogsDir\installCAPI.log"
}
