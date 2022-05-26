#requires -version 2

<#
.SYNOPSIS
  Download a set of scripts to the VM. A Local script with the same name than the global script replace the global one, you will use the local version.
.PARAMETER <Parameter_Name>
   $origin url to the repo
   $target directory destination
   $localPS array of powershell script name to be dowloaded from the local location
   $globalPS array of powershell script name to be dowloaded from the global location
   $localSH array of bash script name to be dowloaded from the local location
   $globalSH array of bash script name to be dowloaded from the global location
.OUTPUTS
  The modules instaled
.NOTES
  Version:        1.0
  Author:         Arambarri Federico
  Creation Date:  19/5/2022
  Purpose/Change: Initial script development
  
.EXAMPLE
  Download-Scripts-Dependencies $templateBaseUrl $Env:ArcBoxDir @() @("installModules-v1","installChocoApps-v1") @() @()
#>

function Download-Scripts-Dependencies {
  param(
    [string] $origin,
    [string] $target,
    [string[]]$localPS = @(),
    [string[]]$globalPS = @(),
    [string[]]$localSH = @(),
    [string[]]$globalSH = @()
  )
  New-Item -ItemType Directory -Force -Path "$target\common\script\powershell\"
  New-Item -ItemType Directory -Force -Path "$target\common\script\bash\"
  foreach ($script in $globalPS) {
    Invoke-WebRequest ("$origin"+"../common/script/powershell/$script.ps1") -OutFile "$target\common\script\powershell\$script.ps1"
  }
  foreach ($script in $localPS) {
    Invoke-WebRequest ("$origin"+"common/script/powershell/$script.ps1") -OutFile "$target\common\script\powershell\$script.ps1"
  }
  foreach ($script in $globalSH) {
    Invoke-WebRequest ("$origin"+"../common/script/bash/$script.sh") -OutFile "$target\common\script\bash\$script.sh"
  }
  foreach ($script in $localSH) {
    Invoke-WebRequest ("$origin"+"common/script/bash/$script.sh") -OutFile "$target\common\script\bash\$script.sh"
  }
}