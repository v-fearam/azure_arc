Write-Output "Arc Common Functions"
# https://docs.microsoft.com/powershell/scripting/developer/help/examples-of-comment-based-help
function Write-Header {
    param (
        [string]
        # Text to be included as important title.
        $title
    )
    <#
        .DESCRIPTION
        Add the text on the output highlighted. It intends to be a section title during the execution.

        .OUTPUTS
        Text writen on the host

        .EXAMPLE
        > Write-Header "Az CLI Login"

        ####################
        # - Az CLI Login
        ####################
    #>
    Write-Host
    Write-Host ("#" * ($title.Length + 8))
    Write-Host "# - $title"
    Write-Host ("#" * ($title.Length + 8))
    Write-Host
}
function InstallChocolateyApp {
    param(
        [string[]]
        # App name list to be installed using chocolaty
        $chocolateyAppList
    )
    <#
        .DESCRIPTION
        Install all the aplication, and if chocolaty is not present, it will be installed. 

        .OUTPUTS
        Chocolaty will be present on the VM and all the indicated app installed.

        .EXAMPLE
        > InstallChocolateyApp -chocolateyAppList  @("azure-cli", "az.powershell")
    #>
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
        [string] 
        # Url to the category root folder on github, for example where is arc data
        $profileRootBaseUrl,
        [string] 
        # Url to the scenario root folder on github, for example quere is capi scenario inside arc data
        $templateBaseUrl,
        [string] 
        # VM admin username
        $adminUsername,
        [string[]]
        # All extra application to be installed. By default this function install a set of common application which are needed for all arc data scenarios.
        $extraChocolateyAppList = @(),
        [switch] 
        # This function download the files to install ProstgreSQL, most of scenarios install it. Some scenarios don't, so add this parameter.
        $avoidPostgreSQL,
        [switch] 
        # this function add a DataService script to be executed at Logon, but one scenario doesn't. This parameter avoid that functionality.
        $avoidScriptAtLogOn,
        [string] 
        # Directory folder to download the files needed.
        $folder
    )
    <#
        .DESCRIPTION
        Common boostrap instalation for Arc Data scenarios 

        .OUTPUTS
        App installed, file dowloaded, profile added

        .EXAMPLE
        > BoostrapArcData -profileRootBaseUrl $profileRootBaseUrl -templateBaseUrl $templateBaseUrl -adminUsername $adminUsername -folder $Env:tempDir

    #>
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
    InstallChocolateyApp -chocolateyAppList $chocolateyAppList

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
        [string] 
        # Path to the icon to be used. It is not mandatory.
        $icon,
        [string] 
        # Name used for the shorcut
        $shortcutName,
        [string]
        # Path to the app to be executed when the shorcut is click
        $targetPath,
        [string]
        # Shorcut parameter. It is optional
        $arguments,
        [string]
        # If WindowStyle is 1, then the application window will be set to its default location and size. If this property has a value of 3, the application will be launched in a maximized window, and if it has a value of 7, it will be launched in a minimized window.
        $windowsStyle = 3,
        [string]
        # If we like the shortcut on an specific user desktop, it should be included. Otherwise, it will be added on the public desktop.
        $username
    )
    <#
        .DESCRIPTION
        Create a Desktop Shorcut 
        
        .OUTPUTS
        A new icon is present on the VM Windows Desktop

        .EXAMPLE
        >  AddDesktopShortcut -shortcutName "Azure Data Studio" -targetPath "C:\Program Files\Azure Data Studio\azuredatastudio.exe" -username $adminUsername
    #>
    
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
        [string[]]
        # Array of extensions to be included. Nothing by default
        $extraAzExtensions = @(),
        [switch]
        #This function install k8s extentions because most of scenarios use them. But they can excluded 
        $notInstallK8extensions
    )
    <#
        .DESCRIPTION
        Install a set of azure cli extentions needed for arc data scenarios. If you need extra extention, it can be required. 
        
        .OUTPUTS
        The extentions are available to be used.

        .EXAMPLE
        >   InstallAzureArcDataAzureCliExtensions
    #>
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
        [string[]] 
        # Array of Data Studio extentions names to be installed
        $azureDataStudioExtensions
    )
    <#
        .DESCRIPTION
        Install a set of Data Studio extentions
        
        .OUTPUTS
        The extentions are available to be used.

        .EXAMPLE
        >    InstallAzureDataStudioExtensions -azureDataStudioExtensions @("microsoft.azcli", "microsoft.azuredatastudio-postgresql", "Microsoft.arc")
    #>
    Write-Header "Installing Azure Data Studio Extensions"
    $Env:argument1 = "--install-extension"
    foreach ($extension in $azureDataStudioExtensions) {
        Write-Output "Installing Arc Data Studio extention: $extension"
        & "C:\Program Files\Azure Data Studio\bin\azuredatastudio.cmd" $Env:argument1 $extension
    }
}
function RegisterAzureArcProviders {
    param (
        [string[]]
        # Array of Arc Provider names to be installed. Note that "Microsoft." is added automatically
        $arcProviderList
    )
    <#
        .DESCRIPTION
        Register Arc Providers
        
        .OUTPUTS
        All the provider are registered

        .EXAMPLE
        > RegisterAzureArcProviders -arcProviderList @("Kubernetes", "KubernetesConfiguration", "ExtendedLocation", "AzureArcData")
    #>
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
        [string[]] 
        # List of az extentions names needed and not included by default
        $extraAzExtensions = @(),
        [string[]]
        # List of azure data studio extension names needed, if they are different from the default
        $azureDataStudioExtensions = @("microsoft.azcli", "microsoft.azuredatastudio-postgresql", "Microsoft.arc"),
        [string[]] 
        # List of azure arc provider names needed, if they are different from the default
        $arcProviderList = @("Kubernetes", "KubernetesConfiguration", "ExtendedLocation", "AzureArcData"),
        [switch]
        # It tell if the k8s extentions should be not installed
        $notInstallK8extensions,
        [string]
        # Service principal id to login Azure cli
        $spnClientId,
        [string]
        # Service principal secret to login Azure cli        
        $spnClientSecret,
        [string]
        # Tenant where the service principal is defined to login Azure cli         
        $spnTenantId,
        [string]
        # VM admin username
        $adminUsername,
        [string]
        # Azure subscription id which is going to be used 
        $subscriptionId
    )
    <#
        .DESCRIPTION
        Common DataServiceLogonScript initialization on all the scenarios
        
        .OUTPUTS
        Extentions and providers installed, Shorcut created, and other initialization activites.

        .EXAMPLE
        > InitializeArcDataCommonAtLogonScript -spnClientId $Env:spnClientId -spnClientSecret $Env:spnClientSecret -spnTenantId $Env:spnTenantId -adminUsername $Env:adminUsername  -subscriptionId $Env:subscriptionId
    #>
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
        [string]
        # Storage account name where the log and kubeconfig file were saved
        $stagingStorageAccountName,
        [string]
        # Resource group where the storage account is
        $resourceGroup,
        [string]
        # VM username
        $username,
        [string]
        # Folder where the file are going to be left
        $folder
    )
    <#
        .DESCRIPTION
        Download k8s files to connect the cluster API and the instalation logs.
        
        .OUTPUTS
        We can connect the cluster and we have the instalation logs

        .EXAMPLE
        > DownloadCapiFiles -stagingStorageAccountName "$Env:stagingStorageAccountName" -resourceGroup "$Env:resourceGroup" -username "$Env:USERNAME" -folder "$Env:TempDir"
    #>
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
        [string]
        # Folder where the image is
        $folder
    )
    <#
        .DESCRIPTION
        Change the desktop wallpaper
        
        .OUTPUTS
        The desktop background will be changed. It doesn't work using Azure Bastion.

        .EXAMPLE
        > ChangingToClientVMWallpaper -folder $Env:TempDir
    #>
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
        [string]
        # URL which is going to be open
        $url,
        [string]
        # Shortcut name
        $name,
        [string]
        #VM user profile where the shortcut is going to be included
        $userProfile
    )
    <#
        .DESCRIPTION
        Create a Shorcut desktop targeting a URL
        
        .OUTPUTS
        The URL can be navigated by clicking the desktop shortcut 

        .EXAMPLE
        >  AddURLShortcutDesktop -url $GrafanaURL -name "Grafana" -userProfile $userProfile
    #>
    $Shell = New-Object -ComObject ("WScript.Shell")
    $Favorite = $Shell.CreateShortcut($userProfile + "\Desktop\$name.url")
    $Favorite.TargetPath = $url;
    $Favorite.Save()
}
function CopyAzureDataStudioSettingsRemplateFile {
    param (
        [string]
        # VM admin username
        $adminUsername,
        [string]
        # Folder where is the Azure Data Studio config file to be used
        $folder
    )
    <#
        .DESCRIPTION
        Set configuration to Azure Data Studio
        
        .OUTPUTS
        Azure data studio is able to operate the installed databases

        .EXAMPLE
        >   CopyAzureDataStudioSettingsRemplateFile -adminUsername $adminUsername -folder $folder
    #>
    Write-Header "Copying Azure Data Studio settings template file"
    New-Item -Path "C:\Users\$adminUsername\AppData\Roaming\azuredatastudio\" -Name "User" -ItemType "directory" -Force
    Copy-Item -Path "$folder\settingsTemplate.json" -Destination "C:\Users\$adminUsername\AppData\Roaming\azuredatastudio\User\settings.json"
}
function ApplyAzureDataStudioSettingsTemplateFileAndOperationsUrlShortcut {
    param (
        [string]
        # VM adminusername
        $adminUsername,
        [string]
        # Folder where is the Azure Data Studio config file to be used
        $folder,
        [string]
        # VM user profile where the shortcut is going to be included
        $userProfile,
        [string]
        # If SQLMI was installed or not
        $deploySQLMI,
        [string]
        # If PostgreSQL was installed or not
        $deployPostgreSQL
    )
    <#
        .DESCRIPTION
        If SQLMI or PostgreSQL was installed, the function configures Azure Data Studio and adds Desktop shortcut   
        
        .OUTPUTS
        Access to databases from Azure Data Studio and accessibility to control panels

        .EXAMPLE
        >   ApplyAzureDataStudioSettingsTemplateFileAndOperationsUrlShortcut -adminUsername $Env:adminUsername -folder $Env:TempDir -userProfile $Env:USERPROFILE -deploySQLMI $Env:deploySQLMI -deployPostgreSQL $Env:deployPostgreSQL
    #>
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
function EnableDataControllerAutoMetrics {
    param (
        [string]
        # Resource group where is the data controller
        $resourceGroup,
        [string]
        # Workplace name used to collect metrics
        $workspaceName,
        [string]
        # Data controller name
        $jumpstartdc = "jumpstart-dc"
    )
    <#
        .DESCRIPTION
        Enabling data controller metrics
        
        .OUTPUTS
        Data controller metrics generation

        .EXAMPLE
        >   EnableDataControllerAutoMetrics -resourceGroup $Env:resourceGroup -workspaceName $Env:workspaceName
    #>
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
        [string]
        # Resource group where the data controller is going to be deployed
        $resourceGroup,
        [string]
        # Folder where the data controller configuration template is located
        $folder,
        [string]
        # Workplace name where the data is collecting
        $workspaceName,
        [string]
        # Az username needed as data controler configuration
        $AZDATA_USERNAME,
        [string]
        # Az passworf needed as data controler configuration
        $AZDATA_PASSWORD,
        [string]
        # Service principal id needed as data controler configuration
        $spnClientId,
        [string]
        # Tenant where the service principal is, it needed as data controler configuration
        $spnTenantId,
        [string]
        # Service principal secret needed as data controler configuration
        $spnClientSecret,
        [string]
        # Subscription id needed as data controler configuration
        $subscriptionId,
        [string]
        # Data controller name
        $jumpstartcl = 'jumpstart-cl'
    )
    <#
        .DESCRIPTION
        Deploy Azure Data controller and checking the impact on the K8s cluster
        
        .OUTPUTS
        Data controler working

        .EXAMPLE
        >   EnableDataControllerAutoMetrics -resourceGroup $Env:resourceGroup -workspaceName $Env:workspaceName
    #>
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
        [string]
        # Resource group where the custom location is going to be deployed
        $resourceGroup,
        [string]
        # Cluster name 
        $clusterName,
        [string]
        # Kubeconfig location
        $KUBECONFIG,
        [string]
        # Custom location name 
        $jumpstartcl = 'jumpstart-cl'
    )
    <#
        .DESCRIPTION
        Create custom location
        
        .OUTPUTS
        Custom location created

        .EXAMPLE
        >   CreateCustomLocation -resourceGroup $Env:resourceGroup -clusterName $Env:ArcK8sClusterName -KUBECONFIG $Env:KUBECONFIG
    #>
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
        [string]
        # Resource group where the cluster is located
        $resourceGroup,
        [string]
        # Cluster name
        $clusterName
    )
    <#
        .DESCRIPTION
        Installing Azure Arc-enabled data services extension
        
        .OUTPUTS
       Arc-enabled data services extension installed and checked

        .EXAMPLE
        >   InstallAzureArcEnabledDataServicesExtension -resourceGroup $Env:resourceGroup -clusterName $Env:ArcK8sClusterName
    #>
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