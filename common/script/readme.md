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
    Path              = 'Modules\Jumpstart.General\Jumpstart.General.psd1'
    RootModule        = 'Jumpstart.General.psm1' 
    ModuleVersion     = '1.0.0.0'  
    Author            = 'Microsoft'
	FunctionsToExport = @('WriteHeader','AddDesktopShortcut','InstallChocolateyPackages','ChangeWallpaper','AddLogonScript','ForceAzureClientsLogin')
	Description       = 'Jumpstart common functions'
    CompanyName       = 'Microsoft'
}
New-ModuleManifest @manifest

$manifest = @{
    Path              = 'Modules\Jumpstart.DataServices\Jumpstart.DataServices.psd1'
    RootModule        = 'Jumpstart.DataServices.psm1'
    ModuleVersion     = '1.0.0.0' 
    RequiredModules = (@{
        ModuleName="Jumpstart.General"
        ModuleVersion="1.0.0.0";
    }) 
    Author            = 'Microsoft'
	FunctionsToExport = @('BootstrapArcData','InstallAzureArcDataCliExtensions','InstallAzureDataStudioExtensions','RegisterAzureArcDataProviders','DownloadCapiFiles','CopyAzureDataStudioSettingsTemplateFile','EnableDataControllerAutoMetrics','DeployAzureArcDataController','CreateCustomLocation','InstallAzureArcEnabledDataServicesExtension','DeployAzureArcPostgreSQL','DeployAzureArcSQLManagedInstance')
	Description       = 'Jumpstart Data Service functions'
    CompanyName       = 'Microsoft'
}
New-ModuleManifest @manifest

$manifest = @{
    Path              = 'Modules\Jumpstart\Jumpstart.psd1'
    ModuleVersion     = '1.0.0.0' 
    RequiredModules = (@{
        ModuleName="Jumpstart.DataServices"
        ModuleVersion="1.0.0.0";
    }) 
    Author            = 'Microsoft'
	Description       = 'Jumpstart Toolkit'
    CompanyName       = 'Microsoft'
}
New-ModuleManifest @manifest
```

