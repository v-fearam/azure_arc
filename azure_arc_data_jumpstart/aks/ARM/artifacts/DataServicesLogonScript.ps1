Start-Transcript -Path "$Env:tempDir\DataServicesLogonScript.log"

$connectedClusterName = "Arc-DataSvc-AKS"

InitializeArcDataCommonAtLogonScript -spnClientId $Env:spnClientId -spnClientSecret $Env:spnClientSecret -spnTenantId $Env:spnTenantId -adminUsername $Env:adminUsername  -subscriptionId $Env:subscriptionId

GetAKSClusterCredentialsKubeconfigFile -resourceGroup $Env:resourceGroup -clusterName $connectedClusterName

# Localize kubeconfig
$Env:KUBECONTEXT = kubectl config current-context
$Env:KUBECONFIG = "C:\Users\$Env:adminUsername\.kube\config"
Start-Sleep -Seconds 20

AKSClusterAsAnAzureArcEnabledKubernetesCluster -connectedClusterName $connectedClusterName -resourceGroup $Env:resourceGroup -azureLocation $Env:azureLocation -workspaceName $Env:workspaceName -KUBECONTEXT $Env:KUBECONTEXT -KUBECONFIG $Env:KUBECONFIG

# Monitor pods across arc namespace
$kubectlMonShell = Start-Process -PassThru PowerShell {for (0 -lt 1) {kubectl get pod -n arc; Start-Sleep -Seconds 5; Clear-Host }}

InstallAzureArcEnabledDataServicesExtension -resourceGroup $Env:resourceGroup -clusterName $connectedClusterName

CreateCustomLocation -resourceGroup $Env:resourceGroup -clusterName $connectedClusterName -KUBECONFIG $Env:KUBECONFIG

DeployAzureArcDataController -resourceGroup $Env:resourceGroup -folder $Env:TempDir -workspaceName $Env:workspaceName -AZDATA_USERNAME $Env:AZDATA_USERNAME -AZDATA_PASSWORD $Env:AZDATA_PASSWORD -spnClientId $Env:spnClientId -spnTenantId $Env:spnTenantId -spnClientSecret $Env:spnClientSecret -subscriptionId $Env:subscriptionId

# If flag set, deploy SQL MI
if ( $Env:deploySQLMI -eq $true -and $Env:enableADAuth -eq $false)
{
& "$Env:TempDir\DeploySQLMI.ps1"
}

# if ADDS domainname is passed as parameter, deploy SQLMI with AD auth support
if ($Env:deploySQLMI -eq $true -and $Env:enableADAuth -eq $true)
{
& "$Env:TempDir\DeploySQLMIADAuth.ps1"
}

# If flag set, deploy PostgreSQL
if ( $Env:deployPostgreSQL -eq $true )
{
& "$Env:TempDir\DeployPostgreSQL.ps1"
}

EnablingDataControllerAutoMetrics -resourceGroup $Env:resourceGroup -workspaceName $Env:workspaceName

ApplyAzureDataStudioSettingsTemplateFileAndOperationsUrlShortcut -adminUsername $Env:adminUsername -folder $Env:TempDir -userProfile $Env:USERPROFILE -deploySQLMI $Env:deploySQLMI -deployPostgreSQL $Env:deployPostgreSQL

# Changing to Client VM wallpaper
ChangingToClientVMWallpaper -folder $Env:TempDir

# Kill the open PowerShell monitoring kubectl get pods
Stop-Process -Id $kubectlMonShell.Id

# Removing the LogonScript Scheduled Task so it won't run on next reboot
Unregister-ScheduledTask -TaskName "DataServicesLogonScript" -Confirm:$false
Start-Sleep -Seconds 5

Stop-Process -Name powershell -Force

Stop-Transcript