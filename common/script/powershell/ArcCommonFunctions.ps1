
function InstallChocolateyPackages {
    param(
        [Parameter(Mandatory = $true)]
        [string[]] $PackageList
    )
    <#
        .SYNOPSIS
        Download and install Chocolatey packages.

        .DESCRIPTION
        Download and install Chocolatey packages. If Chocolatey is not present, it will be installed. 

        .PARAMETER PackageList
        List of packages to install, separated by comma.

        .EXAMPLE
        > InstallChocolateyPackages -Package  @("azure-cli", "az.powershell")
    #>
    try {
        choco config get cacheLocation
    }
    catch {
        WriteHeader "Chocolatey not detected, trying to install now"
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
    }

    foreach ($package in $PackageList) {
        Write-Output "Installing $package"
        & choco install $package /y -Force | Write-Output
    }
}

function BootstrapArcData {
    param (
        [Parameter(Mandatory = $true)]
        [string] $ProfileRootBaseUrl,
        [Parameter(Mandatory = $true)]
        [string] $TemplateBaseUrl,
        [Parameter(Mandatory = $true)]
        [string] $AdminUsername,
        [string[]] $ExtraChocolateyPackage = @(),
        [switch] $SkipPostgreSQLInstall,
        [switch] $SkipLogonScript,
        [Parameter(Mandatory = $true)]
        [string] $Folder
    )
    <#
        .SYNOPSIS
        Common bootstrap installation functionality for Arc Data scenarios. 

        .DESCRIPTION
        Common bootstrap installation functionality for Arc Data scenarios. Installs required Chocolatey packages and downloads the scenario scripts. Invokes 
        several scripts in-line and schedules task to invoke scripts that must run at log-on.

        .PARAMETER ProfileRootBaseUrl
        Url to the root folder of the category of scenarios on GitHub. For example, the Arc-Data root folder. 

        .PARAMETER TemplateBaseUrl
        Url to the root folder of the scenario on GitHub. For example, the capi scenario inside Arc-Data.

        .PARAMETER AdminUsername
        Admin user name for the client VM.

        .PARAMETER ExtraChocolateyPackage
        Chocolatey packages to install, in addition to the common packages required by all Arc-Data scenarios.

        .PARAMETER SkipPostgreSQLInstall
        By default this function downloads the files to install ProstgreSQL as required by most scenarios. Add this parameter to skip installation.

        .PARAMETER SkipLogonScript
        By default, this function schedules a DataService script to execute during the next log-on. Add this parameter to avoid that functionality.

        .PARAMETER Folder
        Local folder where the downloaded scripts will be saved.
        
        .EXAMPLE
        > BootstrapArcData -ProfileRootBaseUrl $profileRootBaseUrl -TemplateBaseUrl $templateBaseUrl -AdminUsername $adminUsername -Folder $Env:tempDir

    #>
    $ErrorActionPreference = 'SilentlyContinue'

    # Uninstall Internet Explorer
    Disable-WindowsOptionalFeature -FeatureName Internet-Explorer-Optional-amd64 -Online -NoRestart

    # Disabling IE Enhanced Security Configuration
    WriteHeader "Disabling IE Enhanced Security Configuration"
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
    WriteHeader "Extending C:\ partition to the maximum size"
    Resize-Partition -DriveLetter C -Size $(Get-PartitionSupportedSize -DriveLetter C).SizeMax

    # Installing tools
    WriteHeader "Installing Chocolatey Packages"
    $chocolateyPackages = $ExtraChocolateyPackage + @("azure-cli", "az.powershell", "kubernetes-cli", "kubectx", "vcredist140", "microsoft-edge", "azcopy10", "vscode", "putty.install", "kubernetes-helm", "grep", "ssms", "dotnetcore-3.1-sdk", "git", "7zip")
    InstallChocolateyPackages -PackageList $chocolateyPackages

    Invoke-WebRequest -Uri "https://azuredatastudio-update.azurewebsites.net/latest/win32-x64-archive/stable" -OutFile "$Folder\azuredatastudio.zip"
    Invoke-WebRequest -Uri "https://aka.ms/azdata-msi" -OutFile "$Folder\AZDataCLI.msi"

    # Downloading GitHub artifacts for DataServicesLogonScript.ps1
    Invoke-WebRequest -Uri ($TemplateBaseUrl + "artifacts/settingsTemplate.json") -OutFile "$Folder/settingsTemplate.json"
    Invoke-WebRequest -Uri ($TemplateBaseUrl + "artifacts/DataServicesLogonScript.ps1") -OutFile "$Folder/DataServicesLogonScript.ps1"
    Invoke-WebRequest -Uri ($TemplateBaseUrl + "artifacts/dataController.json") -OutFile "$Folder/dataController.json"
    Invoke-WebRequest -Uri ($TemplateBaseUrl + "artifacts/dataController.parameters.json") -OutFile "$Folder/dataController.parameters.json"
    Invoke-WebRequest -Uri ($TemplateBaseUrl + "artifacts/SQLMI.json") -OutFile "$Folder/SQLMI.json"
    Invoke-WebRequest -Uri ($TemplateBaseUrl + "artifacts/SQLMI.parameters.json") -OutFile "$Folder/SQLMI.parameters.json"

    Invoke-WebRequest -Uri ($ProfileRootBaseUrl + "../common/script/powershell/DeploySQLMI.ps1") -OutFile "$Folder/DeploySQLMI.ps1"
    Invoke-WebRequest -Uri ($ProfileRootBaseUrl + "../common/script/powershell/SQLMIEndpoints.ps1") -OutFile "$Folder/SQLMIEndpoints.ps1"

    if (-not $SkipPostgreSQLInstall) {
        Invoke-WebRequest -Uri ($TemplateBaseUrl + "artifacts/postgreSQL.json") -OutFile "$Folder/postgreSQL.json"
        Invoke-WebRequest -Uri ($TemplateBaseUrl + "artifacts/postgreSQL.parameters.json") -OutFile "$Folder/postgreSQL.parameters.json"

        Invoke-WebRequest -Uri ($ProfileRootBaseUrl + "../common/script/powershell/DeployPostgreSQL.ps1") -OutFile "$Folder/DeployPostgreSQL.ps1"
    }

    Invoke-WebRequest -Uri ("https://github.com/ErikEJ/SqlQueryStress/releases/download/102/SqlQueryStress.zip") -OutFile "$Folder\SqlQueryStress.zip"
    Invoke-WebRequest -Uri ($ProfileRootBaseUrl + "../img/arcbox_wallpaper.png") -OutFile "$Folder\wallpaper.png"

    Expand-Archive $Folder\azuredatastudio.zip -DestinationPath 'C:\Program Files\Azure Data Studio' -Force
    Start-Process msiexec.exe -Wait -ArgumentList '/I C:\Temp\AZDataCLI.msi /quiet'

    New-Item -path alias:kubectl -value 'C:\ProgramData\chocolatey\lib\kubernetes-cli\tools\kubernetes\client\bin\kubectl.exe'
    New-Item -path alias:azdata -value 'C:\Program Files (x86)\Microsoft SDKs\Azdata\CLI\wbin\azdata.cmd'

    if (-not $SkipLogonScript) {
        # Schedule a task for DataServicesLogonScript.ps1
        $Trigger = New-ScheduledTaskTrigger -AtLogOn
        $Action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "$Folder\DataServicesLogonScript.ps1"
        Register-ScheduledTask -TaskName "DataServicesLogonScript" -Trigger $Trigger -User $AdminUsername -Action $Action -RunLevel "Highest" -Force

        # Disable Windows Server Manager Scheduled Task
        Get-ScheduledTask -TaskName ServerManager | Disable-ScheduledTask
    }
}

