Write-Output "ITPro profile script"

Write-Output "Fetching Workbook Template Artifact for ITPro"
Download-File-Renaming ($templateBaseUrl + "artifacts/mgmtMonitorWorkbookITPro.json") $Env:ArcBoxDir\mgmtMonitorWorkbook.json

. ./itproFullProfile-v1.ps1