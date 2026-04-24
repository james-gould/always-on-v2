<#
.SYNOPSIS
    Builds, publishes, and deploys AlwaysOn workloads to AKS.

.DESCRIPTION
    End-to-end pipeline that:
      1) Builds the Silo container image and pushes it to ACR
      2) Runs aspire publish to generate base Kubernetes manifests
      3) Creates/updates the Cosmos DB connection string as a K8s secret
      4) Applies Kustomize overlays (Azure networking patches) via kubectl

    All steps are idempotent — safe to re-run at any time.

.PARAMETER Environment
    Target environment. Must be 'dev' or 'staging'.

.PARAMETER PublishOnly
    Generates manifests and pushes images but does not apply to the cluster.

.PARAMETER ImageTag
    Container image tag. Defaults to the short git SHA.

.EXAMPLE
    .\Deploy-AppHost.ps1 -Environment dev

.EXAMPLE
    .\Deploy-AppHost.ps1 -Environment dev -PublishOnly

.EXAMPLE
    .\Deploy-AppHost.ps1 -Environment dev -ImageTag v1.0.0
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('dev', 'staging', 'prod')]
    [string]$Environment,

    [Parameter()]
    [switch]$PublishOnly,

    [Parameter()]
    [string]$ImageTag
)

$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path "$PSScriptRoot\..").Path
$appHostDir = Join-Path $repoRoot 'dev\AlwaysOn.AppHost'
$siloDir = Join-Path $repoRoot 'src\AlwaysOn.Silo'
$baseDir = Join-Path $repoRoot 'k8s\base'

$resourceGroup = "rg-alwayson-$Environment"
$aksCluster = "alwayson-$Environment-aks"

# ── Prerequisites ──────────────────────────────────────────────
foreach ($cmd in @('az', 'dotnet', 'aspire')) {
    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
        Write-Error "$cmd is not installed or not on PATH."
    }
}

if (-not $PublishOnly -and -not (Get-Command kubectl -ErrorAction SilentlyContinue)) {
    Write-Error 'kubectl is not installed or not on PATH.'
}

# ── Resolve image tag ─────────────────────────────────────────
if (-not $ImageTag) {
    $ImageTag = git rev-parse --short HEAD 2>$null
    if (-not $ImageTag) { $ImageTag = 'latest' }
}

# ── 1. Resolve ACR ────────────────────────────────────────────
Write-Host "`n[1/5] Resolving ACR..." -ForegroundColor Cyan
$acrLoginServer = az acr list --resource-group $resourceGroup `
    --query "[0].loginServer" -o tsv
if (-not $acrLoginServer) {
    Write-Error "No ACR found in resource group '$resourceGroup'. Run Deploy-Infra.ps1 first."
}
Write-Host "  ACR: $acrLoginServer"

az acr login --name ($acrLoginServer -split '\.')[0] --output none
if ($LASTEXITCODE -ne 0) { Write-Error 'ACR login failed.' }

# ── 2. Build and push container image ─────────────────────────
Write-Host "`n[2/5] Building and pushing Silo image..." -ForegroundColor Cyan
$fullImage = "$acrLoginServer/alwayson-silo:$ImageTag"
Write-Host "  Image: $fullImage"

dotnet publish $siloDir `
    --os linux --arch x64 `
    /t:PublishContainer `
    /p:ContainerRegistry=$acrLoginServer `
    /p:ContainerImageTag=$ImageTag

if ($LASTEXITCODE -ne 0) { Write-Error 'Container image build/push failed.' }

# ── 3. Generate base manifests via Aspire ─────────────────────
Write-Host "`n[3/5] Generating base Kubernetes manifests..." -ForegroundColor Cyan

if (Test-Path $baseDir) {
    Get-ChildItem $baseDir -Exclude '.gitkeep' | Remove-Item -Recurse -Force
}

try {
    Push-Location $appHostDir
    aspire publish -o $baseDir
    if ($LASTEXITCODE -ne 0) { throw 'aspire publish failed.' }
}
finally {
    Pop-Location
}

# Auto-generate kustomization.yaml listing all generated manifests
$manifests = Get-ChildItem $baseDir -Filter '*.yaml' -File |
    Where-Object { $_.Name -ne 'kustomization.yaml' } |
    ForEach-Object { "  - $($_.Name)" }

if (-not $manifests) {
    Write-Error "No YAML manifests found in $baseDir after aspire publish."
}

@"
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
$($manifests -join "`n")
"@ | Set-Content (Join-Path $baseDir 'kustomization.yaml') -Encoding utf8

Write-Host "  Generated base kustomization.yaml with $($manifests.Count) resource(s)"

if ($PublishOnly) {
    Write-Host "`nPublish complete. Manifests are in: $baseDir" -ForegroundColor Green
    return
}

# ── 4. Configure workload identity for Cosmos AAD auth ────────
Write-Host "`n[4/5] Configuring workload identity..." -ForegroundColor Cyan

