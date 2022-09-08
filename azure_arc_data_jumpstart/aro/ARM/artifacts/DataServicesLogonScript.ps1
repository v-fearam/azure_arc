Start-Transcript -Path C:\Temp\DataServicesLogonScript.log

# Local Functions
function InstallAroCli {
    param (
        [string]$folder
    )
    # Install ARO CLI
    Write-Header "Installing the ARO CLI..."
    Invoke-WebRequest "https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/openshift-client-windows.zip" -OutFile "C:\Temp\openshift-client-windows.zip"
    mkdir $folder\OpenShift
    Expand-Archive -Force -Path "C:\Temp\openshift-client-windows.zip" -DestinationPath $folder\OpenShift
    Write-Output "Adding ARO Cli to envrionment variables for this session"
    $env:Path += ";$folder\OpenShift"
    [Environment]::SetEnvironmentVariable(
        "Path",
        [Environment]::GetEnvironmentVariable("Path", [EnvironmentVariableTarget]::Machine) + ";$folder\OpenShift",
        [EnvironmentVariableTarget]::Machine)
}
function GetAroCredentials {
    param (
        [string]$clusterName,
        [string]$resourceGroup 
    )
    Write-Header "Getting ARO cluster credentials"
    $kubcepass = (az aro list-credentials --name $clusterName --resource-group $resourceGroup --query "kubeadminPassword" -o tsv)
    $apiServer = (az aro show -g $resourceGroup -n $clusterName --query apiserverProfile.url -o tsv)
    oc login $apiServer -u kubeadmin -p $kubcepass
    oc adm policy add-scc-to-user privileged system:serviceaccount:azure-arc:azure-arc-kube-aad-proxy-sa
    oc adm policy add-scc-to-user hostaccess system:serviceaccount:azure-arc-data:sa-arc-metricsdc-reader

    Write-Header "Checking kubernetes nodes"
    kubectl get nodes
}

# Main Script
# Deployment environment variables
$connectedClusterName = "Arc-Data-ARO"

InitializeArcDataCommonAtLogonScript -spnClientId $Env:spnClientId -spnClientSecret $Env:spnClientSecret -spnTenantId $Env:spnTenantId -adminUsername $Env:adminUsername  -subscriptionId $Env:subscriptionId -extraAzExtensions @("customlocation", "k8s-configuration") -arcProviderList @("Kubernetes", "KubernetesConfiguration", "ExtendedLocation", "AzureArcData", "RedHatOpenShift")

InstallAroCli -folder $Env:TempDir

GetAroCredentials -clusterName $connectedClusterName -resourceGroup $Env:resourceGroup

# Localize kubeconfig
$Env:KUBECONTEXT = kubectl config current-context
$Env:KUBECONFIG = "C:\Users\$Env:adminUsername\.kube\config"

Start-Sleep -Seconds 10

AKSClusterAsAnAzureArcEnabledKubernetesCluster -connectedClusterName $connectedClusterName -resourceGroup $Env:resourceGroup -azureLocation $Env:azureLocation -workspaceName $Env:workspaceName -KUBECONFIG $Env:KUBECONFIG -KUBECONTEXT $Env:KUBECONTEXT

# Monitor pods across arc namespace
$kubectlMonShell = Start-Process -PassThru PowerShell { for (0 -lt 1) { kubectl get pod -n arc; Start-Sleep -Seconds 5; Clear-Host } }

# Deploying security context
Write-Header "Adding security context for ARO"
kubectl create namespace arc
kubectl apply -f $Env:TempDir\AROSCC.yaml --namespace arc

Start-Sleep -Seconds 10

InstallAzureArcEnabledDataServicesExtension -resourceGroup $Env:resourceGroup -clusterName $connectedClusterName

CreateCustomLocation -resourceGroup $Env:resourceGroup -clusterName $connectedClusterName -KUBECONFIG $Env:KUBECONFIG

DeployAzureArcDataController -resourceGroup $Env:resourceGroup -folder $Env:TempDir -workspaceName $Env:workspaceName -AZDATA_USERNAME $Env:AZDATA_USERNAME -AZDATA_PASSWORD $Env:AZDATA_PASSWORD -spnClientId $Env:spnClientId -spnTenantId $Env:spnTenantId -spnClientSecret $Env:spnClientSecret -subscriptionId $Env:subscriptionId

# If flag set, deploy SQL MI
if ( $Env:deploySQLMI -eq $true ) {
    . "$Env:TempDir\DeploySQLMI.ps1"
    DeployAzureArcSQLManagedInstance -resourceGroup $Env:resourceGroup -folder $Env:TempDir -adminUsername $Env:adminUsername -azdataUsername $Env:AZDATA_USERNAME -azdataPassword $env:AZDATA_PASSWORD -subscriptionId $Env:subscriptionId -SQLMIHA $env:SQLMIHA -deployPostgreSQL $Env:deployPostgreSQL
}

# If flag set, deploy PostgreSQL
if ( $Env:deployPostgreSQL -eq $true ) {
    . "$Env:TempDir\DeployPostgreSQL.ps1"
    DeployAzureArcPostgreSQL  -resourceGroup $Env:resourceGroup -folder $Env:TempDir -azdataPassword $env:AZDATA_PASSWORD -subscriptionId $Env:subscriptionId -deploySQLMI $env:deploySQLMI
}

EnableDataControllerAutoMetrics -resourceGroup $Env:resourceGroup -workspaceName $Env:workspaceName

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