function AddDesktopShortcut {
    param(
        [string] $Icon,
        [Parameter(Mandatory = $true)]
        [string] $ShortcutName,
        [Parameter(Mandatory = $true)]
        [string] $TargetPath,
        [string] $Arguments,
        [string] $WindowStyle = 3,
        [string] $Username,
        [switch] $UrlMode
    )
    <#
        .SYNOPSIS
        Create a Desktop Shortcut.

        .DESCRIPTION
        Create a Desktop Shortcut. If a user name is provided, the shortcut is installed under that user's profile, otherwise the Shortcut is installed for all users.
        
        .PARAMETER Icon
        Path to the icon to use. This parameter is optional.

        .PARAMETER ShortcutName
        Name of the Shortcut.

        .PARAMETER TargetPath
        Path to the executable to invoke when the Shortcut is clicked.

        .PARAMETER Arguments
        Parameters to pass along to the executable when the icon is clicked. This parameter is optional.

        .PARAMETER WindowStyle
        If WindowStyle is 1, the application window will be set to its default location and size. With a value of 3, the application will be launched in a 
        maximized window. With a value of 7, it will be launched in a minimized window.

        .PARAMETER Username
        User name if we want the icon to appear only on that user's desktop. If not specified, the icon will be added on the public desktop.

        .PARAMETER UrlMode
        If the shortcut should be included as URL 

        .EXAMPLE
        > AddDesktopShortcut -ShortcutName "Azure Data Studio" -TargetPath "C:\Program Files\Azure Data Studio\azuredatastudio.exe" -Username $adminUsername
    #>
    
    WriteHeader "Creating $ShortcutName Desktop shortcut"
    If ($UrlMode) {
        $extension = "url"
    }
    else {
        $extension = "lnk"
    }

    if ( -not $Username) {
        $shortcutLocation = "$Env:Public\Desktop\$ShortcutName.$extension"
    }
    else {
        $shortcutLocation = "C:\Users\$Username\Desktop\$ShortcutName.$extension"
    }

    $wScriptShell = New-Object -ComObject WScript.Shell
    $shortcut = $wScriptShell.CreateShortcut($ShortcutLocation)
    $shortcut.TargetPath = $TargetPath
    if ($Arguments) {
        $shortcut.Arguments = $Arguments
    }

    if ($Icon) {
        $shortcut.IconLocation = "${Env:ArcBoxIconDir}\$Icon.ico, 0"
    }
    If (-not ($UrlMode)) {
        $shortcut.WindowStyle = $WindowStyle
    }
    $shortcut.Save()
}

