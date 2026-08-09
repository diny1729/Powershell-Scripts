<#
.SYNOPSIS
    Downloads and merges Kubernetes credentials for all Azure Kubernetes Service (AKS) clusters in the current subscription.

.DESCRIPTION
    This script queries the active Azure CLI subscription for all deployed AKS clusters, iterates through the list, 
    and automatically downloads/merges cluster access credentials into the local Kubeconfig context.

.NOTES
    Prerequisites:
    - Azure CLI (`az`) installed and authenticated via `az login`.
    - `kubectl` installed to manage cluster contexts.
#>

# Check tool prerequisites
if (-not (Get-Command "az" -ErrorAction SilentlyContinue)) {
    Write-Error "Azure CLI ('az') is not installed or available in PATH. Please install Azure CLI."
    exit 1
}

# 1. Ensure user is logged into Azure CLI
$azAccount = az account show --query "user.name" --output tsv 2>$null
if ($null -eq $azAccount) {
    Write-Host "[AUTH] Not logged in. Please run az login first." -ForegroundColor Red
    exit 1
}

# 2. Retrieve active Azure Subscription details
$subId = az account show --query "id" --output tsv
$subName = az account show --query "name" --output tsv

Write-Host "[SUBSCRIPTION] Target Subscription: $subName ($subId)" -ForegroundColor Cyan
Write-Host "[SEARCH] Searching for AKS clusters..." -ForegroundColor Gray

# 3. Query all AKS clusters in the subscription (Returns JSON object array with cluster name and Resource Group)
$clusters = az aks list --query '[].{name:name, rg:resourceGroup}' --output json | ConvertFrom-Json

if ($clusters.Count -eq 0) {
    Write-Warning "No AKS clusters found in this subscription."
    exit 0
}

Write-Host "[SUCCESS] Found $($clusters.Count) cluster(s). Starting credential download..." -ForegroundColor Green
Write-Host ""

# 4. Iterate through each cluster and fetch/merge access credentials into local kubeconfig
foreach ($cluster in $clusters) {
    Write-Host "[INFO] [Cluster: $($cluster.name)] in [RG: $($cluster.rg)]" -ForegroundColor Yellow
    
    # --overwrite-existing merges/updates the cluster context locally
    az aks get-credentials --resource-group $cluster.rg --name $cluster.name --overwrite-existing
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "   Done." -ForegroundColor Green
    } else {
        Write-Host "   [ERROR] Failed to fetch credentials for cluster $($cluster.name)." -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "[COMPLETE] All credentials merged! Run kubectl config get-contexts to view available cluster contexts." -ForegroundColor Cyan