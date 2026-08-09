<#
.SYNOPSIS
    Interactive Kubernetes Pod troubleshooting and diagnostic report wizard.

.DESCRIPTION
    Scans Kubernetes cluster namespaces for Ready or Not-Ready pods, presents an interactive tabular selection menu, 
    parses container configurations (images, ports, state, resource limits/requests, environment variables, mounts), 
    highlights warning/error events, and displays recommended troubleshooting commands.

.NOTES
    Prerequisites:
    - `kubectl` CLI installed and configured with active cluster context.
#>

# -----------------------------------------------------------------------------
# Script: PodTroubleshoot.ps1
# Description: Interactive troubleshooter with structured tabular pod selection menus.
# -----------------------------------------------------------------------------
Clear-Host
Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "        KUBERNETES POD TROUBLESHOOTING WIZARD      " -ForegroundColor Cyan
Write-Host "====================================================" -ForegroundColor Cyan

$CurrentContext = kubectl config current-context 2>$null
if (-not $CurrentContext) { Write-Error "No cluster connection."; exit }

# 1. Select Pod Status Filter
Write-Host "`nSelect Pod Status Filter:" -ForegroundColor Yellow
Write-Host "----------------------------------------------------" -ForegroundColor Gray
Write-Host "[1] Scan for NOT READY pods (Troubleshooting)" -ForegroundColor White
Write-Host "[2] Scan for READY pods (Healthy Inventory)" -ForegroundColor White
Write-Host "----------------------------------------------------" -ForegroundColor Gray

$StatusChoice = Read-Host "`nEnter selection (1 or 2)"
if ($StatusChoice -eq "1" -or [string]::IsNullOrWhiteSpace($StatusChoice)) {
    $TargetReadyState = $false
    $FilterLabel = "Not Ready"
} elseif ($StatusChoice -eq "2") {
    $TargetReadyState = $true
    $FilterLabel = "Ready"
} else {
    Write-Host "Invalid choice. Exiting script." -ForegroundColor Red; exit
}

# 2. Fetch and Display Cluster Namespaces
Write-Host "`nFetching available namespaces..." -ForegroundColor Gray
$RawNamespaces = kubectl get namespaces -o json | ConvertFrom-Json
$NsIndex = 1
$NsMenuMap = @{}

Write-Host "[$NsIndex] -- SCAN ALL NAMESPACES --" -ForegroundColor White
$NsMenuMap.Add($NsIndex, "all")
$NsIndex++

foreach ($Ns in $RawNamespaces.items) {
    Write-Host "[$NsIndex] $($Ns.metadata.name)" -ForegroundColor White
    $NsMenuMap.Add($NsIndex, $Ns.metadata.name)
    $NsIndex++
}

$SelectedNsIndex = [int](Read-Host "`nEnter namespace number")
if (-not $NsMenuMap.ContainsKey($SelectedNsIndex)) { exit }
$TargetNamespace = $NsMenuMap[$SelectedNsIndex]

Write-Host "`nFetching matching pods from cluster..." -ForegroundColor Cyan
if ($TargetNamespace -eq "all") { $Pods = kubectl get pods --all-namespaces -o json | ConvertFrom-Json }
else { $Pods = kubectl get pods -n $TargetNamespace -o json | ConvertFrom-Json }

# 3. Filter Pods based on the selected target state
$FilteredPods = $Pods.items | Where-Object {
    $ReadyCondition = $_.status.conditions | Where-Object { $_.type -eq "Ready" }
    if ($TargetReadyState) { $ReadyCondition.status -eq "True" } else { $ReadyCondition.status -ne "True" }
}

if ($FilteredPods.Count -eq 0 -or $FilteredPods -eq $null) {
    Write-Host "No pods found in a '$FilterLabel' state for namespace '$TargetNamespace'." -ForegroundColor Green; exit
}

# 4. Present Structured Table of matching pods
Write-Host "`nFound $($FilteredPods.Count) pod(s) in a $FilterLabel state:`n" -ForegroundColor Yellow

$PodIndex = 1
$TableRows = @()
$PodMenuMap = @{}

