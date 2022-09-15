function DeployAzureArcSQLManagedInstance {
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingPlainTextForPassword", "")]
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingUsernameAndPasswordParams", "")]
    param (
        [Parameter(Mandatory = $true)]
        [string]$ResourceGroup,
        [Parameter(Mandatory = $true)]
        [string]$Folder,
        [Parameter(Mandatory = $true)]
        [string]$AdminUsername,
        [Parameter(Mandatory = $true)]
        [string]$AzdataUsername,
        [string]$AzdataPassword,
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
        >  DeployAzureArcSQLManagedInstance -ResourceGroup $Env:resourceGroup -Folder $Env:TempDir -AdminUsername $Env:adminUsername -AzdataUsername $Env:AZDATA_USERNAME -AzdataPassword $env:AZDATA_PASSWORD -SubscriptionId $Env:subscriptionId -SQLMIHA $env:SQLMIHA -DeployPostgreSQL $Env:deployPostgreSQL
    #>
    WriteHeader "Deploying Azure Arc-enabled SQL Managed Instance"

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

    (Get-Content -Path $SQLParams) -replace 'resourceGroup-stage', $ResourceGroup | Set-Content -Path $SQLParams
    (Get-Content -Path $SQLParams) -replace 'dataControllerId-stage', $dataControllerId | Set-Content -Path $SQLParams
    (Get-Content -Path $SQLParams) -replace 'customLocation-stage', $customLocationId | Set-Content -Path $SQLParams
    (Get-Content -Path $SQLParams) -replace 'subscriptionId-stage', $SubscriptionId | Set-Content -Path $SQLParams
    (Get-Content -Path $SQLParams) -replace 'azdataUsername-stage', $AzdataUsername | Set-Content -Path $SQLParams
    (Get-Content -Path $SQLParams) -replace 'azdataPassword-stage', $AzdataPassword | Set-Content -Path $SQLParams
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
    kubectl exec $podname -n arc -c arc-sqlmi -- /opt/mssql-tools/bin/sqlcmd -S localhost -U $AzdataUsername -P $AzdataPassword -Q "RESTORE DATABASE AdventureWorks2019 FROM  DISK = N'/var/opt/mssql/data/AdventureWorks2019.bak' WITH MOVE 'AdventureWorks2017' TO '/var/opt/mssql/data/AdventureWorks2019.mdf', MOVE 'AdventureWorks2017_Log' TO '/var/opt/mssql/data/AdventureWorks2019_Log.ldf'" 2>&1 $null

    # Creating Azure Data Studio settings for SQL Managed Instance connection
    WriteHeader "Creating Azure Data Studio settings for SQL Managed Instance connection"
    $settingsTemplate = "$Folder\settingsTemplate.json"

    # Retrieving SQL MI connection endpoint
    $sqlstring = kubectl get sqlmanagedinstances jumpstart-sql -n arc -o=jsonpath='{.status.endpoints.primary}'

    # Replace placeholder values in settingsTemplate.json
    (Get-Content -Path $settingsTemplate) -replace 'arc_sql_mi', $sqlstring | Set-Content -Path $settingsTemplate
    (Get-Content -Path $settingsTemplate) -replace 'sa_username', $AzdataUsername | Set-Content -Path $settingsTemplate
    (Get-Content -Path $settingsTemplate) -replace 'sa_password', $AzdataPassword | Set-Content -Path $settingsTemplate
    (Get-Content -Path $settingsTemplate) -replace 'false', 'true' | Set-Content -Path $settingsTemplate

    # Unzip SqlQueryStress
    Expand-Archive -Path $Folder\SqlQueryStress.zip -DestinationPath $folder\SqlQueryStress

    # Create SQLQueryStress desktop shortcut
    AddDesktopShortcut -Username $AdminUsername -ShortcutName "SqlQueryStress" -TargetPath "$Folder\SqlQueryStress\SqlQueryStress.exe"
  
    # Creating SQLMI Endpoints data
    . "$Folder\SQLMIEndpoints.ps1"
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