<#
.SYNOPSIS
    Comprehensive diagnostic validator for AKS KEDA Add-on, Workload Identity, and Prometheus ScaledObjects.

.DESCRIPTION
    Validates end-to-end KEDA configuration on an Azure Kubernetes Service (AKS) cluster:
    1. Checks AKS KEDA add-on, OIDC issuer, and Workload Identity feature flags via Azure CLI (`az aks show`).
    2. Inspects KEDA Operator deployment, pod phase, environment variables (`AZURE_CLIENT_ID`, `AZURE_FEDERATED_TOKEN_FILE`), and projected volume mounts.
    3. Compares KEDA ServiceAccount client-id annotations with Azure Managed Identity configuration.
    4. Validates Federated Identity Credentials (issuer, subject, audience).
    5. Checks ScaledObject Prometheus triggers and TriggerAuthentication specs.
    6. Confirms 'Monitoring Data Reader' Azure RBAC role assignment on the Managed Identity.

.NOTES
    Prerequisites:
    - Azure CLI (`az`) logged in with permissions to inspect AKS and Managed Identities.
    - `kubectl` configured with cluster admin context.
#>

# ============================================================
# EDIT THESE VALUES
# ============================================================

$AksResourceGroup      = "rg-name"
$AksClusterName        = "aks-cluster-name"

$IdentityResourceGroup = "Identity-rg"
$IdentityName          = "identity-name"

$AppNamespace          = "namespace"
$ScaledObjectName      = "scaled-objectname"

# AKS managed KEDA add-on namespace
$KedaNamespace         = "kube-system"


# ============================================================
# CONNECT TO AKS
# ============================================================

Write-Host "`n=== Connecting to AKS ===" -ForegroundColor Cyan

az aks get-credentials `
    --resource-group $AksResourceGroup `
    --name $AksClusterName `
    --overwrite-existing

if ($LASTEXITCODE -ne 0) {
    throw "Unable to connect to AKS cluster."
}


# ============================================================
# CHECK WHETHER THE AKS KEDA ADD-ON IS ENABLED
# ============================================================

Write-Host "`n=== AKS KEDA Add-on Status ===" -ForegroundColor Cyan

$KedaAddonEnabled = az aks show `
    --resource-group $AksResourceGroup `
    --name $AksClusterName `
    --query "workloadAutoScalerProfile.keda.enabled" `
    --output tsv

Write-Host "KEDA add-on enabled: $KedaAddonEnabled"

if ($KedaAddonEnabled -eq "true") {
    Write-Host "PASS: AKS KEDA add-on is enabled." -ForegroundColor Green
}
else {
    Write-Host "FAIL: AKS KEDA add-on is not reported as enabled." -ForegroundColor Red
}


# ============================================================
# CHECK OIDC AND WORKLOAD IDENTITY
# ============================================================

Write-Host "`n=== AKS OIDC and Workload Identity ===" -ForegroundColor Cyan

$OidcIssuer = az aks show `
    --resource-group $AksResourceGroup `
    --name $AksClusterName `
    --query "oidcIssuerProfile.issuerUrl" `
    --output tsv

$WorkloadIdentityEnabled = az aks show `
    --resource-group $AksResourceGroup `
    --name $AksClusterName `
    --query "securityProfile.workloadIdentity.enabled" `
    --output tsv

Write-Host "OIDC issuer:               $OidcIssuer"
Write-Host "Workload Identity enabled: $WorkloadIdentityEnabled"

if ([string]::IsNullOrWhiteSpace($OidcIssuer)) {
    Write-Host "FAIL: AKS OIDC issuer is missing." -ForegroundColor Red
}
else {
    Write-Host "PASS: AKS OIDC issuer is configured." -ForegroundColor Green
}

if ($WorkloadIdentityEnabled -eq "true") {
    Write-Host "PASS: AKS Workload Identity is enabled." -ForegroundColor Green
}
else {
    Write-Host "FAIL: AKS Workload Identity is not enabled." -ForegroundColor Red
}


