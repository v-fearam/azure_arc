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
function AddDesktopShortcut {
    param(
        [string] $Icon,
        [Parameter(Mandatory = $true)]
        [string] $ShortcutName,
        [Parameter(Mandatory = $true)]
        [string] $TargetPath,
        [string] $Arguments,
        [string] $WindowStyle = 3,
        [string] $Username,
        [switch] $UrlMode
    )
    <#
        .SYNOPSIS
        Create a Desktop Shortcut.

        .DESCRIPTION
        Create a Desktop Shortcut. If a user name is provided, the shortcut is installed under that user's profile, otherwise the Shortcut is installed for all users.
        
        .PARAMETER Icon
        Path to the icon to use. This parameter is optional.

        .PARAMETER ShortcutName
        Name of the Shortcut.

        .PARAMETER TargetPath
        Path to the executable to invoke when the Shortcut is clicked.

        .PARAMETER Arguments
        Parameters to pass along to the executable when the icon is clicked. This parameter is optional.

        .PARAMETER WindowStyle
        If WindowStyle is 1, the application window will be set to its default location and size. With a value of 3, the application will be launched in a 
        maximized window. With a value of 7, it will be launched in a minimized window. https://learn.microsoft.com/troubleshoot/windows-client/admin-development/create-desktop-shortcut-with-wsh

        .PARAMETER Username
        User name if we want the icon to appear only on that user's desktop. If not specified, the icon will be added on the public desktop.

        .PARAMETER UrlMode
        If the shortcut should be included as URL 

        .EXAMPLE
        > AddDesktopShortcut -ShortcutName "Azure Data Studio" -TargetPath "C:\Program Files\Azure Data Studio\azuredatastudio.exe" -Username $adminUsername
    #>
    
    WriteHeader "Creating $ShortcutName Desktop shortcut"
    If ($UrlMode) {
        $extension = "url"
    }
    else {
        $extension = "lnk"
    }

    if ( -not $Username) {
        $shortcutLocation = "$Env:Public\Desktop\$ShortcutName.$extension"
    }
    else {
        $shortcutLocation = "C:\Users\$Username\Desktop\$ShortcutName.$extension"
    }

    $wScriptShell = New-Object -ComObject WScript.Shell
    $shortcut = $wScriptShell.CreateShortcut($ShortcutLocation)
    $shortcut.TargetPath = $TargetPath
    if ($Arguments) {
        $shortcut.Arguments = $Arguments
    }

    if ($Icon) {
        $shortcut.IconLocation = "${Env:ArcBoxIconDir}\$Icon.ico, 0"
    }
    If (-not ($UrlMode)) {
        $shortcut.WindowStyle = $WindowStyle
    }
    $shortcut.Save()
}
function InstallChocolateyPackages {
    param(
        [Parameter(Mandatory = $true)]
        [string[]] $PackageList
    )
    <#
        .SYNOPSIS
        Download and install Chocolatey packages.

        .DESCRIPTION
        Download and install Chocolatey packages. If Chocolatey is not present, it will be installed. 

        .PARAMETER PackageList
        List of packages to install, separated by comma.

        .EXAMPLE
        > InstallChocolateyPackages -Package  @("azure-cli", "az.powershell")
    #>
    try {
        choco config get cacheLocation
    }
    catch {
        WriteHeader "Chocolatey not detected, trying to install now"
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
    }

    foreach ($package in $PackageList) {
        Write-Output "Installing $package"
        & choco install $package /y -Force | Write-Output
    }
}
function ChangeWallpaper {
    param (
        [Parameter(Mandatory = $true)]
        [string] $Folder,
        [string] $image = 'wallpaper.png'
    )
    <#
        .SYNOPSIS
        Change the desktop Wallpaper.

        .DESCRIPTION
        Change the desktop Wallpaper.
        
        .PARAMETER Folder
        Folder where the new Wallpaper image is located.

        .PARAMETER image
        Image name. The default name for Jumpstart scenarios is wallpaper.png

        .EXAMPLE
        > ChangeWallpaper -Folder $Env:TempDir
    #>
    $imgPath = "$Folder\$image"
    $code = @'
        using System.Runtime.InteropServices;
        namespace Win32 {

            public class Wallpaper{
            [DllImport("user32.dll", CharSet=CharSet.Auto)]
            static extern int SystemParametersInfo (int uAction , int uParam , string lpvParam , int fuWinIni) ;

            public static void SetWallpaper(string thePath){
                SystemParametersInfo(20,0,thePath,3);
            }
        }
    }
'@

    add-type $code
    [Win32.Wallpaper]::SetWallpaper($imgPath)
}
function AddLogonScript {
    param(
        [string] $AdminUsername,
        [string] $TaskName,
        [string] $Script
    )
    <#
        .SYNOPSIS
        Create a task which is goingt to execute a script at Logon.

        .DESCRIPTION
        Create a task which is goingt to execute a script at Logon.
        
        .PARAMETER AdminUsername
        Admin VM user name

        .PARAMETER TaskName
        Task name inside Task Scheduler

        .PARAMETER Script
        Path to the powershell script

        .EXAMPLE
        > AddLogonScript -AdminUsername $adminUsername -TaskName "MonitorWorkbookLogonScript" -Script ("$Env:ArcBoxDir\MonitorWorkbookLogonScript.ps1")
    #>
    $Trigger = New-ScheduledTaskTrigger -AtLogOn
    $Action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument $Script
    Register-ScheduledTask -TaskName $TaskName -Trigger $Trigger -User $AdminUsername -Action $Action -RunLevel "Highest" -Force
}
function ForceAzureClientsLogin {
    <#
        .SYNOPSIS
        Force az cli libraries to be loged in, if not it writes an error and close the script. The subcription between powershell client and az cli must be de same.

        .DESCRIPTION
        Force az cli libraries to be loged in, if not it writes an error and close the script. The subcription between powershell client and az cli must be de same.
        
        .EXAMPLE
        > ForceAzureClientsLogin
    #>
    $azureCliContext = $(az account show | ConvertFrom-Json) 2>$null
    if (-not $azureCliContext) {
        Write-Host "ERROR: Azure CLI not logged in or no subscription has been selected!" -ForegroundColor red
        exit
    }
    $azureCliSub = $azureCliContext.id
    $azurePowerShellSub = (Get-AzContext).Subscription.Id
    if ($azurePowerShellSub -ne $azureCliSub) {
        Write-Host "ERROR: Azure PowerShell and Azure CLI must be set to the same context!" -ForegroundColor red
        exit
    }
}