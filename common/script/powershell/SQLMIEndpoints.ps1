Start-Transcript -Path C:\Temp\SQLMIEndpointsLog.log

function CreateSQLMIEndpoints {
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingPlainTextForPassword", "")]
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingUsernameAndPasswordParams", "")]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Folder,
        [Parameter(Mandatory = $true)]
        [string]$AdminUsername,
        [Parameter(Mandatory = $true)]
        [string]$AzdataUsername,
        [Parameter(Mandatory = $true)]
        [string]$AzdataPassword,
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
    Write-Header "Creating SQLMI Endpoints"

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

    Add-Content $Endpoints ""
    Add-Content $Endpoints "SQL Managed Instance password:"
    $AzdataPassword | Add-Content $Endpoints

    AddDesktopShortcut -Username $AdminUsername -TargetPath $Endpoints -ShortcutName "SQLMI Endpoints"
}
