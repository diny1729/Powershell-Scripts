<#
.SYNOPSIS
    Generates an interactive Mermaid.js HTML flowchart mapping Azure Application Gateway traffic routing.

.DESCRIPTION
    Interactively prompts for Azure Application Gateway name and HTTP listener. Traces listeners, path-based or basic
    routing rules, URL path maps, backend HTTP settings, backend address pools, and backend targets, outputting an HTML
    flowchart using Mermaid.js and launching it in the default browser.

.PARAMETER SubscriptionId
    Optional Azure Subscription ID to switch context.

.NOTES
    Prerequisites:
    - Azure PowerShell modules `Az.Accounts` and `Az.Network`.
    - Active Azure login session (`Connect-AzAccount`).
#>

#Requires -Module Az.Accounts, Az.Network

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

# Select Application Gateway
$appgw = Get-AzApplicationGateway |
    Select-Object Name, ResourceGroupName, Location |
    Out-GridView -Title "Select Application Gateway" -PassThru

$appGwObj = Get-AzApplicationGateway `
    -Name $appgw.Name `
    -ResourceGroupName $appgw.ResourceGroupName

# Select Listener
$listener = $appGwObj.HttpListeners |
    Select-Object Name, Protocol, HostName, Id |
    Out-GridView -Title "Select Listener" -PassThru

$realListener = $appGwObj.HttpListeners |
    Where-Object { $_.Id -eq $listener.Id }

# Find Routing Rule
$rule = $appGwObj.RequestRoutingRules |
    Where-Object {
        $_.HttpListener.Id -eq $listener.Id
    }

if (!$rule)
{
    Write-Warning "No routing rule found."
    return
}

Write-Host ""
Write-Host "Rule Found: $($rule.Name)" -ForegroundColor Green
Write-Host "Rule Type : $($rule.RuleType)"
Write-Host ""

$mermaid = @()

$mermaid += "graph LR"
$mermaid += "Client([Client])"

# Listener
$hostText = ""

if ($realListener.HostName)
{
    $hostText = "<br>Host: $($realListener.HostName)"
}

