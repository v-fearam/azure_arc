param (
    [string]$action
)

Write-Output "Arbox Path"

$Env:ArcBoxDir = "C:\ArcBox"
$Env:ArcBoxLogsDir = "$Env:ArcBoxDir\Logs"
$Env:ArcBoxVMDir = "$Env:ArcBoxDir\Virtual Machines"
$Env:ArcBoxKVDir = "$Env:ArcBoxDir\KeyVault"
$Env:ArcBoxGitOpsDir = "$Env:ArcBoxDir\GitOps"
$Env:ArcBoxIconDir = "$Env:ArcBoxDir\Icons"
$Env:agentScript = "$Env:ArcBoxDir\agentScript"
$Env:ToolsDir = "C:\Tools"
$Env:tempDir = "C:\Temp"
$Env:PowerShellCommonScripts = "$Env:ArcBoxDir\common\script\powershell"
$Env:BashCommonScripts = "$Env:ArcBoxDir\common\script\bash"

if ($action -eq "create") {
    Write-Output "Arbox Path creating folders"
    New-Item -Path $Env:ArcBoxDir -ItemType directory -Force
    New-Item -Path $Env:ArcBoxLogsDir -ItemType directory -Force
    New-Item -Path $Env:ArcBoxVMDir -ItemType directory -Force
    New-Item -Path $Env:ArcBoxKVDir -ItemType directory -Force
    New-Item -Path $Env:ArcBoxGitOpsDir -ItemType directory -Force
    New-Item -Path $Env:ArcBoxIconDir -ItemType directory -Force
    New-Item -Path $Env:ToolsDir -ItemType Directory -Force
    New-Item -Path $Env:tempDir -ItemType directory -Force
    New-Item -Path $Env:agentScript -ItemType directory -Force
}
