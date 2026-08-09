<#
.SYNOPSIS
    Interactive Kubernetes traffic flow and routing tracer for Istio mesh VirtualServices.

.DESCRIPTION
    Scans a selected namespace for Istio VirtualServices, allows interactive selection of routing paths/prefixes, 
    maps target Kubernetes Services, dynamically resolves pod selectors (including metadata label fallback), 
    and outputs a live ASCII topology diagram showing traffic flow from VirtualService -> Service -> Pods.

.NOTES
    Prerequisites:
    - `kubectl` connected to an active Kubernetes cluster with Istio CRDs installed.
    - Cluster permissions to read VirtualServices (`networking.istio.io`), Services, and Pods.
#>

# -----------------------------------------------------------------------------
# Script: AKS-TrafficCheck.ps1
# Description: Traffic tracer using direct native kubectl commands for pod label printing
# -----------------------------------------------------------------------------
Clear-Host
Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "     KUBERNETES TRAFFIC FLOW AND ROUTING TRACER     " -ForegroundColor Cyan
Write-Host "====================================================" -ForegroundColor Cyan

# Verify cluster connectivity
$CurrentContext = kubectl config current-context 2>$null
if (-not $CurrentContext) { Write-Error "No cluster connection."; exit }

# 1. Fetch available namespaces
Write-Host "Scanning cluster namespaces..." -ForegroundColor Gray
$RawNamespaces = kubectl get namespaces -o json | ConvertFrom-Json
$NsMenuMap = @{}
$NsIndex = 1

Write-Host "Select a Namespace to trace:" -ForegroundColor Yellow
foreach ($Ns in $RawNamespaces.items) {
    Write-Host "[$NsIndex] " -NoNewline -ForegroundColor Cyan
    Write-Host "$($Ns.metadata.name)" -ForegroundColor White
    $NsMenuMap.Add($NsIndex, $Ns.metadata.name)
    $NsIndex++
}
$SelectedNsIndex = [int](Read-Host "Enter namespace number")
if (-not $NsMenuMap.ContainsKey($SelectedNsIndex)) { exit }
$Namespace = $NsMenuMap[$SelectedNsIndex]

# 2. Fetch and list VirtualServices
Write-Host "Fetching VirtualServices (VS) in namespace: $Namespace..." -ForegroundColor Gray
$VirtualServices = kubectl get virtualservices -n $Namespace -o json 2>$null | ConvertFrom-Json

if ($null -eq $VirtualServices -or $null -eq $VirtualServices.items -or $VirtualServices.items.Count -eq 0) {
    Write-Error "No VirtualServices found in namespace: $Namespace."
    exit
}

Write-Host "Select VirtualService (VS) to Inspect:" -ForegroundColor Yellow
$VsIndex = 1
$VsMenuMap = @{}

foreach ($Vs in $VirtualServices.items) {
    $VsName = $Vs.metadata.name
    $VsHosts = [string]::Join(", ", $Vs.spec.hosts)
    
    Write-Host "[$VsIndex] " -NoNewline -ForegroundColor Cyan
    Write-Host "VS: " -NoNewline -ForegroundColor DarkGray
    Write-Host "$VsName " -NoNewline -ForegroundColor White
    Write-Host "(Hosts bound: $VsHosts)" -ForegroundColor Yellow
    $VsMenuMap.Add($VsIndex, $Vs)
    $VsIndex++
}

$SelectedVsIndex = [int](Read-Host "Enter VS number to inspect paths")
if (-not $VsMenuMap.ContainsKey($SelectedVsIndex)) { exit }
$SelectedVSData = $VsMenuMap[$SelectedVsIndex]

# 3. Tabular Menu Generation for Routes
Write-Host "`nParsing multi-site routing paths..." -ForegroundColor Gray
$PathMenuMap = @{}
$PathIndex = 1
$RouteTableRows = @()

foreach ($RouteRule in $SelectedVSData.spec.http) {
    $PathString = "/"
    $PathType = "Prefix"
    
    if ($RouteRule.match) {
        $MatchObj = $RouteRule.match[0]
        if ($MatchObj.uri.prefix) {
            $PathString = $MatchObj.uri.prefix
            $PathType = "Prefix"
        } elseif ($MatchObj.uri.regex) {
            $PathString = $MatchObj.uri.regex
            $PathType = "Regex"
        }
    }
    
    $TargetSvc = $RouteRule.route[0].destination.host
    if ($TargetSvc -match "^([^.]+)") { $TargetSvcName = $Matches[1] } else { $TargetSvcName = $TargetSvc }

    $RouteRow = [PSCustomObject]@{
        "ID"             = $PathIndex
        "Routing Type"   = $PathType
        "Regex Path / Prefix" = $PathString
        "Target Service" = $TargetSvcName
    }
    $RouteTableRows += $RouteRow

    $PathMenuMap.Add($PathIndex, @{ 
        "Path"    = $PathString; 
        "Type"    = $PathType;
        "Svc"     = $TargetSvcName; 
        "VsName"  = $SelectedVSData.metadata.name; 
        "Host"    = $SelectedVSData.spec.hosts[0] 
    })
    $PathIndex++
}

