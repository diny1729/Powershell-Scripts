<#
.SYNOPSIS
    Adds a new user node pool and migrates workloads from an old node pool.

.NOTES
    Prerequisites: Azure PowerShell (Az module) and kubectl installed/authenticated.
#>

# --- Configuration ---
$ResourceGroupName = "<REDACTED>"       # Change to your resource group name
$ClusterName = "<REDACTED>"  # Change to your AKS cluster name
$OldPoolName = "userpool"                   # Change to your current system pool name
$NewPoolName = "usernewpool"                    # Name for the new D4s_v5 pool
$NewVmSize   = "Standard_D4as_v5"
$NodeCount   = 2
#$MinNodeCount = 1
#$MaxNodeCount = 10
$MaxPodCount = 110
$poolmode = "User" # Set to "System" if you want the new pool to be a system node pool
$AvailabilityZones = 2 # Specify the availability zones for the new node pool as a list, e.g., 1, 2, 3
$LogFile = "AKS_Migration_$(Get-Date -Format 'yyyyMMdd_HHmm').log"

# --- Logging Function ---
function Write-Log {
    param([string]$Message)
    $TimeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogEntry = "[$TimeStamp] $Message"
    Write-Host $LogEntry -ForegroundColor Cyan
    $LogEntry | Out-File -FilePath $LogFile -Append
}

Write-Log "Starting Migration: $OldPoolName (D2s_v5) -> $NewPoolName ($NewVmSize)"

try {

    # 1. Check for and create the new Node Pool if it doesn't exist
    Write-Log "Step 1: Checking for node pool '$NewPoolName'..."
    az aks nodepool show --resource-group $ResourceGroupName --cluster-name $ClusterName --name $NewPoolName -o none 2>$null

    if ($LASTEXITCODE -ne 0) { # If pool does not exist
        Write-Log "Node pool '$NewPoolName' does not exist."
        $currentContext = kubectl config current-context
        $confirmation = Read-Host "Do you want to create the new node pool '$NewPoolName' on cluster '$currentContext'? [Y/N]"
        if ($confirmation -match '^[Yy]$') {
            Write-Log "Step 1: Creating new node pool '$NewPoolName' with VM size $NewVmSize..."
            az aks nodepool add `
                --resource-group $ResourceGroupName `
                --cluster-name $ClusterName `
                --name $NewPoolName `
                --node-vm-size $NewVmSize `
                --mode $poolmode `
                --node-count $NodeCount `
                --max-pods $MaxPodCount
                #--zones $AvailabilityZones

            if ($LASTEXITCODE -ne 0) {
                Write-Log "ERROR: Failed to create node pool '$NewPoolName'. Aborting script."
                return
            }
        }
        else {
            Write-Log "Creation of node pool '$NewPoolName' skipped by user. Aborting migration as the target pool is required."
            return
        }
    } else {
        Write-Log "Step 1: Node pool '$NewPoolName' already exists. Skipping creation."
    }

    # 2 & 3. Cordon and Drain old nodes
    $currentContext = kubectl config current-context
    $confirmation = Read-Host "Do you want to proceed with Cordon & Drain for '$OldPoolName' on cluster '$currentContext'? [Y/N]"
    if ($confirmation -match '^[Yy]$') {
        Write-Log "Step 2: Identifying nodes in '$OldPoolName'..."
        $oldNodes = kubectl get nodes -l "agentpool=$OldPoolName" -o name

        if (-not $oldNodes) {
            Write-Log "Step 2: No nodes found in '$OldPoolName'. Skipping cordon and drain."
        }
        else {
            foreach ($node in $oldNodes) {
                Write-Log "Cordoning $node..."
                kubectl cordon $node

                Write-Log "Draining $node (moving pods to $NewPoolName)..."
                kubectl drain $node --ignore-daemonsets --delete-emptydir-data --force --grace-period=60
            }
        }
    }
    else {
        Write-Log "Step 2 & 3: Cordon/Drain skipped by user. Aborting script to prevent data loss. Please manually migrate workloads before deleting '$OldPoolName'."
        return
    }

    # 4. Verification
    Write-Log "Step 4: Verifying pods are running on the new node pool '$NewPoolName'..."
    kubectl get pods -A -o wide | Select-String $NewPoolName | Out-File -FilePath $LogFile -Append

    # 5. Delete the old Node Pool
    $confirmation = Read-Host "Do you want to DELETE the old node pool '$OldPoolName' from cluster '$currentContext'? This is irreversible. [Y/N]"
    if ($confirmation -match '^[Yy]$') {
        Write-Log "Step 5: Deleting the old node pool '$OldPoolName'..."
        az aks nodepool delete `
            --resource-group $ResourceGroupName `
            --cluster-name $ClusterName `
            --name $OldPoolName
    }
    else {
        Write-Log "Step 5: Deletion of old node pool '$OldPoolName' skipped by user."
    }

    Write-Log "SUCCESS: Migration script finished. Cluster is now running on $NewVmSize."
}
catch {
    Write-Log "ERROR: Migration failed. Check logs. Details: $_"
}