foreach ($Pod in $FilteredPods) {
    $Age = "Unknown"
    if ($Pod.metadata.creationTimestamp) {
        $AgeTimeSpan = (Get-Date) - [DateTime]$Pod.metadata.creationTimestamp
        $Age = "{0}d {1}h" -f $AgeTimeSpan.Days, $AgeTimeSpan.Hours
    }
    
    $Restarts = 0
    if ($Pod.status.containerStatuses) {
        $Restarts = ($Pod.status.containerStatuses.restartCount | Measure-Object -Sum).Sum
    }
    $Status = $Pod.status.phase

    # Build row structure for the console layout
    $RowItem = [PSCustomObject]@{
        "ID"        = $PodIndex
        "Namespace" = $Pod.metadata.namespace
        "Pod Name"  = $Pod.metadata.name
        "Status"    = $Status
        "Age"       = $Age
        "Restarts"  = $Restarts
    }
    $TableRows += $RowItem
    
    # Store reference details for selection processing
    $PodMenuMap.Add($PodIndex, $Pod)
    $PodIndex++
}

# Render data as a neat columnar layout format
$TableRows | Format-Table -AutoSize

$SelectedPodIndex = [int](Read-Host "`nEnter ID number of the pod to analyze")
if (-not $PodMenuMap.ContainsKey($SelectedPodIndex)) { exit }

$PodData = $PodMenuMap[$SelectedPodIndex]
$PodName = $PodData.metadata.name
$PodNamespace = $PodData.metadata.namespace

Write-Host "`nExtracting details for $PodName..." -ForegroundColor Cyan
$DescribeOutput = kubectl describe pod $PodName -n $PodNamespace 2>$null | Out-String

# 5. Output Primary Specification Report
Clear-Host
Write-Host "====================================================" -ForegroundColor Cyan
Write-Host " POD SPECIFICATION REPORT: $PodName " -ForegroundColor Cyan
Write-Host "====================================================" -ForegroundColor Cyan

$ControlledBy = "None/Independent"
if ($PodData.metadata.ownerReferences) {
    $ControlledBy = "$($PodData.metadata.ownerReferences[0].kind)/$($PodData.metadata.ownerReferences[0].name)"
}

$AnnotationsText = "None"
if ($PodData.metadata.annotations) {
    $AnnotationsText = $PodData.metadata.annotations | Out-String
}

$PodAge = "Unknown"
if ($PodData.metadata.creationTimestamp) {
    $TimeSpan = (Get-Date) - [DateTime]$PodData.metadata.creationTimestamp
    $PodAge = "{0}d {1}h {2}m" -f $TimeSpan.Days, $TimeSpan.Hours, $TimeSpan.Minutes
}

[PSCustomObject]@{
    "Pod Name"      = $PodName
    "Namespace"     = $PodNamespace
    "Current Status"= $PodData.status.phase
    "Target Node"   = $PodData.spec.nodeName
    "Controlled By" = $ControlledBy
    "Exact Pod Age" = $PodAge
    "Total Restarts"= ($PodData.status.containerStatuses.restartCount | Measure-Object -Sum).Sum
} | Format-List

Write-Host "--- ANNOTATIONS ---" -ForegroundColor Yellow
Write-Host $AnnotationsText

# 6. Extract Containers, Ports, Resources, and Environment Variables
Write-Host "`n--- CONTAINER CONFIGURATIONS, PORTS AND RESOURCES ---" -ForegroundColor Yellow
function Get-SafeField {
    param([string]$RawText, [string]$RegexPattern)
    if ($RawText -and ($RawText -match $RegexPattern)) { return $Matches[1].Trim() }
    return "Not Specified"
}

if ($DescribeOutput -and ($DescribeOutput -match "(?ms)Containers:\s+(.+?)(?=Conditions:)")) {
    $ContainerBlock = $Matches[1]
    
    $Image     = Get-SafeField -RawText $ContainerBlock -RegexPattern "(?m)^\s+Image:\s+(.+)$"
    $Port      = Get-SafeField -RawText $ContainerBlock -RegexPattern "(?m)^\s+Port:\s+(.+)$"
    $HostPort  = Get-SafeField -RawText $ContainerBlock -RegexPattern "(?m)^\s+Host Port:\s+(.+)$"
    $State     = Get-SafeField -RawText $ContainerBlock -RegexPattern "(?ms)^\s+State:\s+(.*?)(?=^\s+Last State:)"
    $Limits    = Get-SafeField -RawText $ContainerBlock -RegexPattern "(?ms)^\s+Limits:\s+(.*?)(?=^\s+Requests:)"
    $Requests  = Get-SafeField -RawText $ContainerBlock -RegexPattern "(?ms)^\s+Requests:\s+(.*?)(?=^\s+Liveness:|\s+Environment:)"
    $EnvVars   = Get-SafeField -RawText $ContainerBlock -RegexPattern "(?ms)^\s+Environment:\s+(.*?)(?=^\s+Mounts:)"
    $Mounts    = Get-SafeField -RawText $ContainerBlock -RegexPattern "(?ms)^\s+Mounts:\s+(.*?)(?=^\s+Volumes:|\s+Conditions:|\s+[^ ]+:)"

    Write-Host "Image:       $Image" -ForegroundColor White
    Write-Host "Port:        $Port"
    Write-Host "Host Port:   $HostPort"
    Write-Host "`n[Container State]:`n$State" -ForegroundColor Gray
    Write-Host "`n[Limits]:`n$Limits" -ForegroundColor Gray
    Write-Host "[Requests]:`n$Requests" -ForegroundColor Gray
    Write-Host "`n[Environment Variables]:`n$EnvVars"
    Write-Host "`n[Volume Mounts]:`n$Mounts"
} else {
    Write-Host "Container internal metadata details are currently inaccessible." -ForegroundColor Gray
}

