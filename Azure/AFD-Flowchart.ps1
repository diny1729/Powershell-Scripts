<#
.SYNOPSIS
    Generates an interactive Mermaid.js HTML flowchart for Azure Front Door Premium traffic flow topology.

.DESCRIPTION
    Interactively prompts for Azure Front Door profile, Endpoint, and Route. Maps custom domains, SSL certificates,
    WAF rule sets, origin groups, and origins, building a Mermaid JS diagram exported and opened in browser as HTML.

.PARAMETER SubscriptionId
    Optional Azure Subscription ID to switch context.

.NOTES
    Prerequisites:
    - Azure PowerShell modules `Az.Accounts` and `Az.Cdn`.
    - Active Azure login session (`Connect-AzAccount`).
#>

#Requires -Module Az.Accounts, Az.Cdn

[CmdletBinding()]
param(
    [Parameter()]
    [string]$SubscriptionId
)

# Set subscription context if provided, otherwise fallback to current active context
if (-not [string]::IsNullOrWhiteSpace($SubscriptionId)) {
    Set-AzContext -SubscriptionId $SubscriptionId | Out-Null
} else {
    $currentContext = Get-AzContext
    if (-not $currentContext) {
        Write-Error "No active Azure context found. Please run Connect-AzAccount first."
        exit 1
    }
}

############################################
# Front Door Profile
############################################

$profile = Get-AzFrontDoorCdnProfile |
    Select-Object Name,ResourceGroupName,SkuName |
    Out-GridView -Title "Select Front Door Profile" -PassThru

if(!$profile)
{
    return
}

############################################
# Endpoint
############################################

$endpoint = Get-AzFrontDoorCdnEndpoint `
    -ProfileName $profile.Name `
    -ResourceGroupName $profile.ResourceGroupName |
    Select-Object Name, HostName, EnabledState |
    Out-GridView `
        -Title "Select Endpoint" `
        -PassThru

if(!$endpoint)
{
    return
}

############################################
# Route
############################################

$route = Get-AzFrontDoorCdnRoute `
    -ProfileName $profile.Name `
    -EndpointName $endpoint.Name `
    -ResourceGroupName $profile.ResourceGroupName |
    Out-GridView `
        -Title "Select Route" `
        -PassThru

if(!$route)
{
    return
}

$routeObj = Get-AzFrontDoorCdnRoute `
    -ProfileName $profile.Name `
    -EndpointName $endpoint.Name `
    -ResourceGroupName $profile.ResourceGroupName `
    -Name $route.Name

############################################
# Find Origin Group
############################################

$originGroup = $null
$originGroupName = $null

if ($routeObj.OriginGroupId) {
    $originGroupName = $routeObj.OriginGroupId.Split("/")[-1]
} elseif ($routeObj.OriginGroup -and $routeObj.OriginGroup.Id) {
    $originGroupName = $routeObj.OriginGroup.Id.Split("/")[-1]
}

if ($originGroupName)
{
    $originGroup = Get-AzFrontDoorCdnOriginGroup `
        -ProfileName $profile.Name `
        -ResourceGroupName $profile.ResourceGroupName `
        -OriginGroupName $originGroupName
}

############################################
# Mermaid
############################################

$mermaid = @()

$mermaid += "graph LR"

$mermaid += "Client([Client])"

############################################
# Endpoint
############################################

