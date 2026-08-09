<#
.SYNOPSIS
    Adds specified Azure AD users as owners to target Azure AD groups.

.DESCRIPTION
    Prompts for a comma-separated list of User Principal Names (UPNs), iterates through a target list 
    of Azure Active Directory group display names, checks if each user is already an owner, and adds 
    missing users as group owners via the AzureAD module.

.NOTES
    Prerequisites:
    - AzureAD PowerShell module installed (`Install-Module -Name AzureAD`).
    - Azure AD user with permissions to assign group ownership (e.g., User Administrator, Global Administrator, or existing Group Owner).
#>

#Requires -Module AzureAD

# Ensure AzureAD module is available
if (-not (Get-Module -ListAvailable -Name AzureAD)) {
    Write-Error "The 'AzureAD' module is required. Please run: Install-Module -Name AzureAD -Scope CurrentUser"
    exit 1
}

# Sign in to Azure AD if session does not exist
try {
    Get-AzureADTenantDetail -ErrorAction Stop | Out-Null
} catch {
    Connect-AzureAD
}
# Define the user UPN (User Principal Name) of the user you want to add as an owner
$username = Read-Host -Prompt "Enter the username separated by comma:"
$userIdsArray = $username -split ','

# Define an array of Azure AD group display names or IDs where you want to add the owner
$groupNames = @(
  "AD-Group1",
  "AD-Group2"
 ) # Add group names or IDs here

# Iterate through each group and add the specified user as an owner
foreach ($userId in $userIdsArray) {
	foreach ($groupName in $groupNames) {
		$group = Get-AzureADGroup -Filter "DisplayName eq '$groupName'" # Get group details
    
		if ($group) {
			$groupId = $group.ObjectId
			$owner = Get-AzureADGroupOwner -All $true -ObjectId $group.ObjectId | Where-Object { $_.UserType -eq 'member' } | Where-Object {$_.UserPrincipalName -eq $userId}
			if ($owner){
				Write-Host "$userId --- User is already owner of the group $groupName."
			} else {  	
				$user = Get-AzureADUser -ObjectId $userId		
				[void](Add-AzureADGroupOwner -ObjectId $groupId -RefObjectId $user.ObjectId)
				write-host "$userId --- Added to owner of group $groupName"
			} 
		}
	}
}
Read-Host -Prompt "Press Enter to exit"
