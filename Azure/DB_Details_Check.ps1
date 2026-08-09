<#
.SYNOPSIS
    Queries and displays compute configuration details for databases on selected Azure SQL Servers.

.DESCRIPTION
    Enumerates all Azure SQL Servers in the active subscription, presents a numbered selection menu, 
    evaluates database compute models (DTU / Serverless / Provisioned vCore), editions, SKUs, maximum storage size, 
    zone redundancy, and backup redundancy, formatting the results into a clean console table.

.NOTES
    Prerequisites:
    - Azure PowerShell module `Az.Sql`.
    - Authenticated Azure session (`Connect-AzAccount`).
#>

#Requires -Module Az.Sql

# Get all SQL servers in subscription
$allServers = Get-AzSqlServer

# Check if any servers were found
if ($allServers.Count -eq 0) {
    Write-Warning "No SQL Servers found in the current subscription."
    return
}

# Display a numbered menu for the user to select a server
Write-Host "Available SQL Servers:" -ForegroundColor Cyan
for ($i = 0; $i -lt $allServers.Count; $i++) {
    Write-Host "[$($i + 1)] $($allServers[$i].ServerName) (Resource Group: $($allServers[$i].ResourceGroupName))"
}

# Prompt user for selection
$choice = Read-Host "`nEnter the number of the server you want to process"

# Validate input
$selectedIndex = [int]$choice - 1
if ($selectedIndex -lt 0 -or $selectedIndex -ge $allServers.Count) {
    Write-Warning "Invalid selection. Exiting script."
    return
}

# Filter down to the single selected server
$selectedServer = $allServers[$selectedIndex]
$serversToProcess = @($selectedServer)

$dbInfo = @()

# Process only the selected server
foreach ($server in $serversToProcess) {

    $serverName = $server.ServerName
    $resourceGroupName = $server.ResourceGroupName

    Write-Host "`nProcessing Server: $serverName" -ForegroundColor Green

    $databases = Get-AzSqlDatabase `
        -ResourceGroupName $resourceGroupName `
        -ServerName $serverName

    foreach ($db in $databases) {

        # Compute model (DTU / vCore / Serverless)
        $computeModel = if ($db.Sku.Tier -in @("Basic","Standard","Premium")) {
            "DTU"
        }
        elseif ($db.ComputeModel -eq "Serverless") {
            "Serverless"
        }
        else {
            "Provisioned (vCore)"
        }

        $dbInfo += [PSCustomObject]@{
            ServerName        = $serverName
            DatabaseName      = $db.DatabaseName
            Edition           = $db.Edition                      # Basic / Standard / GeneralPurpose / BusinessCritical / Hyperscale
            ServiceTier       = $db.Sku.Tier                     # GP / BC / HS / etc.
            ComputeModel      = $computeModel                    # DTU / Serverless / Provisioned
            SKU               = $db.CurrentServiceObjectiveName  # e.g. GP_Gen5_2
            MaxSizeGB         = [math]::Round($db.MaxSizeBytes / 1GB, 2)
            ZoneRedundant     = $db.ZoneRedundant
            BackupRedundancy  = $db.CurrentBackupStorageRedundancy
        }
    }
}

# Output
$dbInfo | Format-Table -AutoSize