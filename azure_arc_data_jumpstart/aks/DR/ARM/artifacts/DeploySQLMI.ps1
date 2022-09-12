Start-Transcript -Path C:\Temp\DeploySQLMI.log

function deploySqlMI {
    param (
        [string]$customLocationName,
        [string]$resourceGroup,
        [string]$dataControllerName,
        [string]$sqlMIInstance,
        [string]$folder,
        [string]$workspaceName,
        [string]$AZDATA_USERNAME,
        [string]$AZDATA_PASSWORD,
        [string]$subscriptionId
    )
    $customLocationId = $(az customlocation show --name $customLocationName --resource-group $resourceGroup --query id -o tsv)
    $dataControllerId = $(az resource show --resource-group $env:resourceGroup --name dataControllerName --resource-type "Microsoft.AzureArcData/dataControllers" --query id -o tsv)

    ################################################
    # Localize ARM template
    ################################################
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
    if ( $env:SQLMIHA -eq $false ) {
        $replicas = 1 # Value can be only 1
        $pricingTier = "GeneralPurpose"
    }

    # If flag set, deploy SQL MI "Business Critical" tier
    if ( $env:SQLMIHA -eq $true ) {
        $replicas = 3 # Value can be either 2 or 3
        $pricingTier = "BusinessCritical"
    }
    
    ################################################

    ## Deploying primary SQL MI
    $SQLParams = "$folder\SQLMI.parameters.json"

(Get-Content -Path $SQLParams) -replace 'resourceGroup-stage', $resourceGroup | Set-Content -Path $SQLParams
(Get-Content -Path $SQLParams) -replace 'dataControllerId-stage', $dataControllerId | Set-Content -Path $SQLParams
(Get-Content -Path $SQLParams) -replace 'customLocation-stage', $customLocationId | Set-Content -Path $SQLParams
(Get-Content -Path $SQLParams) -replace 'subscriptionId-stage', $subscriptionId | Set-Content -Path $SQLParams
(Get-Content -Path $SQLParams) -replace 'azdataUsername-stage', $AZDATA_USERNAME | Set-Content -Path $SQLParams
(Get-Content -Path $SQLParams) -replace 'azdataPassword-stage', $AZDATA_PASSWORD | Set-Content -Path $SQLParams
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
(Get-Content -Path $SQLParams) -replace 'licenceType-stage' , "LicenseIncluded" | Set-Content -Path $SQLParams
(Get-Content -Path $SQLParams) -replace 'sqlMIName-stage' , $sqlMIInstance | Set-Content -Path $SQLParams


    az deployment group create --resource-group $resourceGroup `
        --template-file "$folder\SQLMI.json" `
        --parameters "$folder\SQLMI.parameters.json"

    Do {
        Write-Output "Waiting for SQL Managed Instance. Hold tight, this might take a few minutes...(45s sleeping loop)"
        Start-Sleep -Seconds 45
        $dcStatus = $(if (kubectl get sqlmanagedinstances -n arc | Select-String "Ready" -Quiet) { "Ready!" }Else { "Nope" })
    } while ($dcStatus -eq "Nope")

    Write-Header "Primary Azure Arc SQL Managed Instance is ready!"
    
    # Update Service Port from 1433 to Non-Standard on secondary cluster
    $payload = '{\"spec\":{\"ports\":[{\"name\":\"port-mssql-tds\",\"port\":11433,\"targetPort\":1433},{\"name\":\"port-mssql-mirroring\",\"port\":5022,\"targetPort\":5022}]}}'
    kubectl patch svc js-sql-dr-external-svc -n arc --type merge --patch $payload
    Start-Sleep -Seconds 5 # To allow the CRD to update

    if ( $env:SQLMIHA -eq $true ) {
        # Update Service Port from 1433 to Non-Standard
        $payload = '{\"spec\":{\"ports\":[{\"name\":\"port-mssql-tds\",\"port\":11433,\"targetPort\":1433},{\"name\":\"port-mssql-mirroring\",\"port\":5022,\"targetPort\":5022}]}}'
        kubectl patch svc js-sql-dr-external-svc -n arc --type merge --patch $payload
        Start-Sleep -Seconds 5 # To allow the CRD to update
    }

    
    
    # Creating Azure Data Studio settings for SQL Managed Instance connection
    Write-Header "Creating Azure Data Studio settings for SQL Managed Instance connection"
    $settingsTemplate = "$Env:TempDir\settingsTemplate.json"

    # Retrieving SQL MI connection endpoint
    $sqlstring = kubectl get sqlmanagedinstances $sqlMIInstance -n arc -o=jsonpath='{.status.endpoints.primary}'

    # Replace placeholder values in settingsTemplate.json
(Get-Content -Path $settingsTemplate) -replace 'arc_sql_mi_primary', $sqlstring | Set-Content -Path $settingsTemplate
(Get-Content -Path $settingsTemplate) -replace 'sa_username', $env:AZDATA_USERNAME | Set-Content -Path $settingsTemplate
(Get-Content -Path $settingsTemplate) -replace 'sa_password', $env:AZDATA_PASSWORD | Set-Content -Path $settingsTemplate
(Get-Content -Path $settingsTemplate) -replace 'false', 'true' | Set-Content -Path $settingsTemplate

}

