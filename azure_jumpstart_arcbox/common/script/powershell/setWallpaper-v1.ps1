#requires -version 2

<#
.SYNOPSIS
  Setting wallpaper
.PARAMETER <Parameter_Name>
.OUTPUTS
  The wallpaper is set
.NOTES
  Version:        1.0
  Author:         Arambarri Federico
  Creation Date:  30/05/20222
  Purpose/Change: Initial script development
  
.EXAMPLE
  Set-WallPapper "ArcServersLogonScript.ps1"
#>

function Set-WallPapper {
    param(
        [string] $scriptToCheck
    )
    # Changing to Jumpstart ArcBox wallpaper
    $code = @' 
using System.Runtime.InteropServices; 
namespace Win32{ 
    
    public class Wallpaper{ 
        [DllImport("user32.dll", CharSet=CharSet.Auto)] 
            static extern int SystemParametersInfo (int uAction , int uParam , string lpvParam , int fuWinIni) ; 
            
            public static void SetWallpaper(string thePath){ 
            SystemParametersInfo(20,0,thePath,3); 
            }
        }
    } 
'@

    $anotherScriptCheck = Get-WmiObject win32_process -filter 'name="powershell.exe"' | Select-Object CommandLine | ForEach-Object { $_ | Select-String "$scriptToCheck" }

    if (-not $anotherScriptCheck) {
        Write-Header "Changing Wallpaper"
        $imgPath = "$Env:ArcBoxDir\wallpaper.png"
        Add-Type $code
        [Win32.Wallpaper]::SetWallpaper($imgPath)
    }
}
  