

<#
.SYNOPSIS
    Lists all Azure SQL Databases in a specified Resource Group & Server along with DTU/vCore sizing.

.DESCRIPTION
    Queries `Get-AzSqlDatabase` for a target server and Resource Group, evaluates max database size in GB, 
    edition, and requested/current DTU or vCore service objectives, outputting formatted tabular results.

.NOTES
    Prerequisites:
    - Azure PowerShell module `Az.Sql`.
    - Authenticated Azure session (`Connect-AzAccount`).
#>

#Requires -Module Az.Sql

# Define the resource group and server name
$serverName = "<REDACTED>"
$resourceGroupName  = "<REDACTED>"

# Get the list of databases
$databases = Get-AzSqlDatabase -ResourceGroupName $resourceGroupName -ServerName $serverName

# Create an array to store the database information
$dbInfo = @()

# Loop through each database and get the size and DTU/vCore information
foreach ($db in $databases) {
    $dbName = $db.DatabaseName
    $dbSize = $db.CurrentServiceObjectiveName
    $dbEdition = $db.Edition
    $dbMaxSize = $db.MaxSizeBytes / 1GB
    $dbDtuOrVcore = if ($db.Edition -eq "Basic" -or $db.Edition -eq "Standard" -or $db.Edition -eq "Premium") {
        $db.RequestedServiceObjectiveName
    } else {
        $db.CurrentServiceObjectiveName
    }

    # Add the information to the array
    $dbInfo += [PSCustomObject]@{
        DatabaseName = $dbName
        Edition = $dbEdition
        MaxSizeGB = [math]::Round($dbMaxSize, 2)
        DTUorVCore = $dbDtuOrVcore
    }
}

# Output the information as a table
$dbInfo | Format-Table -AutoSize