# ============================================================
# FIND THE KEDA OPERATOR DEPLOYMENT AND POD
# ============================================================

Write-Host "`n=== Discovering KEDA Operator ===" -ForegroundColor Cyan

$KedaDeployment = kubectl get deployments `
    -n $KedaNamespace `
    -o json |
    ConvertFrom-Json |
    Select-Object -ExpandProperty items |
    Where-Object {
        $_.metadata.name -match "keda.*operator" -and
        $_.metadata.name -notmatch "metrics|webhook"
    } |
    Select-Object -ExpandProperty metadata |
    Select-Object -ExpandProperty name `
    -First 1

if ([string]::IsNullOrWhiteSpace($KedaDeployment)) {
    Write-Host "FAIL: Unable to find the KEDA operator deployment." -ForegroundColor Red
    Write-Host "Available KEDA resources:" -ForegroundColor Yellow
    kubectl get deployment,pod,serviceaccount -n $KedaNamespace | Select-String "keda"
    throw "KEDA operator deployment not found."
}

$KedaPodJson = kubectl get pods `
    -n $KedaNamespace `
    -o json |
    ConvertFrom-Json |
    Select-Object -ExpandProperty items |
    Where-Object {
        $_.metadata.name -match "keda.*operator" -and
        $_.metadata.name -notmatch "metrics|webhook" -and
        $_.status.phase -eq "Running"
    } |
    Select-Object -First 1

if ($null -eq $KedaPodJson) {
    Write-Host "FAIL: Unable to find a running KEDA operator pod." -ForegroundColor Red
    kubectl get pods -n $KedaNamespace -o wide | Select-String "keda"
    throw "Running KEDA operator pod not found."
}

$KedaPod = $KedaPodJson.metadata.name
$KedaServiceAccount = $KedaPodJson.spec.serviceAccountName

Write-Host "KEDA namespace:      $KedaNamespace"
Write-Host "KEDA deployment:     $KedaDeployment"
Write-Host "KEDA pod:            $KedaPod"
Write-Host "KEDA ServiceAccount: $KedaServiceAccount"


# ============================================================
# CHECK KEDA OPERATOR IMAGE AND VERSION
# ============================================================

Write-Host "`n=== KEDA Operator Image ===" -ForegroundColor Cyan

$KedaImage = $KedaPodJson.spec.containers[0].image
Write-Host "KEDA operator image: $KedaImage"


# ============================================================
# CHECK WORKLOAD IDENTITY LABEL
# ============================================================

Write-Host "`n=== KEDA Workload Identity Pod Label ===" -ForegroundColor Cyan

$PodWiLabel = $KedaPodJson.metadata.labels.'azure.workload.identity/use'

$DeploymentJson = kubectl get deployment $KedaDeployment -n $KedaNamespace -o json | ConvertFrom-Json
$DeploymentWiLabel = $DeploymentJson.spec.template.metadata.labels.'azure.workload.identity/use'

Write-Host "Operator pod label:         $PodWiLabel"
Write-Host "Deployment template label:  $DeploymentWiLabel"

if ($PodWiLabel -eq "true") {
    Write-Host "PASS: KEDA operator pod has azure.workload.identity/use=true." -ForegroundColor Green
}
else {
    Write-Host "FAIL: KEDA operator pod is missing azure.workload.identity/use=true." -ForegroundColor Red
}

if ($DeploymentWiLabel -eq "true") {
    Write-Host "PASS: KEDA deployment template has the Workload Identity label." -ForegroundColor Green
}
else {
    Write-Host "FAIL: KEDA deployment template is missing the Workload Identity label." -ForegroundColor Red
}


# ============================================================
# CHECK KEDA SERVICEACCOUNT ANNOTATIONS
# ============================================================

