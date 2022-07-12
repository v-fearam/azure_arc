
#requires -version 2

<#
.SYNOPSIS
  Merging kubeconfig files from CAPI and Rancher K3s
.PARAMETER <Parameter_Name>
.OUTPUTS
  Merged .kube\config
.NOTES
  Version:        1.0
  Author:         Arambarri Federico
  Creation Date:  24/05/20222
  Purpose/Change: Initial script development
  
.EXAMPLE
  Merging-CAPI-K3s-Kubeconfigs
#>

function Merging-CAPI-K3s-Kubeconfigs {
    # Merging kubeconfig files from CAPI and Rancher K3s
    Write-Header "Merging CAPI & K3s Kubeconfigs"
    Copy-Item -Path "C:\Users\$Env:USERNAME\.kube\config" -Destination "C:\Users\$Env:USERNAME\.kube\config.backup"
    $Env:KUBECONFIG = "C:\Users\$Env:USERNAME\.kube\config;C:\Users\$Env:USERNAME\.kube\config-k3s"
    kubectl config view --raw > C:\users\$Env:USERNAME\.kube\config_tmp
    kubectl config get-clusters --kubeconfig=C:\users\$Env:USERNAME\.kube\config_tmp
    Remove-Item -Path "C:\Users\$Env:USERNAME\.kube\config"
    Remove-Item -Path "C:\Users\$Env:USERNAME\.kube\config-k3s"
    Move-Item -Path "C:\Users\$Env:USERNAME\.kube\config_tmp" -Destination "C:\users\$Env:USERNAME\.kube\config"
    $Env:KUBECONFIG = "C:\users\$Env:USERNAME\.kube\config"
    kubectx
}
  



