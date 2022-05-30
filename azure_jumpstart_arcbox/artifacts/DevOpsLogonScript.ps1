. C:\ArcBox\common\script\powershell\arcboxPaths-v1.ps1

$osmRelease = "v1.1.0"
$osmMeshName = "osm"
$ingressNamespace = "ingress-nginx"

$certname = "ingress-cert"
$certdns = "arcbox.devops.com"

$appClonedRepo = "https://github.com/$Env:githubUser/azure-arc-jumpstart-apps"

Start-Transcript -Path $Env:ArcBoxLogsDir\DevOpsLogonScript.log
. $Env:PowerShellCommonScripts\azureConfigDir-v1.ps1
. $Env:PowerShellCommonScripts\loginAzureTools-v1.ps1
. $Env:PowerShellCommonScripts\downloadCapiFiles-v1.ps1
. $Env:PowerShellCommonScripts\downloadRancherK3sFiles-v1.ps1
. $Env:PowerShellCommonScripts\mergingCAPI-K3sKubeconfigs-v1.ps1
. $Env:PowerShellCommonScripts\setWallpaper-v1.ps1

Azure-Config-Directory $Env:ArcBoxDir  ".devops"

Arbox-Login-Azure-Tools

Download-CAPI-Files

Download-RancherK3s-Files

Merging-CAPI-K3s-Kubeconfigs

# "Download OSM binaries"
Write-Header "Downloading OSM Binaries"
Invoke-WebRequest -Uri "https://github.com/openservicemesh/osm/releases/download/$osmRelease/osm-$osmRelease-windows-amd64.zip" -Outfile "$Env:TempDir\osm-$osmRelease-windows-amd64.zip"
Expand-Archive "$Env:TempDir\osm-$osmRelease-windows-amd64.zip" -DestinationPath $Env:TempDir
Copy-Item "$Env:TempDir\windows-amd64\osm.exe" -Destination $Env:ToolsDir

Write-Header "Adding Tools Folder to PATH"
[System.Environment]::SetEnvironmentVariable('PATH', $Env:PATH + ";$Env:ToolsDir" , [System.EnvironmentVariableTarget]::Machine)
$Env:PATH += ";$Env:ToolsDir"

# Create random 13 character string for Key Vault name
$strLen = 13
$randStr = ( -join ((0x30..0x39) + (0x61..0x7A) | Get-Random -Count $strLen | ForEach-Object { [char]$_ }))
$Env:keyVaultName = "ArcBox-KV-$randStr"

[System.Environment]::SetEnvironmentVariable('keyVaultName', $Env:keyVaultName, [System.EnvironmentVariableTarget]::Machine)

# Create Azure Key Vault
Write-Header "Creating Azure KeyVault"
az keyvault create --name $Env:keyVaultName --resource-group $Env:resourceGroup --location $Env:azureLocation

# Allow SPN to import certificates into Key Vault
Write-Header "Setting KeyVault Access Policies"
az keyvault set-policy --name $Env:keyVaultName --spn $Env:spnClientID --key-permissions --secret-permissions get --certificate-permissions get list import

# Making extension install dynamic
az config set extension.use_dynamic_install=yes_without_prompt
Write-Host "`n"
az -v

# "Create OSM Kubernetes extension instance"
Write-Header "Creating OSM K8s Extension Instance"
az k8s-extension create --cluster-name $Env:capiArcDataClusterName --resource-group $Env:resourceGroup --cluster-type connectedClusters --extension-type Microsoft.openservicemesh --scope cluster --name $osmMeshName

# Create Kubernetes Namespaces
Write-Header "Creating K8s Namespaces"
foreach ($namespace in @('bookstore', 'bookbuyer', 'bookwarehouse', 'hello-arc', 'ingress-nginx')) {
    kubectl create namespace $namespace
}

# Add the bookstore namespaces to the OSM control plane
Write-Header "Adding Bookstore Namespaces to OSM"
osm namespace add bookstore bookbuyer bookwarehouse

# To be able to discover the endpoints of this service, we need OSM controller to monitor the corresponding namespace. 
# However, Nginx must NOT be injected with an Envoy sidecar to function properly.
osm namespace add "$ingressNamespace" --mesh-name "$osmMeshName" --disable-sidecar-injection

#############################
# - Apply GitOps Configs
#############################

Write-Header "Applying GitOps Configs"

