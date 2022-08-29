Start-Transcript -Path C:\Temp\DataServicesLogonScript.log

# Deployment environment variables
$connectedClusterName = "Arc-Data-ARO"

. $Env:tempDir/ArcDataCommonDataServicesLogonScript.ps1 -extraAzExtensions @("customlocation", "k8s-configuration")

# Install ARO CLI
Write-Output "Installing the ARO CLI..."
Invoke-WebRequest "https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/openshift-client-windows.zip" -OutFile "C:\Temp\openshift-client-windows.zip"
Write-Output "`n"
mkdir $Env:TempDir\OpenShift
Expand-Archive -Force -Path "C:\Temp\openshift-client-windows.zip" -DestinationPath $Env:TempDir\OpenShift
Write-Output "`n"
Write-Output "Adding ARO Cli to envrionment variables for this session"
$env:Path += ";$Env:TempDir\OpenShift"
[Environment]::SetEnvironmentVariable(
    "Path",
    [Environment]::GetEnvironmentVariable("Path", [EnvironmentVariableTarget]::Machine) + ";$Env:TempDir\OpenShift",
    [EnvironmentVariableTarget]::Machine)
Write-Output "`n"

SetDefaultSubscription -subscriptionId $Env:subscriptionId

InstallingAzureDataStudioExtensions @("microsoft.azcli", "microsoft.azuredatastudio-postgresql", "Microsoft.arc")

Add-Desktop-Shortcut -shortcutName "Azure Data Studio" -targetPath "C:\Program Files\Azure Data Studio\azuredatastudio.exe" -username $Env:adminUsername

RegisteringAzureArcProviders @("Kubernetes", "KubernetesConfiguration", "ExtendedLocation", "AzureArcData","RedHatOpenShift")

# Getting ARO cluster credentials kubeconfig file
Write-Output "Getting ARO cluster credentials"
Write-Output "`n"
$kubcepass=(az aro list-credentials --name $connectedClusterName --resource-group $Env:resourceGroup --query "kubeadminPassword" -o tsv)
$apiServer=(az aro show -g $Env:resourceGroup -n $Env:clusterName --query apiserverProfile.url -o tsv)
oc login $apiServer -u kubeadmin -p $kubcepass
oc adm policy add-scc-to-user privileged system:serviceaccount:azure-arc:azure-arc-kube-aad-proxy-sa
oc adm policy add-scc-to-user hostaccess system:serviceaccount:azure-arc-data:sa-arc-metricsdc-reader

Write-Output "Checking kubernetes nodes"
Write-Output "`n"
kubectl get nodes
Write-Output "`n"

# Onboarding the ARO cluster as an Azure Arc-enabled Kubernetes cluster
Write-Output "Onboarding the cluster as an Azure Arc-enabled Kubernetes cluster"
Write-Output "`n"
$kubectlMonShell = (AKSClusterAsAnAzureArcEnabledKubernetesCluster -adminUsername $Env:adminUsername -connectedClusterName $connectedClusterName -resourceGroup $Env:resourceGroup -azureLocation $Env:azureLocation -workspaceName $Env:workspaceName)

# Deploying security context
Write-Output "Adding security context for ARO"
Write-Output "`n"
kubectl create namespace arc
kubectl apply -f $Env:TempDir\AROSCC.yaml --namespace arc
Write-Output "`n"

Start-Sleep -Seconds 10

# Installing Azure Arc-enabled data services extension
Write-Output "`n"
Write-Output "Installing Azure Arc-enabled data services extension"
InstallingAzureArcEnabledDataServicesExtensionk8s -resourceGroup $Env:resourceGroup -clusterName $connectedClusterName

Write-Output "`n"
Do {
    Write-Output "Waiting for bootstrapper pod, hold tight...(20s sleeping loop)"
    Start-Sleep -Seconds 20
    $podStatus = $(if(kubectl get pods -n arc | Select-String "bootstrapper" | Select-String "Running" -Quiet){"Ready!"}Else{"Nope"})
    } while ($podStatus -eq "Nope")

$connectedClusterId = az connectedk8s show --name $connectedClusterName --resource-group $Env:resourceGroup --query id -o tsv

$extensionId = az k8s-extension show --name arc-data-services `
                                     --cluster-type connectedClusters `
                                     --cluster-name $connectedClusterName `
                                     --resource-group $Env:resourceGroup `
                                     --query id -o tsv

Start-Sleep -Seconds 20

# Create Custom Location
CreateCustomLocation -resourceGroup $Env:resourceGroup -connectedClusterId $connectedClusterId -extensionId $extensionId -KUBECONFIG $Env:KUBECONFIG

# Deploying Azure Arc Data Controller
Write-Output "`n"
Write-Output "Deploying Azure Arc Data Controller"
Write-Output "`n"
DeployingAzureArcDataController -resourceGroup $Env:resourceGroup -directory $Env:TempDir -workspaceName $Env:workspaceName -AZDATA_USERNAME $Env:AZDATA_USERNAME -AZDATA_PASSWORD $Env:AZDATA_PASSWORD -spnClientId $Env:spnClientId -spnTenantId $Env:spnTenantId -spnClientSecret $Env:spnClientSecret -subscriptionId $Env:subscriptionId

# If flag set, deploy SQL MI
if ( $Env:deploySQLMI -eq $true )
{
& "$Env:TempDir\DeploySQLMI.ps1"
}

# If flag set, deploy PostgreSQL
if ( $Env:deployPostgreSQL -eq $true )
{
& "$Env:TempDir\DeployPostgreSQL.ps1"
}

EnablingDataControllerAutoMetrics -resourceGroup $Env:resourceGroup -workspaceName $Env:workspaceName

# Applying Azure Data Studio settings template file and operations url shortcut
if ( $Env:deploySQLMI -eq $true -or $Env:deployPostgreSQL -eq $true ){
    CopyingAzureDataStudioSettingsRemplateFile -adminUsername $Env:adminUsername -directory $Env:TempDir

    # Creating desktop url shortcuts for built-in Grafana and Kibana services
    $GrafanaURL = kubectl get service/metricsui-external-svc -n arc -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
    $GrafanaURL = "https://" + $GrafanaURL + ":3000"
    Add-URL-Shortcut-Desktop -url $GrafanaURL -name "Grafana" -USERPROFILE $Env:USERPROFILE

    $KibanaURL = kubectl get service/logsui-external-svc -n arc -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
    $KibanaURL = "https://" + $KibanaURL + ":5601"
    Add-URL-Shortcut-Desktop -url $KibanaURL -name "Kibana" -USERPROFILE $Env:USERPROFILE
}

# Changing to Client VM wallpaper
ChangingToClientVMWallpaper -directory $Env:TempDir

# Kill the open PowerShell monitoring kubectl get pods
Stop-Process -Id $kubectlMonShell.Id

# Removing the LogonScript Scheduled Task so it won't run on next reboot
Unregister-ScheduledTask -TaskName "DataServicesLogonScript" -Confirm:$false
Start-Sleep -Seconds 5

Stop-Process -Name powershell -Force

Stop-Transcript