Start-Transcript -Path C:\Temp\SQLMIEndpointsLog.log

function CreateSQLMIEndpoints {
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingPlainTextForPassword", "")]
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingUsernameAndPasswordParams", "")]
    param (
        [string]$folder,
        [string]$adminUsername,
        [string]$azdataUsername,
        [string]$azdataPassword,
        [string]$SQLMIHA
    )
    Write-Header "Creating SQLMI Endpoints"

    New-Item -Path "$folder" -Name "SQLMIEndpoints.txt" -ItemType "file" 
    $Endpoints = "$folder\SQLMIEndpoints.txt"

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
    $azdataUsername | Add-Content $Endpoints

    Add-Content $Endpoints ""
    Add-Content $Endpoints "SQL Managed Instance password:"
    $azdataPassword | Add-Content $Endpoints

    AddDesktopShortcut -username $adminUsername -targetPath $Endpoints -shortcutName "SQLMI Endpoints"
}
