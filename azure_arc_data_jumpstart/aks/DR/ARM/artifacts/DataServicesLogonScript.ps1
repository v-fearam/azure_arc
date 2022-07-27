Start-Transcript -Path C:\Temp\DataServicesLogonScript.log

# Funtion repository
function GettingAKSClusterCredentialsKubeconfigFile {
    param (
        [string]$resourceGroup,
        [string]$primaryClusterName,
        [string]$secondaryClusterName
    )
    # Getting AKS cluster credentials kubeconfig file
    Write-Output "Getting AKS cluster credentials for the primary cluster"
    Write-Output "`n"
    az aks get-credentials --resource-group $resourceGroup `
        --name $primaryClusterName --admin
    Write-Output "`n"
    Write-Output "Checking kubernetes nodes"
    Write-Output "`n"
    kubectl get nodes
    Write-Output "`n"

    Write-Output "Getting AKS cluster credentials for the secondary cluster"
    Write-Output "`n"
    az aks get-credentials --resource-group $resourceGroup `
        --name $secondaryClusterName --admin
    Write-Output "`n"

    Write-Output "Checking kubernetes nodes"
    Write-Output "`n"
    kubectl get nodes
    Write-Output "`n"
}
function AKSClusterAsAnAzureArcEnabledKubernetesCluster {
    param (
        [string]$adminUsername,
        [string]$connectedClusterName,
        [string]$resourceGroup,
        [string]$azureLocation,
        [string]$workspaceName
    )    
    # Creating Kubect aliases
    kubectx primary="$connectedClusterName-admin"
  
    # Localize kubeconfig
    $Env:KUBECONFIG = "C:\Users\$adminUsername\.kube\config"
  
    # Create Kubernetes - Azure Arc Cluster for the primary cluster
    kubectx primary
    az connectedk8s connect --name $connectedClusterName `
        --resource-group $resourceGroup `
        --location $azureLocation `
        --tags 'Project=jumpstart_azure_arc_data_services'

    Start-Sleep -Seconds 10

    # Enabling Container Insights cluster extension on primary cluster
    $workspaceId = $(az resource show --resource-group $resourceGroup --name $workspaceName --resource-type "Microsoft.OperationalInsights/workspaces" --query properties.customerId -o tsv)
    az k8s-extension create --name "azuremonitor-containers" --cluster-name $connectedClusterName --resource-group $resourceGroup --cluster-type connectedClusters --extension-type Microsoft.AzureMonitor.Containers --configuration-settings logAnalyticsWorkspaceResourceID=$workspaceId
  
    # Monitor pods across arc namespace
    return (Start-Process -PassThru PowerShell { for (0 -lt 1) { kubectl get pod -n arc; Start-Sleep -Seconds 5; Clear-Host } })
}
# Main Script
# Deployment environment variables
$primaryConnectedClusterName = "Arc-DataSvc-AKS-Primary"
$secondaryConnectedClusterName = "Arc-DataSvc-AKS-Secondary"
$clusterName = $Env:clusterName
$primaryClusterName = $clusterName + "-Primary"
$secondaryClusterName = $clusterName + "-Secondary"
$primaryDcName = "jumpstart-primary-dc"
$secondaryDcName = "jumpstart-secondary-dc"

. $Env:tempDir/CommonDataServicesLogonScript.ps1 -extraAzExtensions @("customlocation")

SetDefaultSubscription -subscriptionId $Env:subscriptionId

InstallingAzureDataStudioExtensions @("microsoft.azcli", "microsoft.azuredatastudio-postgresql", "Microsoft.arc")

# Creating Azure Data Studio desktop shortcut
Add-Desktop-Shortcut -shortcutName "Azure Data Studio" -targetPath "C:\Program Files\Azure Data Studio\azuredatastudio.exe" -username $Env:adminUsername

RegisteringAzureArcProviders @("Kubernetes", "KubernetesConfiguration", "ExtendedLocation", "AzureArcData")

GettingAKSClusterCredentialsKubeconfigFile -resourceGroup $Env:resourceGroup -primaryClusterName $primaryClusterName -secondaryClusterName $secondaryClusterName

# Onboarding the AKS cluster as an Azure Arc-enabled Kubernetes cluster
Write-Output "Onboarding the cluster as an Azure Arc-enabled Kubernetes cluster"
$kubectlMonShellPrimary = (AKSClusterAsAnAzureArcEnabledKubernetesCluster -adminUsername $Env:adminUsername -connectedClusterName $primaryConnectedClusterName -resourceGroup $Env:resourceGroup -azureLocation $Env:azureLocation -workspaceName $Env:workspaceName)

Write-Output "`n"
Write-Output "Installing Azure Arc-enabled data services extension"
$InstallingAzureArcEnabledDataServicesExtensionResult = InstallingAzureArcEnabledDataServicesExtension $primaryConnectedClusterName $Env:resourceGroup
$primaryExtensionId = $InstallingAzureArcEnabledDataServicesExtensionResult[$InstallingAzureArcEnabledDataServicesExtensionResult.length - 1]
$primaryConnectedClusterId = $InstallingAzureArcEnabledDataServicesExtensionResult[$InstallingAzureArcEnabledDataServicesExtensionResult.length - 2]

CreateCustomLocation -resourceGroup $Env:resourceGroup -connectedClusterId $primaryConnectedClusterId -extensionId $primaryExtensionId -KUBECONFIG $Env:KUBECONFIG -name 'jumpstart-primary-cl'

# Deploying Azure Arc Data Controller
Write-Output "`n"
Write-Output "Deploying Azure Arc Data Controller"
Copy-Item "$Env:TempDir\dataController.parameters.json" -Destination "$Env:TempDir\dataController-bkp.parameters.json"
DeployingAzureArcDataController -resourceGroup $Env:resourceGroup -directory $Env:TempDir -workspaceName $Env:workspaceName -AZDATA_USERNAME $Env:AZDATA_USERNAME -AZDATA_PASSWORD $Env:AZDATA_PASSWORD -spnClientId $Env:spnClientId -spnTenantId $Env:spnTenantId -spnClientSecret $Env:spnClientSecret -subscriptionId $Env:subscriptionId -name "jumpstart-primary-cl" -dataControllerName $primaryDcName

# Create Kubernetes - Azure Arc Cluster for the secondary cluster
# Onboarding the AKS cluster as an Azure Arc-enabled Kubernetes cluster
Write-Output "Onboarding the cluster as an Azure Arc-enabled Kubernetes cluster"
$kubectlMonShellSecondary = (AKSClusterAsAnAzureArcEnabledKubernetesCluster -adminUsername $Env:adminUsername -connectedClusterName $secondaryConnectedClusterName -resourceGroup $Env:resourceGroup -azureLocation $Env:azureLocation -workspaceName $Env:workspaceName)

Write-Output "`n"
Write-Output "Installing Azure Arc-enabled data services extension"
$InstallingAzureArcEnabledDataServicesExtensionResult = InstallingAzureArcEnabledDataServicesExtension $secondaryConnectedClusterName $Env:resourceGroup
$secondaryExtensionId = $InstallingAzureArcEnabledDataServicesExtensionResult[$InstallingAzureArcEnabledDataServicesExtensionResult.length - 1]
$secondaryConnectedClusterId = $InstallingAzureArcEnabledDataServicesExtensionResult[$InstallingAzureArcEnabledDataServicesExtensionResult.length - 2]

CreateCustomLocation -resourceGroup $Env:resourceGroup -connectedClusterId $secondaryConnectedClusterId -extensionId $secondaryExtensionId -KUBECONFIG $Env:KUBECONFIG -name 'jumpstart-secondary-cl'

# Deploying Azure Arc Data Controller
Write-Output "`n"
Write-Output "Deploying Azure Arc Data Controller"
Copy-Item "$Env:TempDir\dataController-bkp.parameters.json" -Destination "$Env:TempDir\dataController.parameters.json"
DeployingAzureArcDataController -resourceGroup $Env:resourceGroup -directory $Env:TempDir -workspaceName $Env:workspaceName -AZDATA_USERNAME $Env:AZDATA_USERNAME -AZDATA_PASSWORD $Env:AZDATA_PASSWORD -spnClientId $Env:spnClientId -spnTenantId $Env:spnTenantId -spnClientSecret $Env:spnClientSecret -subscriptionId $Env:subscriptionId -name 'jumpstart-secondary-cl' -dataControllerName $secondaryDcName

# If flag set, deploy SQL MI
if ( $Env:deploySQLMI -eq $true ) {
    & "$Env:TempDir\DeploySQLMI.ps1"
}

# Enabling data controller auto metrics & logs upload to log analytics on the primary cluster
kubectx primary
EnablingDataControllerAutoMetrics -resourceGroup $Env:resourceGroup -workspaceName $Env:workspaceName -name $primaryDcName

# Enabling data controller auto metrics & logs upload to log analytics on the secondary cluster
kubectx secondary
EnablingDataControllerAutoMetrics -resourceGroup $Env:resourceGroup -workspaceName $Env:workspaceName -name $secondaryDcName

# Applying Azure Data Studio settings template file and operations url shortcut
if ( $Env:deploySQLMI -eq $true) {
    CopyingAzureDataStudioSettingsTemplateFile -adminUsername $Env:adminUsername -directory $Env:TempDir

    # Creating desktop url shortcuts for built-in Grafana and Kibana services
    $GrafanaURL = kubectl get service/metricsui-external-svc -n arc -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
    $GrafanaURL = "https://" + $GrafanaURL + ":3000"
    Add-URL-Shortcut-Desktop -url $GrafanaURL -name "Grafana" -USERPROFILE $Env:USERPROFILE

    $KibanaURL = kubectl get service/logsui-external-svc -n arc -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
    $KibanaURL = "https://" + $KibanaURL + ":5601"
    Add-URL-Shortcut-Desktop -url $KibanaURL -name "Kibana" -USERPROFILE $Env:USERPROFILE
}

Write-Output "`n"
Write-Output "Switching to primary"
kubectx primary
Write-Output "`n"

# Changing to Client VM wallpaper
ChangingToClientVMWallpaper -directory $Env:TempDir

# Kill the open PowerShell monitoring kubectl get pods
Stop-Process -Id $kubectlMonShellPrimary.Id
Stop-Process -Id $kubectlMonShellSecondary.Id

# Removing the LogonScript Scheduled Task so it won't run on next reboot
Unregister-ScheduledTask -TaskName "DataServicesLogonScript" -Confirm:$false
Start-Sleep -Seconds 5

Stop-Process -Name powershell -Force

Stop-Transcript