Start-Transcript -Path "$Env:TempDir\DataServicesLogonScript.log"

# Deployment environment variables
$primaryConnectedClusterName = "Arc-DataSvc-AKS-Primary"
$secondaryConnectedClusterName = "Arc-DataSvc-AKS-Secondary"
$clusterName = $Env:clusterName
$primaryClusterName = $clusterName+"-Primary"
$secondaryClusterName = $clusterName+"-Secondary"
$primaryDcName = "jumpstart-primary-dc"
$secondaryDcName= "jumpstart-secondary-dc"

InitializeArcDataCommonAtLogonScript -extraAzExtensions @("customlocation") -spnClientId $Env:spnClientId -spnClientSecret $Env:spnClientSecret -spnTenantId $Env:spnTenantId -adminUsername $Env:adminUsername  -subscriptionId $Env:subscriptionId

GetAKSClusterCredentialsKubeconfigFile -resourceGroup $Env:resourceGroup -clusterName $primaryClusterName

GetAKSClusterCredentialsKubeconfigFile -resourceGroup $Env:resourceGroup -clusterName $secondaryClusterName

# Creating Kubect aliases
kubectx primary="$primaryConnectedClusterName-admin"
kubectx secondary="$secondaryConnectedClusterName-admin"

# Localize kubeconfig
kubectx primary
$Env:KUBECONTEXT = kubectl config current-context
$Env:KUBECONFIG = "C:\Users\$Env:adminUsername\.kube\config"

AKSClusterAsAnAzureArcEnabledKubernetesCluster -connectedClusterName $primaryConnectedClusterName -resourceGroup $Env:resourceGroup -azureLocation $Env:azureLocation -workspaceName $Env:workspaceName -KUBECONTEXT $Env:KUBECONTEXT -KUBECONFIG $Env:KUBECONFIG

# Monitor pods across arc namespace
$kubectlMonShell = Start-Process -PassThru PowerShell {for (0 -lt 1) {kubectl get pod -n arc; Start-Sleep -Seconds 5; Clear-Host }}

InstallAzureArcEnabledDataServicesExtension -resourceGroup $Env:resourceGroup -clusterName $primaryConnectedClusterName

CreateCustomLocation -jumpstartcl 'jumpstart-primary-cl' -resourceGroup $Env:resourceGroup -clusterName $primaryConnectedClusterName -KUBECONFIG $Env:KUBECONFIG

Copy-Item "$Env:TempDir\dataController.parameters.json" -Destination "$Env:TempDir\dataController.parameters.json.backup"

DeployAzureArcDataController -jumpstartcl "jumpstart-primary-cl" -jumpstartdc $primaryDcName -resourceGroup $Env:resourceGroup -folder $Env:TempDir -workspaceName $Env:workspaceName -AZDATA_USERNAME $Env:AZDATA_USERNAME -AZDATA_PASSWORD $Env:AZDATA_PASSWORD -spnClientId $Env:spnClientId -spnTenantId $Env:spnTenantId -spnClientSecret $Env:spnClientSecret -subscriptionId $Env:subscriptionId

# Create Kubernetes - Azure Arc Cluster for the secondary cluster
kubectx secondary
$Env:KUBECONTEXT = kubectl config current-context

AKSClusterAsAnAzureArcEnabledKubernetesCluster -connectedClusterName $secondaryConnectedClusterName -resourceGroup $Env:resourceGroup -azureLocation $Env:azureLocation -workspaceName $Env:workspaceName -KUBECONTEXT $Env:KUBECONTEXT -KUBECONFIG $Env:KUBECONFIG

InstallAzureArcEnabledDataServicesExtension -resourceGroup $Env:resourceGroup -clusterName $secondaryConnectedClusterName

CreateCustomLocation -jumpstartcl 'jumpstart-secondary-cl' -resourceGroup $Env:resourceGroup -clusterName $secondaryConnectedClusterName -KUBECONFIG $Env:KUBECONFIG

Copy-Item "$Env:TempDir\dataController.parameters.json.backup" -Destination "$Env:TempDir\dataController.parameters.json"

DeployAzureArcDataController -jumpstartcl "jumpstart-secondary-cl" -jumpstartdc $secondaryDcName -resourceGroup $Env:resourceGroup -folder $Env:TempDir -workspaceName $Env:workspaceName -AZDATA_USERNAME $Env:AZDATA_USERNAME -AZDATA_PASSWORD $Env:AZDATA_PASSWORD -spnClientId $Env:spnClientId -spnTenantId $Env:spnTenantId -spnClientSecret $Env:spnClientSecret -subscriptionId $Env:subscriptionId

# If flag set, deploy SQL MI
if ( $Env:deploySQLMI -eq $true )
{
& "$Env:TempDir\DeploySQLMI.ps1"
}

EnableDataControllerAutoMetrics -resourceGroup $Env:resourceGroup -workspaceName $Env:workspaceName -jumpstartdc $primaryDcName

EnableDataControllerAutoMetrics -resourceGroup $Env:resourceGroup -workspaceName $Env:workspaceName -jumpstartdc $secondaryDcName

ApplyAzureDataStudioSettingsTemplateFileAndOperationsUrlShortcut -adminUsername $Env:adminUsername -folder $Env:TempDir -userProfile $Env:USERPROFILE -deploySQLMI $Env:deploySQLMI -deployPostgreSQL $Env:deployPostgreSQL

Write-Host "`n"
Write-Host "Switching to primary"
kubectx primary
Write-Host "`n"

# Changing to Client VM wallpaper
ChangingToClientVMWallpaper -folder $Env:TempDir

# Kill the open PowerShell monitoring kubectl get pods
Stop-Process -Id $kubectlMonShell.Id

# Removing the LogonScript Scheduled Task so it won't run on next reboot
Unregister-ScheduledTask -TaskName "DataServicesLogonScript" -Confirm:$false
Start-Sleep -Seconds 5

Stop-Process -Name powershell -Force

Stop-Transcript