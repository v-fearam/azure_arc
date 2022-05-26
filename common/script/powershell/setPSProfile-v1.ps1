#requires -version 2

<#
.SYNOPSIS
  Set a specific script as PowerShell profile
.PARAMETER <Parameter_Name>
    $originScript url to the web location of the script which i going to be set as PowerShell profile
.OUTPUTS
  The file is set as Profile, so any PS execution will be able to use the function defined there
.NOTES
  Version:        1.0
  Author:         Arambarri Federico
  Creation Date:  18/05/20222
  Purpose/Change: Initial script development
  
.EXAMPLE
  Set-PowerShell-Profile  ($templateBaseUrl+"artifacts\PSProfile.ps1")
#>
function Set-PowerShell-Profile {
  param(
    [string] $originScript
  )
  Invoke-WebRequest ("$originScript") -OutFile $PsHome\Profile.ps1
  .$PsHome\Profile.ps1
}