Write-Host "`nSelect the Path Route you want to troubleshoot:" -ForegroundColor Yellow
$RouteTableRows | Format-Table -AutoSize

$SelectedPathIndex = [int](Read-Host "Enter ID number to map traffic")
if (-not $PathMenuMap.ContainsKey($SelectedPathIndex)) { exit }
$TargetRoute = $PathMenuMap[$SelectedPathIndex]

# 4. Gather live target Service configurations
Write-Host "Mapping live cluster routing topology..." -ForegroundColor Cyan
$SvcName = $TargetRoute.Svc
$SvcData = kubectl get svc $SvcName -n $Namespace -o json 2>$null | ConvertFrom-Json

if (-not $SvcData) {
    Write-Error "Target service $SvcName bound by VirtualService no longer exists."
    exit
}

$SvcPort = $SvcData.spec.ports[0].port
$TargetPort = $SvcData.spec.ports[0].targetPort

# --- NATIVE KUBERNETES SELECTOR QUERY ENGINE ---
$GoTemplate = '{{range $k, $v := .spec.selector}}{{$k}}={{$v}},{{end}}'
$SelectorString = kubectl get svc $SvcName -n $Namespace -o go-template=$GoTemplate 2>$null
if ($SelectorString) { $SelectorString = $SelectorString.TrimEnd(',') }

$UsingMetadataLabels = $false

if ([string]::IsNullOrWhiteSpace($SelectorString)) {
    $UsingMetadataLabels = $true
    $GoTemplateMetadata = '{{range $k, $v := .metadata.labels}}{{if not (regexMatch "kubernetes.io|argocd" $k)}}{{$k}}={{$v}},{{end}}{{end}}'
    $SelectorString = kubectl get svc $SvcName -n $Namespace -o go-template=$GoTemplateMetadata 2>$null
    if ($SelectorString) { $SelectorString = $SelectorString.TrimEnd(',') }
}

# Fetch pods using native selectors flag
$MatchedPods = @()
if (-not [string]::IsNullOrWhiteSpace($SelectorString)) {
    $PodsJson = kubectl get pods -n $Namespace -l $SelectorString -o json 2>$null
    if ($PodsJson) {
        $PodsObject = $PodsJson | ConvertFrom-Json
        if ($PodsObject.items) { $MatchedPods = $PodsObject.items }
    }
}

# 5. Generate Diagram Output
Clear-Host
Write-Host "===============================================================================" -ForegroundColor Cyan
Write-Host "  LIVE TRAFFIC ROUTING MAP FOR VIRTUALSERVICE: $($TargetRoute.VsName)" -ForegroundColor Cyan
Write-Host "===============================================================================" -ForegroundColor Cyan

# Step A: VirtualService Level
Write-Host " [ISTIO VIRTUAL SERVICE ENTRYPOINT] " -ForegroundColor Magenta
Write-Host "   |- " -NoNewline -ForegroundColor DarkGray
Write-Host "VS Name       : " -NoNewline -ForegroundColor White
Write-Host "$($TargetRoute.VsName)" -ForegroundColor Yellow
Write-Host "   |- " -NoNewline -ForegroundColor DarkGray
Write-Host "Matching Domain : " -NoNewline -ForegroundColor White
Write-Host "$($TargetRoute.Host)" -ForegroundColor Yellow
Write-Host "   |- " -NoNewline -ForegroundColor DarkGray
Write-Host "Path Config   : " -NoNewline -ForegroundColor White
Write-Host "[$($TargetRoute.Type)] " -NoNewline -ForegroundColor Magenta
Write-Host "$($TargetRoute.Path)" -ForegroundColor Cyan
Write-Host "         |" -ForegroundColor Green
Write-Host "         v [Mesh Virtual Envoy Path Matching Rule]" -ForegroundColor Green
Write-Host "         |" -ForegroundColor Green

# Step B: Target Service Level
Write-Host " [KUBERNETES TARGET SERVICE] " -ForegroundColor Magenta
Write-Host "   |- " -NoNewline -ForegroundColor DarkGray
Write-Host "Name       : " -NoNewline -ForegroundColor White
Write-Host "$SvcName" -ForegroundColor Yellow
Write-Host "   |- " -NoNewline -ForegroundColor DarkGray
Write-Host "Cluster IP : " -NoNewline -ForegroundColor White
Write-Host "$($SvcData.spec.clusterIP)" -ForegroundColor Yellow

Write-Host "   |- " -NoNewline -ForegroundColor DarkGray
if ($UsingMetadataLabels) {
    Write-Host "SVC Selectors (EMPTY! Falling back to Metadata Labels): " -NoNewline -ForegroundColor Red
} else {
    Write-Host "SVC Selectors (spec.selector): " -NoNewline -ForegroundColor White
}

