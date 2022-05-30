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
Function Set-WallPaper-Internal($Value) {
        Set-ItemProperty -path 'HKCU:\Control Panel\Desktop\' -name WallPaper -value $value
        RUNDLL32.EXE USER32.DLL, UpdatePerUserSystemParameters , 1 , True
}
   
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
        Write-Header "Changing Wallpaper 1"
        $imgPath = "$Env:ArcBoxDir\wallpaper.png"
        Write-Header "$imgPath"
        Add-Type $code
        $variable=Get-ItemProperty -path 'HKCU:\Control Panel\Desktop' | Select-Object -Property WallPaper
        Write-Header "$variable"
        [Win32.Wallpaper]::SetWallpaper($imgPath)
        $variable=Get-ItemProperty -path 'HKCU:\Control Panel\Desktop' | Select-Object -Property WallPaper
        Write-Header "$variable"
        Set-WallPaper-Internal -value $imgPath
        $variable=Get-ItemProperty -path 'HKCU:\Control Panel\Desktop' | Select-Object -Property WallPaper
        Write-Header "$variable"
    }
}
  