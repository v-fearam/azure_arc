
function Write-Header {
    param (
        [string] $title
    )
    <#
        .SYNOPSIS
        Write the title passed as a parameter as a formatted header to the standard output.
        
        .DESCRIPTION
        Write the title passed as a parameter as a formatted header to the standard output. Use this function to separate sections of log entries during execution.

        .PARAMETER title
        Text to write.

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

function InstallChocolateyPackages {
    param(
        [string[]] $packages
    )
    <#
        .SYNOPSIS
        Download and install Chocolatey packages.

        .DESCRIPTION
        Download and install Chocolatey packages. If Chocolatey is not present, it will be installed. 

        .PARAMETER packages
        List of packages to install, separated by comma.

        .EXAMPLE
        > InstallChocolateyPackages -packages  @("azure-cli", "az.powershell")
    #>
    try {
        choco config get cacheLocation
    }
    catch {
        Write-Header "Chocolatey not detected, trying to install now"
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
    }

    foreach ($package in $packages) {
        Write-Output "Installing $package"
        & choco install $package /y -Force | Write-Output
    }
}

function BootstrapArcData {
    param (
        [string] $profileRootBaseUrl,
        [string] $templateBaseUrl,
        [string] $adminUsername,
        [string[]] $extraChocolateyPackages = @(),
        [switch] $skipPostgreSQLInstall,
        [switch] $skipLogonScript,
        [string] $folder
    )
    <#
        .SYNOPSIS
        Common bootstrap installation functionality for Arc Data scenarios. 

        .DESCRIPTION
        Common bootstrap installation functionality for Arc Data scenarios. Installs required Chocolatey packages and downloads the scenario scripts. Invokes 
        several scripts in-line and schedules task to invoke scripts that must run at log-on.

        .PARAMETER profileRootBaseUrl
        Url to the root folder of the category of scenarios on GitHub. For example, the Arc-Data root folder. 

        .PARAMETER templateBaseUrl
        Url to the root folder of the scenario on GitHub. For example, the capi scenario inside Arc-Data.

        .PARAMETER adminUsername
        Admin user name for the client VM.

        .PARAMETER extraChocolateyPackages
        Chocolatey packages to install, in addition to the common packages required by all Arc-Data scenarios.

        .PARAMETER skipPostgreSQLInstall
        By default this function downloads the files to install ProstgreSQL as required by most scenarios. Add this parameter to skip installation.

        .PARAMETER skipLogonScript
        By default, this function schedules a DataService script to execute during the next log-on. Add this parameter to avoid that functionality.

        .PARAMETER folder
        Local folder where the downloaded scripts will be saved.
        
        .EXAMPLE
        > BootstrapArcData -profileRootBaseUrl $profileRootBaseUrl -templateBaseUrl $templateBaseUrl -adminUsername $adminUsername -folder $Env:tempDir

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
    Write-Header "Installing Chocolatey Packages"
    $chocolateyPackages = $extraChocolateyPackages + @("azure-cli", "az.powershell", "kubernetes-cli", "kubectx", "vcredist140", "microsoft-edge", "azcopy10", "vscode", "putty.install", "kubernetes-helm", "grep", "ssms", "dotnetcore-3.1-sdk", "git", "7zip")
    InstallChocolateyPackages -packages $chocolateyPackages

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

    if (-not $skipPostgreSQLInstall) {
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

    if (-not $skipLogonScript) {
        # Schedule a task for DataServicesLogonScript.ps1
        $Trigger = New-ScheduledTaskTrigger -AtLogOn
        $Action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "$folder\DataServicesLogonScript.ps1"
        Register-ScheduledTask -TaskName "DataServicesLogonScript" -Trigger $Trigger -User $adminUsername -Action $Action -RunLevel "Highest" -Force

        # Disable Windows Server Manager Scheduled Task
        Get-ScheduledTask -TaskName ServerManager | Disable-ScheduledTask
    }
}

function AddDesktopShortcut {
    param(
        [string] $icon,
        [string] $shortcutName,
        [string] $targetPath,
        [string] $arguments,
        [string] $windowStyle = 3,
        [string] $username
    )
    <#
        .SYNOPSIS
        Create a Desktop Shortcut.

        .DESCRIPTION
        Create a Desktop Shortcut. If a user name is provided, the shortcut is installed under that user's profile, otherwise the Shortcut is installed for all users.
        
        .PARAMETER icon
        Path to the icon to use. This parameter is optional.

        .PARAMETER shortcutName
        Name of the Shortcut.

        .PARAMETER targetPath
        Path to the executable to invoke when the Shortcut is clicked.

        .PARAMETER arguments
        Parameters to pass along to the executable when the icon is clicked. This parameter is optional.

        .PARAMETER windowStyle
        If WindowStyle is 1, the application window will be set to its default location and size. With a value of 3, the application will be launched in a 
        maximized window. With a value of 7, it will be launched in a minimized window.

        .PARAMETER username
        User name if we want the icon to appear only on that user's desktop. If not specified, the icon will be added on the public desktop.

        .EXAMPLE
        > AddDesktopShortcut -shortcutName "Azure Data Studio" -targetPath "C:\Program Files\Azure Data Studio\azuredatastudio.exe" -username $adminUsername
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
    $shortcut.WindowStyle = $windowStyle
    $shortcut.Save()
}

function InstallAzureArcDataAzureCliExtensions {
    param (
        [string[]] $extraAzExtensions = @(),
        [switch] $skipInstallK8extensions
    )
    <#
        .SYNOPSIS
        Install Azure CLI extensions needed for Arc-Data scenarios.

        .DESCRIPTION
        Install Azure CLI extensions needed for Arc-Data scenarios. If a list of extra extensions is provided, they will also be installed. 

        .PARAMETER extraAzExtensions
        Array of extra extensions to install. 

        .PARAMETER skipInstallK8extensions
        By default this function installs k8s extensions as they are needed by most scenarios. Add this parameter to exclude K8s extensions.

        .EXAMPLE
        > InstallAzureArcDataAzureCliExtensions
    #>
    Write-Header "Installing Azure CLI extensions"
    if ($skipInstallK8extensions) {
        $k8extensions = @()
    }
    else {
        $k8extensions = @("connectedk8s", "k8s-extension")
    }

    $az_extensions = $extraAzExtensions + $k8extensions + @("arcdata")
    foreach ($az_extension in $az_extensions) {
        Write-Output "Installing $az_extension"
        az extension add --name $az_extension
    }
}

function InstallAzureDataStudioExtensions {
    param (
        [string[]] $azureDataStudioExtensions
    )
    <#
        .SYNOPSIS
        Install Data Studio extensions.

        .DESCRIPTION
        Install Data Studio extensions.
        
        .PARAMETER azureDataStudioExtensions
        Array with names of the extensions to install.

        .EXAMPLE
        > InstallAzureDataStudioExtensions -azureDataStudioExtensions @("microsoft.azcli", "microsoft.azuredatastudio-postgresql", "Microsoft.arc")
    #>
    Write-Header "Installing Azure Data Studio Extensions"
    $Env:argument1 = "--install-extension"
    foreach ($extension in $azureDataStudioExtensions) {
        Write-Output "Installing Arc Data Studio extension: $extension"
        & "C:\Program Files\Azure Data Studio\bin\azuredatastudio.cmd" $Env:argument1 $extension
    }
}

function RegisterAzureArcProviders {
    param (
        [string[]] $arcProviderList
    )
    <#
        .SYNOPSIS
        Register Arc Providers.

        .DESCRIPTION
        Register Arc Providers. Outputs each provider configuration to the standard output at the end as a verification step.
        
        .PARAMETER arcProviderList
        Array of Arc providers to install. Note that "Microsoft." is added automatically at the beginning of the name.

        .EXAMPLE
        > RegisterAzureArcProviders -arcProviderList @("Kubernetes", "KubernetesConfiguration", "ExtendedLocation", "AzureArcData")
    #>
    Write-Output "Registering Azure Arc providers, hold tight..."
    Write-Output "`n"
    foreach ($provider in $arcProviderList) {
        Write-Output "Installing $provider"
        az provider register --namespace "Microsoft.$provider" --wait
    }

    foreach ($provider in $arcProviderList) {
        Write-Output "`n"
        az provider show --namespace "Microsoft.$provider" -o table
    }
}

function InitializeArcDataCommonAtLogonScript {
    param (
        [string[]] $extraAzExtensions = @(),
        [string[]] $azureDataStudioExtensions = @("microsoft.azcli", "microsoft.azuredatastudio-postgresql", "Microsoft.arc"),
        [string[]] $arcProviderList = @("Kubernetes", "KubernetesConfiguration", "ExtendedLocation", "AzureArcData"),
        [switch] $skipInstallK8extensions,
        [string] $spnClientId,
        [string] $spnClientSecret,
        [string] $spnTenantId,
        [string] $adminUsername,
        [string] $subscriptionId
    )
    <#
        .SYNOPSIS
        Common DataServiceLogonScript.

        .DESCRIPTION
        Common DataServiceLogonScript. Performs initialization steps common to all Arc-Data scenarios.

        .PARAMETER extraAzExtensions
        List of Azure CLI extensions the scenario needs that are not included by default.

        .PARAMETER azureDataStudioExtensions
        List of Azure Data Studio extensions the scenario needs that are not included by default.

        .PARAMETER arcProviderList
        List of Azure Arc provider the scenario needs that are not included by default.

        .PARAMETER skipInstallK8extensions
        Provide this parameter to skip installation of the K8s extensions.

        .PARAMETER spnClientId
        Service Principal Id to login from Azure CLI.

        .PARAMETER spnClientSecret
        Service principal secret to login from Azure CLI.

        .PARAMETER spnTenantId
        Tenant where the service principal is defined to login from Azure CLI.
        
        .PARAMETER adminUsername
        User name for the client VM.

        .PARAMETER subscriptionId
        Subscription Id of the Azure Subscription to deploy to.

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

    Write-Header "Az CLI version"
    az -v
    if ($skipInstallK8extensions) {
        InstallAzureArcDataAzureCliExtensions -extraAzExtensions $extraAzExtensions
    }
    else {
        InstallAzureArcDataAzureCliExtensions -extraAzExtensions $extraAzExtensions skipInstallK8extensions
    }

    # Set default subscription to run commands against
    # The "subscriptionId" value comes from the clientVM.json ARM template. This is needed in case the Service 
    # Principal has access to multiple subscriptions, which can break the automation logic
    az account set --subscription $subscriptionId

    InstallAzureDataStudioExtensions -azureDataStudioExtensions $azureDataStudioExtensions

    AddDesktopShortcut -shortcutName "Azure Data Studio" -targetPath "C:\Program Files\Azure Data Studio\azuredatastudio.exe" -username $adminUsername

    RegisterAzureArcProviders -arcProviderList $arcProviderList
}

function DownloadCapiFiles {
    param (
        [string] $stagingStorageAccountName,
        [string] $resourceGroup,
        [string] $username,
        [string] $folder
    )
    <#
        .SYNOPSIS
        Download K8s files.

        .DESCRIPTION
        Download k8s files to connect the cluster API and the installation logs. Writes the K8s nodes configuration
        to the standard output at the end as a verification step
        
        .PARAMETER stagingStorageAccountName
        Storage account name where the log and kubeconfig file are located.

        .PARAMETER resourceGroup
        Storage account resource group name.
        
        .PARAMETER username
        User name for the client VM.
        
        .PARAMETER folder
        Folder where the log files are saved.

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
        [string] $folder
    )
    <#
        .SYNOPSIS
        Change the desktop Wallpaper.

        .DESCRIPTION
        Change the desktop Wallpaper. The new Wallpaper image is expected to be named wallpaper.png.
        
        .PARAMETER folder
        Folder where the new Wallpaper image is located.

        .EXAMPLE
        > ChangingToClientVMWallpaper -folder $Env:TempDir
    #>
    $imgPath = "$folder\wallpaper.png"
    $code = @'
        using System.Runtime.InteropServices;
        namespace Win32 {

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
        [string] $url,
        [string] $name,
        [string] $userProfile
    )
    <#
        .SYNOPSIS
        Add a new Shortcut to the Windows Desktop.

        .DESCRIPTION
        Add a new Shortcut to the Windows Desktop.

        .PARAMETER url
        URL to open when the shortcut is clicked.

        .PARAMETER name
        Shortcut name.

        .PARAMETER userProfile
        User name for whom the new shortcut will be added.

        .EXAMPLE
        > AddURLShortcutDesktop -url $GrafanaURL -name "Grafana" -userProfile $userProfile
    #>
    $Shell = New-Object -ComObject ("WScript.Shell")
    $Favorite = $Shell.CreateShortcut($userProfile + "\Desktop\$name.url")
    $Favorite.TargetPath = $url;
    $Favorite.Save()
}

function CopyAzureDataStudioSettingsTemplateFile {
    param (
        [string] $adminUsername,
        [string] $folder
    )
    <#
        .SYNOPSIS
        Override Azure Data Studio configuration file.

        .DESCRIPTION
        Override Azure Data Studio configuration file.
        
        .PARAMETER adminUsername
        Admin user name in the client VM.

        .PARAMETER folder
        Folder where the Azure Data Studio config file is located.

        .EXAMPLE
        > CopyAzureDataStudioSettingsTemplateFile -adminUsername $adminUsername -folder $folder
    #>
    Write-Header "Copying Azure Data Studio settings template file"
    New-Item -Path "C:\Users\$adminUsername\AppData\Roaming\azuredatastudio\" -Name "User" -ItemType "directory" -Force
    Copy-Item -Path "$folder\settingsTemplate.json" -Destination "C:\Users\$adminUsername\AppData\Roaming\azuredatastudio\User\settings.json"
}

function ApplyAzureDataStudioSettingsTemplateFileAndOperationsUrlShortcut {
    param (
        [string] $adminUsername,
        [string] $folder,
        [string] $userProfile,
        [string] $deploySQLMI,
        [string] $deployPostgreSQL
    )
    <#
        .SYNOPSIS
        Configure Azure Data Studio if SQLMI or PostgreSQL was installed.

        .DESCRIPTION
        Configure Azure Data Studio if SQLMI or PostgreSQL was installed.  
        
        .PARAMETER adminUsername
        Admin user name for the client VM.

        .PARAMETER folder
        Folder where the Azure Data Studio config file is located.

        .PARAMETER userProfile
        VM user profile to add the desktop shortcut.
        
        .PARAMETER deploySQLMI
        True if SQLMI was installed.
        
        .PARAMETER deployPostgreSQL
        True if PostgreSQL was installed.

        .EXAMPLE
        > ApplyAzureDataStudioSettingsTemplateFileAndOperationsUrlShortcut -adminUsername $Env:adminUsername -folder $Env:TempDir -userProfile $Env:USERPROFILE -deploySQLMI $Env:deploySQLMI -deployPostgreSQL $Env:deployPostgreSQL
    #>
    if ( $deploySQLMI -eq $true -or $deployPostgreSQL -eq $true ) {
        CopyAzureDataStudioSettingsTemplateFile -adminUsername $adminUsername -folder $folder
    
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
        [string] $resourceGroup,
        [string] $workspaceName,
        [string] $jumpstartdc = "jumpstart-dc"
    )
    <#
        .SYNOPSIS
        Enable data controller metrics.

        .DESCRIPTION
        Enable data controller metrics.
        
        .PARAMETER resourceGroup
        Data controller resource group name.

        .PARAMETER workspaceName
        Name of the workspace to collect metrics.

        .PARAMETER jumpstartdc
        Data controller name.

        .EXAMPLE
        > EnableDataControllerAutoMetrics -resourceGroup $Env:resourceGroup -workspaceName $Env:workspaceName
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
        [string] $resourceGroup,
        [string] $folder,
        [string] $workspaceName,
        [string] $AZDATA_USERNAME,
        [string] $AZDATA_PASSWORD,
        [string] $spnClientId,
        [string] $spnTenantId,
        [string] $spnClientSecret,
        [string] $subscriptionId,
        [string] $jumpstartcl = 'jumpstart-cl'
    )
    <#
        .SYNOPSIS
        Deploy the Data controller to Azure.

        .DESCRIPTION
        Deploys the Data controller to Azure using an ARM template file. Waits until the K8s cluster starts reporting the status of the data controller.
        
        .PARAMETER resourceGroup
        Data controller resource group.
        
        .PARAMETER folder
        Folder where the data controller configuration template is located.
        
        .PARAMETER workspaceName
        Log Analytics Workspace name
        
        .PARAMETER AZDATA_USERNAME
        User account.
        
        .PARAMETER AZDATA_PASSWORD
        User account password.

        .PARAMETER spnClientId
        Client Principal Id.

        .PARAMETER spnTenantId
        Tenant Id.

        .PARAMETER spnClientSecret
        Service Principal secret.

        .PARAMETER subscriptionId
        Subscription Id.

        .PARAMETER jumpstartcl
        Data controller name.

        .EXAMPLE
        > EnableDataControllerAutoMetrics -resourceGroup $Env:resourceGroup -workspaceName $Env:workspaceName
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
        Write-Output "Waiting for the data controller. Hold on tight, this might take a few minutes...(45s sleeping loop)"
        Start-Sleep -Seconds 45
        $dcStatus = $(if (kubectl get datacontroller -n arc | Select-String "Ready" -Quiet) { "Ready!" }Else { "Nope" })
    } while ($dcStatus -eq "Nope")

    Write-Header "Azure Arc data controller is ready!"
}