if ([string]::IsNullOrWhiteSpace($SelectorString)) {
    Write-Host "NONE FOUND" -ForegroundColor Red
} else {
    Write-Host "$SelectorString" -ForegroundColor Cyan
}

Write-Host "   |- " -NoNewline -ForegroundColor DarkGray
Write-Host "Port Map   : " -NoNewline -ForegroundColor White
Write-Host "Mesh Port " -NoNewline -ForegroundColor DarkGray
Write-Host "$SvcPort " -NoNewline -ForegroundColor Yellow
Write-Host "-> " -NoNewline -ForegroundColor White
Write-Host "TargetPort " -NoNewline -ForegroundColor DarkGray
Write-Host "$TargetPort" -ForegroundColor Yellow
Write-Host "         |" -ForegroundColor Green
Write-Host "         v [Endpoints Allocation Load Balancer]" -ForegroundColor Green

# Step C: Pod Targets Loop (REWRITTEN USING DIRECT NATIVE KUBERNETES LABEL EXTRACTION)
if ($MatchedPods.Count -eq 0) {
    Write-Host "         |" -ForegroundColor Green
    Write-Host "         |- CRITICAL: NO HEALTHY BACKEND PODS FOUND MATCHING SELECTORS ($SelectorString)" -ForegroundColor Red
} else {
    foreach ($Pod in $MatchedPods) {
        $PName = $Pod.metadata.name
        $PIp = $Pod.status.podIP
        if ([string]::IsNullOrEmpty($PIp)) { $PIp = "No IP Assigned" }
        $PNode = $Pod.spec.nodeName
        
        # --- NEW DIRECT KUBERNETES QUERY FOR CLEAN LABEL STRINGS ---
        # Runs 'kubectl get pod <name> --show-labels' and isolates the raw label block cleanly
        $RawLabelOutput = kubectl get pod $PName -n $Namespace --show-labels 2>$null
        $PodLabelText = "None Found"
        
        if ($RawLabelOutput -and $RawLabelOutput.Count -gt 1) {
            # Split the second line of output by whitespace columns to extract the final LABELS column string
            $Columns = $RawLabelOutput[1] -split '\s+'
            if ($Columns.Count -ge 6) {
                $RawLabels = $Columns[-1] # The labels column is always the last item element
                
                # Strip out the pod-template-hash value to keep your console line clean
                $CleanedLabelList = @()
                foreach ($L in ($RawLabels -split ',')) {
                    if ($L -notmatch "pod-template-hash") { $CleanedLabelList += $L }
                }
                $PodLabelText = [string]::Join(', ', $CleanedLabelList)
            }
        }

        $ReadyCond = $Pod.status.conditions | Where-Object { $_.type -eq "Ready" }
        if ($ReadyCond.status -eq "True") { $PodColor = "Green"; $StatusLabel = "READY / RUNNING" }
        else { $PodColor = "Red"; $StatusLabel = "NOT READY" }

        if ($UsingMetadataLabels) {
            $StatusLabel += " (WARNING: MATCHED BY METADATA LABELS - CHECK SELECTORS)"
            $PodColor = "Yellow"
        }

        Write-Host "         |" -ForegroundColor Green
        Write-Host "         |-> " -NoNewline -ForegroundColor Green
        Write-Host "[POD INSTANCE] " -NoNewline -ForegroundColor Magenta
        Write-Host "--- Status: " -NoNewline -ForegroundColor White
        Write-Host "$StatusLabel" -ForegroundColor $PodColor
        
        Write-Host "               |- " -NoNewline -ForegroundColor DarkGray
        Write-Host "Name      : " -NoNewline -ForegroundColor White
        Write-Host "$PName" -ForegroundColor Yellow
        
        Write-Host "               |- " -NoNewline -ForegroundColor DarkGray
        Write-Host "Pod Labels: " -NoNewline -ForegroundColor White
        Write-Host "$PodLabelText" -ForegroundColor Cyan
        
        Write-Host "               |- " -NoNewline -ForegroundColor DarkGray
        Write-Host "Pod IP    : " -NoNewline -ForegroundColor White
        Write-Host "$PIp" -ForegroundColor Yellow
        
        Write-Host "               |- " -NoNewline -ForegroundColor DarkGray
        Write-Host "Host Node : " -NoNewline -ForegroundColor White
        Write-Host "$PNode" -ForegroundColor Yellow
    }
}

Write-Host "`n===============================================================================" -ForegroundColor Gray
Write-Host " DIAGNOSTIC COMMANDS SUMMARY:" -ForegroundColor White
Write-Host "   Check Mesh Rules    : " -NoNewline -ForegroundColor DarkGray
Write-Host "kubectl describe virtualservice $($TargetRoute.VsName) -n $Namespace" -ForegroundColor Yellow
Write-Host "   Check Svc Endpoints : " -NoNewline -ForegroundColor DarkGray
Write-Host "kubectl get endpoints $SvcName -n $Namespace" -ForegroundColor Yellow
Write-Host "===============================================================================" -ForegroundColor Gray