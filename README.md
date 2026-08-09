# Azure & Kubernetes (AKS) PowerShell Automation Scripts

[![PowerShell 5.1+](https://img.shields.io/badge/PowerShell-5.1%2B%20%7C%207.x-blue.svg)](https://docs.microsoft.com/powershell/)
[![Azure CLI](https://img.shields.io/badge/Azure%20CLI-2.30%2B-0089D6.svg)](https://docs.microsoft.com/cli/azure/)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-kubectl-326CE5.svg)](https://kubernetes.io/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

An enterprise-grade collection of **PowerShell scripts** designed for system administrators, DevOps engineers, and cloud architects to manage, monitor, troubleshoot, and automate **Microsoft Azure** services and **Azure Kubernetes Service (AKS)** clusters.

---

## 📋 Table of Contents

- [Repository Overview](#-repository-overview)
- [Prerequisites & Requirements](#-prerequisites--requirements)
- [Directory Structure](#-directory-structure)
- [Script Catalog](#-script-catalog)
  - [Azure Kubernetes Service (AKS) & Container Management](#1-azure-kubernetes-service-aks--container-management-aks)
  - [Azure Virtual Desktop (AVD) & VM Operations](#2-azure-virtual-desktop-avd--vm-operations-azure)
  - [Traffic Routing & Flowchart Visualization](#3-traffic-routing--flowchart-visualization-azure)
  - [Azure SQL Database Administration & Sizing](#4-azure-sql-database-administration--sizing-azure)
  - [Security, PKI & Access Control](#5-security-pki--access-control-azure)
  - [Resource Tagging & Management](#6-resource-tagging--management-azure)
- [Usage Examples](#-usage-examples)
- [Built-In Help & AST Verification](#-built-in-help--ast-verification)
- [Contributing](#-contributing)
- [License](#-license)

---

## 📌 Repository Overview

This repository provides reusable, modular PowerShell automation scripts for Azure infrastructure management. Every script includes:
- **Standard Comment-Based Help** (`.SYNOPSIS`, `.DESCRIPTION`, `.NOTES`).
- **Explicit `#Requires` statements** declaring dependent PowerShell modules.
- **Robust error handling** and interactive menu prompts.
- **Clean output formatting** (Console tables, GUI `Out-GridView`, HTML Mermaid flowcharts, CSV exports).

---

## ⚙️ Prerequisites & Requirements

### PowerShell Version
- **PowerShell 5.1+** (Windows PowerShell) or **PowerShell 7.x+** (PowerShell Core).

### Required PowerShell Modules
Install the necessary Azure modules from the PowerShell Gallery:
```powershell
# Install Azure Az module collection
Install-Module -Name Az -Scope CurrentUser -Repository PSGallery -Force

# Install Azure Active Directory module (for AD Group management)
Install-Module -Name AzureAD -Scope CurrentUser -Repository PSGallery -Force

# Install SQL Server module (for Invoke-Sqlcmd queries)
Install-Module -Name SqlServer -Scope CurrentUser -Repository PSGallery -Force
```

### External Command-Line Tools
Ensure the following CLI utilities are installed and available in your system environment `PATH`:
| Tool | Purpose | Download Link |
| :--- | :--- | :--- |
| **Azure CLI (`az`)** | Azure authentication and resource commands | [Install Azure CLI](https://docs.microsoft.com/cli/azure/install-azure-cli) |
| **kubectl** | Kubernetes cluster administration | [Install kubectl](https://kubernetes.io/docs/tasks/tools/) |
| **kubelogin** | Azure AD token authentication for AKS | [Install kubelogin](https://azure.github.io/kubelogin/install.html) |
| **OpenSSL** | PKI self-signed certificate hierarchy generation | [Download OpenSSL](https://slproweb.com/products/Win32OpenSSL.html) |

---

## 📂 Directory Structure

```text
Powershell-Scripts/
├── AKS/                        # Azure Kubernetes Service & Container Scripts
│   ├── AKS Credential Download.ps1
│   ├── AKS-Connect-v1.ps1
│   ├── AKS-Istio-TrafficFlowCheck.ps1
│   ├── AKS_connect.ps1
│   ├── AKS_Node_Pool_Migration.ps1
│   ├── GetPodLogs.ps1
│   ├── Keda-Config-Validation.ps1
│   └── PodTroubleshoot.ps1
├── Azure/                      # Azure Cloud Infrastructure Administration Scripts
│   ├── AD-Group-Owner addition.ps1
│   ├── AFD-Flowchart.ps1
│   ├── AppGateway-Flowchart.ps1
│   ├── Application URL Response Monitor.ps1
│   ├── Archive DB Index rebuild with Auto Resize.ps1
│   ├── AVD Auto-Restart VM.ps1
│   ├── AVD VM Autoshutdown.ps1
│   ├── DB Query Run.ps1
│   ├── DB_Details_Check.ps1
│   ├── DB_Used space check-v1.ps1
│   ├── List Resource without tags.ps1
│   ├── SelfCert-Creation-Existing Root.ps1
│   ├── SelfSignedCert_creation.ps1
│   ├── Specific RG SQL Server DB_DTU Size List.ps1
│   ├── SQL-Connection-Monitor.ps1
│   ├── Tag-Copy to RG.ps1
│   ├── TAG-Update ALL Resources.ps1
│   ├── Tag-Value-View-ALLRG.ps1
│   ├── User Access Removal.ps1
│   └── VM-AutoShutdown.ps1
├── LICENSE                     # MIT Open-Source License
└── README.md                   # Repository Documentation
```

---

## 🛠️ Script Catalog

### 1. Azure Kubernetes Service (AKS) & Container Management (`AKS/`)

| Script File | Synopsis / Functionality |
| :--- | :--- |
| **[AKS Credential Download.ps1](file:///d:/Dinesh/Script/Powershell-Scripts/AKS/AKS%20Credential%20Download.ps1)** | Queries active Azure CLI subscription for all deployed AKS clusters and batch-downloads/merges cluster access credentials into local `~/.kube/config`. |
| **[AKS-Connect-v1.ps1](file:///d:/Dinesh/Script/Powershell-Scripts/AKS/AKS-Connect-v1.ps1)** | Interactive CLI to download AKS cluster credentials into separate environment files (Non-prod/Prod), switch cluster contexts, select namespaces, and convert Azure AD tokens via `kubelogin`. |
| **[AKS-Istio-TrafficFlowCheck.ps1](file:///d:/Dinesh/Script/Powershell-Scripts/AKS/AKS-Istio-TrafficFlowCheck.ps1)** | Interactive traffic tracer for Istio mesh VirtualServices. Maps route paths, target Services, resolves pod selectors, and outputs an ASCII topology map. |
| **[AKS_connect.ps1](file:///d:/Dinesh/Script/Powershell-Scripts/AKS/AKS_connect.ps1)** | Scans `~/.kube/` for config files, updates `$env:KUBECONFIG`, prompts for context and default namespace selection, and executes `kubelogin` conversion. |
| **[AKS_Node_Pool_Migration.ps1](file:///d:/Dinesh/Script/Powershell-Scripts/AKS/AKS_Node_Pool_Migration.ps1)** | Automates workload migration between AKS node pools: creates new node pool, cordons old nodes, drains active pods via `kubectl drain`, verifies pod status, and deletes old node pool. |
| **[GetPodLogs.ps1](file:///d:/Dinesh/Script/Powershell-Scripts/AKS/GetPodLogs.ps1)** | Interactive log fetcher and parser. Fetches pod logs live via `kubectl` or reads disk files, parses Java/Spring/K8s entries, extracts metadata (User/Task IDs), and filters by log level or keywords. |
| **[Keda-Config-Validation.ps1](file:///d:/Dinesh/Script/Powershell-Scripts/AKS/Keda-Config-Validation.ps1)** | Diagnostic suite validating AKS KEDA add-on, OIDC issuer, Workload Identity, ServiceAccount annotations, federated credentials, Prometheus ScaledObjects, and Azure RBAC role assignments. |
| **[PodTroubleshoot.ps1](file:///d:/Dinesh/Script/Powershell-Scripts/AKS/PodTroubleshoot.ps1)** | Interactive pod troubleshooting wizard. Filters Ready/Not-Ready pods, parses container limits, requests, environment variables, mounts, lifecycle events, and suggests kubectl diagnostic commands. |

---

### 2. Azure Virtual Desktop (AVD) & VM Operations (`Azure/`)

| Script File | Synopsis / Functionality |
| :--- | :--- |
| **[AVD Auto-Restart VM.ps1](file:///d:/Dinesh/Script/Powershell-Scripts/Azure/AVD%20Auto-Restart%20VM.ps1)** | Scheduled maintenance workflow for AVD Host Pools: enables drain mode, notifies active users with pop-up messages to save work, waits for grace period, restarts session host VMs, and re-enables logins. |
| **[AVD VM Autoshutdown.ps1](file:///d:/Dinesh/Script/Powershell-Scripts/Azure/AVD%20VM%20Autoshutdown.ps1)** | Azure Function App timer script that evaluates session host connections in AVD host pools and automatically stops idle VMs with zero active connections. |
| **[VM-AutoShutdown.ps1](file:///d:/Dinesh/Script/Powershell-Scripts/Azure/VM-AutoShutdown.ps1)** | Checks logged-in user sessions on Azure VMs via WinRM / PSRemoting (`quser`), fetches admin credentials from Key Vault, and executes async deallocate/shutdown (`Stop-AzVM -NoWait`) for idle VMs. |

---

### 3. Traffic Routing & Flowchart Visualization (`Azure/`)

| Script File | Synopsis / Functionality |
| :--- | :--- |
| **[AFD-Flowchart.ps1](file:///d:/Dinesh/Script/Powershell-Scripts/Azure/AFD-Flowchart.ps1)** | Interactively prompts for Azure Front Door profile, Endpoint, and Route, maps custom domains, SSL certificates, WAF rule sets, origin groups, and origins, exporting an interactive HTML flowchart powered by Mermaid.js. |
| **[AppGateway-Flowchart.ps1](file:///d:/Dinesh/Script/Powershell-Scripts/Azure/AppGateway-Flowchart.ps1)** | Traces Azure Application Gateway routing topology (Listeners, URL path maps, path rules, HTTP settings, backend pools, backend targets) and generates a visual Mermaid.js HTML diagram opened in default browser. |

---

### 4. Azure SQL Database Administration & Sizing (`Azure/`)

| Script File | Synopsis / Functionality |
| :--- | :--- |
| **[Archive DB Index rebuild with Auto Resize.ps1](file:///d:/Dinesh/Script/Powershell-Scripts/Azure/Archive%20DB%20Index%20rebuild%20with%20Auto%20Resize.ps1)** | Dynamically scales Azure SQL Database DTU tiers up (e.g. S2 -> S3), executes parallel index maintenance stored procedures (`Invoke-Sqlcmd`), monitors completion, and restores databases to original DTU size. |
| **[DB Query Run.ps1](file:///d:/Dinesh/Script/Powershell-Scripts/Azure/DB%20Query%20Run.ps1)** | Interactively executes SQL queries across multiple Azure SQL Servers and databases using GUI selection (`Out-GridView`) via Azure AD Access Tokens or Key Vault secrets. |
| **[DB_Details_Check.ps1](file:///d:/Dinesh/Script/Powershell-Scripts/Azure/DB_Details_Check.ps1)** | Enumerates Azure SQL Servers, presents a selection menu, evaluates database compute models (DTU / Serverless / Provisioned vCore), editions, SKUs, max size, and backup redundancy into a clean table. |
| **[DB_Used space check-v1.ps1](file:///d:/Dinesh/Script/Powershell-Scripts/Azure/DB_Used%20space%20check-v1.ps1)** | Queries Azure Monitor metrics (`storage` & `storage_percent`) to calculate used space in GB vs max allocated size, geo-replication status, and DTU sizes for databases across subscriptions. |
| **[Specific RG SQL Server DB_DTU Size List.ps1](file:///d:/Dinesh/Script/Powershell-Scripts/Azure/Specific%20RG%20SQL%20Server%20DB_DTU%20Size%20List.ps1)** | Lists all Azure SQL Databases within a specific Resource Group & Server along with max size in GB, edition, and requested/current DTU or vCore service objectives. |
| **[SQL-Connection-Monitor.ps1](file:///d:/Dinesh/Script/Powershell-Scripts/Azure/SQL-Connection-Monitor.ps1)** | Periodically polls active sessions against `sys.sysprocesses` on an Azure SQL database via ADO.NET (`SqlConnection`), summarizing session counts per host and logging timestamped rows to a CSV file. |

---

### 5. Security, PKI & Access Control (`Azure/`)

| Script File | Synopsis / Functionality |
| :--- | :--- |
| **[AD-Group-Owner addition.ps1](file:///d:/Dinesh/Script/Powershell-Scripts/Azure/AD-Group-Owner%20addition.ps1)** | Prompts for user UPNs, iterates through target Azure Active Directory group display names, checks current ownership, and adds missing users as group owners via the `AzureAD` module. |
| **[User Access Removal.ps1](file:///d:/Dinesh/Script/Powershell-Scripts/Azure/User%20Access%20Removal.ps1)** | Resolves Azure AD Object ID for a user email (UPN), iterates through role assignments across Key Vault, AKS, Resource Group, and Subscription scopes, and removes assignments via `Remove-AzRoleAssignment`. |
| **[SelfSignedCert_creation.ps1](file:///d:/Dinesh/Script/Powershell-Scripts/Azure/SelfSignedCert_creation.ps1)** | Generates a complete 3-tier self-signed PKI hierarchy via OpenSSL: Root CA (10-year), Intermediate CA (10-year), and Server Cert with Subject Alternative Names (SANs), exported as a PFX bundle. |
| **[SelfCert-Creation-Existing Root.ps1](file:///d:/Dinesh/Script/Powershell-Scripts/Azure/SelfCert-Creation-Existing%20Root.ps1)** | Generates an OpenSSL server configuration file with SANs, creates CSR, signs the certificate using an existing Intermediate CA cert/key, and exports a password-protected PFX file for IIS. |

---

### 6. Resource Tagging & Management (`Azure/`)

| Script File | Synopsis / Functionality |
| :--- | :--- |
| **[List Resource without tags.ps1](file:///d:/Dinesh/Script/Powershell-Scripts/Azure/List%20Resource%20without%20tags.ps1)** | Scans an Azure Resource Group via `Get-AzResource` and lists all child resources missing tags. |
| **[TAG-Update ALL Resources.ps1](file:///d:/Dinesh/Script/Powershell-Scripts/Azure/TAG-Update%20ALL%20Resources.ps1)** | Propagates missing tags defined at the Resource Group level to all child resources inside that RG, respecting an exclusion list. |
| **[Tag-Copy to RG.ps1](file:///d:/Dinesh/Script/Powershell-Scripts/Azure/Tag-Copy%20to%20RG.ps1)** | Copies and merges resource tags from a source Resource Group to a destination Resource Group using `Set-AzResourceGroup`. |
| **[Tag-Value-View-ALLRG.ps1](file:///d:/Dinesh/Script/Powershell-Scripts/Azure/Tag-Value-View-ALLRG.ps1)** | Scans all Resource Groups in a subscription, consolidates unique tag keys/values into a matrix table, displays GUI grid (`Out-GridView`), and exports results to CSV. |
| **[Application URL Response Monitor.ps1](file:///d:/Dinesh/Script/Powershell-Scripts/Azure/Application%20URL%20Response%20Monitor.ps1)** | Periodically sends HTTP requests via `Invoke-WebRequest` to a target URL, logs status codes, handles exceptions, and records timestamped entries to a text file. |

---

## 🚀 Usage Examples

### 1. Authenticate to Azure CLI and Azure PowerShell
```powershell
# Authenticate Azure CLI
az login

# Authenticate Azure PowerShell module
Connect-AzAccount
```

### 2. Download All AKS Cluster Credentials
```powershell
.\AKS\"AKS Credential Download.ps1"
```

### 3. Run Pod Troubleshooting Wizard
```powershell
.\AKS\PodTroubleshoot.ps1
```

### 4. Generate Application Gateway Traffic Flowchart
```powershell
.\Azure\AppGateway-Flowchart.ps1 -SubscriptionId "00000000-0000-0000-0000-000000000000"
```

### 5. Parse and Filter Pod Logs Live
```powershell
.\AKS\GetPodLogs.ps1 -PodName "my-app-pod-xyz" -Namespace "prod" -AddKubectlTimestamps
```

---

## 📖 Built-In Help & AST Verification

All scripts fully support standard PowerShell comment-based help. You can inspect detailed parameters and usage notes directly in your terminal:

```powershell
# View synopsis and parameter details for any script
Get-Help .\AKS\Keda-Config-Validation.ps1 -Full
Get-Help .\Azure\AVD Auto-Restart VM.ps1 -Detailed
```

### AST Syntax Verification Test
You can run a one-line PowerShell test to verify that every `.ps1` file in the repository passes Abstract Syntax Tree parsing without errors:

```powershell
Get-ChildItem -Path . -Filter *.ps1 -Recurse | ForEach-Object {
    $err = @()
    $null = [System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$null, [ref]$err)
    if ($err.Count -gt 0) {
        Write-Host "FAIL: $($_.Name) - $($err[0].Message)" -ForegroundColor Red
    } else {
        Write-Host "PASS: $($_.Name)" -ForegroundColor Green
    }
}
```

---

## 🤝 Contributing

Contributions, issues, and feature requests are welcome!
1. **Fork** the repository.
2. Create a feature branch (`git checkout -b feature/AmazingFeature`).
3. Ensure all `.ps1` files pass AST syntax checks and include comment-based help headers.
4. **Commit** your changes (`git commit -m 'Add new Azure automation script'`).
5. **Push** to the branch (`git push origin feature/AmazingFeature`).
6. Open a **Pull Request**.

---

## 📜 License

Distributed under the **MIT License**. See `LICENSE` for more information.
