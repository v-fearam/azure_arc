function WriteHeader {
    param (
        [Parameter(Mandatory = $true)]
        [string] $Title
    )
    <#
        .SYNOPSIS
        Write the title passed as a parameter as a formatted header to the standard output.
        
        .DESCRIPTION
        Write the title passed as a parameter as a formatted header to the standard output. Use this function to separate sections of log entries during execution.

        .PARAMETER Title
        Text to write.

        .EXAMPLE
        > WriteHeader "Az CLI Login"

        ####################
        # - Az CLI Login
        ####################
    #>
    Write-Host
    Write-Host ("#" * ($Title.Length + 8))
    Write-Host "# - $Title"
    Write-Host ("#" * ($Title.Length + 8))
    Write-Host
}