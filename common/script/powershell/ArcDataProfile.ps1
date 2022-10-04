# Create path
Write-Output "Create deployment path"
$Env:tempDir = "C:\Temp"
New-Item -Path $Env:tempDir -ItemType directory -Force

Import-Module ArcJumpstart
