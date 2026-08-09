<#
.SYNOPSIS
    Monitors and logs active session counts per host on an Azure SQL Database to a CSV file.

.DESCRIPTION
    Periodically executes a SQL query against `sys.sysprocesses` on an Azure SQL database using .NET ADO.NET (`SqlConnection`), 
    summarizes total active sessions and hostname breakdowns, and appends timestamped records to a CSV file.

.NOTES
    Prerequisites:
    - .NET Data Provider for SQL Server (`System.Data.SqlClient`).
    - Azure SQL Database credentials and firewall access.
#>

# =====================================================================
# Configuration Variables - Update these with your environment details
# =====================================================================
$ServerName   = "sqlservername.database.windows.net"
$DatabaseName = "dbname"
$Username     = "sqlserverusername"
$Password     = ""
$OutputFile   = ".\AzureSqlSessionMonitor.csv"

# Connection String for Azure SQL Database
$ConnectionString = "Server=tcp:$ServerName,1433;Initial Catalog=$DatabaseName;User ID=$Username;Password=$Password;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"

# The provided SQL Query
$Query = @"
SELECT 
    Hostname,
    SessionCount
FROM (
    -- 1. Total summary row configured to force-sort to the top
    SELECT 
        0 AS SortOrder,
        'Total - ' + CAST(COUNT(*) AS VARCHAR(10)) AS Hostname,
        COUNT(*) AS SessionCount
    FROM sys.sysprocesses WITH (NOLOCK)
    WHERE dbid > 0

    UNION ALL

    -- 2. Detailed breakdown rows grouped by hostname
    SELECT 
        1 AS SortOrder,
        CASE 
            WHEN RTRIM(sp.hostname) = '' THEN 'Internal / Unknown'
            ELSE RTRIM(sp.hostname) 
        END AS Hostname,
        COUNT(*) AS SessionCount
    FROM sys.sysprocesses AS sp WITH (NOLOCK)
    WHERE sp.dbid > 0 and sp.hostname like '%-bt-%'
    GROUP BY sp.hostname
) AS CombinedResults
ORDER BY SortOrder ASC, SessionCount DESC;
"@

Write-Host "Starting Azure SQL Monitoring. Press Ctrl+C to stop." -ForegroundColor Green
Write-Host "Logging to: $OutputFile" -ForegroundColor Yellow

# =====================================================================
# Execution Loop
# =====================================================================
while ($true) {
    # Capture the exact date and time of the current run
    $RunTimestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    
    try {
        # Initialize SQL Connection
        $Connection = New-Object System.Data.SqlClient.SqlConnection($ConnectionString)
        $Connection.Open()

        $Command = $Connection.CreateCommand()
        $Command.CommandText = $Query
        
        # Execute query and read results
        $Reader = $Command.ExecuteReader()
        $RunResults = @()

        while ($Reader.Read()) {
            # Build a custom object with the Timestamp added as the first column
            $RunResults += [PSCustomObject]@{
                Timestamp    = $RunTimestamp
                Hostname     = $Reader["Hostname"].ToString()
                SessionCount = $Reader["SessionCount"]
            }
        }
        
        # Close connection immediately after reading
        $Connection.Close()

        # Append to CSV. (NoTypeInformation prevents PowerShell headers in the CSV)
        $RunResults | Export-Csv -Path $OutputFile -Append -NoTypeInformation

        Write-Host "[$RunTimestamp] Successfully recorded $($RunResults.Count) rows." -ForegroundColor Cyan
    }
    catch {
        Write-Host "[$RunTimestamp] Error executing query: $_" -ForegroundColor Red
    }
    finally {
        # Ensure connection is disposed even if an error occurs
        if ($null -ne $Connection -and $Connection.State -eq 'Open') {
            $Connection.Close()
        }
    }

    # Wait 10 seconds before the next execution
    Start-Sleep -Seconds 10
}