function InstallAzureArcDataAzureCliExtensions {
    param (
        [string[]] $ExtraAzExtensionList = @(),
        [switch] $SkipInstallK8extension
    )
    <#
        .SYNOPSIS
        Install Azure CLI extensions needed for Arc-Data scenarios.

        .DESCRIPTION
        Install Azure CLI extensions needed for Arc-Data scenarios. If a list of extra extensions is provided, they will also be installed. 

        .PARAMETER ExtraAzExtensionList
        Array of extra extensions to install. 

        .PARAMETER SkipInstallK8extension
        By default this function installs k8s extensions as they are needed by most scenarios. Add this parameter to exclude K8s extensions.

        .EXAMPLE
        > InstallAzureArcDataAzureCliExtensions
    #>
    WriteHeader "Installing Azure CLI extensions"
    if ($SkipInstallK8extension) {
        $k8extensions = @()
    }
    else {
        $k8extensions = @("connectedk8s", "k8s-extension")
    }

    $az_extensions = $ExtraAzExtensionList + $k8extensions + @("arcdata")
    foreach ($az_extension in $az_extensions) {
        Write-Output "Installing $az_extension"
        az extension add --name $az_extension
    }
}

function InstallAzureDataStudioExtensions {
    param (
        [Parameter(Mandatory = $true)]
        [string[]] $AzureDataStudioExtensionList
    )
    <#
        .SYNOPSIS
        Install Data Studio extensions.

        .DESCRIPTION
        Install Data Studio extensions.
        
        .PARAMETER AzureDataStudioExtensionList
        Array with names of the extensions to install.

        .EXAMPLE
        > InstallAzureDataStudioExtensions -AzureDataStudioExtension @("microsoft.azcli", "microsoft.azuredatastudio-postgresql", "Microsoft.arc")
    #>
    WriteHeader "Installing Azure Data Studio Extensions"
    $Env:argument1 = "--install-extension"
    foreach ($extension in $AzureDataStudioExtensionList) {
        Write-Output "Installing Arc Data Studio extension: $extension"
        & "C:\Program Files\Azure Data Studio\bin\azuredatastudio.cmd" $Env:argument1 $extension
    }
}

