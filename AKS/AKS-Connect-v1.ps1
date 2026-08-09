<#
.SYNOPSIS
    Interactive CLI tool for connecting to AKS clusters and downloading cluster credentials.

.DESCRIPTION
    Provides an interactive menu system to batch download AKS cluster credentials from Azure CLI into 
    separate environment configuration files (Non-prod / Prod), switch cluster contexts, set active 
    namespaces, and execute kubelogin conversions for Azure AD integrated clusters.

.NOTES
    Prerequisites:
    - Azure CLI (`az`) logged in (`az login`) when downloading credentials.
    - `kubectl` installed and added to PATH.
    - `kubelogin` binary installed for Azure AD token-based cluster authentication.
#>

# --- SETUP DIRECTORY ---
$kubeDir = "$HOME\.kube"
if (-not (Test-Path $kubeDir)) {
    New-Item -ItemType Directory -Path $kubeDir | Out-Null
}

# --- STEP 0: SELECT ACTION ---
Write-Host "=== AKS Cluster Management ===" -ForegroundColor Cyan
Write-Host "1. Connect to existing cluster"
Write-Host "2. Download cluster credential(s) from Azure"
$actionChoice = Read-Host "Select an option (1 or 2)"

if ($actionChoice -ne "1" -and $actionChoice -ne "2") {
    Write-Host "Invalid option. Exiting." -ForegroundColor Red
    exit 1
}

# --- STEP 1: SELECT ENVIRONMENT ---
Write-Host "`n--- Select Environment ---" -ForegroundColor Yellow
Write-Host "1. Non-prod"
Write-Host "2. Prod"
$envChoice = Read-Host "Select environment (1 or 2)"

$envName = ""
$selectedFile = ""

if ($envChoice -eq "1") {
    $envName = "Non-prod"
    $selectedFile = Join-Path $kubeDir "config-nonprod"
}
elseif ($envChoice -eq "2") {
    $envName = "Prod"
    $selectedFile = Join-Path $kubeDir "config-prod"
}
else {
    Write-Host "Invalid environment. Exiting." -ForegroundColor Red
    exit 1
}

Write-Host "Selected Environment: $envName ($selectedFile)" -ForegroundColor Green

# --- STEP 2: DOWNLOAD CREDENTIALS (BATCH / MULTI-SELECT) ---
if ($actionChoice -eq "2") {
    Write-Host "`n--- Fetching AKS Clusters from Azure ---" -ForegroundColor Yellow
    
    # Check Azure CLI authentication
    $azAccount = az account show --query "user.name" --output tsv 2>$null
    if (-not $azAccount) {
        Write-Host "Error: Not logged into Azure CLI. Run 'az login' first." -ForegroundColor Red
        exit 1
    }

    Write-Host "Logged in as: $azAccount" -ForegroundColor Gray
    Write-Host "Retrieving clusters from active Azure subscription..." -ForegroundColor Gray
    $clustersJson = az aks list --output json | ConvertFrom-Json

    if (-not $clustersJson -or $clustersJson.Count -eq 0) {
        Write-Host "No AKS clusters found in this Azure account." -ForegroundColor Red
        exit 1
    }

    Write-Host "`n--- Available AKS Clusters ---" -ForegroundColor Yellow

    # Build structured custom object list
    $clusterTable = foreach ($i in 0..($clustersJson.Count - 1)) {
        [PSCustomObject]@{
            'Index'          = $i + 1
            'Cluster Name'   = $clustersJson[$i].name
            'Resource Group' = $clustersJson[$i].resourceGroup
            'Location'       = $clustersJson[$i].location
        }
    }

    # Render proper aligned table
    $clusterTable | Format-Table -AutoSize

    Write-Host "Selection Format Examples: '1,3,4' | '1-3' | 'all'" -ForegroundColor Cyan
    $clusterInput = Read-Host "Select cluster numbers to download"

    # Parse multi-select inputs
    $selectedIndices = @()

    if ($clusterInput.Trim().ToLower() -eq 'all') {
        $selectedIndices = 0..($clustersJson.Count - 1)
    }
    else {
        $parts = $clusterInput -split '[, ]+' | Where-Object { $_ -and $_.Trim() -ne "" }
        foreach ($part in $parts) {
            if ($part -match '^\d+-\d+$') {
                $range = $part -split '-'
                $start = [int]$range[0]
                $end = [int]$range[1]
                if ($start -ge 1 -and $end -le $clustersJson.Count -and $start -le $end) {
                    $selectedIndices += ($start..$end | ForEach-Object { $_ - 1 })
                }
            }
            else {
                # Pre-declare $val to prevent [ref] runtime errors
                $val = 0
                if ([int]::TryParse($part, [ref]$val)) {
                    if ($val -ge 1 -and $val -le $clustersJson.Count) {
                        $selectedIndices += ($val - 1)
                    }
                }
            }
        }
        $selectedIndices = $selectedIndices | Select-Object -Unique
    }

    if ($selectedIndices.Count -eq 0) {
        Write-Host "No valid cluster selections made. Exiting." -ForegroundColor Red
        exit 1
    }

    # Batch download loop
    Write-Host "`nStarting batch download for $($selectedIndices.Count) cluster(s)..." -ForegroundColor Green
    foreach ($idx in $selectedIndices) {
        $targetCluster = $clustersJson[$idx]
        Write-Host "⏳ Fetching credentials for [$($targetCluster.name)] in RG [$($targetCluster.resourceGroup)]..." -ForegroundColor Yellow
        
        az aks get-credentials --resource-group $targetCluster.resourceGroup --name $targetCluster.name --file "$selectedFile" --overwrite-existing | Out-Null

        if ($LASTEXITCODE -eq 0) {
            Write-Host "   ✅ Merged into $selectedFile" -ForegroundColor Green
        } else {
            Write-Host "   ❌ Failed to fetch credentials for $($targetCluster.name)" -ForegroundColor Red
        }
    }
    Write-Host "Batch credential update complete." -ForegroundColor Green
}

