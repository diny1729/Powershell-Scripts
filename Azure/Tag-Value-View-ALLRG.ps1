<#
.SYNOPSIS
    Consolidates and visualizes all unique tag keys and values across all Resource Groups in a subscription.

.DESCRIPTION
    Scans all Azure Resource Groups in the active subscription, builds a complete list of unique tag keys, 
    creates a pivot table mapping each Resource Group and its tag values, displays a console table and GUI grid (`Out-GridView`), 
    and exports the consolidated tag matrix to CSV.

.NOTES
    Prerequisites:
    - Azure PowerShell module `Az.Resources`.
    - Authenticated Azure session (`Connect-AzAccount`).
#>

#Requires -Module Az.Resources

# Get all resource groups in the subscription
$resourceGroups = Get-AzResourceGroup

# Create a hash table to store unique tag names
$uniqueTags = @{}

# First pass: Collect all unique tag names across resource groups
foreach ($rg in $resourceGroups) {
    if ($rg.Tags) {
        foreach ($tag in $rg.Tags.Keys) {
            $uniqueTags[$tag] = $true
        }
    }
}


# Create an array to hold the results
$rgTagList = @()

# Second pass: Build objects with RG name and each tag as a property
foreach ($rg in $resourceGroups) {
    write-host $rg.ResourceGroupName
    $rgInfo = [ordered]@{
        ResourceGroupName = $rg.ResourceGroupName
        Location = $rg.Location
    }
    foreach ($tag in $uniqueTags.Keys) {
        $rgInfo[$tag] = if ($rg.Tags.ContainsKey($tag)) { $rg.Tags[$tag] }
    }
    $rgTagList += [PSCustomObject]$rgInfo
}

# Display as a table
$rgTagList | Format-Table -AutoSize
$rgTagList | Out-GridView
$rgTagList | export-csv "C:\Users\admin\RGtag_7.csv"