function InitializeArcDataCommonAtLogonScript {
    param (
        [string[]] $ExtraAzExtensionList = @(),
        [string[]] $AzureDataStudioExtensionList = @("microsoft.azcli", "microsoft.azuredatastudio-postgresql", "Microsoft.arc"),
        [string[]] $ArcProviderList = @("Kubernetes", "KubernetesConfiguration", "ExtendedLocation", "AzureArcData"),
        [switch] $SkipInstallK8extension,
        [Parameter(Mandatory = $true)]
        [string] $SpnClientId,
        [Parameter(Mandatory = $true)]
        [string] $SpnClientSecret,
        [Parameter(Mandatory = $true)]
        [string] $SpnTenantId,
        [Parameter(Mandatory = $true)]
        [string] $AdminUsername,
        [Parameter(Mandatory = $true)]
        [string] $SubscriptionId
    )
    <#
        .SYNOPSIS
        Common DataServiceLogonScript.

        .DESCRIPTION
        Common DataServiceLogonScript. Performs initialization steps common to all Arc-Data scenarios.

        .PARAMETER ExtraAzExtensionList
        List of Azure CLI extensions the scenario needs that are not included by default.

        .PARAMETER AzureDataStudioExtensionList
        List of Azure Data Studio extensions the scenario needs that are not included by default.

        .PARAMETER ArcProviderList
        List of Azure Arc provider the scenario needs that are not included by default.

        .PARAMETER SkipInstallK8extension
        Provide this parameter to skip installation of the K8s extensions.

        .PARAMETER SpnClientId
        Service Principal Id to login from Azure CLI.

        .PARAMETER SpnClientSecret
        Service principal secret to login from Azure CLI.

        .PARAMETER SpnTenantId
        Tenant where the service principal is defined to login from Azure CLI.
        
        .PARAMETER AdminUsername
        User name for the client VM.

        .PARAMETER SubscriptionId
        Subscription Id of the Azure Subscription to deploy to.

        .EXAMPLE
        > InitializeArcDataCommonAtLogonScript -SpnClientId $Env:spnClientId -SpnClientSecret $Env:spnClientSecret -SpnTenantId $Env:spnTenantId -AdminUsername $Env:adminUsername  -SubscriptionId $Env:subscriptionId
    #>
    Set-NetFirewallProfile -Profile Domain, Public, Private -Enabled False

    # Login as service principal
    az login --service-principal --username $SpnClientId --password $SpnClientSecret --tenant $SpnTenantId

    # Required for azcopy
    $azurePassword = ConvertTo-SecureString $SpnClientSecret -AsPlainText -Force
    $psCred = New-Object System.Management.Automation.PSCredential($SpnClientId , $AzurePassword)
    Connect-AzAccount -Credential $psCred -TenantId $SpnTenantId -ServicePrincipal

    # Making extension install dynamic
    az config set extension.use_dynamic_install=yes_without_prompt

    WriteHeader "Az CLI version"
    az -v
    if ($SkipInstallK8extension) {
        InstallAzureArcDataAzureCliExtensions -ExtraAzExtensionList $ExtraAzExtensionList
    }
    else {
        InstallAzureArcDataAzureCliExtensions -ExtraAzExtensionList $ExtraAzExtensionList -SkipInstallK8extension
    }

    # Set default subscription to run commands against
    # The "subscriptionId" value comes from the clientVM.json ARM template. This is needed in case the Service 
    # Principal has access to multiple subscriptions, which can break the automation logic
    az account set --subscription $SubscriptionId

    InstallAzureDataStudioExtensions -AzureDataStudioExtensionList $AzureDataStudioExtensionList

    AddDesktopShortcut -ShortcutName "Azure Data Studio" -TargetPath "C:\Program Files\Azure Data Studio\azuredatastudio.exe" -Username $AdminUsername

    RegisterAzureArcProviders -ArcProviderList $ArcProviderList
}

