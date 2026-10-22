#Requires -Version 7.0
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
$projectRoot = Split-Path $PSScriptRoot -Parent
$localRoot = Join-Path $projectRoot '.local'
New-Item -ItemType Directory -Force $localRoot | Out-Null
$compose = Join-Path $PSScriptRoot 'compose.yaml'
$envFile = Join-Path $localRoot 'lab.env'
$stateFile = Join-Path $localRoot 'state.json'
$env:KUBECONFIG = Join-Path $localRoot 'kubeconfig'

function New-Password { [Convert]::ToHexString([Security.Cryptography.RandomNumberGenerator]::GetBytes(24)) }
function Wait-Url([string]$Url, [int]$Minutes = 10) {
    $deadline = (Get-Date).AddMinutes($Minutes)
    do {
        try { Invoke-WebRequest $Url -TimeoutSec 10 | Out-Null; return } catch { Start-Sleep 5 }
    } while ((Get-Date) -lt $deadline)
    throw "Service did not become ready: $Url"
}
function Basic-Header([string]$UserName, [string]$Password) {
    @{ Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("${UserName}:$Password")) }
}
function Save-State {
    $state | ConvertTo-Json | Set-Content $stateFile
    @("LAB_ADMIN_PASSWORD=$($state.AdminPassword)", "LAB_GIT_PASSWORD=$($state.GitPassword)",
      "SONAR_TOKEN=$($state.SonarToken)") | Set-Content $envFile
}
function Invoke-LabCompose {
    & docker compose --env-file $envFile -f $compose @args
}

docker info --format '{{.ServerVersion}}'
if (Test-Path $stateFile) {
    $state = Get-Content $stateFile -Raw | ConvertFrom-Json
} else {
    $state = [pscustomobject]@{AdminPassword=(New-Password); GitPassword=(New-Password); SonarToken='pending'}
    Save-State
}
Write-Host 'Starting local Git, registry and SonarQube services'
Invoke-LabCompose up -d gitea registry sonarqube
Wait-Url 'http://localhost:3000/api/healthz'
Wait-Url 'http://localhost:5000/v2/'
$sonarDeadline = (Get-Date).AddMinutes(15)
do {
    try { $status = Invoke-RestMethod 'http://localhost:9000/api/system/status' } catch { $status=$null }
    if ($status.status -eq 'UP') { break }
    Start-Sleep 5
} while ((Get-Date) -lt $sonarDeadline)
if ($status.status -ne 'UP') { throw 'SonarQube did not start. Check docker compose logs sonarqube.' }

$gitHeaders = Basic-Header 'lab' $state.GitPassword
try { Invoke-RestMethod 'http://localhost:3000/api/v1/user' -Headers $gitHeaders | Out-Null }
catch {
    & docker compose --env-file $envFile -f $compose exec -T -u git -e "USER_PASSWORD=$($state.GitPassword)" gitea sh -c 'gitea admin user create --username lab --password "$USER_PASSWORD" --email lab@habitapp.local --admin --must-change-password=false' | Out-Null
}
foreach ($repo in @('habitapp','habitapp-gitops')) {
    try { Invoke-RestMethod "http://localhost:3000/api/v1/repos/lab/$repo" -Headers $gitHeaders | Out-Null }
    catch { Invoke-RestMethod 'http://localhost:3000/api/v1/user/repos' -Method Post -Headers $gitHeaders -ContentType application/json -Body (@{name=$repo;private=$false;default_branch='main'} | ConvertTo-Json) | Out-Null }
}
if ($state.SonarToken -eq 'pending') {
    $defaultSonarHeaders=Basic-Header 'admin' 'admin'
    Invoke-RestMethod 'http://localhost:9000/api/users/change_password' -Method Post -Headers $defaultSonarHeaders -Body @{login='admin';previousPassword='admin';password=$state.AdminPassword} | Out-Null
    $sonarHeaders=Basic-Header 'admin' $state.AdminPassword
    $token=Invoke-RestMethod 'http://localhost:9000/api/user_tokens/generate' -Method Post -Headers $sonarHeaders -Body @{name='habitapp-jenkins'}
    $state.SonarToken=$token.token
    Save-State
}
$sonarHeaders=Basic-Header 'admin' $state.AdminPassword
$hooks=Invoke-RestMethod 'http://localhost:9000/api/webhooks/list' -Headers $sonarHeaders
if (-not ($hooks.webhooks | Where-Object name -eq 'Jenkins')) {
    Invoke-RestMethod 'http://localhost:9000/api/webhooks/create' -Method Post -Headers $sonarHeaders -Body @{name='Jenkins';url='http://jenkins:8080/sonarqube-webhook/'} | Out-Null
}

