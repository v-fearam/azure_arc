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
    [string]$arcDcName,
    [string]$azureLocation,
    [string]$stagingStorageAccountName,
    [string]$workspaceName,
    [string]$deploySQLMI,
    [string]$SQLMIHA,    
    [string]$deployPostgreSQL,
    [string]$ArcK8sClusterName,
    [string]$templateBaseUrl,
    [string]$profileRootBaseUrl
)

[System.Environment]::SetEnvironmentVariable('adminUsername', $adminUsername, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('spnClientID', $spnClientId, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('spnClientSecret', $spnClientSecret, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('spnTenantId', $spnTenantId, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('spnAuthority', $spnAuthority, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('resourceGroup', $resourceGroup, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('AZDATA_USERNAME', $azdataUsername, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('AZDATA_PASSWORD', $azdataPassword, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('ACCEPT_EULA', $acceptEula, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('arcDcName', $arcDcName, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('subscriptionId', $subscriptionId, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('azureLocation', $azureLocation, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('stagingStorageAccountName', $stagingStorageAccountName, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('workspaceName', $workspaceName, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('deploySQLMI', $deploySQLMI, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('SQLMIHA', $SQLMIHA, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('deployPostgreSQL', $deployPostgreSQL, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('ArcK8sClusterName', $ArcK8sClusterName, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('templateBaseUrl', $templateBaseUrl, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('profileRootBaseUrl', $profileRootBaseUrl, [System.EnvironmentVariableTarget]::Machine)

# Create path
$Env:tempDir = "C:\Temp"
New-Item -Path $Env:tempDir -ItemType directory -Force

Start-Transcript "$Env:tempDir\Bootstrap.log"

#Install Modules
Invoke-WebRequest -Uri ($profileRootBaseUrl + "..\common\script\powershell\CreateJumpstartModule.ps1") -OutFile $Env:tempDir\CreateJumpstartModule.ps1
. $Env:tempDir/CreateJumpstartModule.ps1
CreateJumpstartModule -ProfileRootBaseUrl $profileRootBaseUrl -Folder $Env:ProgramFiles

Invoke-WebRequest -Uri ($profileRootBaseUrl + "..\common\script\powershell\ArcDataProfile.ps1") -OutFile $PsHome\Profile.ps1
. $PsHome\Profile.ps1

BootstrapArcData -ProfileRootBaseUrl $profileRootBaseUrl -TemplateBaseUrl $templateBaseUrl -AdminUsername $adminUsername -Folder $Env:tempDir

# Downloading GitHub artifacts for DataServicesLogonScript.ps1
Invoke-WebRequest -Uri ($templateBaseUrl + "artifacts/capiStorageClass.yaml") -OutFile "$Env:tempDir\capiStorageClass.yaml"

# Schedule a task for DataServicesLogonScript.ps1
AddLogonScript -AdminUsername $adminUsername -TaskName "DataServicesLogonScript" -Script "$Env:tempDir\DataServicesLogonScript.ps1"

# Disable Windows Server Manager Scheduled Task
Get-ScheduledTask -TaskName ServerManager | Disable-ScheduledTask

# Clean up Bootstrap.log
Stop-Transcript
$logSuppress = Get-Content "$Env:tempDir\Bootstrap.log" -Force | Where { $_ -notmatch "Host Application: powershell.exe" } 
$logSuppress | Set-Content "$Env:tempDir\Bootstrap.log" -Force