Write-Host "`n=== KEDA ServiceAccount Annotations ===" -ForegroundColor Cyan

$SaJson = kubectl get serviceaccount $KedaServiceAccount -n $KedaNamespace -o json | ConvertFrom-Json
$SaClientId = $SaJson.metadata.annotations.'azure.workload.identity/client-id'
$SaTenantId = $SaJson.metadata.annotations.'azure.workload.identity/tenant-id'

Write-Host "ServiceAccount client ID: $SaClientId"
Write-Host "ServiceAccount tenant ID: $SaTenantId"

if ([string]::IsNullOrWhiteSpace($SaClientId)) {
    Write-Host "WARNING: ServiceAccount client-id annotation is missing." -ForegroundColor Yellow
}
else {
    Write-Host "PASS: ServiceAccount client-id annotation exists." -ForegroundColor Green
}


# ============================================================
# CHECK WORKLOAD IDENTITY ENVIRONMENT VARIABLES IN KEDA POD
# ============================================================

Write-Host "`n=== KEDA Operator Azure Environment Variables ===" -ForegroundColor Cyan

# Parsed from Pod JSON spec directly (no kubectl exec required)
$KedaEnvVars        = $KedaPodJson.spec.containers[0].env
$AzureClientId      = ($KedaEnvVars | Where-Object { $_.name -eq "AZURE_CLIENT_ID" }).value
$AzureTenantId      = ($KedaEnvVars | Where-Object { $_.name -eq "AZURE_TENANT_ID" }).value
$AzureTokenFile     = ($KedaEnvVars | Where-Object { $_.name -eq "AZURE_FEDERATED_TOKEN_FILE" }).value
$AzureAuthorityHost = ($KedaEnvVars | Where-Object { $_.name -eq "AZURE_AUTHORITY_HOST" }).value

Write-Host "AZURE_CLIENT_ID:            $AzureClientId"
Write-Host "AZURE_TENANT_ID:            $AzureTenantId"
Write-Host "AZURE_FEDERATED_TOKEN_FILE: $AzureTokenFile"
Write-Host "AZURE_AUTHORITY_HOST:       $AzureAuthorityHost"

if ([string]::IsNullOrWhiteSpace($AzureTokenFile)) {
    Write-Host "FAIL: AZURE_FEDERATED_TOKEN_FILE is missing from the KEDA operator." -ForegroundColor Red
    Write-Host "This can cause Prometheus requests to be sent without an Authorization header." -ForegroundColor Red
}
else {
    Write-Host "PASS: KEDA operator has the federated token environment variable." -ForegroundColor Green
}


# ============================================================
# CHECK PROJECTED TOKEN VOLUME
# ============================================================

Write-Host "`n=== KEDA Projected Token Volume ===" -ForegroundColor Cyan

$TokenVolume = $KedaPodJson.spec.volumes |
    Where-Object {
        $_.name -match "azure.*token" -or
        $_.projected.sources.serviceAccountToken.path -contains "azure-identity-token"
    }

$TokenMount = $KedaPodJson.spec.containers[0].volumeMounts |
    Where-Object {
        $_.mountPath -match "/var/run/secrets/azure/tokens"
    }

if ($TokenVolume) {
    Write-Host "PASS: Azure projected token volume exists." -ForegroundColor Green
    $TokenVolume | Select-Object name | Format-Table -AutoSize
}
else {
    Write-Host "FAIL: Azure projected token volume was not found." -ForegroundColor Red
}

if ($TokenMount) {
    Write-Host "PASS: Azure token volume mount exists." -ForegroundColor Green
    $TokenMount | Select-Object name, mountPath, readOnly | Format-Table -AutoSize
}
else {
    Write-Host "FAIL: Azure token volume mount was not found." -ForegroundColor Red
}


# ============================================================
# GET MANAGED IDENTITY VALUES
# ============================================================