Write-Host 'Committing application and deployment configuration to the local Git service'
if (-not (Test-Path (Join-Path $projectRoot '.git'))) {
    git init -b main $projectRoot
}
# The Basic header exists only in this process environment, never in remotes or files.
$env:GIT_CONFIG_COUNT='1'
$env:GIT_CONFIG_KEY_0='http.http://localhost:3000/.extraheader'
$env:GIT_CONFIG_VALUE_0=$gitHeaders.Authorization.Replace('Basic ', 'Authorization: Basic ')
try {
    git -C $projectRoot config user.name 'HabitApp Lab'
    git -C $projectRoot config user.email 'lab@habitapp.local'
    git -C $projectRoot add .
    $changed=git -C $projectRoot diff --cached --name-only
    if ($changed) { git -C $projectRoot commit -m 'Add CI pipeline container packaging and GitOps deployment' }
    git -C $projectRoot push http://localhost:3000/lab/habitapp.git HEAD:main
    $gitopsRoot=Join-Path $localRoot 'gitops'
    if (-not (Test-Path (Join-Path $gitopsRoot '.git'))) {
        git clone http://localhost:3000/lab/habitapp-gitops.git $gitopsRoot
        Copy-Item (Join-Path $projectRoot 'charts') $gitopsRoot -Recurse
        Copy-Item (Join-Path $projectRoot 'environments') $gitopsRoot -Recurse
        git -C $gitopsRoot config user.name 'HabitApp Lab'
        git -C $gitopsRoot config user.email 'lab@habitapp.local'
        git -C $gitopsRoot add .
        git -C $gitopsRoot commit -m 'Initialize Helm deployment'
        git -C $gitopsRoot push origin HEAD:main
    }
} finally {
    Remove-Item Env:GIT_CONFIG_COUNT,Env:GIT_CONFIG_KEY_0,Env:GIT_CONFIG_VALUE_0 -ErrorAction SilentlyContinue
}

Write-Host 'Starting Jenkins'
Invoke-LabCompose up -d --build jenkins
Wait-Url 'http://localhost:8081/login' 20

Write-Host 'Creating the isolated kind Kubernetes cluster'
$kind=Join-Path $localRoot 'kind.exe'
if (-not (Test-Path $kind)) {
    Invoke-WebRequest 'https://kind.sigs.k8s.io/dl/v0.27.0/kind-windows-amd64' -OutFile $kind
}
$clusters=& $kind get clusters
if ($clusters -notcontains 'habitapp-lab') {
    & $kind create cluster --config (Join-Path $PSScriptRoot 'kind.yaml') --kubeconfig $env:KUBECONFIG --wait 180s
}
foreach ($container in @('habitapp-registry','habitapp-gitea')) {
    $networks=docker inspect --format '{{json .NetworkSettings.Networks}}' $container | ConvertFrom-Json
    if (-not $networks.kind) { docker network connect kind $container }
}
$nodes=& $kind get nodes --name habitapp-lab
foreach ($node in $nodes) {
    docker exec $node mkdir -p /etc/containerd/certs.d/localhost:5000
    '[host."http://habitapp-registry:5000"]' | docker exec -i $node sh -c 'cat > /etc/containerd/certs.d/localhost:5000/hosts.toml'
}
kubectl create namespace habitapp --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd --server-side -f https://raw.githubusercontent.com/argoproj/argo-cd/v3.4.12/manifests/install.yaml
kubectl -n argocd rollout status deployment/argocd-repo-server --timeout=300s
$giteaIP=docker inspect --format '{{(index .NetworkSettings.Networks "kind").IPAddress}}' habitapp-gitea
@"
apiVersion: v1
kind: Service
metadata: {name: gitea, namespace: argocd}
spec:
  ports: [{name: http, port: 3000, targetPort: 3000}]
---
apiVersion: discovery.k8s.io/v1
kind: EndpointSlice
metadata:
  name: gitea-external
  namespace: argocd
  labels: {kubernetes.io/service-name: gitea}
addressType: IPv4
ports: [{name: http, port: 3000, protocol: TCP}]
endpoints:
  - addresses: ["$giteaIP"]
    conditions: {ready: true}
"@ | kubectl apply -f -
kubectl apply -f (Join-Path $projectRoot 'argocd/project.yaml')
kubectl apply -f (Join-Path $projectRoot 'argocd/application.yaml')

$jenkinsHeaders=Basic-Header 'admin' $state.AdminPassword
$crumb=Invoke-RestMethod 'http://localhost:8081/crumbIssuer/api/json' -Headers $jenkinsHeaders -SessionVariable jenkinsSession
$jenkinsHeaders[$crumb.crumbRequestField]=$crumb.crumb
Invoke-WebRequest 'http://localhost:8081/job/habitapp/build' -Method Post -Headers $jenkinsHeaders -WebSession $jenkinsSession | Out-Null
Write-Host 'Jenkins build triggered. Watch http://localhost:8081/job/habitapp/'
Write-Host 'Application becomes available at http://localhost:28080 after a successful build and Argo CD synchronization.'
Write-Host 'Local credentials are stored in .local/state.json. Do not publish that file.'
