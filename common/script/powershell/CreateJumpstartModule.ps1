function CreateJumpstartModule() {
    param (
        [Parameter(Mandatory = $true)]
        [string] $ProfileRootBaseUrl,
        [Parameter(Mandatory = $true)]
        [string] $Folder
    )
  
    New-Item -Path $Folder"\WindowsPowerShell\Modules\Jumpstart" -ItemType directory -Force
    New-Item -Path $Folder"\WindowsPowerShell\Modules\Jumpstart.DataServices" -ItemType directory -Force
    New-Item -Path $Folder"\WindowsPowerShell\Modules\Jumpstart.General" -ItemType directory -Force
    Invoke-WebRequest -Uri ($ProfileRootBaseUrl + "..\common\script\powershell\Modules\Jumpstart\Jumpstart.psd1") -OutFile $Folder"\WindowsPowerShell\Modules\Jumpstart\Jumpstart.psd1"
    Invoke-WebRequest -Uri ($ProfileRootBaseUrl + "..\common\script\powershell\Modules\Jumpstart.DataServices\Jumpstart.DataServices.psm1") -OutFile $Folder"\WindowsPowerShell\Modules\Jumpstart.DataServices\Jumpstart.DataServices.psm1"
    Invoke-WebRequest -Uri ($ProfileRootBaseUrl + "..\common\script\powershell\Modules\Jumpstart.DataServices\Jumpstart.DataServices.psd1") -OutFile $Folder"\WindowsPowerShell\Modules\Jumpstart.DataServices\Jumpstart.DataServices.psd1"
    Invoke-WebRequest -Uri ($ProfileRootBaseUrl + "..\common\script\powershell\Modules\Jumpstart.General\Jumpstart.General.psm1") -OutFile $Folder"\WindowsPowerShell\Modules\Jumpstart.General\Jumpstart.General.psm1"
    Invoke-WebRequest -Uri ($ProfileRootBaseUrl + "..\common\script\powershell\Modules\Jumpstart.General\Jumpstart.General.psd1") -OutFile $Folder"\WindowsPowerShell\Modules\Jumpstart.General\Jumpstart.General.psd1"
}