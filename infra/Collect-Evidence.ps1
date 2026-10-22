#Requires -Version 7.0
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$projectRoot=Split-Path $PSScriptRoot -Parent
$env:KUBECONFIG=Join-Path $projectRoot '.local/kubeconfig'
$evidence=Join-Path $projectRoot 'evidence'
New-Item -ItemType Directory -Force $evidence | Out-Null
git -C $projectRoot rev-parse HEAD | Set-Content (Join-Path $evidence 'source-sha.txt')
kubectl -n habitapp get deployment,pods,service -o wide | Set-Content (Join-Path $evidence 'workloads.txt')
kubectl -n habitapp get deployment habitapp -o yaml | Set-Content (Join-Path $evidence 'deployment.yaml')
kubectl -n argocd get application habitapp -o yaml | Set-Content (Join-Path $evidence 'argocd-application.yaml')
kubectl -n habitapp logs -l app=habitapp --tail=100 --prefix | Set-Content (Join-Path $evidence 'application.log')
Invoke-WebRequest 'http://localhost:28080/actuator/health/readiness' | Select-Object StatusCode,Content | ConvertTo-Json | Set-Content (Join-Path $evidence 'readiness.json')
Invoke-RestMethod 'http://localhost:5000/v2/habitapp/tags/list' | ConvertTo-Json | Set-Content (Join-Path $evidence 'registry-tags.json')
$state=Get-Content (Join-Path $projectRoot '.local/state.json') -Raw | ConvertFrom-Json
$basic=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("admin:$($state.AdminPassword)"))
Invoke-WebRequest 'http://localhost:8081/job/habitapp/lastBuild/consoleText' -Headers @{Authorization="Basic $basic"} | Select-Object -ExpandProperty Content | Set-Content (Join-Path $evidence 'jenkins-console.txt')
Write-Host "Evidence saved in $evidence. Review and redact logs before submission."
