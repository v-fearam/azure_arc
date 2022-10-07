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

    if (-not $SkipPostgreSQLInstall) {
        Invoke-WebRequest -Uri ($TemplateBaseUrl + "artifacts/postgreSQL.json") -OutFile "$Folder/postgreSQL.json"
        Invoke-WebRequest -Uri ($TemplateBaseUrl + "artifacts/postgreSQL.parameters.json") -OutFile "$Folder/postgreSQL.parameters.json"
    }

    Invoke-WebRequest -Uri ("https://github.com/ErikEJ/SqlQueryStress/releases/download/102/SqlQueryStress.zip") -OutFile "$Folder\SqlQueryStress.zip"
    Invoke-WebRequest -Uri ($ProfileRootBaseUrl + "../img/arcbox_wallpaper.png") -OutFile "$Folder\wallpaper.png"

    Expand-Archive $Folder\azuredatastudio.zip -DestinationPath 'C:\Program Files\Azure Data Studio' -Force
    Start-Process msiexec.exe -Wait -ArgumentList '/I C:\Temp\AZDataCLI.msi /quiet'

    New-Item -path alias:kubectl -value 'C:\ProgramData\chocolatey\lib\kubernetes-cli\tools\kubernetes\client\bin\kubectl.exe'
    New-Item -path alias:azdata -value 'C:\Program Files (x86)\Microsoft SDKs\Azdata\CLI\wbin\azdata.cmd'
}
function InstallAzureArcDataCliExtensions {
    param (
        [string[]] $ExtraAzExtensionList,
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
    ForceAzureClientsLogin
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
        [string[]] $AzureDataStudioExtensionList = @("microsoft.azcli", "microsoft.azuredatastudio-postgresql", "Microsoft.arc")
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
function RegisterAzureArcDataProviders {
    param (
        [string[]] $ArcProviderList = @("Kubernetes", "KubernetesConfiguration", "ExtendedLocation", "AzureArcData")
    )
    <#
        .SYNOPSIS
        Register Arc Providers.

        .DESCRIPTION
        Register Arc Providers. Outputs each provider configuration to the standard output at the end as a verification step.
        
        .PARAMETER ArcProviderList
        Array of Arc providers to install. Note that "Microsoft." is added automatically at the beginning of the name.

        .EXAMPLE
        > RegisterAzureArcProviders -ArcProvider @("Kubernetes", "KubernetesConfiguration", "ExtendedLocation", "AzureArcData")
    #>
    WriteHeader "Registering Azure Arc providers"
    ForceAzureClientsLogin
    Write-Output "`n"
    foreach ($provider in $ArcProviderList) {
        Write-Output "Installing $provider"
        az provider register --namespace "Microsoft.$provider" --wait
    }

    foreach ($provider in $ArcProviderList) {
        Write-Output "`n"
        az provider show --namespace "Microsoft.$provider" -o table
    }
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
    ForceAzureClientsLogin
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
    ForceAzureClientsLogin
    $Env:WORKSPACE_ID = $(az resource show --resource-group $ResourceGroup --name $WorkspaceName --resource-type "Microsoft.OperationalInsights/workspaces" --query properties.customerId -o tsv)
    $Env:WORKSPACE_SHARED_KEY = $(az monitor log-analytics workspace get-shared-keys --resource-group $ResourceGroup --workspace-name $WorkspaceName  --query primarySharedKey -o tsv)
    az arcdata dc update --name $Jumpstartdc --resource-group $ResourceGroup --auto-upload-logs true
    az arcdata dc update --name $Jumpstartdc --resource-group $ResourceGroup --auto-upload-metrics true
}
function DeployAzureArcDataController {
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
        [Security.SecureString] $AzdataPassword,
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
        User account password as Secure String

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
        > DeployAzureArcDataController -ResourceGroup $Env:resourceGroup -Folder $Env:TempDir -WorkspaceName $Env:workspaceName -AzdataUsername $Env:AZDATA_USERNAME -AzdataPassword (ConvertTo-SecureString $Env:AZDATA_PASSWORD -AsPlainText -Force) -SpnClientId $Env:spnClientId -SpnTenantId $Env:spnTenantId -SpnClientSecret $Env:spnClientSecret -SubscriptionId $Env:subscriptionId
    #>
    WriteHeader "Deploying Azure Arc Data Controller"
    ForceAzureClientsLogin
    $customLocationId = $(az customlocation show --name $Jumpstartcl --resource-group $ResourceGroup --query id -o tsv)
    $workspaceId = $(az resource show --resource-group $ResourceGroup --name $WorkspaceName --resource-type "Microsoft.OperationalInsights/workspaces" --query properties.customerId -o tsv)
    $workspaceKey = $(az monitor log-analytics workspace get-shared-keys --resource-group $ResourceGroup --workspace-name $WorkspaceName --query primarySharedKey -o tsv)

    $dataControllerParams = "$Folder\dataController.parameters.json"
    $AzdataPasswordPlainText = (New-Object PSCredential "user",$AzdataPassword).GetNetworkCredential().Password #ConvertFrom-SecureString -SecureString $AzdataPassword -AsPlainText, -AsPlainText does not work on PS 5.1
    (Get-Content -Path $dataControllerParams) -replace 'resourceGroup-stage', $ResourceGroup | Set-Content -Path $dataControllerParams
    (Get-Content -Path $dataControllerParams) -replace 'azdataUsername-stage', $AzdataUsername | Set-Content -Path $dataControllerParams
    (Get-Content -Path $dataControllerParams) -replace 'azdataPassword-stage', $AzdataPasswordPlainText | Set-Content -Path $dataControllerParams
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
    ForceAzureClientsLogin
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
    ForceAzureClientsLogin
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
function DeployAzureArcPostgreSQL {
    param (
        [Parameter(Mandatory = $true)]
        [string]$ResourceGroup,
        [Parameter(Mandatory = $true)]
        [string]$Folder,
        [Parameter(Mandatory = $true)]
        [Security.SecureString] $AzdataPassword,
        [Parameter(Mandatory = $true)]
        [string]$SubscriptionId,
        [string]$DeploySQLMI,
        [string]$ControllerName = "jumpstart-dc",
        [string]$CustomLocation = "jumpstart-cl"
    )
    
    <#
        .SYNOPSIS
        Deploy Azure Arc-enabled PostgreSQL.  

        .DESCRIPTION
        Deploy Azure Arc-enabled PostgreSQL.  

        .PARAMETER ResourceGroup
         Resource group where the resources are being created.

        .PARAMETER Folder
         Folder where the config files are present     . 

        .PARAMETER AzdataPassword
        Azure cli password.

        .PARAMETER SubscriptionId
        Azure subscription id needed for PostgreSQL configuration.

        .PARAMETER DeploySQLMI
        true if SQLMI was deployed.

        .PARAMETER ControllerName
        Data controller name.

        .PARAMETER CustomLocation
        Custom location name.
        
        .EXAMPLE
        > DeployAzureArcPostgreSQL -ResourceGroup $Env:resourceGroup -Folder $Env:TempDir -AzdataPassword $(ConvertFrom-SecureString -SecureString $AzdataPassword -AsPlainText) -SubscriptionId $Env:subscriptionId -DeploySQLMI $env:deploySQLMI
    #>
    WriteHeader "Deploying Azure Arc-enabled PostgreSQL"
    ForceAzureClientsLogin
    $customLocationId = $(az customlocation show --name $CustomLocation --resource-group $ResourceGroup --query id -o tsv)
    $dataControllerId = $(az resource show --resource-group $ResourceGroup --name $ControllerName --resource-type "Microsoft.AzureArcData/dataControllers" --query id -o tsv)

    WriteHeader  "Localize ARM template"
    $ServiceType = "LoadBalancer"

    # Resource Requests
    $coordinatorCoresRequest = "2"
    $coordinatorMemoryRequest = "4Gi"
    $coordinatorCoresLimit = "4"
    $coordinatorMemoryLimit = "8Gi"

    # Storage
    $StorageClassName = "managed-premium"
    $dataStorageSize = "5Gi"
    $logsStorageSize = "5Gi"
    $backupsStorageSize = "5Gi"

    # Citus Scale out
    $numWorkers = 1
    ################################################

    $PSQLParams = "$Folder\postgreSQL.parameters.json"
    $AzdataPasswordPlainText = (New-Object PSCredential "user",$AzdataPassword).GetNetworkCredential().Password #ConvertFrom-SecureString -SecureString $AzdataPassword -AsPlainText, -AsPlainText does not work on PS 5.1
    (Get-Content -Path $PSQLParams) -replace 'resourceGroup-stage', $ResourceGroup | Set-Content -Path $PSQLParams
    (Get-Content -Path $PSQLParams) -replace 'dataControllerId-stage', $dataControllerId | Set-Content -Path $PSQLParams
    (Get-Content -Path $PSQLParams) -replace 'customLocation-stage', $customLocationId | Set-Content -Path $PSQLParams
    (Get-Content -Path $PSQLParams) -replace 'subscriptionId-stage', $SubscriptionId | Set-Content -Path $PSQLParams
    (Get-Content -Path $PSQLParams) -replace 'azdataPassword-stage', $AzdataPasswordPlainText | Set-Content -Path $PSQLParams
    (Get-Content -Path $PSQLParams) -replace 'serviceType-stage', $ServiceType | Set-Content -Path $PSQLParams
    (Get-Content -Path $PSQLParams) -replace 'coordinatorCoresRequest-stage', $coordinatorCoresRequest | Set-Content -Path $PSQLParams
    (Get-Content -Path $PSQLParams) -replace 'coordinatorMemoryRequest-stage', $coordinatorMemoryRequest | Set-Content -Path $PSQLParams
    (Get-Content -Path $PSQLParams) -replace 'coordinatorCoresLimit-stage', $coordinatorCoresLimit | Set-Content -Path $PSQLParams
    (Get-Content -Path $PSQLParams) -replace 'coordinatorMemoryLimit-stage', $coordinatorMemoryLimit | Set-Content -Path $PSQLParams
    (Get-Content -Path $PSQLParams) -replace 'dataStorageClassName-stage', $StorageClassName | Set-Content -Path $PSQLParams
    (Get-Content -Path $PSQLParams) -replace 'logsStorageClassName-stage', $StorageClassName | Set-Content -Path $PSQLParams
    (Get-Content -Path $PSQLParams) -replace 'backupStorageClassName-stage', $StorageClassName | Set-Content -Path $PSQLParams
    (Get-Content -Path $PSQLParams) -replace 'dataSize-stage', $dataStorageSize | Set-Content -Path $PSQLParams
    (Get-Content -Path $PSQLParams) -replace 'logsSize-stage', $logsStorageSize | Set-Content -Path $PSQLParams
    (Get-Content -Path $PSQLParams) -replace 'backupsSize-stage', $backupsStorageSize | Set-Content -Path $PSQLParams
    (Get-Content -Path $PSQLParams) -replace 'numWorkersStage', $numWorkers | Set-Content -Path $PSQLParams

    az deployment group create --resource-group $ResourceGroup `
        --template-file "$Folder\postgreSQL.json" `
        --parameters "$Folder\postgreSQL.parameters.json"

    # Ensures postgres container is initiated and ready to accept restores
    $pgWorkerPodName = "jumpstartps-0"
  
    Do {
        Write-Output "Waiting for PostgreSQL. Hold tight, this might take a few minutes...(45s sleeping loop)"
        Start-Sleep -Seconds 45
        $buildService = $(if ((kubectl get pods -n arc | Select-String $pgWorkerPodName | Select-String "Running" -Quiet)) { "Ready!" }Else { "Nope" })
    } while ($buildService -eq "Nope")

    WriteHeader "Azure Arc-enabled PostgreSQL is ready!"
    Start-Sleep -Seconds 60
    
    # Downloading demo database and restoring onto Postgres
    WriteHeader "Downloading AdventureWorks.sql template for Postgres... (1/3)"
    kubectl exec $pgWorkerPodName  -n arc -c postgres -- /bin/bash -c "curl -o /tmp/AdventureWorks2019.sql 'https://jumpstart.blob.core.windows.net/jumpstartbaks/AdventureWorks2019.sql?sp=r&st=2021-09-08T21:04:16Z&se=2030-09-09T05:04:16Z&spr=https&sv=2020-08-04&sr=b&sig=MJHGMyjV5Dh5gqyvfuWRSsCb4IMNfjnkM%2B05F%2F3mBm8%3D'" 2>&1 | Out-Null
    WriteHeader "Creating AdventureWorks database on Postgres... (2/3)"
    kubectl exec $pgWorkerPodName  -n arc -c postgres -- psql -U postgres -c 'CREATE DATABASE "adventureworks2019";' postgres 2>&1 | Out-Null
    WriteHeader "Restoring AdventureWorks database on Postgres. (3/3)"
    kubectl exec $pgWorkerPodName  -n arc -c postgres -- psql -U postgres -d adventureworks2019 -f /tmp/AdventureWorks2019.sql 2>&1 | Out-Null

    # Creating Azure Data Studio settings for PostgreSQL connection
    WriteHeader "Creating Azure Data Studio settings for PostgreSQL connection"
    $settingsTemplate = "$Folder\settingsTemplate.json"

    # Retrieving PostgreSQL connection endpoint
    $pgsqlstring = kubectl get postgresql jumpstartps -n arc -o=jsonpath='{.status.primaryEndpoint}'

    # Replace placeholder values in settingsTemplate.json
    (Get-Content -Path $settingsTemplate) -replace 'arc_postgres_host', $pgsqlstring.split(":")[0] | Set-Content -Path $settingsTemplate
    (Get-Content -Path $settingsTemplate) -replace 'arc_postgres_port', $pgsqlstring.split(":")[1] | Set-Content -Path $settingsTemplate
    (Get-Content -Path $settingsTemplate) -replace 'ps_password', $AzdataPasswordPlainText | Set-Content -Path $settingsTemplate


    # If SQL MI isn't being deployed, clean up settings file
    if ( $DeploySQLMI -eq $false ) {
        $string = Get-Content -Path $settingsTemplate | Select-Object -First 9 -Last 24
        $string | Set-Content -Path $settingsTemplate
    }
}
function DeployAzureArcSQLManagedInstance {
    param (
        [Parameter(Mandatory = $true)]
        [string]$ResourceGroup,
        [Parameter(Mandatory = $true)]
        [string]$Folder,
        [Parameter(Mandatory = $true)]
        [string]$AdminUsername,
        [Parameter(Mandatory = $true)]
        [string]$AzdataUsername,
        [Security.SecureString]$AzdataPassword,
        [Parameter(Mandatory = $true)]
        [string]$SubscriptionId,
        [Parameter(Mandatory = $true)]
        [string]$SQLMIHA,
        [string]$DeployPostgreSQL,
        [string]$ControllerName = "jumpstart-dc",
        [string]$CustomLocation = "jumpstart-cl"
    )
    <#
        .SYNOPSIS
        Deploy Azure Arc-enabled SQLManagedInstance.

        .DESCRIPTION
        Deploy Azure Arc-enabled SQLManagedInstance.

        .PARAMETER ResourceGroup
         Resource group where the resources are being created.

        .PARAMETER Folder
         Folder where the config files are present. 

        .PARAMETER AdminUsername
        VM admin username.

        .PARAMETER AzdataUsername
        Az username needed for SQLManagedInstance configuration.

        .PARAMETER AzdataPassword
        Az password needed for SQLManagedInstance configuration.

        .PARAMETER SubscriptionId
        Azure subscription id needed for SQLManagedInstance configuration.

        .PARAMETER SQLMIHA
        true if SQLMIHA was deployed

        .PARAMETER DeployPostgreSQL
        true if PostgreSQL was deployed

        .PARAMETER ControllerName
        Data controller name.

        .PARAMETER CustomLocation
        Custom location name.
        
        .EXAMPLE
        >  DeployAzureArcSQLManagedInstance -ResourceGroup $Env:resourceGroup -Folder $Env:TempDir -AdminUsername $Env:adminUsername -AzdataUsername $Env:AZDATA_USERNAME -AzdataPassword $(ConvertFrom-SecureString -SecureString $AzdataPassword -AsPlainText) -SubscriptionId $Env:subscriptionId -SQLMIHA $env:SQLMIHA -DeployPostgreSQL $Env:deployPostgreSQL
    #>
    WriteHeader "Deploying Azure Arc-enabled SQL Managed Instance"
    ForceAzureClientsLogin
    $customLocationId = $(az customlocation show --name $CustomLocation --resource-group $ResourceGroup --query id -o tsv)
    $dataControllerId = $(az resource show --resource-group $ResourceGroup --name $ControllerName --resource-type "Microsoft.AzureArcData/dataControllers" --query id -o tsv)

    WriteHeader  "Localize ARM template"
    $ServiceType = "LoadBalancer"
    $readableSecondaries = $ServiceType

    # Resource Requests
    $vCoresRequest = "2"
    $memoryRequest = "4Gi"
    $vCoresLimit = "4"
    $memoryLimit = "8Gi"

    # Storage
    $StorageClassName = "managed-premium"
    $dataStorageSize = "5"
    $logsStorageSize = "5"
    $dataLogsStorageSize = "5"

    # If flag set, deploy SQL MI "General Purpose" tier
    if ( $SQLMIHA -eq $false ) {
        $replicas = 1 # Value can be only 1
        $pricingTier = "GeneralPurpose"
    }

    # If flag set, deploy SQL MI "Business Critical" tier
    if ( $SQLMIHA -eq $true ) {
        $replicas = 3 # Value can be either 2 or 3
        $pricingTier = "BusinessCritical"
    }

    ################################################
    $SQLParams = "$Folder\SQLMI.parameters.json"
    $AzdataPasswordPlainText = (New-Object PSCredential "user",$AzdataPassword).GetNetworkCredential().Password #ConvertFrom-SecureString -SecureString $AzdataPassword -AsPlainText, -AsPlainText does not work on PS 5.1
    (Get-Content -Path $SQLParams) -replace 'resourceGroup-stage', $ResourceGroup | Set-Content -Path $SQLParams
    (Get-Content -Path $SQLParams) -replace 'dataControllerId-stage', $dataControllerId | Set-Content -Path $SQLParams
    (Get-Content -Path $SQLParams) -replace 'customLocation-stage', $customLocationId | Set-Content -Path $SQLParams
    (Get-Content -Path $SQLParams) -replace 'subscriptionId-stage', $SubscriptionId | Set-Content -Path $SQLParams
    (Get-Content -Path $SQLParams) -replace 'azdataUsername-stage', $AzdataUsername | Set-Content -Path $SQLParams
    (Get-Content -Path $SQLParams) -replace 'azdataPassword-stage', $AzdataPasswordPlainText | Set-Content -Path $SQLParams
    (Get-Content -Path $SQLParams) -replace 'serviceType-stage', $ServiceType | Set-Content -Path $SQLParams
    (Get-Content -Path $SQLParams) -replace 'readableSecondaries-stage', $readableSecondaries | Set-Content -Path $SQLParams
    (Get-Content -Path $SQLParams) -replace 'vCoresRequest-stage', $vCoresRequest | Set-Content -Path $SQLParams
    (Get-Content -Path $SQLParams) -replace 'memoryRequest-stage', $memoryRequest | Set-Content -Path $SQLParams
    (Get-Content -Path $SQLParams) -replace 'vCoresLimit-stage', $vCoresLimit | Set-Content -Path $SQLParams
    (Get-Content -Path $SQLParams) -replace 'memoryLimit-stage', $memoryLimit | Set-Content -Path $SQLParams
    (Get-Content -Path $SQLParams) -replace 'dataStorageClassName-stage', $StorageClassName | Set-Content -Path $SQLParams
    (Get-Content -Path $SQLParams) -replace 'dataLogsStorageClassName-stage', $StorageClassName | Set-Content -Path $SQLParams
    (Get-Content -Path $SQLParams) -replace 'logsStorageClassName-stage', $StorageClassName | Set-Content -Path $SQLParams
    (Get-Content -Path $SQLParams) -replace 'dataSize-stage', $dataStorageSize | Set-Content -Path $SQLParams
    (Get-Content -Path $SQLParams) -replace 'logsSize-stage', $logsStorageSize | Set-Content -Path $SQLParams
    (Get-Content -Path $SQLParams) -replace 'dataLogseSize-stage', $dataLogsStorageSize | Set-Content -Path $SQLParams
    (Get-Content -Path $SQLParams) -replace 'replicasStage' , $replicas | Set-Content -Path $SQLParams
    (Get-Content -Path $SQLParams) -replace 'pricingTier-stage' , $pricingTier | Set-Content -Path $SQLParams

    az deployment group create --resource-group $ResourceGroup `
        --template-file "$Folder\SQLMI.json" `
        --parameters "$Folder\SQLMI.parameters.json"

    Write-Output "`n"
    Do {
        Write-Output "Waiting for SQL Managed Instance. Hold tight, this might take a few minutes...(45s sleeping loop)"
        Start-Sleep -Seconds 45
        $dcStatus = $(if (kubectl get sqlmanagedinstances -n arc | Select-String "Ready" -Quiet) { "Ready!" }Else { "Nope" })
    } while ($dcStatus -eq "Nope")

    WriteHeader  "Azure Arc-enabled SQL Managed Instance is ready!"

    # Update Service Port from 1433 to Non-Standard
    $payload = '{\"spec\":{\"ports\":[{\"name\":\"port-mssql-tds\",\"port\":11433,\"targetPort\":1433}]}}'
    kubectl patch svc jumpstart-sql-external-svc -n arc --type merge --patch $payload
    Start-Sleep -Seconds 5 # To allow the CRD to update

    if ( $SQLMIHA -eq $true ) {
        # Update Service Port from 1433 to Non-Standard
        $payload = '{\"spec\":{\"ports\":[{\"name\":\"port-mssql-tds\",\"port\":11433,\"targetPort\":1433}]}}'
        kubectl patch svc jumpstart-sql-secondary-external-svc -n arc --type merge --patch $payload
        Start-Sleep -Seconds 5 # To allow the CRD to update
    }

    # Downloading demo database and restoring onto SQL MI
    $podname = "jumpstart-sql-0"
    Write-Output "Downloading AdventureWorks database for MS SQL... (1/2)"
    kubectl exec $podname -n arc -c arc-sqlmi -- wget https://github.com/Microsoft/sql-server-samples/releases/download/adventureworks/AdventureWorks2019.bak -O /var/opt/mssql/data/AdventureWorks2019.bak 2>&1 | Out-Null
    Write-Output "Restoring AdventureWorks database for MS SQL. (2/2)"
    kubectl exec $podname -n arc -c arc-sqlmi -- /opt/mssql-tools/bin/sqlcmd -S localhost -U $AzdataUsername -P $AzdataPasswordPlainText -Q "RESTORE DATABASE AdventureWorks2019 FROM  DISK = N'/var/opt/mssql/data/AdventureWorks2019.bak' WITH MOVE 'AdventureWorks2017' TO '/var/opt/mssql/data/AdventureWorks2019.mdf', MOVE 'AdventureWorks2017_Log' TO '/var/opt/mssql/data/AdventureWorks2019_Log.ldf'" 2>&1 $null

    # Creating Azure Data Studio settings for SQL Managed Instance connection
    WriteHeader "Creating Azure Data Studio settings for SQL Managed Instance connection"
    $settingsTemplate = "$Folder\settingsTemplate.json"

    # Retrieving SQL MI connection endpoint
    $sqlstring = kubectl get sqlmanagedinstances jumpstart-sql -n arc -o=jsonpath='{.status.endpoints.primary}'

    # Replace placeholder values in settingsTemplate.json
    (Get-Content -Path $settingsTemplate) -replace 'arc_sql_mi', $sqlstring | Set-Content -Path $settingsTemplate
    (Get-Content -Path $settingsTemplate) -replace 'sa_username', $AzdataUsername | Set-Content -Path $settingsTemplate
    (Get-Content -Path $settingsTemplate) -replace 'sa_password', $AzdataPasswordPlainText | Set-Content -Path $settingsTemplate
    (Get-Content -Path $settingsTemplate) -replace 'false', 'true' | Set-Content -Path $settingsTemplate

    # Unzip SqlQueryStress
    Expand-Archive -Path $Folder\SqlQueryStress.zip -DestinationPath $folder\SqlQueryStress

    # Create SQLQueryStress desktop shortcut
    AddDesktopShortcut -Username $AdminUsername -ShortcutName "SqlQueryStress" -TargetPath "$Folder\SqlQueryStress\SqlQueryStress.exe"
  
    # Creating SQLMI Endpoints data
    CreateSQLMIEndpoints -Folder $Folder -AdminUsername $AdminUsername -AzdataUsername $AzdataUsername -AzdataPassword $AzdataPassword -SQLMIHA $SQLMIHA

    # If PostgreSQL isn't being deployed, clean up settings file
    if ( $DeployPostgreSQL -eq $false ) {
        $string = Get-Content $settingsTemplate
        $string[25] = $string[25] -replace ",", ""
        $string | Set-Content $settingsTemplate
        $string = Get-Content $settingsTemplate | Select-Object -First 25 -Last 4
        $string | Set-Content -Path $settingsTemplate
    }
}
function CreateSQLMIEndpoints {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Folder,
        [Parameter(Mandatory = $true)]
        [string]$AdminUsername,
        [Parameter(Mandatory = $true)]
        [string]$AzdataUsername,
        [Parameter(Mandatory = $true)]
        [Security.SecureString]$AzdataPassword,
        [string]$SQLMIHA
    )
    <#
        .SYNOPSIS
        Create Azure Arc SQLManagedInstance enpoints shortcut.

        .DESCRIPTION
        Create Azure Arc SQLManagedInstance enpoints shortcut.

        .PARAMETER Folder
        Folder where the template is located.

        .PARAMETER AdminUsername
        VM admin username.

        .PARAMETER AzdataUsername
        Az username needed for SQLManagedInstance configuration.

        .PARAMETER AzdataPassword
        Az password needed for SQLManagedInstance configuration.

        .PARAMETER SQLMIHA
        true if SQLMIHA was deployed

        .EXAMPLE
        >  CreateSQLMIEndpoints -Folder $Folder -AdminUsername $adminUsername -AzdataUsername $azdataUsername -AzdataPassword $AzdataPassword -SQLMIHA $SQLMIHA
    #>
    WriteHeader "Creating SQLMI Endpoints"

    New-Item -Path "$Folder" -Name "SQLMIEndpoints.txt" -ItemType "file" 
    $Endpoints = "$Folder\SQLMIEndpoints.txt"

    # Retrieving SQL MI connection endpoints
    Add-Content $Endpoints "Primary SQL Managed Instance external endpoint:"
    $primaryEndpoint = kubectl get sqlmanagedinstances jumpstart-sql -n arc -o=jsonpath='{.status.endpoints.primary}'
    $primaryEndpoint = $primaryEndpoint.Substring(0, $primaryEndpoint.IndexOf(',')) + ",11433" | Add-Content $Endpoints
    Add-Content $Endpoints ""

    if ( $SQLMIHA -eq $true ) {
        Add-Content $Endpoints "Secondary SQL Managed Instance external endpoint:"
        $secondaryEndpoint = kubectl get sqlmanagedinstances jumpstart-sql -n arc -o=jsonpath='{.status.endpoints.secondary}'
        $secondaryEndpoint = $secondaryEndpoint.Substring(0, $secondaryEndpoint.IndexOf(',')) + ",11433" | Add-Content $Endpoints
    }

    # Retrieving SQL MI connection username and password
    Add-Content $Endpoints ""
    Add-Content $Endpoints "SQL Managed Instance username:"
    $AzdataUsername | Add-Content $Endpoints

    $AzdataPasswordPlainText = (New-Object PSCredential "user",$AzdataPassword).GetNetworkCredential().Password #ConvertFrom-SecureString -SecureString $AzdataPassword -AsPlainText, -AsPlainText does not work on PS 5.1
    Add-Content $Endpoints ""
    Add-Content $Endpoints "SQL Managed Instance password:"
    $AzdataPasswordPlainText | Add-Content $Endpoints

    AddDesktopShortcut -Username $AdminUsername -TargetPath $Endpoints -ShortcutName "SQLMI Endpoints"
}


