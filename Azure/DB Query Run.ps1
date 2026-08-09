<#
.SYNOPSIS
    Interactively executes SQL queries across multiple Azure SQL Servers and databases using Azure AD or SQL Auth.

.DESCRIPTION
    Lists Azure SQL Servers in the subscription, lets the user select target servers via GUI (`Out-GridView`), 
    prompts for SQL query text, filters or prompts for target databases, and executes queries via `Invoke-Sqlcmd` 
    using either Azure AD Access Tokens or Key Vault secrets.

.NOTES
    Prerequisites:
    - Azure PowerShell modules: `Az.Accounts`, `Az.Sql`, `Az.KeyVault`.
    - `SqlServer` module installed (`Invoke-Sqlcmd`).
    - Authenticated Azure session (`Connect-AzAccount`).
#>

#Requires -Module Az.Accounts, Az.Sql, Az.KeyVault

#Connect-AzAccount -Identity  | Out-Null

$authType = Read-Host "Select Authentication Type (L for Local SQL Auth, A for Azure AD)"
if ($authType -match "^[Aa]") {
    $useAzureAD = $true
    Write-Host "Using Azure AD Authentication" -ForegroundColor Cyan
    try {
        $accessToken = (Get-AzAccessToken -ResourceUrl https://database.windows.net).Token
    } catch {
        Write-Error "Failed to get Azure Access Token. Ensure you are logged in with Connect-AzAccount."
        exit
    }
} else {
    $useAzureAD = $false
    Write-Host "Using Local SQL Authentication" -ForegroundColor Cyan
    $keyvaultname1 = "<REDACTED>"
    $Pass = Get-AzKeyVaultSecret -VaultName $keyvaultname1 -Name adminpass -AsPlainText
}

# Get all Azure SQL Servers and let the user select from a GUI list
$AzSqlServer = Get-AzSqlServer | Select-Object -Property ServerName, ResourceGroupName, Location, FullyQualifiedDomainName
$selectedServers = $AzSqlServer | Out-GridView -PassThru -Title "Select SQL Server(s) to Query"

if (-not $selectedServers) {
    Write-Host "No servers selected. Exiting." -ForegroundColor Yellow
    exit
}

# Prompt for the query to run on all databases for the selected servers
$queryToRun = Read-Host "`nEnter the SQL query to execute on the selected databases"

$dbSelectionMethod = Read-Host "Do you want to (S)elect databases via GUI or (F)ilter by name pattern? (S/F)"
$dbFilterPattern = $null
if ($dbSelectionMethod -match "^[Ff]") {
    $dbFilterPattern = Read-Host "Enter database name filter pattern (wildcards supported, e.g. *wms*)"
}

foreach ($SourceServer in $selectedServers) {
    $SourceServerName = $SourceServer.FullyQualifiedDomainName
    write-Host "`nChecking SQL Server: $SourceServerName" -ForegroundColor Cyan

    #Assign SQL Server UserName using a switch statement for better readability
    if (-not $useAzureAD) {
        $SourceUsername = switch -Wildcard ($SourceServerName) {
            "*<REDACTED>*" { "sqlserverusername" }
            "*<REDACTED>*" { "sqlserverusername" }
            "*<REDACTED>*" { "sqlserverusername" }
            "*<REDACTED>*" { "sqlserverusername" }
            "*<REDACTED>*" { "sqlserverusername" }
            "*<REDACTED>*" { "sqlserverusername" }
            "**<REDACTED>*" { "sqlserverusername" }
            default { "" }
        }
        Write-Host "SQL Server $SourceServerName Username: $SourceUsername will be used"
        if (-not $SourceUsername) {
            Write-Warning "Could not determine username for server '$SourceServerName'. Skipping."
            continue
        }
    }

    # Get a list of databases on the source server
    try {
        if ($useAzureAD) {
            $Databases = Invoke-Sqlcmd -ServerInstance $SourceServerName -AccessToken $accessToken -Query "SELECT name FROM sys.databases WHERE database_id > 4" -ErrorAction Stop
        } else {
            $Databases = Invoke-Sqlcmd -ServerInstance $SourceServerName -Username $SourceUsername -Password $Pass -Query "SELECT name FROM sys.databases WHERE database_id > 4" -ErrorAction Stop
        }
    }
    catch {
        Write-Error "Failed to get database list from server '$SourceServerName'. Error: $($_.Exception.Message)"
        continue # Skip to the next server
    }

    if ($dbSelectionMethod -match "^[Ff]") {
        $selectedDatabases = $Databases | Where-Object { $_.name -like $dbFilterPattern }
        Write-Host "Automatically selected $($selectedDatabases.Count) databases matching '$dbFilterPattern'." -ForegroundColor Cyan
    } else {
        # Let the user select databases from a GUI list
        $selectedDatabases = $Databases | Out-GridView -PassThru -Title "Select Databases on '$SourceServerName' (filter for wms, refs, etc.)"
    }
    
    if (-not $selectedDatabases) {
        Write-Host "No databases selected for server '$SourceServerName'. Skipping." -ForegroundColor Yellow
        continue
    }

    # Loop through each selected database and run the query
    foreach ($db in $selectedDatabases) {
        $DatabaseName = $db.name
        Write-Host "`n--- Querying Database: $DatabaseName ---" -ForegroundColor Green
        try {
            if ($useAzureAD) {
                $result = Invoke-Sqlcmd -ServerInstance $SourceServerName -Database $DatabaseName -AccessToken $accessToken -Query $queryToRun -ErrorAction Stop
            } else {
                $result = Invoke-Sqlcmd -ServerInstance $SourceServerName -Database $DatabaseName -Username $SourceUsername -Password $Pass -Query $queryToRun -ErrorAction Stop
            }
            if ($result) {
                $result | Format-Table -AutoSize
            } else {
                Write-Host "Query executed successfully, but returned no results." -ForegroundColor Yellow
            }
        } catch {
            Write-Error "Failed to run query on database '$DatabaseName'. Error: $($_.Exception.Message)"
        }
    }
}










