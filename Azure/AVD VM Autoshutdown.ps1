<#
.SYNOPSIS
    Automated process to stop unused session hosts in a WVD/AVD personal or pooled host pool.

.DESCRIPTION
    Evaluates session hosts in specified Azure Virtual Desktop host pools, identifies session hosts with zero active 
    user connections that are not in drain mode, and safely shuts down idle session host VMs to minimize cost.

.PARAMETER Timer
    Timer trigger object passed automatically when executing inside an Azure Function App.

.NOTES
    Prerequisites:
    - Azure PowerShell modules: `Az.DesktopVirtualization`, `Az.Compute`.
    - Managed Identity or Azure credentials with Virtual Machine Contributor & Desktop Virtualization Reader roles.
    - Personal or Pooled AVD Host Pool with Start on Connect enabled.
#>

#Requires -Module Az.DesktopVirtualization, Az.Compute

param($Timer)
 
######## Variables ##########
## Update "HostPool" value with your host pool, and "HostPoolRG" with the value of the host pool resource group.
## See the next step if working with multiple host pools.
$allHostPools = @()
$allHostPools += (@{
        HostPool   = "hostpoolname";
        HostPoolRG = "rg-name"
    })
$allHostPools += (@{
        HostPool   = "hostpoolname1";
        HostPoolRG = "rg-name"
    })
# If using multiple host pools, Copy the block the code below and pasted it above this line.  Update with the host pool name and resource group.
# Repeat for each additional host pool.
<#
$allHostPools += (@{
        HostPool   = "<HostPoolName>";
        HostPoolRG = "<HostPoolResourceGroup>"
    })
#>
 
########## Script Execution ##########
$count = 0
while ($count -lt $allHostPools.Count) {
    $pool = $allHostPools[$count].HostPool
    $poolRg = $allHostPools[$count].HostPoolRG
    Write-Output "This is the key (pool) $pool"
    write-output "this is the value (rg) $poolRg"
    # Get the active Session hosts
    try {
        $activeShs = (Get-AzWvdUserSession -ErrorAction Stop -HostPoolName $pool -ResourceGroupName $poolRg).name
    }
    catch {
        $ErrorMessage = $_.Exception.message
        Write-Error ("Error getting a list of user sessions: " + $ErrorMessage)
        Break
    }
    
    $allActive = @()
    foreach ($activeSh in $activeShs) {
        $activeSh = ($activeSh -split { $_ -eq '.' -or $_ -eq '/' })[1]
        if ($activeSh -notin $allActive) {
            $allActive += $activeSh
        }
    }
    # Get the Session Hosts
    # Exclude servers in drain mode and do not allow new connections
    try {
        $runningSessionHosts = (Get-AzWvdSessionHost -ErrorAction Stop -HostPoolName $Pool -ResourceGroupName $PoolRg | Where-Object { $_.AllowNewSession -eq $true } )
        Write-Host "Stopped Hosts:"
		(Get-AzWvdSessionHost -ErrorAction Stop -HostPoolName $Pool -ResourceGroupName $PoolRg | Where-Object { $_.Status -eq "Shutdown" }).name
		Write-Host "Running Hosts:"
		(Get-AzWvdSessionHost -ErrorAction Stop -HostPoolName $Pool -ResourceGroupName $PoolRg | Where-Object { $_.Status -eq "Available" }).name
    }
    catch {
        $ErrorMessage = $_.Exception.message
        Write-Error ("Error getting a list of running session hosts: " + $ErrorMessage)
        Break
    }
    $availableSessionHosts = ($runningSessionHosts | Where-Object { $_.Status -eq "Available" })
    #Evaluate the list of running session hosts against 
    foreach ($sessionHost in $availableSessionHosts) {
        $sessionHostName = (($sessionHost).name -split { $_ -eq '.' -or $_ -eq '/' })[1]
        if ($sessionHostName -notin $allActive) {
            Write-Host "Server $sessionHostName is not active, shut down"
            try {
                # Stop the VM
                Write-Output "Stopping Session Host $sessionHostName"
                Get-azvm -ErrorAction Stop -Name $sessionHostName | Stop-AzVM -ErrorAction Stop -Force -NoWait
            }
            catch {
                $ErrorMessage = $_.Exception.message
                Write-Error ("Error stopping the VM: " + $ErrorMessage)
                Break
            }
        }
        else {
            write-host "Server $sessionHostName has an active session, won't shut down"
        }
    }
    $count += 1
}
Write-Output "This is the end of script"