function DownloadCapiFiles {
    param (
        [Parameter(Mandatory = $true)]
        [string] $StagingStorageAccountName,
        [Parameter(Mandatory = $true)]
        [string] $ResourceGroup,
        [Parameter(Mandatory = $true)]
        [string] $Username,
        [Parameter(Mandatory = $true)]
        [string] $Folder
    )
    <#
        .SYNOPSIS
        Download K8s files.

        .DESCRIPTION
        Download k8s files to connect the cluster API and the installation logs. Writes the K8s nodes configuration
        to the standard output at the end as a verification step
        
        .PARAMETER StagingStorageAccountName
        Storage account name where the log and kubeconfig file are located.

        .PARAMETER ResourceGroup
        Storage account resource group name.
        
        .PARAMETER Username
        User name for the client VM.
        
        .PARAMETER Folder
        Folder where the log files are saved.

        .EXAMPLE
        > DownloadCapiFiles -StagingStorageAccountName "$Env:stagingStorageAccountName" -ResourceGroup "$Env:resourceGroup" -Username "$Env:USERNAME" -Folder "$Env:TempDir"
    #>
    WriteHeader "Downloading CAPI Kubernetes cluster kubeconfig file"
    $sourceFile = "https://$StagingStorageAccountName.blob.core.windows.net/staging-capi/config"
    $context = (Get-AzStorageAccount -ResourceGroupName $ResourceGroup).Context
    $sas = New-AzStorageAccountSASToken -Context $context -Service Blob -ResourceType Object -Permission racwdlup
    $sourceFile = $sourceFile + $sas
    azcopy cp --check-md5 FailIfDifferentOrMissing $sourceFile  "C:\Users\$Username\.kube\config"

    # Downloading 'installCAPI.log' log file
    WriteHeader "Downloading 'installCAPI.log' log file"
    $sourceFile = "https://$StagingStorageAccountName.blob.core.windows.net/staging-capi/installCAPI.log"
    $sourceFile = $sourceFile + $sas
    azcopy cp --check-md5 FailIfDifferentOrMissing $sourceFile  "$Folder\installCAPI.log"

    WriteHeader "Checking kubernetes nodes"
    kubectl get nodes
}

