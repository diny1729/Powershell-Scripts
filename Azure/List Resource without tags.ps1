<#
.SYNOPSIS
    Lists all Azure resources within a Resource Group that are missing tags.

.DESCRIPTION
    Scans a designated Azure Resource Group via `Get-AzResource`, checks the tag collection for each child resource, 
    and outputs the names of any resources that have empty or null tags.

.NOTES
    Prerequisites:
    - Azure PowerShell module `Az.Resources`.
    - Authenticated Azure session (`Connect-AzAccount`).
#>

#Requires -Module Az.Resources

# Get the resource group name
$resourceGroupName = "rg-name"

# Get the resource group
$resourceGroup = Get-AzResourceGroup -Name $resourceGroupName

# Get the resources in the resource group
$resources = Get-AzResource -ResourceGroupName $resourceGroupName

# Loop through the resources
foreach ($resource in $resources) {

    # Get the tags for the resource
    $tags = $resource.Tags

    # Check if the tags are empty
    if ($tags -eq $null -or $tags.Count -eq 0) {

        # Print the resource name
        Write-Host $resource.Name
    }
}