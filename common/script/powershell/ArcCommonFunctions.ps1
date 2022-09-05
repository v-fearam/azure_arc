Write-Output "Arc Common Functions"

function Write-Header {
    param (
        [string]
        $title
    )

    Write-Host
    Write-Host ("#" * ($title.Length + 8))
    Write-Host "# - $title"
    Write-Host ("#" * ($title.Length + 8))
    Write-Host
}
function InstallChocolateyApp {
    param(
        [string[]]$chocolateyAppList
    )
    try {
        choco config get cacheLocation
    }
    catch {
        Write-Header "Chocolatey not detected, trying to install now"
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
    }
    foreach ($app in $chocolateyAppList) {
        Write-Output "Installing $app"
        & choco install $app /y -Force | Write-Output
    }
}
function BoostrapArcData {
    param (
        [string] $profileRootBaseUrl,
        [string] $templateBaseUrl,
        [string] $adminUsername,
        [string[]]$extraChocolateyAppList = @(),
        [switch] $avoidPostgreSQL,
        [switch] $avoidScriptAtLogOn,
        [string] $folder
    )
    
    $ErrorActionPreference = 'SilentlyContinue'

    # Uninstall Internet Explorer
    Disable-WindowsOptionalFeature -FeatureName Internet-Explorer-Optional-amd64 -Online -NoRestart

    # Disabling IE Enhanced Security Configuration
    Write-Header "Disabling IE Enhanced Security Configuration"
    function Disable-ieESC {
        $AdminKey = "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A7-37EF-4b3f-8CFC-4F3A74704073}"
        $UserKey = "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A8-37EF-4b3f-8CFC-4F3A74704073}"
        Set-ItemProperty -Path $AdminKey -Name "IsInstalled" -Value 0
        Set-ItemProperty -Path $UserKey -Name "IsInstalled" -Value 0
        Stop-Process -Name Explorer
        Write-Output "IE Enhanced Security Configuration (ESC) has been disabled." -ForegroundColor Green
    }
    Disable-ieESC

    # Extending C:\ partition to the maximum size
    Write-Header "Extending C:\ partition to the maximum size"
    Resize-Partition -DriveLetter C -Size $(Get-PartitionSupportedSize -DriveLetter C).SizeMax

    # Installing tools
    Write-Header "Installing Chocolatey Apps"
    $chocolateyAppList = $extraChocolateyAppList + @("azure-cli", "az.powershell", "kubernetes-cli", "kubectx", "vcredist140", "microsoft-edge", "azcopy10", "vscode", "putty.install", "kubernetes-helm", "grep", "ssms", "dotnetcore-3.1-sdk", "git", "7zip")
    InstallChocolateyApp $chocolateyAppList

    Invoke-WebRequest -Uri "https://azuredatastudio-update.azurewebsites.net/latest/win32-x64-archive/stable" -OutFile "$folder\azuredatastudio.zip"
    Invoke-WebRequest -Uri "https://aka.ms/azdata-msi" -OutFile "$folder\AZDataCLI.msi"

    # Downloading GitHub artifacts for DataServicesLogonScript.ps1
    Invoke-WebRequest -Uri ($templateBaseUrl + "artifacts/settingsTemplate.json") -OutFile "$folder/settingsTemplate.json"
    Invoke-WebRequest -Uri ($templateBaseUrl + "artifacts/DataServicesLogonScript.ps1") -OutFile "$folder/DataServicesLogonScript.ps1"
    Invoke-WebRequest -Uri ($templateBaseUrl + "artifacts/dataController.json") -OutFile "$folder/dataController.json"
    Invoke-WebRequest -Uri ($templateBaseUrl + "artifacts/dataController.parameters.json") -OutFile "$folder/dataController.parameters.json"
    Invoke-WebRequest -Uri ($templateBaseUrl + "artifacts/SQLMI.json") -OutFile "$folder/SQLMI.json"
    Invoke-WebRequest -Uri ($templateBaseUrl + "artifacts/SQLMI.parameters.json") -OutFile "$folder/SQLMI.parameters.json"

    Invoke-WebRequest -Uri ($profileRootBaseUrl + "../common/script/powershell/DeploySQLMI.ps1") -OutFile "$folder/DeploySQLMI.ps1"
    Invoke-WebRequest -Uri ($profileRootBaseUrl + "../common/script/powershell/SQLMIEndpoints.ps1") -OutFile "$folder/SQLMIEndpoints.ps1"

    if (-not $avoidPostgreSQL) {
        Invoke-WebRequest -Uri ($templateBaseUrl + "artifacts/postgreSQL.json") -OutFile "$folder/postgreSQL.json"
        Invoke-WebRequest -Uri ($templateBaseUrl + "artifacts/postgreSQL.parameters.json") -OutFile "$folder/postgreSQL.parameters.json"

        Invoke-WebRequest -Uri ($profileRootBaseUrl + "../common/script/powershell/DeployPostgreSQL.ps1") -OutFile "$folder/DeployPostgreSQL.ps1"
    }

    Invoke-WebRequest -Uri ("https://github.com/ErikEJ/SqlQueryStress/releases/download/102/SqlQueryStress.zip") -OutFile "$folder\SqlQueryStress.zip"
    Invoke-WebRequest -Uri ($profileRootBaseUrl + "../img/arcbox_wallpaper.png") -OutFile "$folder\wallpaper.png"

    Expand-Archive $folder\azuredatastudio.zip -DestinationPath 'C:\Program Files\Azure Data Studio' -Force
    Start-Process msiexec.exe -Wait -ArgumentList '/I C:\Temp\AZDataCLI.msi /quiet'

    New-Item -path alias:kubectl -value 'C:\ProgramData\chocolatey\lib\kubernetes-cli\tools\kubernetes\client\bin\kubectl.exe'
    New-Item -path alias:azdata -value 'C:\Program Files (x86)\Microsoft SDKs\Azdata\CLI\wbin\azdata.cmd'

    if (-not $avoidScriptAtLogOn) {
        # Creating scheduled task for DataServicesLogonScript.ps1
        $Trigger = New-ScheduledTaskTrigger -AtLogOn
        $Action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "$folder\DataServicesLogonScript.ps1"
        Register-ScheduledTask -TaskName "DataServicesLogonScript" -Trigger $Trigger -User $adminUsername -Action $Action -RunLevel "Highest" -Force

        # Disabling Windows Server Manager Scheduled Task
        Get-ScheduledTask -TaskName ServerManager | Disable-ScheduledTask
    }
}
function AddDesktopShortcut {
    param(
        [string] $icon,
        [string] $shortcutName,
        [string] $targetPath,
        [string] $arguments,
        [string] $windowsStyle = 3,
        [string] $username
    )
    #If WindowStyle is 1, then the application window will be set to its default location and size. If this property has a value of 3, the application will be launched in a maximized window, and if it has a value of 7, it will be launched in a minimized window.
    Write-Header "Creating $shortcutName Desktop shortcut"
    if ( -not $username) {
        $shortcutLocation = "$Env:Public\Desktop\$shortcutName.lnk"
    }
    else {
        $shortcutLocation = "C:\Users\$username\Desktop\$shortcutName.lnk"
    }
    $wScriptShell = New-Object -ComObject WScript.Shell
    $shortcut = $wScriptShell.CreateShortcut($shortcutLocation)
    $shortcut.TargetPath = $targetPath
    if ($arguments) {
        $shortcut.Arguments = $arguments
    }
    if ($icon) {
        $shortcut.IconLocation = "${Env:ArcBoxIconDir}\$icon.ico, 0"
    }
    $shortcut.WindowStyle = $windowsStyle
    $shortcut.Save()
}
function InstallAzureArcDataAzureCliExtensions {
    param (
        [string[]] $extraAzExtensions = @(),
        [switch] $notInstallK8extensions
    )
    Write-Header "Installing Azure CLI extensions"
    if ($notInstallK8extensions) {
        $k8extensions = @()
    }
    else {
        $k8extensions = @("connectedk8s", "k8s-extension")
    }
    $az_extensions = $extraAzExtensions + $k8extensions + @("arcdata")
    foreach ($az_extension in $az_extensions) {
        Write-Output "Instaling $az_extension"
        az extension add --name $az_extension
    }
}
function InstallAzureDataStudioExtensions {
    param (
        [string[]] $azureDataStudioExtensions
    )
    Write-Header "Installing Azure Data Studio Extensions"
    $Env:argument1 = "--install-extension"
    foreach ($extension in $azureDataStudioExtensions) {
        Write-Output "Installing Arc Data Studio extention: $extension"
        & "C:\Program Files\Azure Data Studio\bin\azuredatastudio.cmd" $Env:argument1 $extension
    }
}
function RegisterAzureArcProviders {
    param (
        [string[]] $arcProviderList
    )
    Write-Output "Registering Azure Arc providers, hold tight..."
    Write-Output "`n"
    foreach ($app in $arcProviderList) {
        Write-Output "Installing $app"
        az provider register --namespace "Microsoft.$app" --wait
    }
    foreach ($app in $arcProviderList) {
        Write-Output "`n"
        az provider show --namespace "Microsoft.$app" -o table
    }
}
function InitializeArcDataCommonAtLogonScript {
    param (
        [string[]] $extraAzExtensions = @(),
        [string[]] $azureDataStudioExtensions = @("microsoft.azcli", "microsoft.azuredatastudio-postgresql", "Microsoft.arc"),
        [string[]] $arcProviderList = @("Kubernetes", "KubernetesConfiguration", "ExtendedLocation", "AzureArcData"),
        [switch] $notInstallK8extensions,
        [string]$spnClientId,
        [string]$spnClientSecret,
        [string]$spnTenantId,
        [string]$adminUsername,
        [string]$subscriptionId
    )
    # Main script
    Set-NetFirewallProfile -Profile Domain, Public, Private -Enabled False

    # Login as service principal
    az login --service-principal --username $spnClientId --password $spnClientSecret --tenant $spnTenantId

    # Required for azcopy
    $azurePassword = ConvertTo-SecureString $spnClientSecret -AsPlainText -Force
    $psCred = New-Object System.Management.Automation.PSCredential($spnClientId , $azurePassword)
    Connect-AzAccount -Credential $psCred -TenantId $spnTenantId -ServicePrincipal

    # Making extension install dynamic
    az config set extension.use_dynamic_install=yes_without_prompt

    Write-Header "Az cli version"
    az -v
    if ($notInstallK8extensions) {
        InstallAzureArcDataAzureCliExtensions -extraAzExtensions $extraAzExtensions
    }
    else {
        InstallAzureArcDataAzureCliExtensions -extraAzExtensions $extraAzExtensions -notInstallK8extensions
    }

    # Set default subscription to run commands against
    # "subscriptionId" value comes from clientVM.json ARM template, based on which 
    # subscription user deployed ARM template to. This is needed in case Service 
    # Principal has access to multiple subscriptions, which can break the automation logic
    az account set --subscription $subscriptionId

    InstallAzureDataStudioExtensions -azureDataStudioExtensions $azureDataStudioExtensions

    AddDesktopShortcut -shortcutName "Azure Data Studio" -targetPath "C:\Program Files\Azure Data Studio\azuredatastudio.exe" -username $adminUsername

    RegisterAzureArcProviders -arcProviderList $arcProviderList
}
function DownloadCapiFiles {
    param (
        [string]$stagingStorageAccountName,
        [string]$resourceGroup,
        [string]$username,
        [string]$folder
    )
    # Downloading CAPI Kubernetes cluster kubeconfig file
    Write-Header "Downloading CAPI Kubernetes cluster kubeconfig file"
    $sourceFile = "https://$stagingStorageAccountName.blob.core.windows.net/staging-capi/config"
    $context = (Get-AzStorageAccount -ResourceGroupName $resourceGroup).Context
    $sas = New-AzStorageAccountSASToken -Context $context -Service Blob -ResourceType Object -Permission racwdlup
    $sourceFile = $sourceFile + $sas
    azcopy cp --check-md5 FailIfDifferentOrMissing $sourceFile  "C:\Users\$username\.kube\config"

    # Downloading 'installCAPI.log' log file
    Write-Header "Downloading 'installCAPI.log' log file"
    $sourceFile = "https://$stagingStorageAccountName.blob.core.windows.net/staging-capi/installCAPI.log"
    $sourceFile = $sourceFile + $sas
    azcopy cp --check-md5 FailIfDifferentOrMissing $sourceFile  "$folder\installCAPI.log"

    Write-Header "Checking kubernetes nodes"
    kubectl get nodes
}
function ChangingToClientVMWallpaper {
    param (
        [string]$folder
    )

    $imgPath = "$folder\wallpaper.png"
    $code = @'
using System.Runtime.InteropServices;
namespace Win32{

     public class Wallpaper{
        [DllImport("user32.dll", CharSet=CharSet.Auto)]
         static extern int SystemParametersInfo (int uAction , int uParam , string lpvParam , int fuWinIni) ;

         public static void SetWallpaper(string thePath){
            SystemParametersInfo(20,0,thePath,3);
         }
    }
 }
'@

    add-type $code
    [Win32.Wallpaper]::SetWallpaper($imgPath)
}
function AddURLShortcutDesktop {
    param (
        [string]$url,
        [string]$name,
        [string]$userProfile
    )
    $Shell = New-Object -ComObject ("WScript.Shell")
    $Favorite = $Shell.CreateShortcut($userProfile + "\Desktop\$name.url")
    $Favorite.TargetPath = $url;
    $Favorite.Save()
}
function CopyAzureDataStudioSettingsRemplateFile {
    param (
        [string]$adminUsername,
        [string]$folder
    )
    Write-Header "Copying Azure Data Studio settings template file"
    New-Item -Path "C:\Users\$adminUsername\AppData\Roaming\azuredatastudio\" -Name "User" -ItemType "directory" -Force
    Copy-Item -Path "$folder\settingsTemplate.json" -Destination "C:\Users\$adminUsername\AppData\Roaming\azuredatastudio\User\settings.json"
}
function ApplyAzureDataStudioSettingsTemplateFileAndOperationsUrlShortcut {
    param (
        [string]$adminUsername,
        [string]$folder,
        [string]$userProfile,
        [string]$deploySQLMI,
        [string]$deployPostgreSQL
    )
    if ( $deploySQLMI -eq $true -or $deployPostgreSQL -eq $true ) {
        CopyAzureDataStudioSettingsRemplateFile -adminUsername $adminUsername -folder $folder
    
        # Creating desktop url shortcuts for built-in Grafana and Kibana services 
        $GrafanaURL = kubectl get service/metricsui-external-svc -n arc -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
        $GrafanaURL = "https://" + $GrafanaURL + ":3000"
        AddURLShortcutDesktop -url $GrafanaURL -name "Grafana" -userProfile $userProfile

        $KibanaURL = kubectl get service/logsui-external-svc -n arc -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
        $KibanaURL = "https://" + $KibanaURL + ":5601"
        AddURLShortcutDesktop -url $KibanaURL -name "Kibana" -userProfile $userProfile
    }
}
function EnablingDataControllerAutoMetrics {
    param (
        [string]$resourceGroup,
        [string]$workspaceName,
        [string]$jumpstartdc = "jumpstart-dc"
    )
    Write-Header "Enabling data controller auto metrics & logs upload to log analytics"
    $Env:WORKSPACE_ID = $(az resource show --resource-group $resourceGroup --name $workspaceName --resource-type "Microsoft.OperationalInsights/workspaces" --query properties.customerId -o tsv)
    $Env:WORKSPACE_SHARED_KEY = $(az monitor log-analytics workspace get-shared-keys --resource-group $resourceGroup --workspace-name $workspaceName  --query primarySharedKey -o tsv)
    az arcdata dc update --name $jumpstartdc --resource-group $resourceGroup --auto-upload-logs true
    az arcdata dc update --name $jumpstartdc --resource-group $resourceGroup --auto-upload-metrics true
}
function DeployAzureArcDataController {
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingPlainTextForPassword", "")]
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingUsernameAndPasswordParams", "")]
    param (
        [string]$resourceGroup,
        [string]$folder,
        [string]$workspaceName,
        [string]$AZDATA_USERNAME,
        [string]$AZDATA_PASSWORD,
        [string]$spnClientId,
        [string]$spnTenantId,
        [string]$spnClientSecret,
        [string]$subscriptionId,
        [string]$jumpstartcl = 'jumpstart-cl'
    )
    Write-Header "Deploying Azure Arc Data Controller"
    $customLocationId = $(az customlocation show --name $jumpstartcl --resource-group $resourceGroup --query id -o tsv)
    $workspaceId = $(az resource show --resource-group $resourceGroup --name $workspaceName --resource-type "Microsoft.OperationalInsights/workspaces" --query properties.customerId -o tsv)
    $workspaceKey = $(az monitor log-analytics workspace get-shared-keys --resource-group $resourceGroup --workspace-name $workspaceName --query primarySharedKey -o tsv)

    $dataControllerParams = "$folder\dataController.parameters.json"

    (Get-Content -Path $dataControllerParams) -replace 'resourceGroup-stage', $resourceGroup | Set-Content -Path $dataControllerParams
    (Get-Content -Path $dataControllerParams) -replace 'azdataUsername-stage', $AZDATA_USERNAME | Set-Content -Path $dataControllerParams
    (Get-Content -Path $dataControllerParams) -replace 'azdataPassword-stage', $AZDATA_PASSWORD | Set-Content -Path $dataControllerParams
    (Get-Content -Path $dataControllerParams) -replace 'customLocation-stage', $customLocationId | Set-Content -Path $dataControllerParams
    (Get-Content -Path $dataControllerParams) -replace 'subscriptionId-stage', $subscriptionId | Set-Content -Path $dataControllerParams
    (Get-Content -Path $dataControllerParams) -replace 'spnClientId-stage', $spnClientId | Set-Content -Path $dataControllerParams
    (Get-Content -Path $dataControllerParams) -replace 'spnTenantId-stage', $spnTenantId | Set-Content -Path $dataControllerParams
    (Get-Content -Path $dataControllerParams) -replace 'spnClientSecret-stage', $spnClientSecret | Set-Content -Path $dataControllerParams
    (Get-Content -Path $dataControllerParams) -replace 'logAnalyticsWorkspaceId-stage', $workspaceId | Set-Content -Path $dataControllerParams
    (Get-Content -Path $dataControllerParams) -replace 'logAnalyticsPrimaryKey-stage', $workspaceKey | Set-Content -Path $dataControllerParams

    az deployment group create --resource-group $resourceGroup `
        --template-file "$folder\dataController.json" `
        --parameters "$folder\dataController.parameters.json"

    Write-Output "`n"
    Do {
        Write-Output "Waiting for data controller. Hold tight, this might take a few minutes...(45s sleeping loop)"
        Start-Sleep -Seconds 45
        $dcStatus = $(if (kubectl get datacontroller -n arc | Select-String "Ready" -Quiet) { "Ready!" }Else { "Nope" })
    } while ($dcStatus -eq "Nope")

    Write-Header "Azure Arc data controller is ready!"
}
function CreateCustomLocation {
    param (
        [string]$resourceGroup,
        [string]$clusterName,
        [string]$KUBECONFIG,
        [string]$jumpstartcl = 'jumpstart-cl'
    )
    Write-Header "Create Custom Location"
    $connectedClusterId = az connectedk8s show --name $clusterName --resource-group $resourceGroup --query id -o tsv

    $extensionId = az k8s-extension show --name arc-data-services `
        --cluster-type connectedClusters `
        --cluster-name $clusterName `
        --resource-group $resourceGroup `
        --query id -o tsv

    Start-Sleep -Seconds 20
    # Create Custom Location
    az customlocation create --name $jumpstartcl `
        --resource-group $resourceGroup `
        --namespace arc `
        --host-resource-id $connectedClusterId `
        --cluster-extension-ids $extensionId `
        --kubeconfig $KUBECONFIG
    
}
function InstallAzureArcEnabledDataServicesExtension {
    param (
        [string]$resourceGroup,
        [string]$clusterName
    )
    Write-Header "Installing Azure Arc-enabled data services extension"
    az k8s-extension create --name arc-data-services `
        --extension-type microsoft.arcdataservices `
        --cluster-type connectedClusters `
        --cluster-name $clusterName `
        --resource-group $resourceGroup `
        --auto-upgrade false `
        --scope cluster `
        --release-namespace arc `
        --config Microsoft.CustomLocation.ServiceAccount=sa-arc-bootstrapper `

    Do {
        Write-Output "Waiting for bootstrapper pod, hold tight...(20s sleeping loop)"
        Start-Sleep -Seconds 20
        $podStatus = $(if (kubectl get pods -n arc | Select-String "bootstrapper" | Select-String "Running" -Quiet) { "Ready!" }Else { "Nope" })
    } while ($podStatus -eq "Nope")
}