Write-Host "`n=== Managed Identity Values ===" -ForegroundColor Cyan

$IdentityJson = az identity show `
    --resource-group $IdentityResourceGroup `
    --name $IdentityName `
    --output json

if ($LASTEXITCODE -ne 0) {
    throw "Unable to retrieve the specified managed identity."
}

$Identity = $IdentityJson | ConvertFrom-Json

Write-Host "Identity name:         $($Identity.name)"
Write-Host "Identity client ID:    $($Identity.clientId)"
Write-Host "Identity principal ID: $($Identity.principalId)"
Write-Host "Identity tenant ID:    $($Identity.tenantId)"
Write-Host "Identity resource ID:  $($Identity.id)"


# ============================================================
# COMPARE IDENTITY VALUES
# ============================================================

Write-Host "`n=== Identity Value Comparison ===" -ForegroundColor Cyan

if ($SaClientId -eq $Identity.clientId) {
    Write-Host "PASS: ServiceAccount client ID matches the managed identity." -ForegroundColor Green
}
elseif ([string]::IsNullOrWhiteSpace($SaClientId)) {
    Write-Host "WARNING: ServiceAccount does not contain a client-id annotation." -ForegroundColor Yellow
}
else {
    Write-Host "FAIL: ServiceAccount client ID does not match the managed identity." -ForegroundColor Red
    Write-Host "ServiceAccount:  $SaClientId"
    Write-Host "Managed identity: $($Identity.clientId)"
}

if ($AzureClientId -eq $Identity.clientId) {
    Write-Host "PASS: KEDA pod AZURE_CLIENT_ID matches the managed identity." -ForegroundColor Green
}
elseif ([string]::IsNullOrWhiteSpace($AzureClientId)) {
    Write-Host "FAIL: AZURE_CLIENT_ID is missing from the KEDA operator." -ForegroundColor Red
}
else {
    Write-Host "FAIL: KEDA pod AZURE_CLIENT_ID does not match the managed identity." -ForegroundColor Red
    Write-Host "KEDA pod:        $AzureClientId"
    Write-Host "Managed identity: $($Identity.clientId)"
}


# ============================================================
# VALIDATE FEDERATED IDENTITY CREDENTIAL
# ============================================================

Write-Host "`n=== Federated Identity Credential ===" -ForegroundColor Cyan

$ExpectedSubject = "system:serviceaccount:${KedaNamespace}:${KedaServiceAccount}"

Write-Host "Expected issuer:   $OidcIssuer"
Write-Host "Expected subject:  $ExpectedSubject"
Write-Host "Expected audience: api://AzureADTokenExchange"

$FederatedCredentialsJson = az identity federated-credential list `
    --resource-group $IdentityResourceGroup `
    --identity-name $IdentityName `
    --output json

$FederatedCredentials = $FederatedCredentialsJson | ConvertFrom-Json

$FederatedCredentials |
    Select-Object name, issuer, subject, audiences |
    Format-List

$MatchingFederation = $FederatedCredentials |
    Where-Object {
        $_.issuer.TrimEnd("/") -eq $OidcIssuer.TrimEnd("/") -and
        $_.subject -eq $ExpectedSubject -and
        $_.audiences -contains "api://AzureADTokenExchange"
    }

if ($MatchingFederation) {
    Write-Host "PASS: A matching federated identity credential was found." -ForegroundColor Green
    $MatchingFederation |
        Select-Object name, issuer, subject, audiences |
        Format-List
}
else {
    Write-Host "FAIL: No federated credential matches the KEDA operator." -ForegroundColor Red
    Write-Host "Required subject: $ExpectedSubject" -ForegroundColor Yellow
}


# ============================================================
# VALIDATE THE SCALEDOBJECT
# ============================================================

Write-Host "`n=== ScaledObject Configuration ===" -ForegroundColor Cyan

$ScaledObjectJson = kubectl get scaledobject $ScaledObjectName `
    -n $AppNamespace `
    -o json 2>$null