# 7. Extract Volumes Block
Write-Host "`n--- VOLUMES DEFINED ---" -ForegroundColor Yellow
if ($DescribeOutput -and ($DescribeOutput -match "(?ms)^Volumes:\s+(.*?)(?=QoS Class:)")) {
    Write-Host $Matches[1].Trim()
} else {
    Write-Host "No structural storage volumes bound to this runtime instance." -ForegroundColor Gray
}

# 8. Render Operational Events
Write-Host "`n====================================================" -ForegroundColor Red
Write-Host "         UNUSUAL EVENTS / LIFECYCLE ALERTS          " -ForegroundColor Red
Write-Host "====================================================" -ForegroundColor Red

if ($DescribeOutput -and $DescribeOutput -match "(?ms)^Events:\s+(.+)$") {
    $EventsBlock = $Matches[1].Trim()
    $EventLines = $EventsBlock -split "`n"
    foreach ($Line in $EventLines) {
        if ($Line -match "Warning" -or $Line -match "Failed" -or $Line -match "Error") {
            Write-Host $Line -ForegroundColor LightRed
        } else {
            Write-Host $Line -ForegroundColor Gray
        }
    }
} else {
    Write-Host "No active platform events found. Running state is completely clear." -ForegroundColor Green
}

# 9. Output Recommended Commands
Write-Host "`n====================================================" -ForegroundColor Green
Write-Host "            RECOMMENDED NEXT STEPS TO RUN           " -ForegroundColor Green
Write-Host "====================================================" -ForegroundColor Green

Write-Host "1. To check the full, native raw description of this pod run:" -ForegroundColor Gray
Write-Host "   kubectl describe pod $PodName -n $PodNamespace" -ForegroundColor Yellow

Write-Host "`n2. To check the active running logs of this pod run:" -ForegroundColor Gray
Write-Host "   kubectl logs $PodName -n $PodNamespace" -ForegroundColor Yellow

if ($ControlledBy -ne "None/Independent") {
    $ControllerType = $PodData.metadata.ownerReferences[0].kind
    $ControllerName = $PodData.metadata.ownerReferences[0].name

    Write-Host "`n3. Parent Controller detected ($ControllerType). To inspect its definition run:" -ForegroundColor Gray

    switch ($ControllerType) {
        "ReplicaSet" {
            $BaseDeploymentName = $ControllerName -replace '-[a-z0-9]+$', ''
            Write-Host "   kubectl describe deployment $BaseDeploymentName -n $PodNamespace" -ForegroundColor Yellow
            Write-Host "   kubectl get replicaset $ControllerName -n $PodNamespace -o wide" -ForegroundColor Yellow
        }
        "StatefulSet" { Write-Host "   kubectl describe sts $ControllerName -n $PodNamespace" -ForegroundColor Yellow }
        "DaemonSet"   { Write-Host "   kubectl describe ds $ControllerName -n $PodNamespace" -ForegroundColor Yellow }
        "Job"         { Write-Host "   kubectl describe job $ControllerName -n $PodNamespace" -ForegroundColor Yellow }
        default       { Write-Host "   kubectl describe $ControlledBy -n $PodNamespace" -ForegroundColor Yellow }
    }
} else {
    Write-Host "`n3. Standalone pod. To check resources in this namespace run:" -ForegroundColor Gray
    Write-Host "   kubectl get deployments,jobs,sts -n $PodNamespace" -ForegroundColor Yellow
}
Write-Host ""
##