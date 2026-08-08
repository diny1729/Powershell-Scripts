# 1. Ensure you are logged in
$azAccount = az account show --query "user.name" --output tsv 2>$null
if ($null -eq $azAccount) {
    Write-Host "🔐 Not logged in. Please run 'az login' first." -ForegroundColor Red
    exit
}

# 2. Get the current Subscription ID and Name
$subId = az account show --query "id" --output tsv
$subName = az account show --query "name" --output tsv

Write-Host "📂 Target Subscription: $subName ($subId)" -ForegroundColor Cyan
Write-Host "🔎 Searching for AKS clusters..." -ForegroundColor Gray

# 3. Get all clusters in the subscription (Returns Name and Resource Group)
$clusters = az aks list --query "[].{name:name, rg:resourceGroup}" --output json | ConvertFrom-Json

if ($clusters.Count -eq 0) {
    Write-Warning "No AKS clusters found in this subscription."
    exit
}

Write-Host "✅ Found $($clusters.Count) cluster(s). Starting download...`n" -ForegroundColor Green

# 4. Loop through and fetch credentials
foreach ($cluster in $clusters) {
    Write-Host "⏳ [Cluster: $($cluster.name)] in [RG: $($cluster.rg)]" -ForegroundColor Yellow
    
    # --overwrite-existing updates the token/context if it already exists locally
    az aks get-credentials --resource-group $cluster.rg --name $cluster.name --overwrite-existing
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "   Done." -ForegroundColor Green
    } else {
        Write-Host "   ❌ Failed to fetch credentials." -ForegroundColor Red
    }
}

Write-Host "`n🚀 All credentials merged! Run 'kubectl config get-contexts' to see them all." -ForegroundColor Cyan