az aks get-credentials --resource-group $resourceGroup `
    --name $aksCluster --overwrite-existing --output none
if ($LASTEXITCODE -ne 0) { Write-Error 'Failed to get AKS credentials.' }

# Get the managed identity client ID and Cosmos account endpoint from infra outputs
$siloIdentityClientId = az deployment group show `
    --resource-group $resourceGroup `
    --name main `
    --query "properties.outputs.siloIdentityClientId.value" -o tsv
if (-not $siloIdentityClientId) {
    Write-Error "Failed to get silo managed identity client ID from deployment outputs."
}

$cosmosEndpoint = az deployment group show `
    --resource-group $resourceGroup `
    --name main `
    --query "properties.outputs.cosmosAccountEndpoint.value" -o tsv
if (-not $cosmosEndpoint) {
    Write-Error "Failed to get Cosmos account endpoint from deployment outputs."
}

$redisHostName = az deployment group show `
    --resource-group $resourceGroup `
    --name main `
    --query "properties.outputs.redisHostName.value" -o tsv
if (-not $redisHostName) {
    Write-Error "Failed to get Redis host name from deployment outputs."
}

$eventGridEndpoint = az deployment group show `
    --resource-group $resourceGroup `
    --name main `
    --query "properties.outputs.eventGridEndpoint.value" -o tsv
if (-not $eventGridEndpoint) {
    Write-Error "Failed to get Event Grid endpoint from deployment outputs."
}

$ingressPipName = az deployment group show `
    --resource-group $resourceGroup `
    --name main `
    --query "properties.outputs.ingressPipName.value" -o tsv
if (-not $ingressPipName) {
    Write-Error "Failed to get ingress public IP name from deployment outputs."
}

$ingressPipResourceGroup = az deployment group show `
    --resource-group $resourceGroup `
    --name main `
    --query "properties.outputs.ingressPipResourceGroup.value" -o tsv
if (-not $ingressPipResourceGroup) {
    Write-Error "Failed to get ingress public IP resource group from deployment outputs."
}

$ingressPipAddress = az deployment group show `
    --resource-group $resourceGroup `
    --name main `
    --query "properties.outputs.ingressPipAddress.value" -o tsv

Write-Host "  Identity client ID: $siloIdentityClientId"
Write-Host "  Cosmos endpoint   : $cosmosEndpoint"
Write-Host "  Redis host        : $redisHostName"
Write-Host "  Event Grid        : $eventGridEndpoint"
Write-Host "  Ingress PIP       : $ingressPipName ($ingressPipAddress)"

# Create the K8s service account with workload identity annotation
$saYaml = @"
apiVersion: v1
kind: ServiceAccount
metadata:
  name: silo-sa
  namespace: default
  annotations:
    azure.workload.identity/client-id: "$siloIdentityClientId"
  labels:
    azure.workload.identity/use: "true"
"@
$saYaml | kubectl apply -f -
if ($LASTEXITCODE -ne 0) { Write-Error 'Failed to create service account.' }

# ── 5. Deploy via Helm ─────────────────────────────────────────
Write-Host "`n[5/5] Deploying to AKS via Helm..." -ForegroundColor Cyan

if (-not (Get-Command helm -ErrorAction SilentlyContinue)) {
    Write-Error 'helm is not installed or not on PATH.'
}

# Render the chart with dynamic values injected.
# cache_password is set to empty because Azure Redis uses AAD-only auth (no access keys).
$rendered = helm template alwayson $baseDir `
    --set "parameters.silo.silo_image=$fullImage" `
    --set "secrets.silo.cache_password=" 2>&1

if ($LASTEXITCODE -ne 0) {
    Write-Error "Helm template failed: $rendered"
}

# Write rendered output and patch the service for internal LB
$outputDir = Join-Path $repoRoot "k8s\.rendered\$Environment"
if (Test-Path $outputDir) { Remove-Item $outputDir -Recurse -Force }
New-Item -ItemType Directory -Path $outputDir -Force | Out-Null

$renderedText = $rendered -join "`n"

