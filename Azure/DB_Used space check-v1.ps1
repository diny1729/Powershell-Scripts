<#
.SYNOPSIS
    Reports used space, storage percentages, and DTU sizes for Azure SQL Databases across servers.

.DESCRIPTION
    Interactively prompts for Azure subscription and target SQL Servers, queries Azure Monitor metrics (`storage` & `storage_percent`),
    calculates used storage in GB vs maximum allocated storage size, determines geo-replication status, and displays sorted results.

.NOTES
    Prerequisites:
    - Azure PowerShell modules: `Az.Accounts`, `Az.Sql`, `Az.Resources`, `Az.Monitor`.
    - Authenticated Azure session (`Connect-AzAccount`).
#>

#Requires -Module Az.Accounts, Az.Sql, Az.Resources, Az.Monitor

# Connect to your Azure account (you might need to log in)
Connect-AzAccount

# Initialize an empty array to store the data
$OutData = New-Object System.Collections.Generic.List[PSCustomObject]

# List of databases to ignore (e.g., system databases)
$IgnoreDB = @('master', 'SSISDB')

# Select the Azure subscription
$Subscription = Get-AzSubscription | Out-GridView -OutputMode 'Single'

if ($Subscription) {
    Select-AzSubscription $Subscription

    # Get all Azure SQL Servers
    $AzSqlServer = Get-AzSqlServer | Out-GridView -OutputMode Multiple

    if ($AzSqlServer) {
        foreach ($server in $AzSqlServer) {
            # Get all SQL databases (excluding ignored ones)
            $SQLDatabase = Get-AzSqlDatabase -ServerName $server.ServerName -ResourceGroupName $server.ResourceGroupName |
                           Where-Object { $_.DatabaseName -notin $IgnoreDB }

            foreach ($database in $SQLDatabase) {
                # Get the database resource
                $db_resource = Get-AzResource -ResourceId $database.ResourceId

                # Database maximum storage size (in GB)
                $db_MaximumStorageSize = $database.MaxSizeBytes / 1GB

                # Database used space (in GB)
                $db_metric_storage = $db_resource | Get-AzMetric -MetricName 'storage' -WarningAction SilentlyContinue
                $db_UsedSpace = $db_metric_storage.Data.Maximum | Select-Object -Last 1
                $db_UsedSpace = [math]::Round($db_UsedSpace / 1GB, 2)

                # Database used space percentage
                $db_metric_storage_percent = $db_resource | Get-AzMetric -MetricName 'storage_percent' -WarningAction SilentlyContinue

                # Determine if the database is a geo-replica
                $isGeoReplica = if ($database.Edition -eq 'Standard' -and $database.ServiceObjectiveName -match 'Geo') { $true } else { $false }

                # Get the DTU size
                $dtuSize = $database.CurrentServiceObjectiveName

                # Add data to the output array
                $OutData.Add([PSCustomObject]@{
                    ServerName       = $server.ServerName
                    DatabaseName     = $database.DatabaseName
                    MaxSizeGB        = $db_MaximumStorageSize
                    UsedSpaceGB      = $db_UsedSpace
                    UsedSpacePercent = $db_metric_storage_percent.Data.Maximum | Select-Object -Last 1
                    IsGeoReplica     = $isGeoReplica
                    DTUSize          = $dtuSize
                })
            }
        }
    }
}

# Display the collected data
#$OutData | Sort-Object UsedSpacePercent -Descending | Format-Table -AutoSize | out-file c:\users\admin\desktop\db_usage.csv

# Get the sorted data once
$data = $OutData | Sort-Object UsedSpacePercent -Descending

# Display nicely in the PowerShell session
$data | Format-Table -AutoSize
