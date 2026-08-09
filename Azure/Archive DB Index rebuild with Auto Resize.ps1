<#
.SYNOPSIS
    Automates DTU scaling for Azure SQL Databases before executing background index maintenance jobs.

.DESCRIPTION
    Dynamically increases Azure SQL Database DTU service objectives (e.g. S2 -> S3 or P1 -> P2), executes database index 
    rebuild stored procedures in parallel background jobs (`Invoke-Sqlcmd`), monitors job completion, and automatically restores 
    databases to their original DTU service tier.

.NOTES
    Prerequisites:
    - Azure PowerShell module `Az.Sql`.
    - `SqlServer` PowerShell module (`Invoke-Sqlcmd`).
    - Azure Key Vault automation credentials configured (`Get-AutomationPSCredential`).
#>

#Requires -Module Az.Sql

if (-not (Get-Module -ListAvailable -Name Az.Sql)) {
    Write-Output "'Az.Sql' module not found. Installing..."
    Install-Module -Name Az.Sql -Scope CurrentUser -Repository PSGallery -Force
} else {
    Write-Output "'Az.Sql' module is already installed."
}

Connect-azaccount -identity -SubscriptionId "subscriptionid"

$AzureSQLServerName = "servername.database.windows.net" 
$Arc1SQLDatabaseName = "archiveprod1"
$Arc2SQLDatabaseName = "archiveprod2"


function DBDtuIncrement {
    param (
        [Parameter(Mandatory)]
        $dbname
    )
    $resourceGroup = "rgname"
    $serverName = "sqlservername"
    $db = Get-AzSqlDatabase -ResourceGroupName $resourceGroup -ServerName $serverName -DatabaseName $dbname
    
    # Save current tier and DTUs
    $currentEdition = $db.Edition        # E.g. Standard, Premium
    $currentCapacity = $db.CurrentServiceObjectiveName  # e.g. S3, P1, etc.

    # ---- Scale Up ----
    $standardTiers = @("S0", "S1", "S2", "S3", "S4", "S6", "S7", "S9", "S12")
    $premiumTiers = @("P1", "P2", "P4", "P6", "P11", "P15")
    $targetCapacity = $currentCapacity

    if ($currentEdition -eq "Standard"){
        $index = $standardTiers.IndexOf($currentCapacity)
        if ($index -ge 0 -and $index -lt ($standardTiers.Count - 1)) { $targetCapacity = $standardTiers[$index + 1] }
    }
    if ($currentEdition -eq "Premium") {
        $index = $premiumTiers.IndexOf($currentCapacity)
        if ($index -ge 0 -and $index -lt ($premiumTiers.Count - 1)) { $targetCapacity = $premiumTiers[$index + 1] }
    }
    $targetEdition = $currentEdition
    Write-Host ".....DB: $dbname....."
    Write-Host "Current Edition : $currentEdition"
    Write-Host "Current Capacity: $currentCapacity"
    Write-Host "Target Edition  : $targetEdition"
    Write-Host "Target Capacity : $targetCapacity"

    if ($targetCapacity -ne $currentCapacity) {

        Write-Host "$dbname - Scaling From $currentCapacity - $currentEdition -- to -- $targetCapacity - $targetEdition"
        #Set-AzSqlDatabase -ResourceGroupName $resourceGroup `
                          #-ServerName $serverName `
                          #-DatabaseName $dbname `
                          #-Edition $targetEdition `
                          #-RequestedServiceObjectiveName $targetCapacity | Out-Null
    
        # Optional: wait until scale completes (polling loop)
        do {
            Start-Sleep -Seconds 15
            $status = (Get-AzSqlDatabase -ResourceGroupName $resourceGroup -ServerName $serverName -DatabaseName $dbname).Status
            Write-Host "Database status: $status"
        } while ($status -ne "Online")
        Write-Host "DB: $dbname Resize Completed"
    } else {
        Write-Host "DB: $dbname Target and Current Capacity same hence ignoring Increament of DTU"
    }
    return [PSCustomObject]@{
        dbname  = $dbname
        Edition = $currentEdition
        Capacity = $currentCapacity
    }
}


function RestoreDtu {
    param (
        [Parameter(Mandatory)] $dbname,
        [Parameter(Mandatory)] $edition,
        [Parameter(Mandatory)] $capacity
    )

    $resourceGroup = "rg-name"
    $serverName = "sqlservername"

    Write-Output "Restoring $dbname to $edition - $capacity"

    #Set-AzSqlDatabase -ResourceGroupName $resourceGroup `
                      #-ServerName $serverName `
                      #-DatabaseName $dbname `
                      #-Edition $edition `
                      #-RequestedServiceObjectiveName $capacity | Out-Null

    do {
        Start-Sleep -Seconds 15
        $status = (Get-AzSqlDatabase -ResourceGroupName $resourceGroup -ServerName $serverName -DatabaseName $dbname).Status
        Write-Output "Restoring: Database status: $status"
    } while ($status -ne "Online")

    Write-Output "$dbname restored to original size."
}


# Define the databases and their respective outputs
$databases = @(
    @{ Name = $Arc1SQLDatabaseName; OutputVariable = "Arc1Output" },
    @{ Name = $Arc2SQLDatabaseName; OutputVariable = "Arc2Output" }
)

# Retrieve credentials securely
$cred = Get-AutomationPSCredential -Name "DB-Arc-Creds"
$username = $cred.UserName
$password = $cred.GetNetworkCredential().Password
$server = $AzureSQLServerName

# Create a collection to track jobs
$jobs = @()
$originalConfigs = @()

# Start a background job for each database
foreach ($db in $databases) {
    if ([string]::IsNullOrWhiteSpace($db.Name)) {
        Write-Warning "Skipping database because Name is null. Check variable definitions for OutputVariable: $($db.OutputVariable)"
        continue
    }

    # DTU Size Increment
    write-Output "**********Incrementing DB: $($db.Name) DTU Size.***********"
    $originalConfig = DBDtuIncrement -dbname $db.Name
    $originalConfigs += $originalConfig
    Write-Output "Function returned:"
    $originalConfig | Format-List | Out-String | Write-Output

    # Index Rebuild Job
    $job = Start-Job -ScriptBlock {
        param ($db, $server, $username, $password)
        Write-Output "Maintenance Job to DB : $($db.Name)"
        #$result = Invoke-Sqlcmd -ServerInstance $server `
                                #-Username $username `
                                #-Password $password `
                                #-Database $db.Name `
                                #-Query "exec [dbo].[usp_DB_Maint]" `
                                #-QueryTimeout 65535 `
                                #-ConnectionTimeout 60 `
                                #-Verbose 4>&1

        # Return output with tag
        [PSCustomObject]@{
            OutputName = $db.OutputVariable
            Result     = $result
        }

    } -ArgumentList $db, $server, $username, $password
    $jobs += $job
}

# Wait for all jobs to complete
Wait-Job -Job $jobs

# Collect results
$outputResults = @{}
foreach ($job in $jobs) {
    $jobResult = Receive-Job -Job $job
    $outputResults[$jobResult.OutputName] = $jobResult.Result
    Remove-Job -Job $job
}

# Access your named output
#$Arc1Output = $outputResults["Arc1Output"]
#$Arc1Output
#$Arc2Output = $outputResults["Arc2Output"]
#$Arc2Output

# Restore DB size AFTER jobs complete
foreach ($config in $originalConfigs) {
    write-Output "**********Restoring DB: $($config.dbname) to original size.***********"
    #RestoreDtu -dbname $config.dbname -edition $config.Edition -capacity $config.Capacity
}
#