# Split into individual documents, patch silo-service and silo-deployment
$documents = $renderedText -split '(?m)^---\s*$'
$docIndex = 0
foreach ($doc in $documents) {
    $trimmed = $doc.Trim()
    if (-not $trimmed) { continue }
    $docIndex++

    # Patch silo-config: add Cosmos endpoint, Redis, Event Grid, and remove stale connection strings
    if ($trimmed -match 'kind:\s*"ConfigMap"' -and $trimmed -match 'name:\s*"silo-config"') {
        # Remove the placeholder connection string and URI
        $trimmed = $trimmed -replace '(?m)^\s*ConnectionStrings__alwayson:.*$\n', ''
        $trimmed = $trimmed -replace '(?m)^\s*ALWAYSON_URI:.*$\n', ''
        # Add the Cosmos account endpoint for AAD auth
        $trimmed = $trimmed -replace '(ALWAYSON_DATABASENAME:.*)', "`$1`n  Orleans__Cosmos__AccountEndpoint: `"$cosmosEndpoint`""
        # Redis connection string for AAD-only auth (no password, SSL on port 6380)
        $trimmed = $trimmed -replace '(?m)^\s*ConnectionStrings__cache:.*$\n', ''
        $trimmed = $trimmed -replace '(Orleans__Cosmos__AccountEndpoint:.*)', "`$1`n  ConnectionStrings__cache: `"$($redisHostName):6380,ssl=True,abortConnect=False`""
        # Event Grid endpoint for pull-delivery messaging
        $trimmed = $trimmed -replace '(ConnectionStrings__cache:.*)', "`$1`n  ConnectionStrings__eventgrid: `"$eventGridEndpoint`""
    }

    # Patch silo-service: ClusterIP → public LoadBalancer bound to the pre-allocated PIP.
    # AFD reaches the origin via this fixed IP; the aks-system NSG blocks non-AFD traffic.
    if ($trimmed -match 'name:\s*"silo-service"' -and $trimmed -match 'type:\s*"ClusterIP"') {
        $trimmed = $trimmed -replace 'type:\s*"ClusterIP"', 'type: "LoadBalancer"'
        $annotations = @(
            '  annotations:'
            "    service.beta.kubernetes.io/azure-pip-name: `"$ingressPipName`""
            "    service.beta.kubernetes.io/azure-load-balancer-resource-group: `"$ingressPipResourceGroup`""
        ) -join "`n"
        # Inject annotations under metadata: of the silo-service document (idempotent — skip if already present).
        if ($trimmed -notmatch 'azure-pip-name') {
            $trimmed = $trimmed -replace '(metadata:\s*\n\s*name:\s*"silo-service"[^\n]*\n)', "`$1$annotations`n"
        }
    }

    # Patch silo-deployment: add serviceAccountName, workload identity label, and probes
    if ($trimmed -match 'kind:\s*"Deployment"' -and $trimmed -match 'name:\s*"silo-deployment"') {
        # Add workload identity label to pod template labels
        $trimmed = $trimmed -replace `
            '(app\.kubernetes\.io/instance:\s*"alwayson"\n\s*spec:\n\s*containers:)', `
            ('app.kubernetes.io/instance: "alwayson"' + "`n" + '        azure.workload.identity/use: "true"' + "`n" + '    spec:' + "`n" + '      serviceAccountName: "silo-sa"' + "`n" + '      containers:')

        # Add readiness and liveness probes to the first container
        $trimmed = $trimmed -replace `
            '(ports:\s*\n(\s*- containerPort: \d+\n)+)', `
            ("`$1" + '          readinessProbe:' + "`n" + '            httpGet:' + "`n" + '              path: /alive' + "`n" + '              port: 8080' + "`n" + '            initialDelaySeconds: 15' + "`n" + '            periodSeconds: 10' + "`n" + '          livenessProbe:' + "`n" + '            httpGet:' + "`n" + '              path: /alive' + "`n" + '              port: 8080' + "`n" + '            initialDelaySeconds: 15' + "`n" + '            periodSeconds: 30' + "`n")
    }

    Set-Content (Join-Path $outputDir "manifest-$docIndex.yaml") -Value $trimmed -Encoding utf8
}

Write-Host "  Rendered $docIndex manifest(s)"

# Apply all rendered manifests idempotently
kubectl apply -f $outputDir --recursive
if ($LASTEXITCODE -ne 0) { Write-Error 'kubectl apply failed.' }

# Patch silo-secrets with correct Azure service endpoints.
# The Aspire-generated secret uses in-cluster service names; we override with Azure endpoints.
# Using stringData so K8s handles base64 encoding automatically.
$redisConn = "$($redisHostName):6380,ssl=True,abortConnect=False"
$patchJson = @{ stringData = @{ ConnectionStrings__cache = $redisConn; ConnectionStrings__eventgrid = $eventGridEndpoint } } | ConvertTo-Json -Compress
kubectl patch secret silo-secrets --type=merge -p $patchJson
if ($LASTEXITCODE -ne 0) { Write-Error 'Failed to patch silo-secrets.' }

# Wait for the LoadBalancer external IP to be assigned
Write-Host "`nWaiting for silo-service external IP..." -ForegroundColor Cyan
$externalIp = $null
for ($i = 0; $i -lt 30; $i++) {
    $externalIp = kubectl get svc silo-service -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>$null
    if ($externalIp) { break }
    Start-Sleep -Seconds 10
}

Write-Host "`nDeployment complete." -ForegroundColor Green
Write-Host "  Image : $fullImage"
Write-Host "  Chart : $baseDir"
if ($externalIp) {
    Write-Host "  Silo LB IP: $externalIp" -ForegroundColor Yellow
    if ($ingressPipAddress -and $externalIp -ne $ingressPipAddress) {
        Write-Host "  WARNING: LB IP does not match the pre-allocated ingress PIP ($ingressPipAddress). Check service annotations." -ForegroundColor Red
    }
} else {
    Write-Host "  WARNING: Could not determine silo-service external IP. Check 'kubectl get svc silo-service'." -ForegroundColor Red
}