if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($ScaledObjectJson)) {
    Write-Host "FAIL: Unable to retrieve ScaledObject '$ScaledObjectName' in namespace '$AppNamespace'." -ForegroundColor Red
    throw "ScaledObject not found."
}

$ScaledObject = $ScaledObjectJson | ConvertFrom-Json

$PrometheusTrigger = $ScaledObject.spec.triggers |
    Where-Object { $_.type -eq "prometheus" } |
    Select-Object -First 1

if ($null -eq $PrometheusTrigger) {
    Write-Host "FAIL: No Prometheus trigger found in the ScaledObject." -ForegroundColor Red
}
else {
    Write-Host "Prometheus server:      $($PrometheusTrigger.metadata.serverAddress)"
    Write-Host "Prometheus metric name: $($PrometheusTrigger.metadata.metricName)"
    Write-Host "Prometheus query:       $($PrometheusTrigger.metadata.query)"
    Write-Host "Threshold:              $($PrometheusTrigger.metadata.threshold)"
    Write-Host "Authentication name:    $($PrometheusTrigger.authenticationRef.name)"
    Write-Host "Authentication kind:    $($PrometheusTrigger.authenticationRef.kind)"
}


# ============================================================
# VALIDATE TRIGGERAUTHENTICATION
# ============================================================

Write-Host "`n=== TriggerAuthentication Configuration ===" -ForegroundColor Cyan

$TriggerAuthName = $PrometheusTrigger.authenticationRef.name
$TriggerAuthKind = $PrometheusTrigger.authenticationRef.kind

