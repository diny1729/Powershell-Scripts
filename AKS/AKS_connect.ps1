# --- STEP 0: SELECT KUBECONFIG FILE ---
$kubeDir = "$HOME\.kube"
$configFiles = Get-ChildItem -Path $kubeDir -File | Where-Object { $_.Name -like "*config*" -or $_.Extension -eq ".yaml" }

if ($configFiles.Count -eq 0) {
    Write-Host "No kubeconfig files found in $kubeDir." -ForegroundColor Red
    exit 1
}

$selectedFile = $null
if ($configFiles.Count -eq 1) {
    $selectedFile = $configFiles[0].FullName
    Write-Host "Only one config file found: $($configFiles[0].Name)" -ForegroundColor Cyan
}
else {
    Write-Host "`n--- Available Kubeconfig Files ---" -ForegroundColor Yellow
    for ($i = 0; $i -lt $configFiles.Count; $i++) {
        Write-Host ("{0}. {1}" -f ($i + 1), $configFiles[$i].Name)
    }
    $fileInput = Read-Host "Select the number for the config file you want to use"
    $fIndex = 0 
    if (-not [int]::TryParse($fileInput, [ref]$fIndex) -or $fIndex -lt 1 -or $fIndex -gt $configFiles.Count) {
        Write-Host "Invalid file selection. Exiting." -ForegroundColor Red
        exit 1
    }
    $selectedFile = $configFiles[$fIndex - 1].FullName
}

$env:KUBECONFIG = $selectedFile
Write-Host "`nTarget Config Set: $selectedFile" -ForegroundColor Green

# --- STEP 1: SELECT CONTEXT ---
$contexts = @((kubectl config get-contexts -o name) -split "`r?`n" | Where-Object { $_ -and $_.Trim() -ne "" })

if ($contexts.Count -eq 0) {
    Write-Host "No contexts found in this file." -ForegroundColor Red
    exit 1
}

$selectedContext = $null
if ($contexts.Count -eq 1) {
    $selectedContext = $contexts[0]
    kubectl config use-context $selectedContext
}
else {
    Write-Host "`n--- Available AKS Cluster Contexts ---" -ForegroundColor Yellow
    for ($i = 0; $i -lt $contexts.Count; $i++) {
        Write-Host ("{0}. {1}" -f ($i + 1), $contexts[$i])
    }
    $contextInput = Read-Host "Enter the number of the context to connect to"
    $cIndex = 0
    if (-not [int]::TryParse($contextInput, [ref]$cIndex) -or $cIndex -lt 1 -or $cIndex -gt $contexts.Count) {
        Write-Host "Invalid selection. Exiting." -ForegroundColor Red
        exit 1
    }
    $selectedContext = $contexts[$cIndex - 1]
    kubectl config use-context $selectedContext
}

# --- STEP 1.5: SELECT NAMESPACE (NEW) ---
$useNamespace = Read-Host "`nDo you want to set a specific default namespace? (y/n)"
if ($useNamespace -eq 'y') {
    Write-Host "Fetching namespaces..." -ForegroundColor Gray
    $namespaces = @((kubectl get namespaces -o name) -split "`r?`n" | ForEach-Object { $_.Replace("namespace/", "") } | Where-Object { $_ })
    
    if ($namespaces.Count -gt 0) {
        Write-Host "`n--- Available Namespaces ---" -ForegroundColor Yellow
        for ($i = 0; $i -lt $namespaces.Count; $i++) {
            Write-Host ("{0}. {1}" -f ($i + 1), $namespaces[$i])
        }
        
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

# --- STEP 2: SPECIAL LOGIC FOR MONITORING CLUSTER ---
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
