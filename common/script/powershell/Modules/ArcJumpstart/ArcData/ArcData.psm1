function RegisterAzureArcProviders {
    param (
        [Parameter(Mandatory = $true)]
        [string[]] $ArcProviderList
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
    Write-Output "Registering Azure Arc providers, hold tight..."
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