$mermaid += @"
Endpoint["Front Door Endpoint
<br>Name: $($endpoint.Name)
<br>State: $($endpoint.EnabledState)"]
"@

$mermaid += "Client --> Endpoint"

############################################
# Domains (Updated with SSL & Traffic Status)
############################################

$lastNodes = @()

try
{
    if($routeObj.CustomDomain)
    {
        $i = 1

        foreach($domain in $routeObj.CustomDomain)
        {
            $domainName = $domain.Id.Split("/")[-1]

            # Query extended domain settings for SSL and Validation information
            $domainDetails = Get-AzFrontDoorCdnCustomDomain `
                -ProfileName $profile.Name `
                -ResourceGroupName $profile.ResourceGroupName `
                -CustomDomainName $domainName

            # Evaluate SSL details
            $certType = if ($domainDetails.TlsSetting.CertificateType) { $domainDetails.TlsSetting.CertificateType } else { "N/A" }
            $minTls   = if ($domainDetails.TlsSetting.MinimumTlsVersion) { $domainDetails.TlsSetting.MinimumTlsVersion } else { "N/A" }
            
            # Evaluate Validation and Traffic Allowance states
            $valState = if ($domainDetails.DomainValidationState) { $domainDetails.DomainValidationState } else { "Unknown" }
            $traffic  = if ($valState -eq "Approved") { "Allowed" } else { "Blocked ($valState)" }

            $node = "Domain$i"

            $mermaid += @"
$node["Custom Domain
<br>Name: $domainName
<br>SSL Cert: $certType
<br>Min TLS: $minTls
<br>Validation: $valState
<br>Traffic: $traffic"]
"@
            $mermaid += "Endpoint --> $node"
            $mermaid += "class $node domain" 

            $lastNodes += $node

            $i++
        }
    }
}
catch {}

if($lastNodes.Count -eq 0)
{
    $lastNodes += "Endpoint"
}

############################################
# Route 
############################################

$routePatterns = if($routeObj.PatternToMatch) { ($routeObj.PatternToMatch -join ", ") } else { "None" }
$supportedProtocols = if($routeObj.SupportedProtocol) { ($routeObj.SupportedProtocol -join ", ") } else { "None" }

$mermaid += @"
Route["Route
<br>Name: $($routeObj.Name)
<br>State: $($routeObj.EnabledState)
<br>Accepted Proto: $supportedProtocols
<br>Forwarding Proto: $($routeObj.ForwardingProtocol)
<br>HTTPS Redirect: $($routeObj.HttpsRedirect)
<br>Patterns: $routePatterns"]
"@

foreach($node in $lastNodes)
{
    $mermaid += "$node --> Route"
}

############################################
# Rule Sets
############################################

$lastNode = "Route"

try
{
    if($routeObj.RuleSet)
    {
        $idx = 1

        foreach($rs in $routeObj.RuleSet)
        {
            $rsName = $rs.Id.Split("/")[-1]

            $rsNode = "RuleSet$idx"

            $mermaid += @"
$rsNode["Rule Set
<br>$rsName"]
"@

            $mermaid += "$lastNode --> $rsNode"
            $mermaid += "class $rsNode ruleset" 

            $lastNode = $rsNode

            $idx++
        }
    }
}
catch {}

############################################
# Origin Group
############################################

if($originGroup)
{
    $mermaid += @"
OriginGroup["Origin Group
<br>Name: $($originGroup.Name)"]
"@

    $mermaid += "$lastNode --> OriginGroup"

    ########################################
    # Origins 
    ########################################

    $origins = Get-AzFrontDoorCdnOrigin `
        -ProfileName $profile.Name `
        -ResourceGroupName $profile.ResourceGroupName `
        -OriginGroupName $originGroup.Name

    foreach($origin in $origins)
    {
        $node = "Origin_" + ($origin.Name -replace '[^a-zA-Z0-9]','_')

        $privateLink = "Disabled"

        if($origin.SharedPrivateLinkResource)
        {
            $privateLink = "Enabled"
        }

        $mermaid += @"
$node["Origin
<br>Name: $($origin.Name)
<br>Host: $($origin.HostName)
<br>Host Header: $($origin.OriginHostHeader)
<br>Priority: $($origin.Priority)
<br>Weight: $($origin.Weight)
<br>Private Link: $privateLink"]
"@

        $mermaid += "OriginGroup --> $node"
        $mermaid += "class $node origin" 
    }
}

############################################
# Styling
############################################

$mermaid += @"

classDef endpoint fill:#0078D4,color:#fff
classDef domain fill:#50E6FF,color:#000
classDef route fill:#FFB900,color:#000
classDef ruleset fill:#D83B01,color:#fff
classDef origingroup fill:#5C2D91,color:#fff
classDef origin fill:#107C10,color:#fff

class Endpoint endpoint
class Route route
class OriginGroup origingroup

"@

$diagram = $mermaid -join "`r`n"

############################################
# HTML
############################################

$html = @"
<html>

<head>

<script src="https://cdn.jsdelivr.net/npm/mermaid/dist/mermaid.min.js"></script>

<script>
mermaid.initialize({
startOnLoad:true,
securityLevel:'loose'
});
</script>

<style>

body{
font-family:Segoe UI;
padding:20px;
background:#f5f5f5;
}

.container{
background:white;
padding:20px;
border-radius:10px;
box-shadow:0 2px 8px rgba(0,0,0,.15);
}

</style>

</head>

<body>

<div class='container'>

<h2>Azure Front Door Premium Traffic Flow</h2>

<p>
Client → Endpoint → Domain → Route → Rule Set → Origin Group → Origin
</p>

<div class="mermaid">

$diagram

</div>

</div>

</body>

</html>
"@

$file = "$env:TEMP\AFD-TrafficFlow.html"

$html | Out-File $file -Encoding utf8

Start-Process $file

Write-Host ""
Write-Host "Diagram generated: $file" -ForegroundColor Green