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
        maximized window. With a value of 7, it will be launched in a minimized window.

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