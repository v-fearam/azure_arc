Write-Output "ITPro-Full profile script"

Write-Output "Fetching Artifacts for ITPro Flavor"
Download-Files ($templateBaseUrl + "artifacts")  @("ArcServersLogonScript.ps1", "ArcSQLManualOnboarding.ps1") $Env:ArcBoxDir
Download-Files ($templateBaseUrl + "artifacts")  @("installArcAgent.ps1", "installArcAgentSQLSP.ps1", "installArcAgentUbuntu.sh", "installArcAgentCentOS.sh", "installArcAgentSQLUser.ps1") "$Env:ArcBoxDir\agentScript"
Download-Files ($templateBaseUrl + "artifacts/icons")  @("arcsql.ico") $Env:ArcBoxDir

Write-Output "Creating scheduled task for ArcServersLogonScript.ps1"
Configuring-Logon-Scripts $Env:adminUsername "ArcServersLogonScript" ("$Env:ArcBoxDir\ArcServersLogonScript.ps1")