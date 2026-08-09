<#
.SYNOPSIS
    Automates maintenance drain, user notification, and restart of Azure Virtual Desktop (AVD) session host VMs.

.DESCRIPTION
    Executes a scheduled maintenance workflow for AVD Host Pools:
    1. Enables drain mode on all session hosts to prevent new user sessions.
    2. Identifies active user sessions and sends pop-up warning messages requesting users save work and log off.
    3. Waits for a configurable grace period ($WaitTimeSeconds).
    4. Restarts session host Virtual Machines.
    5. Disables drain mode to reopen session hosts for user connections.

.NOTES
    Prerequisites:
    - Azure PowerShell modules: `Az.Accounts`, `Az.DesktopVirtualization`, `Az.Compute`.
    - Azure account with Desktop Virtualization Virtual Machine Contributor rights.
#>

#Requires -Module Az.Accounts, Az.DesktopVirtualization, Az.Compute

# -------------------------------------------------------------------------
# 1. PREREQUISITES MODULE CHECK
# -------------------------------------------------------------------------
$RequiredModules = @(
    "Az.Accounts",
    "Az.DesktopVirtualization",
    "Az.Compute"
)

foreach ($ModuleName in $RequiredModules) {
    if (-not (Get-Module -ListAvailable -Name $ModuleName)) {
        Write-Output "Installing missing module: $ModuleName"
        Install-Module -Name $ModuleName -Scope CurrentUser -Force -AllowClobber
    }
}

# -------------------------------------------------------------------------
# 2. CONFIGURATION
# -------------------------------------------------------------------------
$poolRg          = "<REDACTED>"
$hostPoolName    = "<REDACTED>"
$WaitTimeSeconds = 600   # 5 minutes warning

# -------------------------------------------------------------------------
# 3. AUTHENTICATION
# -------------------------------------------------------------------------
try {
    Get-AzSubscription -ErrorAction Stop | Out-Null
}
catch {
    Write-Output "Connecting to Azure using Managed Identity or interactive login..."
    # Connect-AzAccount -Identity -ErrorAction Stop
}

# -------------------------------------------------------------------------
# 4. MAINTENANCE WORKFLOW
# -------------------------------------------------------------------------
try {

    # ---------------------------------------------------------------------
    # Fetch session hosts
    # ---------------------------------------------------------------------
    $sessionHosts = Get-AzWvdSessionHost `
        -ResourceGroupName $poolRg `
        -HostPoolName $hostPoolName

    if (-not $sessionHosts) {
        throw "No session hosts found in host pool $hostPoolName"
    }

    # ---------------------------------------------------------------------
    # PHASE A: ENABLE DRAIN MODE (OPTIONAL)
    # ---------------------------------------------------------------------
    
    foreach ($sh in $sessionHosts) {
        # Extract the short name (e.g., JDA-LS-VD-7) from "JDA-LS-VD/JDA-LS-VD-7"
        $shNameOnly = $sh.Name.Split('/')[-1]
    
        Write-Output "Enabling drain mode on $shNameOnly"
    
        Update-AzWvdSessionHost `
            -ResourceGroupName $poolRg `
            -HostPoolName $hostPoolName `
            -Name $shNameOnly `
            -AllowNewSession:$false
    }
    

    # ---------------------------------------------------------------------
    # PHASE B: IDENTIFY ACTIVE USER SESSIONS & SEND NOTIFICATIONS
    # ---------------------------------------------------------------------

    # Build authoritative session host lookup (short name → short name)
    $hostLookup = @{}
    foreach ($sh in $sessionHosts) {
        # Example: JDA-LS-VD/JDA-LS-VD-7 → JDA-LS-VD-7
        $shortName = $sh.Name.Split('/')[-1]
        $hostLookup[$shortName] = $shortName
    }

    # Get active user sessions
    $userSessions = Get-AzWvdUserSession `
        -ResourceGroupName $poolRg `
        -HostPoolName $hostPoolName `
        -ErrorAction SilentlyContinue

    foreach ($session in $userSessions) {

        # Extract host name from UserSession ID
        if ($session.Id -match '/sessionhosts/([^/]+)/usersessions/') {
            $shortHostName = $matches[1].Trim()
        }
        else {
            Write-Warning "Skipping session: Unable to parse host from ID: $($session.Id)"
            continue
        }

        # Resolve host name
        if ($hostLookup.ContainsKey($shortHostName)) {
            $targetHost = $hostLookup[$shortHostName]
        }
        else {
            Write-Verbose "Host $shortHostName not found in lookup. Using parsed value."
            $targetHost = $shortHostName
        }

        Write-Output "Sending maintenance message to $($session.UserPrincipalName) on $targetHost"

        # Extract numeric session ID
        $numericSessionId = $session.Name.Split('/')[-1]

        try {
            Send-AzWvdUserSessionMessage `
                -ResourceGroupName $poolRg `
                -HostPoolName $hostPoolName `
                -SessionHostName $targetHost `
                -UserSessionId $numericSessionId `
                -MessageTitle "Scheduled Maintenance" `
                -MessageBody "This session host will restart in 10 minutes. PLEASE SAVE YOU WORK WITHIN 5 MIN AND & LOGOFF." `
                -ErrorAction Stop
        }
        catch {
            Write-Warning "Failed to send message to $($session.UserPrincipalName): $($_.Exception.Message)"
        }
    }

    # ---------------------------------------------------------------------
    # PHASE C: WAIT BEFORE RESTART (OPTIONAL)
    # ---------------------------------------------------------------------
    Start-Sleep -Seconds $WaitTimeSeconds

    # ---------------------------------------------------------------------
    # PHASE D: RESTART SESSION HOST VMS (PARALLEL)
    # ---------------------------------------------------------------------
    foreach ($sh in $sessionHosts) {
        # Example: JDA-LS-VD/JDA-LS-VD-6 → JDA-LS-VD-6
        $vmName = $sh.Name.Split('/')[-1]
        Write-Output "Restarting VM: $vmName"

        # Restart-AzVM -ResourceGroupName $poolRg -Name $vmName -NoWait
    }
    # ---------------------------------------------------------------------
    # PHASE E: DISABLE DRAIN MODE (OPTIONAL)
    # ---------------------------------------------------------------------
    
    foreach ($sh in $sessionHosts) {
        # Extract the short name (e.g., JDA-LS-VD-7) from "JDA-LS-VD/JDA-LS-VD-7"
        $shNameOnly = $sh.Name.Split('/')[-1]
    
        Write-Output "Enabling drain mode on $shNameOnly"
    
        Update-AzWvdSessionHost `
            -ResourceGroupName $poolRg `
            -HostPoolName $hostPoolName `
            -Name $shNameOnly `
            -AllowNewSession:$true
    }

    Write-Output "AVD maintenance cycle completed successfully."
}
catch {
    Write-Error "Maintenance failed: $($_.Exception.Message)"
}



