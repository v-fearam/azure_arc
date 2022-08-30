Start-Transcript -Path C:\Temp\DataServicesLogonScript.log

InitializeArcDataCommonAtLogonScript 

DownloadCapiFiles -stagingStorageAccountName "$Env:stagingStorageAccountName" -resourceGroup "$Env:resourceGroup" -username "$Env:USERNAME" -folder "$Env:TempDir"

# Localize kubeconfig
$Env:KUBECONTEXT = kubectl config current-context
$Env:KUBECONFIG = "C:\Users\$Env:adminUsername\.kube\config"

Start-Sleep -Seconds 10

$kubectlMonShell = Start-Process -PassThru PowerShell { for (0 -lt 1) { kubectl get pod -n arc; Start-Sleep -Seconds 5; Clear-Host } }

InstallAzureArcEnabledDataServicesExtension -resourceGroup $Env:resourceGroup -clusterName $Env:ArcK8sClusterName

CreateCustomLocation -resourceGroup $Env:resourceGroup -clusterName $Env:ArcK8sClusterName -KUBECONFIG $Env:KUBECONFIG

DeployAzureArcDataController -resourceGroup $Env:resourceGroup -directory $Env:TempDir -workspaceName $Env:workspaceName -AZDATA_USERNAME $Env:AZDATA_USERNAME -AZDATA_PASSWORD $Env:AZDATA_PASSWORD -spnClientId $Env:spnClientId -spnTenantId $Env:spnTenantId -spnClientSecret $Env:spnClientSecret -subscriptionId $Env:subscriptionId

# If flag set, deploy SQL MI
if ( $Env:deploySQLMI -eq $true ) {
    & "$Env:TempDir\DeploySQLMI.ps1"
}

# If flag set, deploy PostgreSQL
if ( $Env:deployPostgreSQL -eq $true ) {
    & "$Env:TempDir\DeployPostgreSQL.ps1"
}

EnablingDataControllerAutoMetrics -resourceGroup $Env:resourceGroup -workspaceName $Env:workspaceName

ApplyAzureDataStudioSettingsTemplateFileAndOperationsUrlShortcut -adminUsername $Env:adminUsername -folder $Env:TempDir -userProfile $Env:USERPROFILE -deploySQLMI $Env:deploySQLMI -deployPostgreSQL $Env:deployPostgreSQL

# Changing to Client VM wallpaper
ChangingToClientVMWallpaper -directory $Env:TempDir

# Kill the open PowerShell monitoring kubectl get pods
Stop-Process -Id $kubectlMonShell.Id

# Removing the LogonScript Scheduled Task so it won't run on next reboot
Unregister-ScheduledTask -TaskName "DataServicesLogonScript" -Confirm:$false
Start-Sleep -Seconds 5

Stop-Process -Name powershell -Force

Stop-Transcript