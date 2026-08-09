<#
.SYNOPSIS
    Propagates missing tags from a Resource Group to all child resources within that RG.

.DESCRIPTION
    Retrieves tags defined at the Azure Resource Group level, iterates through all resources inside the Resource Group, 
    checks an exclusion list, and applies any missing tag key/value pairs to child resources using `Set-AzResource`.

.NOTES
    Prerequisites:
    - Azure PowerShell module `Az.Resources`.
    - Authenticated Azure session (`Connect-AzAccount`).
#>

#Requires -Module Az.Resources

# Parameters
$rgName = "rgname"
$tagsToExclude = @("tagname1", "tagname2") # Add the RG tags you want to skip here

# 1. Get the tags from the Resource Group
$rg = Get-AzResourceGroup -Name $rgName
$rgTags = $rg.Tags

if ($null -eq $rgTags -or $rgTags.Count -eq 0) {
    Write-Warning "Resource Group '$rgName' has no tags to propagate."
    return
}

# 2. Get all resources within that Resource Group
$resources = Get-AzResource -ResourceGroupName $rgName

# 3. Loop through each resource
foreach ($resource in $resources) {
    $resourceTags = if ($null -ne $resource.Tags) { $resource.Tags } else { @{} }
    $needsUpdate = $false
    
    # Check each tag from the RG
    foreach ($key in $rgTags.Keys) {
        
        # SKIP if the tag is in the exclusion list
        if ($tagsToExclude -contains $key) {
            Write-Host "Skipping tag [$key] on $($resource.Name) - Key is in Exclusion List." -ForegroundColor Yellow
            continue
        }

        # ONLY add the tag if the key does not exist on the resource
        if (-not $resourceTags.ContainsKey($key)) {
            $resourceTags[$key] = $rgTags[$key]
            $needsUpdate = $true
            Write-Host "Adding missing tag [$key] to $($resource.Name)" -ForegroundColor Cyan
        }
        else {
            Write-Host "Skipping tag [$key] on $($resource.Name) - Tag already exists." -ForegroundColor Gray
        }
    }

    # 4. Only call the API if we actually modified the collection
    if ($needsUpdate) {
        Set-AzResource -ResourceId $resource.ResourceId -Tag $resourceTags -Force
    }
}

Write-Host "Processing complete!" -ForegroundColor Green