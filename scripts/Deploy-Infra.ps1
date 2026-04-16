<#
.SYNOPSIS
    Legacy Bicep deployment script for AlwaysOn infrastructure.

.DESCRIPTION
    This script deploys the hand-authored Bicep templates under infra/. The current
        preferred AKS deployment pipeline is:
            1) scripts/Deploy-AppHost.ps1 (aspire publish)
            2) scripts/Deploy-Infra.ps1 (provision AKS/Cosmos/KeyVault/network)
            3) scripts/Deploy-AppHost.ps1 -ApplyToCluster (kubectl apply)

.PARAMETER Environment
    Target environment. Must be 'dev' or 'staging'.

.PARAMETER Location
    Azure region for the resource group. Defaults to 'uksouth'.

.PARAMETER DryRun
    Runs a what-if preview without deploying any resources.

.EXAMPLE
    .\Deploy-Infra.ps1 -Environment dev
    .\Deploy-Infra.ps1 -Environment staging -Location northeurope
    .\Deploy-Infra.ps1 -Environment dev -DryRun
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('dev', 'staging')]
    [string]$Environment,

    [Parameter()]
    [string]$Location = 'uksouth',

    [Parameter()]
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path "$PSScriptRoot\..").Path
$templateFile = Join-Path $repoRoot 'infra' 'main.bicep'
$paramsFile = Join-Path $repoRoot 'infra' "main.bicepparam.$Environment.json"
$resourceGroup = "rg-alwayson-$Environment"

# Validate prerequisites
if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    Write-Error 'Azure CLI (az) is not installed or not on PATH.'
}

$account = az account show --output json 2>$null | ConvertFrom-Json
if (-not $account) {
    Write-Error 'Not logged in. Run "az login" first.'
}

Write-Host "Subscription : $($account.name) ($($account.id))" -ForegroundColor Cyan
Write-Host "Environment  : $Environment" -ForegroundColor Cyan
Write-Host "Location     : $Location" -ForegroundColor Cyan
Write-Host "Resource Group: $resourceGroup" -ForegroundColor Cyan

if (-not (Test-Path $paramsFile)) {
    Write-Error "Parameter file not found: $paramsFile"
}

# Ensure resource group exists
$rgExists = az group exists --name $resourceGroup --output tsv
if ($rgExists -ne 'true') {
    Write-Host "Creating resource group '$resourceGroup' in '$Location'..." -ForegroundColor Yellow
    az group create --name $resourceGroup --location $Location --output none
    if ($LASTEXITCODE -ne 0) { Write-Error 'Failed to create resource group.' }
}

# Deploy or what-if
if ($DryRun) {
    Write-Host "`nRunning what-if (no resources will be modified)...`n" -ForegroundColor Yellow
    az deployment group what-if `
        --resource-group $resourceGroup `
        --template-file $templateFile `
        --parameters "@$paramsFile"
} else {
    Write-Host "`nDeploying infrastructure...`n" -ForegroundColor Green
    az deployment group create `
        --resource-group $resourceGroup `
        --template-file $templateFile `
        --parameters "@$paramsFile" `
        --output table
}

if ($LASTEXITCODE -ne 0) {
    Write-Error 'Deployment failed.'
} else {
    $action = if ($DryRun) { 'What-if' } else { 'Deployment' }
    Write-Host "`n$action completed successfully." -ForegroundColor Green
}