# Create GitOps config for NGINX Ingress Controller
Write-Host "Creating GitOps config for NGINX Ingress Controller"
az k8s-configuration flux create `
    --cluster-name $Env:capiArcDataClusterName `
    --resource-group $Env:resourceGroup `
    --name config-nginx `
    --namespace $ingressNamespace `
    --cluster-type connectedClusters `
    --scope cluster `
    --url $appClonedRepo `
    --branch main --sync-interval 3s `
    --kustomization name=nginx path=./nginx/release

# Create GitOps config for Bookstore application
Write-Host "Creating GitOps config for Bookstore application"
az k8s-configuration flux create `
    --cluster-name $Env:capiArcDataClusterName `
    --resource-group $Env:resourceGroup `
    --name config-bookstore `
    --cluster-type connectedClusters `
    --url $appClonedRepo `
    --branch main --sync-interval 3s `
    --kustomization name=bookstore path=./bookstore/yaml

# Create GitOps config for Bookstore RBAC
Write-Host "Creating GitOps config for Bookstore RBAC"
az k8s-configuration flux create `
    --cluster-name $Env:capiArcDataClusterName `
    --resource-group $Env:resourceGroup `
    --name config-bookstore-rbac `
    --cluster-type connectedClusters `
    --scope namespace `
    --namespace bookstore `
    --url $appClonedRepo `
    --branch main --sync-interval 3s `
    --kustomization name=bookstore path=./bookstore/rbac-sample

# Create GitOps config for Bookstore Traffic Split
Write-Host "Creating GitOps config for Bookstore Traffic Split"
az k8s-configuration flux create `
    --cluster-name $Env:capiArcDataClusterName `
    --resource-group $Env:resourceGroup `
    --name config-bookstore-osm `
    --cluster-type connectedClusters `
    --scope namespace `
    --namespace bookstore `
    --url $appClonedRepo `
    --branch main --sync-interval 3s `
    --kustomization name=bookstore path=./bookstore/osm-sample

# Create GitOps config for Hello-Arc application
Write-Host "Creating GitOps config for Hello-Arc application"
az k8s-configuration flux create `
    --cluster-name $Env:capiArcDataClusterName `
    --resource-group $Env:resourceGroup `
    --name config-helloarc `
    --namespace hello-arc `
    --cluster-type connectedClusters `
    --scope namespace `
    --url $appClonedRepo `
    --branch main --sync-interval 3s `
    --kustomization name=helloarc path=./hello-arc/yaml

################################################
# - Install Key Vault Extension / Create Ingress
################################################

Write-Header "Installing KeyVault Extension"

Write-Host "Generating a TLS Certificate"
$cert = New-SelfSignedCertificate -DnsName $certdns -KeyAlgorithm RSA -KeyLength 2048 -NotAfter (Get-Date).AddYears(1) -CertStoreLocation "Cert:\CurrentUser\My"
$certPassword = ConvertTo-SecureString -String "arcbox" -Force -AsPlainText
Export-PfxCertificate -Cert "cert:\CurrentUser\My\$($cert.Thumbprint)" -FilePath "$Env:TempDir\$certname.pfx" -Password $certPassword
Import-PfxCertificate -FilePath "$Env:TempDir\$certname.pfx" -CertStoreLocation Cert:\LocalMachine\Root -Password $certPassword

Write-Host "Importing the TLS certificate to Key Vault"
az keyvault certificate import --vault-name $Env:keyVaultName --password "arcbox" -n $certname -f "$Env:TempDir\$certname.pfx"

Write-Host "Installing Azure Key Vault Kubernetes extension instance"
az k8s-extension create --name 'akvsecretsprovider' --extension-type Microsoft.AzureKeyVaultSecretsProvider --scope cluster --cluster-name $Env:capiArcDataClusterName --resource-group $Env:resourceGroup --cluster-type connectedClusters --release-train preview --release-namespace kube-system --configuration-settings 'secrets-store-csi-driver.enableSecretRotation=true' 'secrets-store-csi-driver.syncSecret.enabled=true'

# Replace Variable values
Get-ChildItem -Path $Env:ArcBoxKVDir |
ForEach-Object {
        (Get-Content -path $_.FullName -Raw) -Replace '\{JS_CERTNAME}', $certname | Set-Content -Path $_.FullName
        (Get-Content -path $_.FullName -Raw) -Replace '\{JS_KEYVAULTNAME}', $Env:keyVaultName | Set-Content -Path $_.FullName
        (Get-Content -path $_.FullName -Raw) -Replace '\{JS_HOST}', $certdns | Set-Content -Path $_.FullName
        (Get-Content -path $_.FullName -Raw) -Replace '\{JS_TENANTID}', $Env:spnTenantId | Set-Content -Path $_.FullName
}

Write-Header "Creating Ingress Controller"

# Deploy Ingress resources for Bookstore and Hello-Arc App
foreach ($namespace in @('bookstore', 'bookbuyer', 'hello-arc')) {
    # Create the Kubernetes secret with the service principal credentials
    kubectl create secret generic secrets-store-creds --namespace $namespace --from-literal clientid=$Env:spnClientID --from-literal clientsecret=$Env:spnClientSecret
    kubectl --namespace $namespace label secret secrets-store-creds secrets-store.csi.k8s.io/used=true

    # Deploy Key Vault resources and Ingress for Book Store and Hello-Arc App
    kubectl --namespace $namespace apply -f "$Env:ArcBoxKVDir\$namespace.yaml"
}

$ip = kubectl get service/ingress-nginx-controller --namespace $ingressNamespace --output=jsonpath='{.status.loadBalancer.ingress[0].ip}'

#Insert into HOSTS file
Add-Content -Path $Env:windir\System32\drivers\etc\hosts -Value "`n`t$ip`t$certdns" -Force

