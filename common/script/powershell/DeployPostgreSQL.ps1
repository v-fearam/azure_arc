function DeployAzureArcPostgreSQL {
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingPlainTextForPassword", "")]
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingUsernameAndPasswordParams", "")]
    param (
        [Parameter(Mandatory = $true)]
        [string]$ResourceGroup,
        [Parameter(Mandatory = $true)]
        [string]$Folder,
        [Parameter(Mandatory = $true)]
        [string]$AzdataPassword,
        [Parameter(Mandatory = $true)]
        [string]$SubscriptionId,
        [string]$DeploySQLMI,
        [string]$ControllerName = "jumpstart-dc",
        [string]$CustomLocation = "jumpstart-cl"
    )
    
    <#
        .SYNOPSIS
        Deploy Azure Arc PostgreSQL.  

        .DESCRIPTION
        Deploy Azure Arc PostgreSQL.  

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
        > DeployAzureArcPostgreSQL -ResourceGroup $Env:resourceGroup -Folder $Env:TempDir -AzdataPassword $env:AZDATA_PASSWORD -SubscriptionId $Env:subscriptionId -DeploySQLMI $env:deploySQLMI
    #>
    Write-Header "Deploying Azure Arc PostgreSQL"
   
    $customLocationId = $(az customlocation show --name $CustomLocation --resource-group $ResourceGroup --query id -o tsv)
    $dataControllerId = $(az resource show --resource-group $ResourceGroup --name $ControllerName --resource-type "Microsoft.AzureArcData/dataControllers" --query id -o tsv)

    Write-Header  "Localize ARM template"
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

(Get-Content -Path $PSQLParams) -replace 'resourceGroup-stage', $ResourceGroup | Set-Content -Path $PSQLParams
(Get-Content -Path $PSQLParams) -replace 'dataControllerId-stage', $dataControllerId | Set-Content -Path $PSQLParams
(Get-Content -Path $PSQLParams) -replace 'customLocation-stage', $customLocationId | Set-Content -Path $PSQLParams
(Get-Content -Path $PSQLParams) -replace 'subscriptionId-stage', $SubscriptionId | Set-Content -Path $PSQLParams
(Get-Content -Path $PSQLParams) -replace 'azdataPassword-stage', $AzdataPassword | Set-Content -Path $PSQLParams
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
    $pgControllerPodName = "jumpstartps-0"
  
    Do {
        Write-Output "Waiting for PostgreSQL. Hold tight, this might take a few minutes...(45s sleeping loop)"
        Start-Sleep -Seconds 45
        $buildService = $(if (kubectl get pods -n arc | Select-String $pgControllerPodName | Select-String "Running" -Quiet) { "Ready!" }Else { "Nope" })
    } while ($buildService -eq "Nope")

    Write-Header "Azure Arc-enabled PostgreSQL is ready!"
    Start-Sleep -Seconds 60

  # Update Service Port from 5432 to Non-Standard
  #  $payload = '{\"spec\":{\"ports\":[{\"name\":\"port-pgsql\",\"port\":15432,\"targetPort\":5432}]}}'
  #  kubectl patch svc jumpstartps-external-svc -n arc --type merge --patch $payload
  #  Start-Sleep -Seconds 60

    # Downloading demo database and restoring onto Postgres
    Write-Header "Downloading AdventureWorks.sql template for Postgres... (1/3)"
    kubectl exec $pgControllerPodName -n arc -c postgres -- /bin/bash -c "curl -o /tmp/AdventureWorks2019.sql 'https://jumpstart.blob.core.windows.net/jumpstartbaks/AdventureWorks2019.sql?sp=r&st=2021-09-08T21:04:16Z&se=2030-09-09T05:04:16Z&spr=https&sv=2020-08-04&sr=b&sig=MJHGMyjV5Dh5gqyvfuWRSsCb4IMNfjnkM%2B05F%2F3mBm8%3D'" 2>&1 | Out-Null
    Write-Header "Creating AdventureWorks database on Postgres... (2/3)"
    kubectl exec $pgControllerPodName -n arc -c postgres -- psql -U postgres -c 'CREATE DATABASE "adventureworks2019";' postgres 2>&1 | Out-Null
    Write-Header "Restoring AdventureWorks database on Postgres. (3/3)"
    kubectl exec $pgControllerPodName -n arc -c postgres -- psql -U postgres -d adventureworks2019 -f /tmp/AdventureWorks2019.sql 2>&1 | Out-Null

    # Creating Azure Data Studio settings for PostgreSQL connection
    Write-Header "Creating Azure Data Studio settings for PostgreSQL connection"
    $settingsTemplate = "$Folder\settingsTemplate.json"

    # Retrieving PostgreSQL connection endpoint
    $pgsqlstring = kubectl get postgresql jumpstartps -n arc -o=jsonpath='{.status.primaryEndpoint}'
    Write-Output "connection string: $pgsqlstring"
    # Replace placeholder values in settingsTemplate.json
    (Get-Content -Path $settingsTemplate) -replace 'arc_postgres_host', $pgsqlstring.split(":")[0] | Set-Content -Path $settingsTemplate
    (Get-Content -Path $settingsTemplate) -replace 'arc_postgres_port', $pgsqlstring.split(":")[1] | Set-Content -Path $settingsTemplate
    (Get-Content -Path $settingsTemplate) -replace 'ps_password', $AzdataPassword | Set-Content -Path $settingsTemplate


    # If SQL MI isn't being deployed, clean up settings file
    if ( $DeploySQLMI -eq $false ) {
        $string = Get-Content -Path $settingsTemplate | Select-Object -First 9 -Last 24
        $string | Set-Content -Path $settingsTemplate
    }
}

