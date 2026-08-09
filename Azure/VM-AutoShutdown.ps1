
<#
.SYNOPSIS
    Automated shutdown of Azure Virtual Machines when zero active user sessions are detected.

.DESCRIPTION
    Connects to Azure using Managed Identity, iterates through target application servers by IP, retrieves VM admin credentials 
    from Azure Key Vault, executes remote `quser` via PowerShell remoting (`Invoke-Command`) to inspect active sessions, 
    and issues an async shutdown/deallocate command (`Stop-AzVM -NoWait`) if 0 users are logged in.

.PARAMETER Timer
    Timer trigger object passed automatically when executing inside an Azure Function App.

.NOTES
    Prerequisites:
    - Azure PowerShell modules: `Az.Accounts`, `Az.Compute`, `Az.KeyVault`.
    - WinRM / PSRemoting configured with SSL/Basic Auth on target servers.
    - System Assigned Managed Identity with Key Vault Secret User & Virtual Machine Contributor roles.
#>

#Requires -Module Az.Accounts, Az.Compute, Az.KeyVault

param($Timer)

# Authenticate to Azure using Managed Identity if session is not active
try {
    Get-AzContext -ErrorAction Stop | Out-Null
} catch {
    Connect-AzAccount -Identity -ErrorAction Stop
}

$kvname = "<REDACTED>"
$appserver = @('10.50.0.4', '10.50.0.8', '10.50.0.28') # Server IPs which need to be monitored/stopped
$secret = "<REDACTED>"
$resourceGroupName = "rg-name"

foreach ($server in $appserver) {
    $scriptBlock = {
        # Run the quser command and store the output in a variable
        $quserOutput = quser

        # The first line of the output is a header, so we exclude it
        $users = $quserOutput[1..($quserOutput.Length - 1)]

        # Count the number of active users
        $numberOfUsers = $users.Length

        # Return the number of users
        return $numberOfUsers
    }

    # Fetch VM credentials stored in Key Vault based on server IP
    if ($server -eq "10.50.0.4") {
        $secret = "secret-name-1"
        $ps = Get-AzKeyVaultSecret -VaultName $kvname -Name $secret -AsPlainText
        $servername = "vm-app-1"
    }
    elseif ($server -eq "10.50.0.8") {
        $secret = "secret-name-2"
        $ps = Get-AzKeyVaultSecret -VaultName $kvname -Name $secret -AsPlainText
        $servername = "vm-app-2"
    }
    elseif ($server -eq "10.50.0.28") {
        $secret = "secret-name-3"
        $ps = Get-AzKeyVaultSecret -VaultName $kvname -Name $secret -AsPlainText
        $servername = "vm-app-3"
    }

    $Username = "adminuser"
    $Password = ConvertTo-SecureString "$ps" -AsPlainText -Force
    $credentials = New-Object System.Management.Automation.PSCredential($Username, $Password)
    
    # Check VM Running Status
    $vm = Get-AzVM -ResourceGroupName $resourceGroupName -Name $servername -Status
    $numberOfUsers = 1
    $serverstatus = $vm.Statuses[1].DisplayStatus

    if ($serverstatus -ne "VM deallocated") {
        # Query logged in user session count via PSRemoting
        $sessionOption = New-PSSessionOption -SkipCACheck -SkipCNCheck -SkipRevocationCheck
        $numberOfUsers = Invoke-Command -ComputerName $server -Credential $credentials -UseSSL -SessionOption $sessionOption -Authentication Basic -ScriptBlock $scriptBlock -ErrorAction SilentlyContinue
        Write-Output "Currently Logged in user Count on VM $servername --- $numberOfUsers"
    }

    # Stop VM when zero active users logged in
    if ($numberOfUsers -eq 0) {
        Write-Host "Server $servername does not have active sessions. Initiating shutdown..." -ForegroundColor Yellow
        try {
            Write-Output "Stopping Session Host VM: $servername"
            Get-AzVM -ResourceGroupName $resourceGroupName -Name $servername | Stop-AzVM -ErrorAction Stop -Force -NoWait
            Write-Output "$servername -- VM Stop signal sent."
        }
        catch {
            $ErrorMessage = $_.Exception.Message
            Write-Error "Error stopping VM $servername : $ErrorMessage"
            break
        }
    }
    else {
        Write-Host "Server $servername has active session ($numberOfUsers) or is already stopped. Skipping shutdown." -ForegroundColor Cyan
    }
}

Write-Output "VM AutoShutdown process completed."