# Deployment environment variables
$primaryControllerName = "jumpstart-primary-dc"
$secondaryControllerName = "jumpstart-secondary-dc"
$primarySqlMIInstance = "js-sql-pr"
$secondarySqlMIInstance = "js-sql-dr"

# Deploying Azure Arc SQL Managed Instance
Write-Header "Deploying Azure Arc SQL Managed Instance"

kubectx primary
Copy-Item "$Env:TempDir\SQLMI.parameters.json" -Destination "$Env:TempDir\SQLMI.parameters.json.backup"
Copy-Item "$Env:TempDir\settingsTemplate.json" -Destination "$Env:TempDir\settingsTemplate.json.backup"
deploySqlMI -customLocationName "jumpstart-primary-cl" -resourceGroup $env:resourceGroup -dataControllerName $primaryControllerName -sqlMIInstance $primarySqlMIInstance -folder $Env:TempDir -subscriptionId $env:subscriptionId -AZDATA_USERNAME $env:AZDATA_USERNAME -AZDATA_PASSWORD  $env:AZDATA_PASSWORD

# Downloading demo database and restoring onto SQL MI
$podname = "js-sql-pr-0"
Write-Host "`n"
Write-Host "Downloading AdventureWorks database for MS SQL... (1/2)"
kubectl exec $podname -n arc -c arc-sqlmi -- wget https://github.com/Microsoft/sql-server-samples/releases/download/adventureworks/AdventureWorks2019.bak -O /var/opt/mssql/data/AdventureWorks2019.bak 2>&1 | Out-Null
Write-Host "Restoring AdventureWorks database for MS SQL. (2/2)"
kubectl exec $podname -n arc -c arc-sqlmi -- /opt/mssql-tools/bin/sqlcmd -S localhost -U $Env:AZDATA_USERNAME -P $Env:AZDATA_PASSWORD -Q "RESTORE DATABASE AdventureWorks2019 FROM  DISK = N'/var/opt/mssql/data/AdventureWorks2019.bak' WITH MOVE 'AdventureWorks2017' TO '/var/opt/mssql/data/AdventureWorks2019.mdf', MOVE 'AdventureWorks2017_Log' TO '/var/opt/mssql/data/AdventureWorks2019_Log.ldf'" 2>&1 $null

## Deploying Secondary SQL MI
kubectx secondary
Copy-Item "$Env:TempDir\SQLMI.parameters.json.backup" -Destination "$Env:TempDir\SQLMI.parameters.json"
Copy-Item "$Env:TempDir\settingsTemplate.json.backup" -Destination "$Env:TempDir\settingsTemplate.json"
deploySqlMI -customLocationName "jumpstart-secondary-cl" -resourceGroup $env:resourceGroup -dataControllerName $secondaryControllerName -sqlMIInstance $secondarySqlMIInstance -folder $Env:TempDir -subscriptionId $env:subscriptionId -AZDATA_USERNAME $env:AZDATA_USERNAME -AZDATA_PASSWORD  $env:AZDATA_PASSWORD

# Creating SQLMI Endpoints data
& "$Env:TempDir\SQLMIEndpoints.ps1"

# Creating distributed DAG
Write-Host "Configuring the primary cluster DAG"
New-Item -Path "$Env:TempDir/sqlcerts" -ItemType Directory
Write-Host "`n"
kubectx primary
$primaryMirroringEndpoint = $(az sql mi-arc show -n $primarySqlMIInstance --k8s-namespace arc --use-k8s -o tsv --query 'status.endpoints.mirroring')
az sql mi-arc get-mirroring-cert --name $primarySqlMIInstance --cert-file "$Env:TempDir/sqlcerts/sqlprimary.pem" --k8s-namespace arc --use-k8s
Write-Host "`n"

Write-Host "Configuring the secondary cluster DAG"
Write-Host "`n"
kubectx secondary
$secondaryMirroringEndpoint = $(az sql mi-arc show -n $secondarySqlMIInstance --k8s-namespace arc --use-k8s -o tsv --query 'status.endpoints.mirroring')
az sql mi-arc get-mirroring-cert --name $secondarySqlMIInstance --cert-file "$Env:TempDir/sqlcerts/sqlsecondary.pem" --k8s-namespace arc --use-k8s
Write-Host "`n"

Write-Host "`n"
kubectx primary
az sql instance-failover-group-arc create --shared-name jumpstartDag --name primarycr --mi $primarySqlMIInstance --role primary --partner-mi $secondarySqlMIInstance  --partner-mirroring-url "tcp://$secondaryMirroringEndpoint" --partner-mirroring-cert-file "$Env:TempDir/sqlcerts/sqlsecondary.pem" --k8s-namespace arc --use-k8s
Write-Host "`n"
kubectx secondary
az sql instance-failover-group-arc create --shared-name jumpstartDag --name secondarycr --mi $secondarySqlMIInstance --role secondary --partner-mi $primarySqlMIInstance  --partner-mirroring-url "tcp://$primaryMirroringEndpoint" --partner-mirroring-cert-file "$Env:TempDir/sqlcerts/sqlprimary.pem" --k8s-namespace arc --use-k8s
