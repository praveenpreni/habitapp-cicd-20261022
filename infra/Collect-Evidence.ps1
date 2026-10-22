#Requires -Version 7.0
[CmdletBinding()]
param([string]$RunName = (Get-Date -Format 'yyyyMMdd-HHmmss'))
$ErrorActionPreference='Stop'
$projectRoot=Split-Path $PSScriptRoot -Parent
$env:KUBECONFIG=Join-Path $projectRoot '.local/kubeconfig'
if ($RunName -notmatch '^[A-Za-z0-9_-]+$') { throw 'Use letters numbers hyphens or underscores for RunName.' }
$evidence=Join-Path $projectRoot "evidence/$RunName"
New-Item -ItemType Directory -Force $evidence | Out-Null
git -C $projectRoot rev-parse HEAD | Set-Content (Join-Path $evidence 'source-sha.txt')
kubectl -n habitapp get deployment,pods,service -o wide | Set-Content (Join-Path $evidence 'workloads.txt')
kubectl -n habitapp top pods --containers | Set-Content (Join-Path $evidence 'cpu-memory.txt')
if ($LASTEXITCODE -ne 0) { throw 'CPU and memory collection failed. Run Enable-Monitoring.ps1 and wait for samples.' }
kubectl -n habitapp get pods -o 'custom-columns=NAME:.metadata.name,PHASE:.status.phase,RESTARTS:.status.containerStatuses[*].restartCount' | Set-Content (Join-Path $evidence 'restarts.txt')
kubectl -n habitapp get events --sort-by=.metadata.creationTimestamp | Set-Content (Join-Path $evidence 'events.txt')
kubectl -n habitapp get secrets -o 'custom-columns=NAME:.metadata.name,TYPE:.type' | Set-Content (Join-Path $evidence 'secret-metadata.txt')
kubectl -n habitapp get deployment habitapp -o yaml | Set-Content (Join-Path $evidence 'deployment.yaml')
kubectl -n argocd get application habitapp -o yaml | Set-Content (Join-Path $evidence 'argocd-application.yaml')
kubectl -n habitapp logs -l app=habitapp --tail=100 --prefix | Set-Content (Join-Path $evidence 'application.log')
Invoke-WebRequest 'http://127.0.0.1:28080/actuator/health/readiness' | Select-Object StatusCode,Content | ConvertTo-Json | Set-Content (Join-Path $evidence 'readiness.json')
$state=Get-Content (Join-Path $projectRoot '.local/state.json') -Raw | ConvertFrom-Json
$registryAuth=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("$($state.RegistryUser):$($state.RegistryPassword)"))
Invoke-RestMethod 'http://127.0.0.1:5000/v2/habitapp/tags/list' -Headers @{Authorization="Basic $registryAuth"} | ConvertTo-Json | Set-Content (Join-Path $evidence 'registry-tags.json')
$basic=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("admin:$($state.AdminPassword)"))
Invoke-WebRequest 'http://127.0.0.1:8081/job/habitapp/lastCompletedBuild/consoleText' -Headers @{Authorization="Basic $basic"} | Select-Object -ExpandProperty Content | Set-Content (Join-Path $evidence 'jenkins-console.txt')
Invoke-RestMethod 'http://127.0.0.1:8081/job/habitapp/lastCompletedBuild/api/json?tree=number,result,url,timestamp,duration' -Headers @{Authorization="Basic $basic"} | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $evidence 'jenkins-build.json')
Invoke-RestMethod 'http://127.0.0.1:9000/api/qualitygates/project_status?projectKey=habit-tracker' -Headers @{Authorization="Basic $basic"} | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $evidence 'sonarqube-quality-gate.json')
Invoke-RestMethod 'http://127.0.0.1:9000/api/measures/component?component=habit-tracker&metricKeys=coverage,bugs,vulnerabilities,code_smells' -Headers @{Authorization="Basic $basic"} | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $evidence 'sonarqube-measures.json')
Write-Host "Evidence saved in $evidence. Review and redact logs before submission."
