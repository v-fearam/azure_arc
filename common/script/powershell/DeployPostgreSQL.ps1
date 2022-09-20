function DeployAzureArcPostgreSQL {
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingPlainTextForPassword", "")]
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingUsernameAndPasswordParams", "")]
    param (
        [string]
        # Resource group where the resource are being created
        $resourceGroup,
        [string]
        # Folder where the config files are present
        $folder,
        [string]
        # Az password needed for PostgreSQL configuration
        $azdataPassword,
        [string]
        # Azure subscription id needed for PostgreSQL configuration
        $subscriptionId,
        [string]
        # true if SQLMI was deployed
        $deploySQLMI,
        [string]
        # Data controller name
        $controllerName = "jumpstart-dc",
        [string]
        # Custom location name
        $customLocation = "jumpstart-cl"
    )
    <#
        .DESCRIPTION
        Deploy  Azure Arc-enabled PostgreSQL  
        
        .OUTPUTS
        Azure Arc-enabled PostgreSQL on the k8s cluster

        .EXAMPLE
        > DeployAzureArcPostgreSQL  -resourceGroup $Env:resourceGroup -folder $Env:TempDir -azdataPassword $env:AZDATA_PASSWORD -subscriptionId $Env:subscriptionId -deploySQLMI $env:deploySQLMI
    #>
    Write-Header "Deploying Azure Arc-enabled PostgreSQL"
   
    $customLocationId = $(az customlocation show --name $customLocation --resource-group $resourceGroup --query id -o tsv)
    $dataControllerId = $(az resource show --resource-group $resourceGroup --name $controllerName --resource-type "Microsoft.AzureArcData/dataControllers" --query id -o tsv)

    Write-Header  Localize ARM template
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

    $PSQLParams = "$folder\postgreSQL.parameters.json"

(Get-Content -Path $PSQLParams) -replace 'resourceGroup-stage', $resourceGroup | Set-Content -Path $PSQLParams
(Get-Content -Path $PSQLParams) -replace 'dataControllerId-stage', $dataControllerId | Set-Content -Path $PSQLParams
(Get-Content -Path $PSQLParams) -replace 'customLocation-stage', $customLocationId | Set-Content -Path $PSQLParams
(Get-Content -Path $PSQLParams) -replace 'subscriptionId-stage', $subscriptionId | Set-Content -Path $PSQLParams
(Get-Content -Path $PSQLParams) -replace 'azdataPassword-stage', $azdataPassword | Set-Content -Path $PSQLParams
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

    az deployment group create --resource-group $resourceGroup `
        --template-file "$folder\postgreSQL.json" `
        --parameters "$folder\postgreSQL.parameters.json"

    # Ensures postgres container is initiated and ready to accept restores
    $pgWorkerPodName = "jumpstartps-0"

    Do {
        Write-Output "Waiting for PostgreSQL. Hold tight, this might take a few minutes...(45s sleeping loop)"
        Start-Sleep -Seconds 45
        $buildService = $(if((kubectl get pods -n arc | Select-String $pgWorkerPodName| Select-String "Running" -Quiet)){"Ready!"}Else{"Nope"})
    } while ($buildService -eq "Nope")

    Write-Header "Azure Arc-enabled PostgreSQL is ready!"
    Start-Sleep -Seconds 60

    # Downloading demo database and restoring onto Postgres
    Write-Header "Downloading AdventureWorks.sql template for Postgres... (1/3)"
    kubectl exec $pgWorkerPodName  -n arc -c postgres -- /bin/bash -c "curl -o /tmp/AdventureWorks2019.sql 'https://jumpstart.blob.core.windows.net/jumpstartbaks/AdventureWorks2019.sql?sp=r&st=2021-09-08T21:04:16Z&se=2030-09-09T05:04:16Z&spr=https&sv=2020-08-04&sr=b&sig=MJHGMyjV5Dh5gqyvfuWRSsCb4IMNfjnkM%2B05F%2F3mBm8%3D'" 2>&1 | Out-Null
    Write-Header "Creating AdventureWorks database on Postgres... (2/3)"
    kubectl exec $pgWorkerPodName  -n arc -c postgres -- psql -U postgres -c 'CREATE DATABASE "adventureworks2019";' postgres 2>&1 | Out-Null
    Write-Header "Restoring AdventureWorks database on Postgres. (3/3)"
    kubectl exec $pgWorkerPodName  -n arc -c postgres -- psql -U postgres -d adventureworks2019 -f /tmp/AdventureWorks2019.sql 2>&1 | Out-Null

    # Creating Azure Data Studio settings for PostgreSQL connection
    Write-Header "Creating Azure Data Studio settings for PostgreSQL connection"
    $settingsTemplate = "$folder\settingsTemplate.json"

    # Retrieving PostgreSQL connection endpoint
    $pgsqlstring = kubectl get postgresql jumpstartps -n arc -o=jsonpath='{.status.primaryEndpoint}'

    # Replace placeholder values in settingsTemplate.json
(Get-Content -Path $settingsTemplate) -replace 'arc_postgres_host', $pgsqlstring.split(":")[0] | Set-Content -Path $settingsTemplate
(Get-Content -Path $settingsTemplate) -replace 'arc_postgres_port', $pgsqlstring.split(":")[1] | Set-Content -Path $settingsTemplate
(Get-Content -Path $settingsTemplate) -replace 'ps_password', $azdataPassword | Set-Content -Path $settingsTemplate


    # If SQL MI isn't being deployed, clean up settings file
    if ( $deploySQLMI -eq $false ) {
        $string = Get-Content -Path $settingsTemplate | Select-Object -First 9 -Last 24
        $string | Set-Content -Path $settingsTemplate
    }
}