# --- STEP 3: SET KUBECONFIG AND SELECT CONTEXT ---
if (-not (Test-Path $selectedFile)) {
    Write-Host "Config file '$selectedFile' does not exist. Please download credentials first." -ForegroundColor Red
    exit 1
}

$env:KUBECONFIG = $selectedFile
Write-Host "`nTarget Config Set: $selectedFile" -ForegroundColor Green

$contexts = @((kubectl config get-contexts -o name) -split "`r?`n" | Where-Object { $_ -and $_.Trim() -ne "" })

if ($contexts.Count -eq 0) {
    Write-Host "No contexts found in $selectedFile." -ForegroundColor Red
    exit 1
}

$selectedContext = $null
if ($contexts.Count -eq 1) {
    $selectedContext = $contexts[0]
    kubectl config use-context $selectedContext
    Write-Host "Auto-selected single context: $selectedContext" -ForegroundColor Cyan
}
else {
    Write-Host "`n--- Available Contexts ($envName) ---" -ForegroundColor Yellow
    
    $contextTable = foreach ($i in 0..($contexts.Count - 1)) {
        [PSCustomObject]@{
            'Index'   = $i + 1
            'Context' = $contexts[$i]
        }
    }
    $contextTable | Format-Table -AutoSize

    $contextInput = Read-Host "Enter the number of the context to connect to"
    $cIndex = 0
    if (-not [int]::TryParse($contextInput, [ref]$cIndex) -or $cIndex -lt 1 -or $cIndex -gt $contexts.Count) {
        Write-Host "Invalid selection. Exiting." -ForegroundColor Red
        exit 1
    }
    $selectedContext = $contexts[$cIndex - 1]
    kubectl config use-context $selectedContext
}

# --- STEP 4: SELECT NAMESPACE ---
$useNamespace = Read-Host "`nDo you want to set a specific default namespace? (y/n)"
if ($useNamespace -eq 'y') {
    Write-Host "Fetching namespaces..." -ForegroundColor Gray
    $namespaces = @((kubectl get namespaces -o name) -split "`r?`n" | ForEach-Object { $_.Replace("namespace/", "") } | Where-Object { $_ })
    
    if ($namespaces.Count -gt 0) {
        Write-Host "`n--- Available Namespaces ---" -ForegroundColor Yellow
        
        $nsTable = foreach ($i in 0..($namespaces.Count - 1)) {
            [PSCustomObject]@{
                'Index'     = $i + 1
                'Namespace' = $namespaces[$i]
            }
        }
        $nsTable | Format-Table -AutoSize
        
        $nsInput = Read-Host "Select the number for the namespace"
        $nsIndex = 0
        if ([int]::TryParse($nsInput, [ref]$nsIndex) -and $nsIndex -ge 1 -and $nsIndex -le $namespaces.Count) {
            $selectedNS = $namespaces[$nsIndex - 1]
            kubectl config set-context --current --namespace=$selectedNS
            Write-Host "Default namespace set to: $selectedNS" -ForegroundColor Green
        } else {
            Write-Host "Invalid selection. Skipping namespace set." -ForegroundColor Yellow
        }
    }
}

# --- STEP 5: MONITORING CLUSTER SPECIAL LOGIC ---
if ($selectedContext -eq "<REDACTED>") {
    Write-Host "`nMonitoring cluster detected. Running kubelogin conversion..." -ForegroundColor Cyan
    if (Get-Command "kubelogin" -ErrorAction SilentlyContinue) {
        kubelogin convert-kubeconfig -l azurecli --kubeconfig "$selectedFile"
        Write-Host "Kubelogin conversion complete." -ForegroundColor Green
    }
    else {
        Write-Host "Error: 'kubelogin' command not found." -ForegroundColor Red
    }
}

Write-Host "`nDone! Connected to $selectedContext ($($selectedFile | Split-Path -Leaf))" -ForegroundColor Magenta