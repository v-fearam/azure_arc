#requires -version 2

<#
.SYNOPSIS
  Create desktop icon
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
  Creating-Desktop-Shortcut -shortcutName "CAPI Bookstore" -iconLocation "bookstore" -targetPath "powershell.exe" -arguments "-ExecutionPolicy Bypass -File $Env:ArcBoxDir\BookStoreLaunch.ps1" -windowsStyle 7
#>
function Creating-Desktop-Shortcut {
  param(
    [string] $icon,
    [string] $shortcutName,
    [string] $targetPath,
    [string] $arguments,
    [string] $windowsStyle = 3,
    [string] $username
  )
  #If WindowStyle is 1, then the application window will be set to its default location and size. If this property has a value of 3, the application will be launched in a maximized window, and if it has a value of 7, it will be launched in a minimized window.
  Write-Output "Creating $shortcutName Icon on Desktop"
  if ( -not $username){
    $shortcutLocation = "$Env:Public\Desktop\$shortcutName.lnk"
  }else{
    $shortcutLocation = "C:\Users\$username\Desktop\$shortcutName.lnk"
  }  
  $wScriptShell = New-Object -ComObject WScript.Shell
  $shortcut = $wScriptShell.CreateShortcut($shortcutLocation)
  $shortcut.TargetPath = $targetPath
  if ($arguments){
    $shortcut.Arguments = $arguments
  } 
  if ($icon){
    $shortcut.IconLocation = "${Env:ArcBoxIconDir}\$icon.ico, 0"
  }  
  $shortcut.WindowStyle = $windowsStyle
  $shortcut.Save()
}
