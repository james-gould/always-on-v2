<#
.SYNOPSIS
    Publishes or deploys the Aspire AppHost for AlwaysOn.

.DESCRIPTION
    Uses the Aspire AppHost as the source of truth for generated infrastructure and
    deployment artifacts. This replaces the hand-authored Bicep deployment flow for
    the current Aspire-based topology.

.PARAMETER ResourceGroup
    Azure resource group name used by aspire deploy.

.PARAMETER Location
    Azure region used by aspire deploy.

.PARAMETER SubscriptionId
    Azure subscription ID used by aspire deploy.

.PARAMETER PublishOnly
    Generates publish artifacts without deploying them.

.PARAMETER OutputPath
    Output path for publish artifacts. Defaults to artifacts/aspire.

.EXAMPLE
    .\Deploy-AppHost.ps1 -ResourceGroup rg-alwayson-dev -Location uksouth

.EXAMPLE
    .\Deploy-AppHost.ps1 -PublishOnly
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$ResourceGroup = 'rg-alwayson-dev',

    [Parameter()]
    [string]$Location = 'uksouth',

    [Parameter()]
    [string]$SubscriptionId,

    [Parameter()]
    [switch]$PublishOnly,

    [Parameter()]
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path "$PSScriptRoot\..").Path
$appHostDir = Join-Path $repoRoot 'dev\AlwaysOn.AppHost'
$publishOutput = if ($OutputPath) { $OutputPath } else { Join-Path $repoRoot 'artifacts\aspire' }

if (-not (Get-Command aspire -ErrorAction SilentlyContinue)) {
    Write-Error 'The Aspire CLI is not installed or not on PATH. Install it from https://aspire.dev/get-started/install-cli/.'
}

if (-not (Test-Path $appHostDir)) {
    Write-Error "AppHost directory not found: $appHostDir"
}

if (-not $PublishOnly) {
    if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
        Write-Error 'Azure CLI (az) is not installed or not on PATH.'
    }

    $account = az account show --output json 2>$null | ConvertFrom-Json
    if (-not $account) {
        Write-Error 'Not logged in. Run "az login" first.'
    }
}

$previousSubscriptionId = $env:Azure__SubscriptionId
$previousLocation = $env:Azure__Location
$previousResourceGroup = $env:Azure__ResourceGroup

try {
    if ($PSBoundParameters.ContainsKey('SubscriptionId')) {
        $env:Azure__SubscriptionId = $SubscriptionId
    }

    $env:Azure__Location = $Location
    $env:Azure__ResourceGroup = $ResourceGroup

    Push-Location $appHostDir

    if ($PublishOnly) {
        Write-Host "Publishing Aspire artifacts to '$publishOutput'..." -ForegroundColor Cyan
        aspire publish -o $publishOutput
    }
    else {
        Write-Host "Deploying Aspire AppHost from '$appHostDir'..." -ForegroundColor Cyan
        aspire deploy
    }

    if ($LASTEXITCODE -ne 0) {
        throw 'Aspire command failed.'
    }
}
finally {
    Pop-Location

    $env:Azure__SubscriptionId = $previousSubscriptionId
    $env:Azure__Location = $previousLocation
    $env:Azure__ResourceGroup = $previousResourceGroup
}