function CreateCustomLocation {
    param (
        [string] $resourceGroup,
        [string] $clusterName,
        [string] $KUBECONFIG,
        [string] $jumpstartcl = 'jumpstart-cl'
    )
    <#
        .SYNOPSIS
        Create custom location.
 
        .DESCRIPTION
        Create custom location.
        
        .PARAMETER resourceGroup
        Resource group where the custom location is going to be deployed.

        .PARAMETER clusterName
        Cluster name.

        .PARAMETER KUBECONFIG
        Kubeconfig location.

        .PARAMETER jumpstartcl
         Custom location name.
        
        .EXAMPLE
        > CreateCustomLocation -resourceGroup $Env:resourceGroup -clusterName $Env:ArcK8sClusterName -KUBECONFIG $Env:KUBECONFIG
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
        [string] $resourceGroup,
        [string] $clusterName
    )
    <#
        .SYNOPSIS
        Install the Azure Arc-enabled data services extension.

        .DESCRIPTION
        Install the Azure Arc-enabled data services extension.

        .PARAMETER resourceGroup
        Resource group where the cluster is located.

        .PARAMETER clusterName
        Cluster name.
        
        .EXAMPLE
        > InstallAzureArcEnabledDataServicesExtension -resourceGroup $Env:resourceGroup -clusterName $Env:ArcK8sClusterName
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
        --config Microsoft.CustomLocation.ServiceAccount=sa-arc-bootstrapper

    Do {
        Write-Output "Waiting for bootstrapper pod, hold tight...(20s sleeping loop)"
        Start-Sleep -Seconds 20
        $podStatus = $(if (kubectl get pods -n arc | Select-String "bootstrapper" | Select-String "Running" -Quiet) { "Ready!" }Else { "Nope" })
    } while ($podStatus -eq "Nope")
}
function GetAKSClusterCredentialsKubeconfigFile() {
    param (
        [string]$resourceGroup,
        [string]$clusterName
    )
    <#
        .SYNOPSIS
        Get k8s config file to connect AKS
        
        .DESCRIPTION
        Get k8s config file to connect AKS
        
        .PARAMETER resourceGroup
        Resource group where the cluster is located.

        .PARAMETER clusterName
        Cluster name.

        .EXAMPLE
        >  GetAKSClusterCredentialsKubeconfigFile -resourceGroup $Env:resourceGroup -clusterName $connectedClusterName
    #>
    Write-Header "Getting AKS cluster credentials for the $clusterName cluster"
    az aks get-credentials --resource-group $resourceGroup --name $clusterName --admin
    Write-Header "Checking kubernetes nodes"
    kubectl get nodes
}
function AKSClusterAsAnAzureArcEnabledKubernetesCluster {
    param (
        [string]$connectedClusterName,
        [string]$resourceGroup,
        [string]$azureLocation,
        [string]$workspaceName,
        [string]$KUBECONFIG,
        [string]$KUBECONTEXT
    )
    <#
        .SYNOPSIS
        On board AKS as ARC Cluster and collect metrics

        .DESCRIPTION
        On board AKS as ARC Cluster and collect metrics
        
        .PARAMETER resourceGroup
        Resource group where the cluster is located.

        .PARAMETER connectedClusterName
        Cluster name.
        
        .PARAMETER azureLocation
        Azure Location where the cluster is.

        .PARAMETER workspaceName
        Workpace collecting metric from cluster.

        .PARAMETER KUBECONFIG
        AKS cluster config file.

        .PARAMETER KUBECONTEXT
        AKS cluster local context.

        .EXAMPLE
        >  AKSClusterAsAnAzureArcEnabledKubernetesCluster -connectedClusterName $connectedClusterName -resourceGroup $Env:resourceGroup -azureLocation $Env:azureLocation -workspaceName $Env:workspaceName -KUBECONTEXT $Env:KUBECONTEXT -KUBECONFIG $Env:KUBECONFIG
    #>
    Write-Header "Create Kubernetes - Azure Arc Cluster"
    az connectedk8s -h
    az connectedk8s connect --name $connectedClusterName --resource-group $resourceGroup --location $azureLocation --tags 'Project=jumpstart_azure_arc_data_services' --kube-config $KUBECONFIG --kube-context $KUBECONTEXT

    Start-Sleep -Seconds 10

    Write-Header "Enabling Container Insights cluster extension"
    $workspaceId = $(az resource show --resource-group $resourceGroup --name $workspaceName --resource-type "Microsoft.OperationalInsights/workspaces" --query properties.customerId -o tsv)
    az k8s-extension create --name "azuremonitor-containers" --cluster-name $connectedClusterName --resource-group $resourceGroup --cluster-type connectedClusters --extension-type Microsoft.AzureMonitor.Containers --configuration-settings logAnalyticsWorkspaceResourceID=$workspaceId
}