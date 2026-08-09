<#
.SYNOPSIS
    Copies and merges resource tags from a source Resource Group to a destination Resource Group.

.DESCRIPTION
    Fetches existing tags on both source and destination Resource Groups, merges all tag key/value pairs 
    from the source (overwriting existing values if keys overlap), and updates the destination Resource Group using `Set-AzResourceGroup`.

.NOTES
    Prerequisites:
    - Azure PowerShell module `Az.Resources`.
    - Authenticated Azure session (`Connect-AzAccount`).
#>

#Requires -Module Az.Resources

# Parameters
$sourceRGName = ""
$destRGName   = ""

# 1. Fetch Source and Destination Resource Groups
$sourceRG = Get-AzResourceGroup -Name $sourceRGName
$destRG   = Get-AzResourceGroup -Name $destRGName

if ($null -eq $sourceRG -or $null -eq $destRG) {
    Write-Error "One or both Resource Groups could not be found."
    return
}

# 2. Get the Tag objects (handle null cases)
$sourceTags = if ($null -ne $sourceRG.Tags) { $sourceRG.Tags } else { @{} }
$destTags   = if ($null -ne $destRG.Tags) { $destRG.Tags } else { @{} }

Write-Host "Source Tags found: $($sourceTags.Count)"
Write-Host "Existing Destination Tags found: $($destTags.Count)"

# 3. Merge Tags
# We start with destination tags and overwrite/add source tags
foreach ($key in $sourceTags.Keys) {
    $destTags[$key] = $sourceTags[$key]
}

# 4. Apply the merged tag set to the destination Resource Group
Set-AzResourceGroup -Name $destRGName -Tag $destTags

Write-Host "Successfully synced tags to $destRGName." -ForegroundColor Green