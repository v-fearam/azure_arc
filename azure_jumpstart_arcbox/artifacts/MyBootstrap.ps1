param (
    [string]$adminUsername,
    [string]$spnClientId,
    [string]$spnClientSecret,
    [string]$spnTenantId,
    [string]$spnAuthority,
    [string]$subscriptionId,
    [string]$resourceGroup,
    [string]$azdataUsername,
    [string]$azdataPassword,
    [string]$acceptEula,
    [string]$registryUsername,
    [string]$registryPassword,
    [string]$arcDcName,
    [string]$azureLocation,
    [string]$mssqlmiName,
    [string]$POSTGRES_NAME,   
    [string]$POSTGRES_WORKER_NODE_COUNT,
    [string]$POSTGRES_DATASIZE,
    [string]$POSTGRES_SERVICE_TYPE,
    [string]$stagingStorageAccountName,
    [string]$workspaceName,
    [string]$capiArcDataClusterName,
    [string]$k3sArcClusterName,
    [string]$githubUser,
    [string]$templateBaseUrl,
    [string]$flavor,
    [string]$automationTriggerAtLogon
)

[System.Environment]::SetEnvironmentVariable('adminUsername', $adminUsername, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('spnClientID', $spnClientId, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('spnClientSecret', $spnClientSecret, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('spnTenantId', $spnTenantId, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('spnAuthority', $spnAuthority, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('SPN_CLIENT_ID', $spnClientId, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('SPN_CLIENT_SECRET', $spnClientSecret, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('SPN_TENANT_ID', $spnTenantId, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('SPN_AUTHORITY', $spnAuthority, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('resourceGroup', $resourceGroup, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('AZDATA_USERNAME', $azdataUsername, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('AZDATA_PASSWORD', $azdataPassword, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('ACCEPT_EULA', $acceptEula, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('registryUsername', $registryUsername, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('registryPassword', $registryPassword, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('arcDcName', $arcDcName, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('subscriptionId', $subscriptionId, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('azureLocation', $azureLocation, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('mssqlmiName', $mssqlmiName, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('POSTGRES_NAME', $POSTGRES_NAME, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('POSTGRES_WORKER_NODE_COUNT', $POSTGRES_WORKER_NODE_COUNT, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('POSTGRES_DATASIZE', $POSTGRES_DATASIZE, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('POSTGRES_SERVICE_TYPE', $POSTGRES_SERVICE_TYPE, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('stagingStorageAccountName', $stagingStorageAccountName, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('workspaceName', $workspaceName, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('capiArcDataClusterName', $capiArcDataClusterName, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('k3sArcClusterName', $k3sArcClusterName, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('githubUser', $githubUser, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('templateBaseUrl', $templateBaseUrl, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('flavor', $flavor, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('automationTriggerAtLogon', $automationTriggerAtLogon, [System.EnvironmentVariableTarget]::Machine)

# Creating ArcBox path
Write-Output "Creating ArcBox path"
. ./arcboxPaths-v1.ps1 create

Start-Transcript -Path $Env:ArcBoxLogsDir\Bootstrap.log

. ./downloadFiles-v1.ps1
. ./setPSProfile-v1.ps1
. ./installModules-v1.ps1
. ./installChocoApps-v1.ps1
. ./configuringLogonScripts-v1.ps1
. ./installHyperVAndReboot-v1.ps1
. ./downloadScriptDependencies-v1.ps1

$ErrorActionPreference = 'SilentlyContinue'

# Copy PowerShell Profile and Reload
Set-PowerShell-Profile  ($templateBaseUrl + "artifacts\PSProfile.ps1")

# Extending C:\ partition to the maximum size
Write-Output  "Extending C:\ partition to the maximum size"
Resize-Partition -DriveLetter C -Size $(Get-PartitionSupportedSize -DriveLetter C).SizeMax

Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force

# Installing Posh-SSH PowerShell Module
Write-Output "Posh-SSH"
Install-Modules @('Posh-SSH')

# Installing DHCP service 
Write-Output "Installing DHCP service"
Install-WindowsFeature -Name "DHCP" -IncludeManagementTools

# Installing tools
Write-Output "Installing Chocolatey Apps"
Install-ChocolateyApps @("azure-cli", "az.powershell", "kubernetes-cli", "vcredist140", "microsoft-edge", "azcopy10", "vscode", "git", "7zip", "kubectx", "terraform", "putty.install", "kubernetes-helm", "ssms", "dotnetcore-3.1-sdk", "setdefaultbrowser", "zoomit")

# All flavors
Write-Output "Fetching Artifacts for All Flavors"

Download-File-Renaming ($templateBaseUrl + "../img/arcbox_wallpaper.png") $Env:ArcBoxDir\wallpaper.png

Download-Files ($templateBaseUrl + "artifacts")  @("MonitorWorkbookLogonScript.ps1", "mgmtMonitorWorkbook.parameters.json", "DeploymentStatus.ps1") $Env:ArcBoxDir

Download-Files ($templateBaseUrl + "artifacts")  @("LogInstructions.txt") $Env:ArcBoxLogsDir

Download-Files ($templateBaseUrl + "../tests/")  @("GHActionDeploy.ps1", "OpenSSHDeploy.ps1") $Env:ArcBoxDir

# ITPro
if ($flavor -eq "ITPro") {
    . ./itproProfile-v1.ps1
}

# DevOps
if ($flavor -eq "DevOps") {
    . ./devopsProfile-v1.ps1
}

# Full
if ($flavor -eq "Full") {
    . ./fullProfile-v1.ps1
}

New-Item -path alias:kubectl -value 'C:\ProgramData\chocolatey\lib\kubernetes-cli\tools\kubernetes\client\bin\kubectl.exe'
New-Item -path alias:azdata -value 'C:\Program Files (x86)\Microsoft SDKs\Azdata\CLI\wbin\azdata.cmd'

Write-Output "Creating scheduled task for MonitorWorkbookLogonScript.ps1"
Configuring-Logon-Scripts $adminUsername "MonitorWorkbookLogonScript" ("$Env:ArcBoxDir\MonitorWorkbookLogonScript.ps1")

# Disabling Windows Server Manager Scheduled Task
Get-ScheduledTask -TaskName ServerManager | Disable-ScheduledTask

Download-Scripts-Dependencies `
    -origin ($templateBaseUrl) `
    -target ($Env:ArcBoxDir) `
    -localPS @("arcboxPaths-v1","azureConfigDir-v1","loginAzureTools-v1","downloadCapiFiles-v1","downloadRancherK3sFiles-v1","mergingCAPI-K3sKubeconfigs-v1","setWallpaper-v1")
# Install Hyper-V and reboot
Installing-Hyper-V-And-Restart

Stop-Transcript