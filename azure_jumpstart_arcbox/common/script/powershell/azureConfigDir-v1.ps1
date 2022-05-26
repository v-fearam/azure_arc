#requires -version 2

<#
.SYNOPSIS
  Create Azure Config Directory and set it as hidden
.PARAMETER <Parameter_Name>
    $path where the directory is going to be created
    $name directory name
.OUTPUTS
  $Env:AZURE_CONFIG_DIR is set to allow the script work
.NOTES
  Version:        1.0
  Author:         Arambarri Federico
  Creation Date:  23/05/20222
  Purpose/Change: Initial script development
  
.EXAMPLE
  Azure-Config-Directory $Env:ArcBoxDir  ".devops"
#>
function Azure-Config-Directory {
  param(
    [string] $path,
    [string] $name
  )
  $cliDir = New-Item -Path "$path\.cli\" -Name $name -ItemType Directory

  if (-not $($cliDir.Parent.Attributes.HasFlag([System.IO.FileAttributes]::Hidden))) {
    $folder = Get-Item $cliDir.Parent.FullName -ErrorAction SilentlyContinue
    $folder.Attributes += [System.IO.FileAttributes]::Hidden
  }

  $Env:AZURE_CONFIG_DIR = $cliDir.FullName
}
