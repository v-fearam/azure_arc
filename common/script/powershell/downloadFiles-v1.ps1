#requires -version 2

<#
.SYNOPSIS
  Download a set of files from a web location to your to the computer
.PARAMETER <Parameter_Name>
    $origin url to the web location
    $filenames array of names to download
    $target a directory on your machine
.OUTPUTS
  The files are downloded to $target with the same name
.NOTES
  Version:        1.0
  Author:         Arambarri Federico
  Creation Date:  18/05/20222
  Purpose/Change: Initial script development
  
.EXAMPLE
  Download-Files ($templateBaseUrl + "../tests/")  @("GHActionDeploy.ps1", "OpenSSHDeploy.ps1") $Env:ArcBoxDir
#>
function Download-Files {
  param(
    [string] $origin ,
    [string[]] $filenames ,
    [string] $target
  )
  foreach ($filename in $filenames) {
    Invoke-WebRequest ("$origin/$filename") -OutFile "$target\$filename"
  }
}

<#
.SYNOPSIS
  Download a file and save it with another name
.PARAMETER <Parameter_Name>
    $originFile url to the web location of the file
    $targetFile full path, including the new name for the file
.OUTPUTS
  The file are downloded to $targetFile 
.NOTES
  Version:        1.0
  Author:         Arambarri Federico
  Creation Date:  18/05/20222
  Purpose/Change: Initial script development
  
.EXAMPLE
  Download-File-Renaming ($templateBaseUrl + "../img/arcbox_wallpaper.png") $Env:ArcBoxDir\wallpaper.png
#>
function Download-File-Renaming {
  param(
    [string] $originFile ,
    [string] $targetFile
  )
  Invoke-WebRequest $originFile -OutFile "$targetFile"
}