if ([string]::IsNullOrWhiteSpace($TriggerAuthName)) {
    Write-Host "FAIL: Prometheus trigger does not have authenticationRef.name." -ForegroundColor Red
}
else {
    if ($TriggerAuthKind -eq "ClusterTriggerAuthentication") {
        $TriggerAuthJson = kubectl get clustertriggerauthentication $TriggerAuthName `
            -o json 2>$null
    }
    else {
        $TriggerAuthJson = kubectl get triggerauthentication $TriggerAuthName `
            -n $AppNamespace `
            -o json 2>$null
    }

    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($TriggerAuthJson)) {
        Write-Host "FAIL: Authentication object '$TriggerAuthName' could not be found." -ForegroundColor Red
    }
    else {
        $TriggerAuth = $TriggerAuthJson | ConvertFrom-Json

        $TriggerProvider   = $TriggerAuth.spec.podIdentity.provider
        $TriggerIdentityId = $TriggerAuth.spec.podIdentity.identityId

        Write-Host "Authentication object: $TriggerAuthName"
        Write-Host "Identity provider:     $TriggerProvider"
        Write-Host "Configured identityId: $TriggerIdentityId"
        Write-Host "Expected client ID:    $($Identity.clientId)"

        if ($TriggerProvider -eq "azure-workload") {
            Write-Host "PASS: TriggerAuthentication provider is azure-workload." -ForegroundColor Green
        }
        else {
            Write-Host "FAIL: Provider should be azure-workload." -ForegroundColor Red
        }

        if ($TriggerIdentityId -eq $Identity.clientId) {
            Write-Host "PASS: TriggerAuthentication identityId matches the identity client ID." -ForegroundColor Green
        }
        elseif ([string]::IsNullOrWhiteSpace($TriggerIdentityId)) {
            Write-Host "WARNING: TriggerAuthentication identityId is empty." -ForegroundColor Yellow
        }
        else {
            Write-Host "FAIL: TriggerAuthentication identityId does not match the managed identity client ID." -ForegroundColor Red
        }
    }
}


# ============================================================
# CHECK MONITORING DATA READER ROLE
# ============================================================

Write-Host "`n=== Managed Identity Azure Role Assignments ===" -ForegroundColor Cyan

# 1. Retrieve the Principal ID using the Identity Name
$PrincipalId = az identity show `
    --name $IdentityName `
    --resource-group $IdentityResourceGroup `
    --query principalId `
    --output tsv

if (-not $PrincipalId) {
    Write-Host "ERROR: Could not find Managed Identity '$IdentityName' in resource group '$IdentityResourceGroup'." -ForegroundColor Red
}
else {
    # 2. Get role assignments for the resolved Principal ID
    $RoleAssignmentsJson = az role assignment list `
        --assignee $PrincipalId `
        --include-inherited `
        --all `
        --output json

    $RoleAssignments = $RoleAssignmentsJson | ConvertFrom-Json

    # 3. Filter for "Monitoring Data Reader" role
    $MonitoringRoles = $RoleAssignments |
        Where-Object {
            $_.roleDefinitionName -eq "Monitoring Data Reader"
        }

    if ($MonitoringRoles) {
        Write-Host "PASS: Monitoring Data Reader role assignment found for '$IdentityName'." -ForegroundColor Green
        $MonitoringRoles |
            Select-Object roleDefinitionName, scope |
            Format-Table -AutoSize
    }
    else {
        Write-Host "FAIL: Monitoring Data Reader role assignment was not found for '$IdentityName'." -ForegroundColor Red
    }
}

# ============================================================
# GET RECENT KEDA PROMETHEUS/AUTHENTICATION LOGS
# ============================================================

Write-Host "`n=== Recent KEDA Authentication and Prometheus Logs ===" -ForegroundColor Cyan

kubectl logs `
    -n $KedaNamespace `
    $KedaPod `
    --since=30m 2>$null |
    Select-String `
        -Pattern "prometheus|Unauthorized|Authorization|azure|token|identity|credential|error"


# ============================================================
# FINAL SUMMARY
# ============================================================

Write-Host "`n=== Final Validation Summary ===" -ForegroundColor Cyan

$Failures = @()

if ($KedaAddonEnabled -ne "true") {
    $Failures += "AKS KEDA add-on is not enabled."
}

if ($WorkloadIdentityEnabled -ne "true") {
    $Failures += "AKS Workload Identity is not enabled."
}

if ([string]::IsNullOrWhiteSpace($OidcIssuer)) {
    $Failures += "AKS OIDC issuer is missing."
}

if ($PodWiLabel -ne "true") {
    $Failures += "KEDA operator pod is missing azure.workload.identity/use=true."
}

if ([string]::IsNullOrWhiteSpace($AzureClientId)) {
    $Failures += "KEDA operator is missing AZURE_CLIENT_ID."
}

if ([string]::IsNullOrWhiteSpace($AzureTokenFile)) {
    $Failures += "KEDA operator is missing AZURE_FEDERATED_TOKEN_FILE."
}

if (-not $TokenVolume) {
    $Failures += "KEDA operator is missing the projected Azure token volume."
}

if (-not $MatchingFederation) {
    $Failures += "No federated identity credential matches the KEDA ServiceAccount."
}

if ($TriggerProvider -ne "azure-workload") {
    $Failures += "TriggerAuthentication provider is not azure-workload."
}

if (
    -not [string]::IsNullOrWhiteSpace($TriggerIdentityId) -and
    $TriggerIdentityId -ne $Identity.clientId
) {
    $Failures += "TriggerAuthentication identityId does not match the managed identity client ID."
}

if (-not $MonitoringRoles) {
    $Failures += "Monitoring Data Reader role assignment was not found."
}

if ($Failures.Count -eq 0) {
    Write-Host "PASS: All main KEDA Workload Identity validations passed." -ForegroundColor Green
}
else {
    Write-Host "The following problems were detected:" -ForegroundColor Red

    foreach ($Failure in $Failures) {
        Write-Host " - $Failure" -ForegroundColor Red
    }
}

Write-Host "`nValidation completed." -ForegroundColor Cyan