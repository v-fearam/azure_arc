Start-Transcript -Path C:\Temp\DataServicesLogonScript.log

Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled False

# Making extension install dynamic
az config set extension.use_dynamic_install=yes_without_prompt

# Required for azcopy
$azurePassword = ConvertTo-SecureString $Env:spnClientSecret -AsPlainText -Force
$psCred = New-Object System.Management.Automation.PSCredential($Env:spnClientId , $azurePassword)
Connect-AzAccount -Credential $psCred -TenantId $Env:spnTenantId -ServicePrincipal

# Login as service principal
az login --service-principal --username $Env:spnClientId --password $Env:spnClientSecret --tenant $Env:spnTenantId

InstallAzureArcDataCliExtensions

InstallAzureDataStudioExtensions

AddDesktopShortcut -ShortcutName "Azure Data Studio" -TargetPath "C:\Program Files\Azure Data Studio\azuredatastudio.exe" -Username $AdminUsername

RegisterAzureArcDataProviders

DownloadCapiFiles -StagingStorageAccountName "$Env:stagingStorageAccountName" -ResourceGroup "$Env:resourceGroup" -Username "$Env:USERNAME" -Folder "$Env:TempDir"

# Localize kubeconfig
$Env:KUBECONTEXT = kubectl config current-context
$Env:KUBECONFIG = "C:\Users\$Env:adminUsername\.kube\config"

Start-Sleep -Seconds 10

$kubectlMonShell = Start-Process -PassThru PowerShell { for (0 -lt 1) { kubectl get pod -n arc; Start-Sleep -Seconds 5; Clear-Host } }

InstallAzureArcEnabledDataServicesExtension -ResourceGroup $Env:resourceGroup -ClusterName $Env:ArcK8sClusterName

CreateCustomLocation -ResourceGroup $Env:resourceGroup -ClusterName $Env:ArcK8sClusterName -Kubeconfig $Env:KUBECONFIG

Write-Host $Env:AZDATA_PASSWORD
$AzdataPasswordSecure = ConvertTo-SecureString $Env:AZDATA_PASSWORD -AsPlainText -Force
Write-Host $AzdataPasswordSecure
DeployAzureArcDataController -ResourceGroup $Env:resourceGroup -Folder $Env:TempDir -WorkspaceName $Env:workspaceName -AzdataUsername $Env:AZDATA_USERNAME -AzdataPassword $AzdataPasswordSecure -SpnClientId $Env:spnClientId -SpnTenantId $Env:spnTenantId -SpnClientSecret $Env:spnClientSecret -SubscriptionId $Env:subscriptionId

# If flag set, deploy SQL MI
if ( $Env:deploySQLMI -eq $true ) {
    DeployAzureArcSQLManagedInstance -ResourceGroup $Env:resourceGroup -Folder $Env:TempDir -AdminUsername $Env:adminUsername -AzdataUsername $Env:AZDATA_USERNAME -AzdataPassword $AzdataPasswordSecure -SubscriptionId $Env:subscriptionId -SQLMIHA $Env:SQLMIHA -DeployPostgreSQL $Env:deployPostgreSQL
}

# If flag set, deploy PostgreSQL
if ( $Env:deployPostgreSQL -eq $true ) {
    DeployAzureArcPostgreSQL -ResourceGroup $Env:resourceGroup -Folder $Env:TempDir -AzdataPassword $AzdataPasswordSecure -SubscriptionId $Env:subscriptionId -DeploySQLMI $Env:deploySQLMI
}

EnableDataControllerAutoMetrics -ResourceGroup $Env:resourceGroup -WorkspaceName $Env:workspaceName

if ( $Env:deploySQLMI -eq $true -or $Env:deployPostgreSQL -eq $true ){
    CopyAzureDataStudioSettingsTemplateFile -AdminUsername $Env:adminUsername -Folder $Env:TempDir

    # Creating desktop url shortcuts for built-in Grafana and Kibana services 
    $GrafanaURL = kubectl get service/metricsui-external-svc -n arc -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
    $GrafanaURL = "https://" + $GrafanaURL + ":3000"
    AddDesktopShortcut -ShortcutName "Grafana" -TargetPath $GrafanaURL -Username $Env:adminUsername -UrlMode

    $KibanaURL = kubectl get service/logsui-external-svc -n arc -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
    $KibanaURL = "https://" + $KibanaURL + ":5601"
    AddDesktopShortcut -ShortcutName "Kibana" -TargetPath $KibanaURL -Username $Env:adminUsername -UrlMode
}

# Changing to Client VM wallpaper
ChangeWallpaper -Folder $Env:TempDir

# Kill the open PowerShell monitoring kubectl get pods
Stop-Process -Id $kubectlMonShell.Id

# Removing the LogonScript Scheduled Task so it won't run on next reboot
Unregister-ScheduledTask -TaskName "DataServicesLogonScript" -Confirm:$false
Start-Sleep -Seconds 5

Stop-Process -Name powershell -Force

Stop-Transcript