$mermaid += @"
Listener["Listener
<br>Name: $($realListener.Name)
<br>Protocol: $($realListener.Protocol)
$hostText"]
"@

$mermaid += "Client --> Listener"

#---------------------------------------------------
# PATH BASED ROUTING
#---------------------------------------------------
if($rule.RuleType -eq "PathBasedRouting")
{
    $urlMap = $appGwObj.UrlPathMaps |
        Where-Object {
            $_.Id -eq $rule.UrlPathMap.Id
        }

    $mermaid += @"
URLMAP["Path Routing
<br>URL Map: $($urlMap.Name)"]
"@

    $mermaid += "Listener --> URLMAP"

    foreach($pathRule in $urlMap.PathRules)
    {
        $setting = $appGwObj.BackendHttpSettingsCollection |
            Where-Object {
                $_.Id -eq $pathRule.BackendHttpSettings.Id
            }

        $pool = $appGwObj.BackendAddressPools |
            Where-Object {
                $_.Id -eq $pathRule.BackendAddressPool.Id
            }

        $ruleNode = "PathRule_$($pathRule.Name -replace '[^a-zA-Z0-9]', '_')"
        $setNode  = "Set_$($setting.Name -replace '[^a-zA-Z0-9]', '_')"
        $poolNode = "Pool_$($pool.Name -replace '[^a-zA-Z0-9]', '_')"

        $paths = $pathRule.Paths -join ', '

        $mermaid += @"
$ruleNode["Path Route
<br>Rule: $($pathRule.Name)
<br>Paths: $paths"]
"@

        $mermaid += @"
$setNode["Backend Settings
<br>Name: $($setting.Name)
<br>Protocol: $($setting.Protocol)
<br>Port: $($setting.Port)
<br>Timeout: $($setting.RequestTimeout)s"]
"@

        $mermaid += @"
$poolNode["Backend Pool
<br>Name: $($pool.Name)
<br>Targets: $($pool.BackendAddresses.Count)"]
"@

        $mermaid += "URLMAP --> $ruleNode"
        $mermaid += "$ruleNode --> $setNode"
        $mermaid += "$setNode --> $poolNode"

        foreach($target in $pool.BackendAddresses)
        {
            $targetName = if($target.Fqdn)
            {
                $target.Fqdn
            }
            else
            {
                $target.IpAddress
            }

            $safeNode = "Target_" + ($targetName -replace '[^a-zA-Z0-9]', '_')

            $mermaid += @"
$safeNode["Backend Target
<br>$targetName"]
"@

            $mermaid += "$poolNode --> $safeNode"
            $mermaid += "class $safeNode backend"
        }

        $mermaid += "class $ruleNode path"
        $mermaid += "class $setNode setting"
        $mermaid += "class $poolNode pool"
    }

    # Default Route
    if($urlMap.DefaultBackendAddressPool)
    {
        $defaultPool = $appGwObj.BackendAddressPools |
            Where-Object {
                $_.Id -eq $urlMap.DefaultBackendAddressPool.Id
            }

        $defaultSetting = $appGwObj.BackendHttpSettingsCollection |
            Where-Object {
                $_.Id -eq $urlMap.DefaultBackendHttpSettings.Id
            }

        $defSetNode = "DefaultSetting"
        $defPoolNode = "DefaultPool"

        $mermaid += @"
$defSetNode["Backend Settings
<br>Name: $($defaultSetting.Name)
<br>Protocol: $($defaultSetting.Protocol)
<br>Port: $($defaultSetting.Port)"]
"@

        $mermaid += @"
$defPoolNode["Backend Pool
<br>Name: $($defaultPool.Name)
<br>Default Route"]
"@

        $mermaid += "URLMAP -->|Default Route| $defSetNode"
        $mermaid += "$defSetNode --> $defPoolNode"

        foreach($addr in $defaultPool.BackendAddresses)
        {
            $target = if($addr.Fqdn)
            {
                $addr.Fqdn
            }
            else
            {
                $addr.IpAddress
            }

            $safeNode = "Target_" + ($target -replace '[^a-zA-Z0-9]', '_')

            $mermaid += @"
$safeNode["Backend Target
<br>$target"]
"@

            $mermaid += "$defPoolNode --> $safeNode"
        }

        $mermaid += "class $defSetNode setting"
        $mermaid += "class $defPoolNode pool"
    }
}
#---------------------------------------------------
# BASIC ROUTING
#---------------------------------------------------
else
{
    $setting = $appGwObj.BackendHttpSettingsCollection |
        Where-Object {
            $_.Id -eq $rule.BackendHttpSettings.Id
        }

    $pool = $appGwObj.BackendAddressPools |
        Where-Object {
            $_.Id -eq $rule.BackendAddressPool.Id
        }

    $setNode = "BackendSettings"
    $poolNode = "BackendPool"

    $mermaid += @"
$setNode["Backend Settings
<br>Name: $($setting.Name)
<br>Protocol: $($setting.Protocol)
<br>Port: $($setting.Port)
<br>Timeout: $($setting.RequestTimeout)s"]
"@

    $mermaid += @"
$poolNode["Backend Pool
<br>Name: $($pool.Name)
<br>Targets: $($pool.BackendAddresses.Count)"]
"@

    $mermaid += "Listener --> $setNode"
    $mermaid += "$setNode --> $poolNode"

    foreach($target in $pool.BackendAddresses)
    {
        $targetName = if($target.Fqdn)
        {
            $target.Fqdn
        }
        else
        {
            $target.IpAddress
        }

        $safeNode = "Target_" + ($targetName -replace '[^a-zA-Z0-9]', '_')

        $mermaid += @"
$safeNode["Backend Target
<br>$targetName"]
"@

        $mermaid += "$poolNode --> $safeNode"
        $mermaid += "class $safeNode backend"
    }

    $mermaid += "class $setNode setting"
    $mermaid += "class $poolNode pool"
}

# Colors
$mermaid += @"

classDef listener fill:#0078D4,color:#ffffff,stroke:#005A9E
classDef path fill:#FFB900,color:#000000,stroke:#CC8800
classDef setting fill:#107C10,color:#ffffff,stroke:#0B5A0B
classDef pool fill:#5C2D91,color:#ffffff,stroke:#401F68
classDef backend fill:#00B7C3,color:#000000,stroke:#008E99

class Listener listener
class URLMAP path

"@

$diagram = $mermaid -join "`r`n"

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
    margin:20px;
    background:#f5f5f5;
}

.container{
    background:white;
    padding:20px;
    border-radius:10px;
    box-shadow:0 2px 8px rgba(0,0,0,.2);
}

</style>

</head>

<body>

<div class="container">

<h2>Azure Application Gateway Traffic Flow</h2>

<p>
Listener → Path Route → Backend Settings → Backend Pool → Backend Target
</p>

<div class="mermaid">

$diagram

</div>

</div>

</body>

</html>
"@

$reportFile = "$env:TEMP\AppGatewayFlow.html"

$html | Set-Content $reportFile -Encoding UTF8

Start-Process $reportFile

Write-Host ""
Write-Host "Report generated: $reportFile" -ForegroundColor Green