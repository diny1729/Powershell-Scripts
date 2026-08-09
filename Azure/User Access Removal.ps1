<#
.SYNOPSIS
    Removes specified Azure RBAC role assignments for a targeted user across multiple scopes.

.DESCRIPTION
    Resolves the Azure Active Directory Object ID for a given user email (UPN), iterates through a list of role 
    assignments (Key Vault, AKS, Resource Group, Subscription), resolves the exact target resource scope ID, 
    and removes the role assignments via `Remove-AzRoleAssignment`.

.NOTES
    Prerequisites:
    - Azure PowerShell modules: `Az.Resources`, `Az.Accounts`, `Az.KeyVault`.
    - User/Service Principal with User Access Administrator or Owner permissions.
#>

#Requires -Module Az.Resources, Az.Accounts, Az.KeyVault

# 1. Define the User Principal Name (Email)
$userEmail = "username@abc.com"

# 2. Get the User Object ID
$userObj = Get-AzADUser -UserPrincipalName $userEmail
if (-not $userObj) {
    Write-Error "Could not find user: $userEmail"
    return
}

$userObjectId = $userObj.Id

# 3. Define the targets for removal
$assignments = @(
    @{ Role = "Key Vault Reader";           Resource = ""; Type = "KeyVault" }
    @{ Role = "Key Vault Secrets Officer";  Resource = ""; Type = "KeyVault" }
    @{ Role = "Reader";                    Resource = "";  Type = "AKS" }
    @{ Role = "Reader";                    Resource = "";  Type = "AKS" }
    @{ Role = "Contributor";               Resource = "";   Type = "ResourceGroup" }
    @{ Role = "Reader and Data Access";    Resource = ""; Type = "Subscription" }
)

Write-Host "Starting role removal for $userEmail..." -ForegroundColor Cyan

foreach ($item in $assignments) {
    try {
        $params = @{
            ObjectId = $userObjectId
            RoleDefinitionName = $item.Role
        }

        # Determine Scope based on Type
        if ($item.Type -eq "KeyVault") {
            $resource = Get-AzKeyVault -VaultName $item.Resource -ErrorAction Stop
            $params.Scope = $resource.ResourceId
        }
        elseif ($item.Type -eq "AKS") {
            # Searching across the subscription for the AKS cluster
            $resource = Get-AzResource -Name $item.Resource -ResourceType "Microsoft.ContainerService/managedClusters" -ErrorAction Stop
            $params.Scope = $resource.ResourceId
        }
        elseif ($item.Type -eq "ResourceGroup") {
            $resource = Get-AzResourceGroup -Name $item.Resource -ErrorAction Stop
            $params.Scope = $resource.ResourceId
        }
        elseif ($item.Type -eq "Subscription") {
            $sub = Get-AzSubscription -SubscriptionName $item.Resource -ErrorAction Stop
            $params.Scope = "/subscriptions/$($sub.Id)"
        }

        # Execute Removal
        Write-Host "Removing '$($item.Role)' from '$($item.Resource)'..." -NoNewline
        Remove-AzRoleAssignment @params -ErrorAction Stop
        Write-Host " DONE" -ForegroundColor Green
    }
    catch {
        Write-Host " FAILED: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

Write-Host "Process complete." -ForegroundColor Cyan