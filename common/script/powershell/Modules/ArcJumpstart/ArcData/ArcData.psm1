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