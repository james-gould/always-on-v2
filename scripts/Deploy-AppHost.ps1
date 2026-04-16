<#
.SYNOPSIS
    Publishes Aspire Kubernetes manifests for AlwaysOn and optionally applies them to AKS.

.DESCRIPTION
    Uses the Aspire AppHost as the source of truth for generated Kubernetes manifests.
    In an AKS workflow, infrastructure provisioning remains managed by infra/main.bicep.
    Typical pipeline order is:
      1) aspire publish (generate manifests)
      2) infra deploy (AKS/Cosmos/KeyVault/network)
      3) kubectl apply (deploy workloads)

.PARAMETER PublishOnly
    Generates Kubernetes manifest artifacts and does not apply them.

.PARAMETER OutputPath
    Output path for publish artifacts. Defaults to artifacts/aspire.

.PARAMETER ApplyToCluster
    Applies published manifests to the current kubectl context.

.PARAMETER KubeContext
    Optional kubectl context name to target when applying manifests.

.EXAMPLE
    .\Deploy-AppHost.ps1

.EXAMPLE
    .\Deploy-AppHost.ps1 -PublishOnly

.EXAMPLE
    .\Deploy-AppHost.ps1 -ApplyToCluster -KubeContext alwayson-dev
#>

[CmdletBinding()]
param(
    [Parameter()]
    [switch]$PublishOnly,

    [Parameter()]
    [string]$OutputPath,

    [Parameter()]
    [switch]$ApplyToCluster,

    [Parameter()]
    [string]$KubeContext
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

if ($ApplyToCluster -and -not (Get-Command kubectl -ErrorAction SilentlyContinue)) {
    Write-Error 'kubectl is not installed or not on PATH.'
}

try {
    Push-Location $appHostDir

    Write-Host "Publishing Aspire Kubernetes artifacts to '$publishOutput'..." -ForegroundColor Cyan
    aspire publish -o $publishOutput

    if ($LASTEXITCODE -ne 0) {
        throw 'Aspire publish failed.'
    }

    if ($PublishOnly) {
        return
    }

    if ($ApplyToCluster) {
        $manifestFiles = Get-ChildItem -Path $publishOutput -Recurse -File -Include *.yaml, *.yml
        if (-not $manifestFiles) {
            Write-Error "No Kubernetes manifest files were found under: $publishOutput"
        }

        if ($KubeContext) {
            kubectl config use-context $KubeContext | Out-Null
            if ($LASTEXITCODE -ne 0) {
                throw "Failed to switch kubectl context to '$KubeContext'."
            }
        }

        Write-Host "Applying manifests from '$publishOutput'..." -ForegroundColor Cyan
        foreach ($manifestFile in $manifestFiles) {
            kubectl apply -f $manifestFile.FullName
            if ($LASTEXITCODE -ne 0) {
                throw "kubectl apply failed for '$($manifestFile.FullName)'."
            }
        }
    }
}
finally {
    Pop-Location
}
