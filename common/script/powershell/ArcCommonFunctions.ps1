Write-Output "Arc Common Functions"

function InstallChocolateyApp {
    param(
        [string[]]$chocolateyAppList
    )
    try {
        choco config get cacheLocation
    }
    catch {
        Write-Output "Chocolatey not detected, trying to install now"
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
        [switch] $avoidScriptAtLogOn
    )
    
    $ErrorActionPreference = 'SilentlyContinue'

    # Uninstall Internet Explorer
    Disable-WindowsOptionalFeature -FeatureName Internet-Explorer-Optional-amd64 -Online -NoRestart

    # Disabling IE Enhanced Security Configuration
    Write-Output "Disabling IE Enhanced Security Configuration"
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
    Write-Output "Extending C:\ partition to the maximum size"
    Resize-Partition -DriveLetter C -Size $(Get-PartitionSupportedSize -DriveLetter C).SizeMax

    # Installing tools
    Write-Output "Installing Chocolatey Apps"
    $chocolateyAppList = $extraChocolateyAppList + @("azure-cli", "az.powershell", "kubernetes-cli", "kubectx", "vcredist140", "microsoft-edge", "azcopy10", "vscode", "putty.install", "kubernetes-helm", "grep", "ssms", "dotnetcore-3.1-sdk", "git", "7zip")
    InstallChocolateyApp $chocolateyAppList

    Invoke-WebRequest -Uri "https://azuredatastudio-update.azurewebsites.net/latest/win32-x64-archive/stable" -OutFile "$Env:tempDir\azuredatastudio.zip"
    Invoke-WebRequest -Uri "https://aka.ms/azdata-msi" -OutFile "$Env:tempDir\AZDataCLI.msi"

    # Downloading GitHub artifacts for DataServicesLogonScript.ps1
    Invoke-WebRequest -Uri ($templateBaseUrl + "artifacts/settingsTemplate.json") -OutFile "$Env:tempDir/settingsTemplate.json"
    Invoke-WebRequest -Uri ($templateBaseUrl + "artifacts/DataServicesLogonScript.ps1") -OutFile "$Env:tempDir/DataServicesLogonScript.ps1"
    Invoke-WebRequest -Uri ($templateBaseUrl + "artifacts/DeploySQLMI.ps1") -OutFile "$Env:tempDir/DeploySQLMI.ps1"
    Invoke-WebRequest -Uri ($templateBaseUrl + "artifacts/dataController.json") -OutFile "$Env:tempDir/dataController.json"
    Invoke-WebRequest -Uri ($templateBaseUrl + "artifacts/dataController.parameters.json") -OutFile "$Env:tempDir/dataController.parameters.json"
    Invoke-WebRequest -Uri ($templateBaseUrl + "artifacts/SQLMI.json") -OutFile "$Env:tempDir/SQLMI.json"
    Invoke-WebRequest -Uri ($templateBaseUrl + "artifacts/SQLMI.parameters.json") -OutFile "$Env:tempDir/SQLMI.parameters.json"
    Invoke-WebRequest -Uri ($templateBaseUrl + "artifacts/SQLMIEndpoints.ps1") -OutFile "$Env:tempDir/SQLMIEndpoints.ps1"

    if (-not $avoidPostgreSQL) {
        Invoke-WebRequest -Uri ($templateBaseUrl + "artifacts/postgreSQL.json") -OutFile "$Env:tempDir/postgreSQL.json"
        Invoke-WebRequest -Uri ($templateBaseUrl + "artifacts/postgreSQL.parameters.json") -OutFile "$Env:tempDir/postgreSQL.parameters.json"
        Invoke-WebRequest -Uri ($templateBaseUrl + "artifacts/DeployPostgreSQL.ps1") -OutFile "$Env:tempDir/DeployPostgreSQL.ps1"
    }

    Invoke-WebRequest -Uri ("https://github.com/ErikEJ/SqlQueryStress/releases/download/102/SqlQueryStress.zip") -OutFile "$Env:tempDir\SqlQueryStress.zip"
    Invoke-WebRequest -Uri ($profileRootBaseUrl + "../img/arcbox_wallpaper.png") -OutFile "$Env:tempDir\wallpaper.png"

    Expand-Archive $Env:tempDir\azuredatastudio.zip -DestinationPath 'C:\Program Files\Azure Data Studio'
    Start-Process msiexec.exe -Wait -ArgumentList '/I C:\Temp\AZDataCLI.msi /quiet'

    New-Item -path alias:kubectl -value 'C:\ProgramData\chocolatey\lib\kubernetes-cli\tools\kubernetes\client\bin\kubectl.exe'
    New-Item -path alias:azdata -value 'C:\Program Files (x86)\Microsoft SDKs\Azdata\CLI\wbin\azdata.cmd'

    if (-not $avoidScriptAtLogOn) {
        # Creating scheduled task for DataServicesLogonScript.ps1
        $Trigger = New-ScheduledTaskTrigger -AtLogOn
        $Action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "$Env:tempDir\DataServicesLogonScript.ps1"
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
    Write-Output "`n"
    Write-Output "Creating $shortcutName Desktop shortcut"
    Write-Output "`n"
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
    Write-Output "Installing Azure CLI extensions"
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
    Write-Output "`n"
    Write-Output "Installing Azure Data Studio Extensions"
    Write-Output "`n"
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
        [switch] $notInstallK8extensions
    )
    # Main script
    Set-NetFirewallProfile -Profile Domain, Public, Private -Enabled False

    # Login as service principal
    az login --service-principal --username $Env:spnClientId --password $Env:spnClientSecret --tenant $Env:spnTenantId

    # Required for azcopy
    $azurePassword = ConvertTo-SecureString $Env:spnClientSecret -AsPlainText -Force
    $psCred = New-Object System.Management.Automation.PSCredential($Env:spnClientId , $azurePassword)
    Connect-AzAccount -Credential $psCred -TenantId $Env:spnTenantId -ServicePrincipal

    # Making extension install dynamic
    az config set extension.use_dynamic_install=yes_without_prompt

    Write-Output "Az cli version"
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
    az account set --subscription $Env:subscriptionId

    InstallAzureDataStudioExtensions -azureDataStudioExtensions $azureDataStudioExtensions

    AddDesktopShortcut -shortcutName "Azure Data Studio" -targetPath "C:\Program Files\Azure Data Studio\azuredatastudio.exe" -username $Env:adminUsername

    RegisterAzureArcProviders -arcProviderList $arcProviderList
}

