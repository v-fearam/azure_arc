
function Get-Postgre-Files {
    param(
        [string] $templateBaseUrl
    )
    Get-File ($templateBaseUrl + "artifacts") @("postgreSQL.json", "postgreSQL.parameters.json", "DeployPostgreSQL.ps1") ($Env:tempDir)
}