Write-Header "Configuring Edge Policies"

# Disable Edge 'First Run' Setup
$edgePolicyRegistryPath = 'HKLM:SOFTWARE\Policies\Microsoft\Edge'
$desktopSettingsRegistryPath = 'HKCU:SOFTWARE\Microsoft\Windows\Shell\Bags\1\Desktop'
$firstRunRegistryName = 'HideFirstRunExperience'
$firstRunRegistryValue = '0x00000001'
$savePasswordRegistryName = 'PasswordManagerEnabled'
$savePasswordRegistryValue = '0x00000000'
$autoArrangeRegistryName = 'FFlags'
$autoArrangeRegistryValue = '1075839525'

If (-NOT (Test-Path -Path $edgePolicyRegistryPath)) {
    New-Item -Path $edgePolicyRegistryPath -Force | Out-Null
}

New-ItemProperty -Path $edgePolicyRegistryPath -Name $firstRunRegistryName -Value $firstRunRegistryValue -PropertyType DWORD -Force
New-ItemProperty -Path $edgePolicyRegistryPath -Name $savePasswordRegistryName -Value $savePasswordRegistryValue -PropertyType DWORD -Force
Set-ItemProperty -Path $desktopSettingsRegistryPath -Name $autoArrangeRegistryName -Value $autoArrangeRegistryValue -Force

# Tab Auto-Refresh Extension
New-Item -Path HKLM:\SOFTWARE\Policies\Microsoft\Edge\ExtensionInstallForcelist -Force
New-ItemProperty -Path HKLM:\SOFTWARE\Policies\Microsoft\Edge\ExtensionInstallForcelist -Name 1 -Value odiofbnciojkpogljollobmhplkhmofe -Force

Write-Header "Creating Desktop Icons"

# Creating CAPI Hello Arc Icon on Desktop
$shortcutLocation = "$Env:Public\Desktop\CAPI Hello-Arc.lnk"
$wScriptShell = New-Object -ComObject WScript.Shell
$shortcut = $wScriptShell.CreateShortcut($shortcutLocation)
$shortcut.TargetPath = "https://$certdns"
$shortcut.IconLocation = "$Env:ArcBoxIconDir\arc.ico, 0"
$shortcut.WindowStyle = 3
$shortcut.Save()

# Creating CAPI Bookstore Icon on Desktop
$shortcutLocation = "$Env:Public\Desktop\CAPI Bookstore.lnk"
$wScriptShell = New-Object -ComObject WScript.Shell
$shortcut = $wScriptShell.CreateShortcut($shortcutLocation)
$shortcut.TargetPath = "powershell.exe"
$shortcut.Arguments = "-ExecutionPolicy Bypass -File $Env:ArcBoxDir\BookStoreLaunch.ps1"
$shortcut.IconLocation = "$Env:ArcBoxIconDir\bookstore.ico, 0"
$shortcut.WindowStyle = 7
$shortcut.Save()

Set-WallPapper "ArcServersLogonScript.ps1"

# Removing the LogonScript Scheduled Task so it won't run on next reboot
Write-Header "Removing Logon Task"
Unregister-ScheduledTask -TaskName "DevOpsLogonScript" -Confirm:$false
Start-Sleep -Seconds 5

# Executing the deployment logs bundle PowerShell script in a new window
Write-Header "Uploading Log Bundle"
Invoke-Expression 'cmd /c start Powershell -Command { 
    $RandomString = -join ((48..57) + (97..122) | Get-Random -Count 6 | % {[char]$_})
    Write-Host "Sleeping for 5 seconds before creating deployment logs bundle..."
    Start-Sleep -Seconds 5
    Write-Host "`n"
    Write-Host "Creating deployment logs bundle"
    7z a $Env:ArcBoxLogsDir\LogsBundle-"$RandomString".zip $Env:ArcBoxLogsDir\*.log
}'
