<#
.SYNOPSIS
    Monitors HTTP status code responses for a target URL at regular polling intervals.

.DESCRIPTION
    Periodically sends HTTP requests via `Invoke-WebRequest` to a specified web endpoint or API URL,
    captures the HTTP status code (handling exceptions gracefully), and appends timestamped log records to a text file.

.NOTES
    Prerequisites:
    - Standard PowerShell environment (`Invoke-WebRequest`).
#>

# Target Endpoint Configuration
$url = "https://servername.privatelink.backend.windows.net:8080/login"  # Replace with your API endpoint

function Get-HttpStatusCode {
    param(
        [string]$url
    )

    try {
        $Response = Invoke-WebRequest -Uri $url -UseBasicParsing
        Write-Host "HTTP Status Code for $url : $($Response.StatusCode)"
        return $Response.StatusCode
    } catch {
        Write-Warning "Error accessing $url : $_"
        return $_.Exception.Response.StatusCode.value__
    }
}

# Set log file and interval
$LogFile = "HttpStatusCodeLog.txt"
$Interval = 10   # 60 seconds = 1 minute
Add-Content -Path $LogFile -Value  "URL Response code - $url"
while ($true) {
    $StatusCode = Get-HttpStatusCode $url
    $TimeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $LogFile -Value "Time: $TimeStamp - Status Code: $StatusCode"
	Write-Host "Time: $TimeStamp --- $url --- Status Code: $StatusCode"
    Start-Sleep -Seconds $Interval
}