function ChangingToClientVMWallpaper {
    param (
        [Parameter(Mandatory = $true)]
        [string] $Folder
    )
    <#
        .SYNOPSIS
        Change the desktop Wallpaper.

        .DESCRIPTION
        Change the desktop Wallpaper. The new Wallpaper image is expected to be named wallpaper.png.
        
        .PARAMETER Folder
        Folder where the new Wallpaper image is located.

        .EXAMPLE
        > ChangingToClientVMWallpaper -Folder $Env:TempDir
    #>
    $imgPath = "$Folder\wallpaper.png"
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

function CopyAzureDataStudioSettingsTemplateFile {
    param (
        [Parameter(Mandatory = $true)]
        [string] $AdminUsername,
        [Parameter(Mandatory = $true)]
        [string] $Folder
    )
    <#
        .SYNOPSIS
        Override Azure Data Studio configuration file.

        .DESCRIPTION
        Override Azure Data Studio configuration file.
        
        .PARAMETER AdminUsername
        Admin user name in the client VM.

        .PARAMETER Folder
        Folder where the Azure Data Studio config file is located.

        .EXAMPLE
        > CopyAzureDataStudioSettingsTemplateFile -AdminUsername $adminUsername -Folder $folder
    #>
    WriteHeader "Copying Azure Data Studio settings template file"
    New-Item -Path "C:\Users\$AdminUsername\AppData\Roaming\azuredatastudio\" -Name "User" -ItemType "directory" -Force
    Copy-Item -Path "$Folder\settingsTemplate.json" -Destination "C:\Users\$AdminUsername\AppData\Roaming\azuredatastudio\User\settings.json"
}

function ApplyAzureDataStudioSettingsTemplateFileAndOperationsUrlShortcut {
    param (
        [Parameter(Mandatory = $true)]
        [string] $AdminUsername,
        [Parameter(Mandatory = $true)]
        [string] $Folder,
        [Parameter(Mandatory = $true)]
        [string] $DeploySQLMI,
        [string] $DeployPostgreSQL
    )
    <#
        .SYNOPSIS
        Configure Azure Data Studio if SQLMI or PostgreSQL was installed.

        .DESCRIPTION
        Configure Azure Data Studio if SQLMI or PostgreSQL was installed.  
        
        .PARAMETER AdminUsername
        Admin user name for the client VM.

        .PARAMETER Folder
        Folder where the Azure Data Studio config file is located.

        .PARAMETER DeploySQLMI
        True if SQLMI was installed.
        
        .PARAMETER DeployPostgreSQL
        True if PostgreSQL was installed.

        .EXAMPLE
        > ApplyAzureDataStudioSettingsTemplateFileAndOperationsUrlShortcut -AdminUsername $Env:adminUsername -Folder $Env:TempDir -DeploySQLMI $Env:deploySQLMI -DeployPostgreSQL $Env:deployPostgreSQL
    #>
    if ( $DeploySQLMI -eq $true -or $DeployPostgreSQL -eq $true ) {
        CopyAzureDataStudioSettingsTemplateFile -AdminUsername $AdminUsername -Folder $Folder
    
        # Creating desktop url shortcuts for built-in Grafana and Kibana services 
        $GrafanaURL = kubectl get service/metricsui-external-svc -n arc -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
        $GrafanaURL = "https://" + $GrafanaURL + ":3000"
        AddDesktopShortcut -ShortcutName "Grafana" -TargetPath $GrafanaURL -Username $AdminUsername -UrlMode

        $KibanaURL = kubectl get service/logsui-external-svc -n arc -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
        $KibanaURL = "https://" + $KibanaURL + ":5601"
        AddDesktopShortcut -ShortcutName "Kibana" -TargetPath $KibanaURL -Username $AdminUsername -UrlMode
    }
}

function EnableDataControllerAutoMetrics {
    param (
        [Parameter(Mandatory = $true)]
        [string] $ResourceGroup,
        [Parameter(Mandatory = $true)]
        [string] $WorkspaceName,
        [string] $Jumpstartdc = "jumpstart-dc"
    )
    <#
        .SYNOPSIS
        Enable data controller metrics.

        .DESCRIPTION
        Enable data controller metrics.
        
        .PARAMETER ResourceGroup
        Data controller resource group name.

        .PARAMETER WorkspaceName
        Name of the workspace to collect metrics.

        .PARAMETER Jumpstartdc
        Data controller name.

        .EXAMPLE
        > EnableDataControllerAutoMetrics -ResourceGroup $Env:resourceGroup -WorkspaceName $Env:workspaceName
    #>
    WriteHeader "Enabling data controller auto metrics & logs upload to log analytics"
    $Env:WORKSPACE_ID = $(az resource show --resource-group $ResourceGroup --name $WorkspaceName --resource-type "Microsoft.OperationalInsights/workspaces" --query properties.customerId -o tsv)
    $Env:WORKSPACE_SHARED_KEY = $(az monitor log-analytics workspace get-shared-keys --resource-group $ResourceGroup --workspace-name $WorkspaceName  --query primarySharedKey -o tsv)
    az arcdata dc update --name $Jumpstartdc --resource-group $ResourceGroup --auto-upload-logs true
    az arcdata dc update --name $Jumpstartdc --resource-group $ResourceGroup --auto-upload-metrics true
}

function DeployAzureArcDataController {
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingPlainTextForPassword", "")]
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingUsernameAndPasswordParams", "")]
    param (
        [Parameter(Mandatory = $true)]
        [string] $ResourceGroup,
        [Parameter(Mandatory = $true)]
        [string] $Folder,
        [Parameter(Mandatory = $true)]
        [string] $WorkspaceName,
        [Parameter(Mandatory = $true)]
        [string] $AzdataUsername,
        [Parameter(Mandatory = $true)]
        [string] $AzdataPassword,
        [Parameter(Mandatory = $true)]
        [string] $SpnClientId,
        [Parameter(Mandatory = $true)]
        [string] $SpnTenantId,
        [Parameter(Mandatory = $true)]
        [string] $SpnClientSecret,
        [Parameter(Mandatory = $true)]
        [string] $SubscriptionId,
        [string] $Jumpstartcl = 'jumpstart-cl'
    )
    <#
        .SYNOPSIS
        Deploy the Data controller to Azure.

        .DESCRIPTION
        Deploys the Data controller to Azure using an ARM template file. Waits until the K8s cluster starts reporting the status of the data controller.
        
        .PARAMETER ResourceGroup
        Data controller resource group.
        
        .PARAMETER Folder
        Folder where the data controller configuration template is located.
        
        .PARAMETER WorkspaceName
        Log Analytics Workspace name
        
        .PARAMETER AzdataUsername
        User account.
        
        .PARAMETER AzdataPassword
        User account password.

        .PARAMETER spnClientId
        Client Principal Id.

        .PARAMETER SpnTenantId
        Tenant Id.

        .PARAMETER SpnClientSecret
        Service Principal secret.

        .PARAMETER SubscriptionId
        Subscription Id.

        .PARAMETER Jumpstartcl
        Data controller name.

        .EXAMPLE
        > DeployAzureArcDataController -ResourceGroup $Env:resourceGroup -Folder $Env:TempDir -WorkspaceName $Env:workspaceName -AzdataUsername $Env:AZDATA_USERNAME -AzdataPassword $Env:AZDATA_PASSWORD -SpnClientId $Env:spnClientId -SpnTenantId $Env:spnTenantId -SpnClientSecret $Env:spnClientSecret -SubscriptionId $Env:subscriptionId
    #>
    WriteHeader "Deploying Azure Arc Data Controller"
    $customLocationId = $(az customlocation show --name $Jumpstartcl --resource-group $ResourceGroup --query id -o tsv)
    $workspaceId = $(az resource show --resource-group $ResourceGroup --name $WorkspaceName --resource-type "Microsoft.OperationalInsights/workspaces" --query properties.customerId -o tsv)
    $workspaceKey = $(az monitor log-analytics workspace get-shared-keys --resource-group $ResourceGroup --workspace-name $WorkspaceName --query primarySharedKey -o tsv)

    $dataControllerParams = "$Folder\dataController.parameters.json"

    (Get-Content -Path $dataControllerParams) -replace 'resourceGroup-stage', $ResourceGroup | Set-Content -Path $dataControllerParams
    (Get-Content -Path $dataControllerParams) -replace 'azdataUsername-stage', $AzdataUsername | Set-Content -Path $dataControllerParams
    (Get-Content -Path $dataControllerParams) -replace 'azdataPassword-stage', $AzdataPassword | Set-Content -Path $dataControllerParams
    (Get-Content -Path $dataControllerParams) -replace 'customLocation-stage', $customLocationId | Set-Content -Path $dataControllerParams
    (Get-Content -Path $dataControllerParams) -replace 'subscriptionId-stage', $SubscriptionId | Set-Content -Path $dataControllerParams
    (Get-Content -Path $dataControllerParams) -replace 'spnClientId-stage', $SpnClientId | Set-Content -Path $dataControllerParams
    (Get-Content -Path $dataControllerParams) -replace 'spnTenantId-stage', $SpnTenantId | Set-Content -Path $dataControllerParams
    (Get-Content -Path $dataControllerParams) -replace 'spnClientSecret-stage', $SpnClientSecret | Set-Content -Path $dataControllerParams
    (Get-Content -Path $dataControllerParams) -replace 'logAnalyticsWorkspaceId-stage', $workspaceId | Set-Content -Path $dataControllerParams
    (Get-Content -Path $dataControllerParams) -replace 'logAnalyticsPrimaryKey-stage', $workspaceKey | Set-Content -Path $dataControllerParams

    az deployment group create --resource-group $ResourceGroup `
        --template-file "$Folder\dataController.json" `
        --parameters "$Folder\dataController.parameters.json"
    Write-Output "`n"

    Do {
        Write-Output "Waiting for the data controller. Hold on tight, this might take a few minutes...(45s sleeping loop)"
        Start-Sleep -Seconds 45
        $dcStatus = $(if (kubectl get datacontroller -n arc | Select-String "Ready" -Quiet) { "Ready!" }Else { "Nope" })
    } while ($dcStatus -eq "Nope")

    WriteHeader "Azure Arc data controller is ready!"
}

function CreateCustomLocation {
    param (
        [Parameter(Mandatory = $true)]
        [string] $ResourceGroup,
        [Parameter(Mandatory = $true)]
        [string] $ClusterName,
        [Parameter(Mandatory = $true)]
        [string] $Kubeconfig,
        [string] $jumpstartcl = 'jumpstart-cl'
    )
    <#
        .SYNOPSIS
        Create custom location.
 
        .DESCRIPTION
        Create custom location.
        
        .PARAMETER ResourceGroup
        Resource group where the custom location is going to be deployed.

        .PARAMETER ClusterName
        Cluster name.

        .PARAMETER Kubeconfig
        Kubeconfig location.

        .PARAMETER Jumpstartcl
         Custom location name.
        
        .EXAMPLE
        > CreateCustomLocation -ResourceGroup $Env:resourceGroup -ClusterName $Env:ArcK8sClusterName -Kubeconfig $Env:KUBECONFIG
    #>
    WriteHeader "Create Custom Location"
    $connectedClusterId = az connectedk8s show --name $ClusterName --resource-group $ResourceGroup --query id -o tsv

    $extensionId = az k8s-extension show --name arc-data-services `
        --cluster-type connectedClusters `
        --cluster-name $ClusterName `
        --resource-group $ResourceGroup `
        --query id -o tsv

    Start-Sleep -Seconds 20
    # Create Custom Location
    az customlocation create --name $Jumpstartcl `
        --resource-group $ResourceGroup `
        --namespace arc `
        --host-resource-id $connectedClusterId `
        --cluster-extension-ids $extensionId `
        --kubeconfig $Kubeconfig
    
}

function InstallAzureArcEnabledDataServicesExtension {
    param (
        [Parameter(Mandatory = $true)]
        [string] $ResourceGroup,
        [Parameter(Mandatory = $true)]
        [string] $ClusterName
    )
    <#
        .SYNOPSIS
        Install the Azure Arc-enabled data services extension.

        .DESCRIPTION
        Install the Azure Arc-enabled data services extension.

        .PARAMETER ResourceGroup
        Resource group where the cluster is located.

        .PARAMETER ClusterName
        Cluster name.
        
        .EXAMPLE
        > InstallAzureArcEnabledDataServicesExtension -ResourceGroup $Env:resourceGroup -ClusterName $Env:ArcK8sClusterName
    #>
    WriteHeader "Installing Azure Arc-enabled data services extension"
    az k8s-extension create --name arc-data-services `
        --extension-type microsoft.arcdataservices `
        --cluster-type connectedClusters `
        --cluster-name $ClusterName `
        --resource-group $ResourceGroup `
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