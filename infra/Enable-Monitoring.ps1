#Requires -Version 7.0
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$PSNativeCommandUseErrorActionPreference=$true
$projectRoot=Split-Path $PSScriptRoot -Parent
$env:KUBECONFIG=Join-Path $projectRoot '.local/kubeconfig'
$context=kubectl config current-context
if ($context -ne 'kind-habitapp-lab') { throw 'This script is only for the isolated kind lab.' }
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/download/v0.7.2/components.yaml
# kind kubelets use local certificates. This relaxation is for this lab only.
kubectl -n kube-system patch deployment metrics-server --type=json -p '[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
kubectl -n kube-system rollout status deployment/metrics-server --timeout=180s
Write-Host 'Metrics Server is installed. Allow a minute for CPU and memory samples.'
kubectl -n habitapp get pods
