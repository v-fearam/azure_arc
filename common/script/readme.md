# Arc Jumpstart toolkit common code

The Arc Jumpstart toolkit follows the guidance at
* https://docs.microsoft.com/powershell/scripting/developer/cmdlet/strongly-encouraged-development-guidelines?view=powershell-7.2

## Code documentation

The Arc Jumpstart toolkit files documentation follows the guidance at
*  https://docs.microsoft.com/powershell/scripting/developer/help/examples-of-comment-based-help?view=powershell-7.2.

# Generate module Manifest

```
 cd common\script\powershell
 $manifest = @{
    Path              = 'Modules\ArcJumpstart\ArcJumpstart.psd1'
    ModuleVersion     = '1.0.0.0'  
	NestedModules     = @('.\ArcData\ArcData.psm1','.\General\General.psm1')
    Author            = 'Microsoft'
	FunctionsToExport = @('BootstrapArcData','InstallAzureArcDataCliExtensions','InstallAzureDataStudioExtensions','RegisterAzureArcDataProviders','DownloadCapiFiles','CopyAzureDataStudioSettingsTemplateFile','EnableDataControllerAutoMetrics','DeployAzureArcDataController','CreateCustomLocation','InstallAzureArcEnabledDataServicesExtension','DeployAzureArcPostgreSQL','DeployAzureArcSQLManagedInstance','WriteHeader','AddDesktopShortcut','InstallChocolateyPackages','ChangeWallpaper','AddLogonScript')
	Description       = 'ArcJumpstart common functions'
    CompanyName       = 'Microsoft'
}
New-ModuleManifest @manifest
```