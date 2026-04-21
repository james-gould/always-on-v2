# GitHub Actions OIDC Authentication

## Overview

The GitHub Actions workflows authenticate to Azure using **OpenID Connect (OIDC)** federation — no secrets or passwords are stored. GitHub issues a short-lived JWT on each workflow run, and Azure AD validates it against pre-configured federated identity credentials on the app registration.

## App Registration

| Property | Value |
|---|---|
| Display name | `always-on-v2` |
| Application (client) ID | `75a8cefc-6884-4cac-942d-3e76f6d5edde` |
| Service principal object ID | `0d0bbee7-6b9b-4e41-99de-9fa35bd32c23` |

## Federated Identity Credentials

Three credentials are configured to cover every trigger path in the workflows:

| Name | Subject | Purpose |
|---|---|---|
| `github-environment-dev` | `repo:james-gould/always-on-v2:environment:dev` | Jobs that declare `environment: dev` (deploy-infra, deploy-app, purge) |
| `github-branch-master` | `repo:james-gould/always-on-v2:ref:refs/heads/master` | Jobs on `master` push without a GitHub environment (validate-infra) |
| `github-pull-request` | `repo:james-gould/always-on-v2:pull_request` | Jobs triggered by pull requests (validate-infra on PR) |

All three use:
- **Issuer**: `https://token.actions.githubusercontent.com`
- **Audience**: `api://AzureADTokenExchange`

### Why three credentials?

GitHub's OIDC token `sub` claim varies depending on the trigger and whether the job uses a GitHub environment:

- A job with `environment: dev` produces `repo:<owner>/<repo>:environment:dev`
- A push to `master` without an environment produces `repo:<owner>/<repo>:ref:refs/heads/master`
- A PR produces `repo:<owner>/<repo>:pull_request`

Azure AD matches the `sub` claim exactly, so each variant needs its own credential.

### Adding a new environment (e.g. staging)

```bash
az ad app federated-credential create \
  --id 75a8cefc-6884-4cac-942d-3e76f6d5edde \
  --parameters '{
    "name": "github-environment-staging",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:james-gould/always-on-v2:environment:staging",
    "audiences": ["api://AzureADTokenExchange"],
    "description": "GitHub Actions - staging environment"
  }'
```

## RBAC Role Assignments

The service principal has two roles at the subscription scope:

| Role | Scope | Why |
|---|---|---|
| **Contributor** | `/subscriptions/2b4c73d5-769b-4b2f-9f5f-420c55fdee99` | Create/delete resource groups, deploy Bicep templates, access AKS credentials, push to ACR |
| **User Access Administrator** | `/subscriptions/2b4c73d5-769b-4b2f-9f5f-420c55fdee99` | Create role assignments defined in Bicep (Key Vault RBAC, AcrPull, Cosmos data contributor) |

Without **Contributor**, the OIDC login succeeds but `az` returns "no subscriptions found".
Without **User Access Administrator**, Bicep deployments fail on `Microsoft.Authorization/roleAssignments/write`.

## Required GitHub Repository Secrets

Set these in **Settings > Secrets and variables > Actions**:

| Secret | Value |
|---|---|
| `AZURE_CLIENT_ID` | `75a8cefc-6884-4cac-942d-3e76f6d5edde` |
| `AZURE_TENANT_ID` | *(your Azure AD tenant ID)* |
| `AZURE_SUBSCRIPTION_ID` | `2b4c73d5-769b-4b2f-9f5f-420c55fdee99` |

## Troubleshooting

| Error | Cause | Fix |
|---|---|---|
| `no configured federated identity credentials` | App registration has no FIC, or the FIC subject doesn't match the token's `sub` claim | Check the repo name (including hyphens/casing) and trigger type match a configured FIC |
| `No matching federated identity record found for presented assertion subject '...'` | The `sub` claim in the error message doesn't match any FIC | Create a new FIC with the exact subject shown in the error |
| `No subscriptions found for '***'` | SP authenticated but has no RBAC role on the subscription | Assign Contributor (or a scoped role) to the SP |
