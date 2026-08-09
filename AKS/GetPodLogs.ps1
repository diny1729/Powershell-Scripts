<#
.SYNOPSIS
    Interactive Kubernetes pod log fetching, regex parsing, filtering, and structured analysis tool.

.DESCRIPTION
    Retrieves logs directly from a target pod/container via `kubectl` or opens an existing log file from disk.
    Parses structured Java/Spring/Kubernetes log entries, extracts metadata (User IDs, Task IDs, Error Titles),
    and presents an interactive CLI menu to filter by Log Level, Logger, User ID, or keywords, exportable to file/JSON.

.PARAMETER LogPath
    Path to an existing local log file on disk to parse and analyze.

.PARAMETER PodName
    Name of the active Kubernetes pod from which to stream/fetch logs live via `kubectl`.

.PARAMETER Namespace
    Kubernetes namespace where the target pod resides. Defaults to 'default'.

.PARAMETER Container
    Specific container name within a multi-container pod to fetch logs from.

.PARAMETER AddKubectlTimestamps
    Switch parameter to pass `--timestamps` flag to `kubectl logs`.

.NOTES
    Prerequisites:
    - `kubectl` CLI installed if fetching live pod logs.
    - Standard PowerShell 5.1+ / PowerShell Core.
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$LogPath,

    [Parameter()]
    [string]$PodName,

    [Parameter()]
    [string]$Namespace = 'default',

    [Parameter()]
    [string]$Container,

    [Parameter()]
    [switch]$AddKubectlTimestamps
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$script:TempFilePath = $null

function Fetch-PodLogs {
    param(
        [string]$Pod,
        [string]$Ns,
        [string]$ContainerName,
        [bool]$UseTimestamps
    )

    if (-not (Get-Command 'kubectl' -ErrorAction SilentlyContinue)) {
        throw "The 'kubectl' command line tool was not found in PATH. Please verify kubectl is installed and configured."
    }

    Write-Host "Fetching logs from pod '$Pod' in namespace '$Ns'..." -ForegroundColor Cyan

    $tempFile = [System.IO.Path]::GetTempFileName()
    $kubectlArgs = @('logs', $Pod, '-n', $Ns)

    if (-not [string]::IsNullOrWhiteSpace($ContainerName)) {
        $kubectlArgs += @('-c', $ContainerName)
    }

    if ($UseTimestamps) {
        $kubectlArgs += '--timestamps'
    }

    try {
        & kubectl $kubectlArgs 2>&1 | Out-File -FilePath $tempFile -Encoding utf8
        
        if (-not (Test-Path $tempFile) -or (Get-Item $tempFile).Length -eq 0) {
            throw "Failed to fetch logs or the retrieved log output is empty."
        }

        return $tempFile
    }
    catch {
        if (Test-Path $tempFile) { Remove-Item $tempFile -ErrorAction SilentlyContinue }
        throw "Kubectl log retrieval failed: $_"
    }
}

function Read-ExistingLogPath {
    param([string]$InitialPath)

    $candidate = $InitialPath
    while ([string]::IsNullOrWhiteSpace($candidate) -or -not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
        if (-not [string]::IsNullOrWhiteSpace($candidate)) {
            Write-Host "File not found: $candidate" -ForegroundColor Yellow
        }
        $candidate = Read-Host 'Enter the full path to the log file'
        $candidate = $candidate.Trim('"')
    }
    return (Resolve-Path -LiteralPath $candidate).Path
}

function Extract-Metadata {
    param([pscustomobject]$Entry)

    $text = $Entry.Text

    # User ID or Device ID Extraction
    if ($text -match '"userId"\s*:\s*"(?<Uid>[^"]+)"') {
        $Entry.UserId = $Matches['Uid']
    }
    elseif ($text -match 'from User\s+(?<Uid>[^\s:]+)') {
        $Entry.UserId = $Matches['Uid']
    }
    elseif ($text -match 'from\s+(?<Uid>[a-zA-Z0-9._%+-]+@ubimax)') {
        $Entry.UserId = $Matches['Uid']
    }
    elseif ($text -match 'deviceId=(?<Dev>[^\s&"]+)') {
        $Entry.UserId = "Device:$($Matches['Dev'])"
    }

    # Task ID or Task Result ID Extraction
    if ($text -match 'Task data:\s*\{.*?"id"\s*:\s*(?<Tid>\d+)') {
        $Entry.TaskId = $Matches['Tid']
    }
    elseif ($text -match 'Task\s+(?<Tid>\d+)\s*\(') {
        $Entry.TaskId = $Matches['Tid']
    }
    elseif ($text -match '"entityId"\s*:\s*(?<Tid>\d+)') {
        $Entry.TaskId = $Matches['Tid']
    }
    elseif ($text -match 'task_result_id\)=\((?<Tid>\d+)\)') {
        $Entry.TaskId = "Result:$($Matches['Tid'])"
    }
}

function Read-LogEntries {
    param([Parameter(Mandatory = $true)][string]$Path)

    $structuredPattern = '^(?<Timestamp>\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,7})?(?:Z|[+-]\d{2}:?\d{2}))\s+\[(?<Domain>[^\]]*)\]\s+(?<Level>TRACE|DEBUG|INFO|WARN|ERROR|FATAL)\s+\d+\s+---\s+\[(?<Thread>[^\]]+)\]\s+(?<Logger>\S+)\s+:\s+(?<Message>.*)$'
    $fallbackStartPattern = '^(?<Timestamp>\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,7})?(?:Z|[+-]\d{2}:?\d{2}))\s+(?<Rest>.*)$'
    $levelPattern = '(?:^|\s)(?<Level>TRACE|DEBUG|INFO|WARN|ERROR|FATAL)(?:\s|$)'

    $entries = New-Object System.Collections.Generic.List[object]
    $current = $null

    foreach ($line in [System.IO.File]::ReadLines($Path)) {
        $mStruct = [regex]::Match($line, $structuredPattern, [System.Text.RegularExpressions.RegexOptions]::CultureInvariant)
        
        if ($mStruct.Success) {
            if ($null -ne $current) {
                $obj = [pscustomobject]$current
                Extract-Metadata -Entry $obj
                $entries.Add($obj)
            }

            $timestamp = [DateTimeOffset]::Parse(
                $mStruct.Groups['Timestamp'].Value,
                [Globalization.CultureInfo]::InvariantCulture,
                [Globalization.DateTimeStyles]::AllowWhiteSpaces
            )

            $current = [ordered]@{
                Timestamp = $timestamp
                Domain    = if ($mStruct.Groups['Domain'].Value) { $mStruct.Groups['Domain'].Value } else { 'N/A' }
                Level     = $mStruct.Groups['Level'].Value.ToUpperInvariant()
                Logger    = $mStruct.Groups['Logger'].Value
                Message   = $mStruct.Groups['Message'].Value
                TaskId    = 'N/A'
                UserId    = 'N/A'
                FirstLine = $line
                Text      = $line
            }
        }
        else {
            $mFallback = [regex]::Match($line, $fallbackStartPattern, [System.Text.RegularExpressions.RegexOptions]::CultureInvariant)
            if ($mFallback.Success) {
                if ($null -ne $current) {
                    $obj = [pscustomobject]$current
                    Extract-Metadata -Entry $obj
                    $entries.Add($obj)
                }

                $timestamp = [DateTimeOffset]::Parse(
                    $mFallback.Groups['Timestamp'].Value,
                    [Globalization.CultureInfo]::InvariantCulture,
                    [Globalization.DateTimeStyles]::AllowWhiteSpaces
                )
                $levelMatch = [regex]::Match($mFallback.Groups['Rest'].Value, $levelPattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
                $level = if ($levelMatch.Success) { $levelMatch.Groups['Level'].Value.ToUpperInvariant() } else { '' }

                $current = [ordered]@{
                    Timestamp = $timestamp
                    Domain    = 'N/A'
                    Level     = $level
                    Logger    = 'General'
                    Message   = $mFallback.Groups['Rest'].Value
                    TaskId    = 'N/A'
                    UserId    = 'N/A'
                    FirstLine = $line
                    Text      = $line
                }
            }
            elseif ($null -ne $current) {
                $current.Text += [Environment]::NewLine + $line
            }
        }
    }

    if ($null -ne $current) {
        $obj = [pscustomobject]$current
        Extract-Metadata -Entry $obj
        $entries.Add($obj)
    }
    return $entries
}

function Read-Hours {
    while ($true) {
        Write-Host ''
        Write-Host 'Choose time range:' -ForegroundColor Cyan
        Write-Host '  1. Last 1 hour'
        Write-Host '  2. Last 4 hours'
        Write-Host '  3. Last 6 hours'
        Write-Host '  4. Last 12 hours'
        Write-Host '  5. Last 24 hours'
        Write-Host '  6. Custom hours'
        $choice = Read-Host 'Selection'
        switch ($choice) {
            '1' { return 1 }
            '2' { return 4 }
            '3' { return 6 }
            '4' { return 12 }
            '5' { return 24 }
            '6' {
                $value = 0.0
                if ([double]::TryParse((Read-Host 'Enter number of hours'), [ref]$value) -and $value -gt 0) {
                    return $value
                }
                Write-Host 'Enter a number greater than zero.' -ForegroundColor Yellow
            }
            default { Write-Host 'Invalid selection.' -ForegroundColor Yellow }
        }
    }
}

function Get-ReferenceTime {
    param([object[]]$Entries)

    $latest = ($Entries | Sort-Object Timestamp | Select-Object -Last 1).Timestamp
    Write-Host ''
    Write-Host 'Time-range reference:' -ForegroundColor Cyan
    Write-Host "  1. Latest timestamp in log (recommended): $($latest.ToString('yyyy-MM-dd HH:mm:ss.fff zzz'))"
    Write-Host "  2. Current UTC time:                  $([DateTimeOffset]::UtcNow.ToString('yyyy-MM-dd HH:mm:ss.fff zzz'))"
    $choice = Read-Host 'Selection [default 1]'
    if ($choice -eq '2') { return [DateTimeOffset]::UtcNow }
    return $latest
}

function Get-FilteredEntries {
    param(
        [object[]]$Entries,
        [DateTimeOffset]$ReferenceTime,
        [double]$Hours,
        [string]$LogLevel = '',
        [string]$LoggerName = '',
        [string]$UserId = '',
        [string]$TaskId = '',
        [string]$SearchText = ''
    )

    $from = $ReferenceTime.AddHours(-$Hours)
    $result = @($Entries | Where-Object { $_.Timestamp -ge $from -and $_.Timestamp -le $ReferenceTime })

    if (-not [string]::IsNullOrWhiteSpace($LogLevel)) {
        $result = @($result | Where-Object { $_.Level -eq $LogLevel.ToUpperInvariant() })
    }

    if (-not [string]::IsNullOrWhiteSpace($LoggerName)) {
        $result = @($result | Where-Object { $_.Logger -like "*$LoggerName*" })
    }

    if (-not [string]::IsNullOrWhiteSpace($UserId)) {
        $result = @($result | Where-Object { $_.UserId -like "*$UserId*" })
    }

    if (-not [string]::IsNullOrWhiteSpace($TaskId)) {
        $result = @($result | Where-Object { $_.TaskId -like "*$TaskId*" })
    }

    if (-not [string]::IsNullOrWhiteSpace($SearchText)) {
        $result = @($result | Where-Object {
            $_.Text.IndexOf($SearchText, [StringComparison]::OrdinalIgnoreCase) -ge 0
        })
    }
    return $result
}

function Select-LoggerFromList {
    param(
        [object[]]$Entries,
        [DateTimeOffset]$ReferenceTime,
        [double]$Hours
    )

    $timeFiltered = @(Get-FilteredEntries -Entries $Entries -ReferenceTime $ReferenceTime -Hours $Hours)

    if ($timeFiltered.Count -eq 0) {
        Write-Host "No log entries found in the selected $Hours hour(s) time window." -ForegroundColor Yellow
        return ''
    }

    $loggerGroups = @($timeFiltered | Where-Object { $_.Logger -ne 'N/A' -and $_.Logger -ne 'General' } | Group-Object Logger | Sort-Object Count -Descending)

    if ($loggerGroups.Count -eq 0) {
        Write-Host "No distinct logger names found in this time window." -ForegroundColor Yellow
        return Read-Host "Type custom logger name manually"
    }

    $from = $ReferenceTime.AddHours(-$Hours)
    Write-Host ''
    Write-Host "==========================================================================" -ForegroundColor Cyan
    Write-Host " AVAILABLE LOGGERS & LOG COUNT ($Hours hr time window)" -ForegroundColor Cyan
    Write-Host " Time Window (UTC): $($from.UtcDateTime.ToString('yyyy-MM-dd HH:mm:ss')) to $($ReferenceTime.UtcDateTime.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor DarkGray
    Write-Host "==========================================================================" -ForegroundColor Cyan

    for ($i = 0; $i -lt $loggerGroups.Count; $i++) {
        $group = $loggerGroups[$i]
        Write-Host ("  {0,2}. {1,-58} [{2} logs]" -f ($i + 1), $group.Name, $group.Count)
    }

    $customOpt = $loggerGroups.Count + 1
    $allOpt    = $loggerGroups.Count + 2

    Write-Host ("  {0,2}. Custom / Search Keyword" -f $customOpt)
    Write-Host ("  {0,2}. All Loggers (No Filter)" -f $allOpt)

    while ($true) {
        $selection = Read-Host "Select a logger number"
        $idx = 0
        if ([int]::TryParse($selection, [ref]$idx)) {
            if ($idx -ge 1 -and $idx -le $loggerGroups.Count) {
                return $loggerGroups[$idx - 1].Name
            }
            elseif ($idx -eq $customOpt) {
                return Read-Host "Enter custom logger/keyword"
            }
            elseif ($idx -eq $allOpt) {
                return ''
            }
        }
        Write-Host "Invalid selection. Enter a number between 1 and $allOpt." -ForegroundColor Yellow
    }
}

function Show-LoggerLogLevelBreakdown {
    param(
        [object[]]$Entries,
        [DateTimeOffset]$ReferenceTime,
        [double]$Hours,
        [string]$LoggerName
    )

    if ([string]::IsNullOrWhiteSpace($LoggerName)) { return }

    $filtered = @(Get-FilteredEntries -Entries $Entries -ReferenceTime $ReferenceTime -Hours $Hours -LoggerName $LoggerName)
    
    if ($filtered.Count -gt 0) {
        Write-Host ''
        Write-Host "==========================================================================" -ForegroundColor Cyan
        Write-Host " LOG LEVEL BREAKDOWN FOR: $LoggerName ($($filtered.Count) total logs)" -ForegroundColor Cyan
        Write-Host "==========================================================================" -ForegroundColor Cyan
        
        $levelGroups = $filtered | Group-Object Level | Sort-Object Count -Descending
        foreach ($g in $levelGroups) {
            $color = switch ($g.Name) {
                'ERROR' { 'Red' }
                'WARN'  { 'Yellow' }
                'INFO'  { 'Green' }
                'DEBUG' { 'DarkGray' }
                default { 'White' }
            }
            $lvlName = if ([string]::IsNullOrWhiteSpace($g.Name)) { 'OTHER' } else { $g.Name }
            Write-Host ("  * {0,-7} : {1} log(s)" -f $lvlName, $g.Count) -ForegroundColor $color
        }
        Write-Host ''
    }
}

function Show-ErrorGroupSummary {
    param(
        [object[]]$Entries,
        [DateTimeOffset]$ReferenceTime,
        [double]$Hours
    )

    $errorItems = @(Get-FilteredEntries -Entries $Entries -ReferenceTime $ReferenceTime -Hours $Hours -LogLevel 'ERROR')
    $from = $ReferenceTime.AddHours(-$Hours)

    Write-Host ''
    Write-Host ('=' * 80) -ForegroundColor DarkGray
    Write-Host "ERROR NAMES & CATEGORY SUMMARY REPORT" -ForegroundColor Cyan
    Write-Host "Time Window (UTC): $($from.UtcDateTime.ToString('yyyy-MM-dd HH:mm:ss')) to $($ReferenceTime.UtcDateTime.ToString('yyyy-MM-dd HH:mm:ss'))"
    Write-Host "Total Error Logs:  $($errorItems.Count)" -ForegroundColor $(if ($errorItems.Count -gt 0) { 'Red' } else { 'Green' })
    Write-Host ('=' * 80) -ForegroundColor DarkGray

    if ($errorItems.Count -eq 0) {
        Write-Host 'No ERROR entries found in this time window.' -ForegroundColor Green
        return
    }

    $grouped = $errorItems | Group-Object -Property {
        $msg = $_.Message
        if ($msg -match '^(?<ErrorTitle>[^:\r\n]+(?:\:[^:\r\n]+)?)') {
            $title = $Matches['ErrorTitle']
            if ($title.Length -gt 70) { $title = $title.Substring(0, 67) + '...' }
            return "$($_.Logger) | $title"
        }
        return "$($_.Logger) | Generic Error"
    } | Sort-Object Count -Descending

    $summaryReport = foreach ($group in $grouped) {
        $parts = $group.Name -split ' \| ', 2
        [pscustomobject]@{
            Count          = $group.Count
            Logger         = $parts[0]
            ErrorName      = $parts[1]
            LatestLogUtc   = ($group.Group | Sort-Object Timestamp | Select-Object -Last 1).Timestamp.UtcDateTime.ToString('yyyy-MM-dd HH:mm:ss')
        }
    }

    $summaryReport | Format-Table -AutoSize -Wrap
}

function Show-UserAndTaskErrorSummary {
    param(
        [object[]]$Entries,
        [DateTimeOffset]$ReferenceTime,
        [double]$Hours
    )

    $errorItems = @(Get-FilteredEntries -Entries $Entries -ReferenceTime $ReferenceTime -Hours $Hours -LogLevel 'ERROR')
    $from = $ReferenceTime.AddHours(-$Hours)

    Write-Host ''
    Write-Host ('=' * 80) -ForegroundColor DarkGray
    Write-Host "ERROR BREAKDOWN BY USER ID & TASK ID" -ForegroundColor Cyan
    Write-Host "Time Window (UTC): $($from.UtcDateTime.ToString('yyyy-MM-dd HH:mm:ss')) to $($ReferenceTime.UtcDateTime.ToString('yyyy-MM-dd HH:mm:ss'))"
    Write-Host ('=' * 80) -ForegroundColor DarkGray

    if ($errorItems.Count -eq 0) {
        Write-Host 'No ERROR entries found in this time window.' -ForegroundColor Green
        return
    }

    $grouped = $errorItems | Group-Object -Property UserId, TaskId, Logger | Sort-Object Count -Descending

    $report = foreach ($group in $grouped) {
        $first = $group.Group[0]
        [pscustomobject]@{
            Count        = $group.Count
            UserId       = $first.UserId
            TaskId       = $first.TaskId
            Logger       = $first.Logger
            LatestLogUtc = ($group.Group | Sort-Object Timestamp | Select-Object -Last 1).Timestamp.UtcDateTime.ToString('yyyy-MM-dd HH:mm:ss')
        }
    }

    $report | Format-Table -AutoSize
}

function Show-LogLevelBreakdown {
    param(
        [object[]]$Entries,
        [DateTimeOffset]$ReferenceTime,
        [double]$Hours
    )

    $windowItems = @(Get-FilteredEntries -Entries $Entries -ReferenceTime $ReferenceTime -Hours $Hours)
    $from = $ReferenceTime.AddHours(-$Hours)

    Write-Host ''
    Write-Host ('=' * 80) -ForegroundColor DarkGray
    Write-Host "LOG LEVEL SUMMARY BREAKDOWN" -ForegroundColor Cyan
    Write-Host "Time Window (UTC): $($from.UtcDateTime.ToString('yyyy-MM-dd HH:mm:ss')) to $($ReferenceTime.UtcDateTime.ToString('yyyy-MM-dd HH:mm:ss'))"
    Write-Host ('=' * 80) -ForegroundColor DarkGray

    $breakdown = $windowItems | Group-Object Level | Select-Object @{N='LogLevel';E={$_.Name}}, Count | Sort-Object Count -Descending
    $breakdown | Format-Table -AutoSize
}

function Show-FullLogEntries {
    param(
        [object[]]$Results,
        [string]$Title = "Full Complete Log Details"
    )

    Write-Host ''
    Write-Host ('=' * 80) -ForegroundColor DarkGray
    Write-Host "FULL COMPLETE LOG ENTRIES (Total Count: $($Results.Count))" -ForegroundColor Cyan
    Write-Host "Filter Context: $Title" -ForegroundColor Cyan
    Write-Host ('=' * 80) -ForegroundColor DarkGray

    if ($Results.Count -eq 0) {
        Write-Host 'No matching entries found.' -ForegroundColor Green
        return
    }

    $index = 1
    foreach ($entry in $Results) {
        Write-Host ""
        Write-Host "--- [ENTRY $index OF $($Results.Count)] | UTC: $($entry.Timestamp.UtcDateTime.ToString('yyyy-MM-dd HH:mm:ss.fff')) | Level: $($entry.Level) | Logger: $($entry.Logger) ---" -ForegroundColor Yellow
        if ($entry.UserId -ne 'N/A' -or $entry.TaskId -ne 'N/A') {
            Write-Host "Metadata -> UserId: $($entry.UserId) | TaskId: $($entry.TaskId)" -ForegroundColor Cyan
        }
        Write-Host $entry.Text
        $index++
    }
}

function Show-StructuredWordSearch {
    param(
        [object[]]$Entries,
        [DateTimeOffset]$ReferenceTime
    )

    $keyword = Read-Host 'Enter search word/phrase (e.g. MultipartException, foreign key, updateLpnPosition)'
    if ([string]::IsNullOrWhiteSpace($keyword)) {
        Write-Host 'Search keyword cannot be empty.' -ForegroundColor Yellow
        return
    }

    $lvl = Read-Host 'Filter by Log Level (e.g., ERROR, WARN, INFO, or press Enter for ALL)'
    $hours = Read-Hours

    $matched = @(Get-FilteredEntries -Entries $Entries -ReferenceTime $ReferenceTime -Hours $hours -LogLevel $lvl -SearchText $keyword)

    Write-Host ''
    Write-Host ('=' * 80) -ForegroundColor DarkGray
    Write-Host "STRUCTURED LOG SEARCH RESULTS: '$keyword'" -ForegroundColor Cyan
    Write-Host "Total Matches Found: $($matched.Count)" -ForegroundColor $(if ($matched.Count -gt 0) { 'Green' } else { 'Yellow' })
    Write-Host ('=' * 80) -ForegroundColor DarkGray

    if ($matched.Count -eq 0) {
        Write-Host "No logs found containing '$keyword'." -ForegroundColor Yellow
        return
    }

    Write-Host "Choose output format:" -ForegroundColor Cyan
    Write-Host "  1. Structured Table View (Default)"
    Write-Host "  2. Structured Detailed List View (Property by Property)"
    Write-Host "  3. Structured JSON Output"
    $formatChoice = Read-Host "Selection [default 1]"

    $structuredObjects = foreach ($item in $matched) {
        [ordered]@{
            TimestampUtc = $item.Timestamp.UtcDateTime.ToString('yyyy-MM-dd HH:mm:ss.fff')
            Level        = $item.Level
            Domain       = $item.Domain
            Logger       = $item.Logger
            UserId       = $item.UserId
            TaskId       = $item.TaskId
            Message      = $item.Message
        }
    }

    switch ($formatChoice) {
        '2' { $structuredObjects | Format-List }
        '3' { $structuredObjects | ConvertTo-Json -Depth 3 }
        default { $structuredObjects | Format-Table -AutoSize -Wrap }
    }

    Export-Results -Results $matched
}

function Show-ResultsTable {
    param(
        [object[]]$Results,
        [string]$Title = "Matching Log Summary"
    )

    Write-Host ''
    Write-Host "--- $Title (Count: $($Results.Count)) ---" -ForegroundColor Cyan

    if ($Results.Count -gt 0) {
        $Results | Select-Object @{N='TimestampUtc';E={$_.Timestamp.UtcDateTime.ToString('yyyy-MM-dd HH:mm:ss.fff')}},
            Level, UserId, TaskId, Logger, @{N='MessageSummary';E={$_.Message}} | Format-Table -Wrap -AutoSize
    }
    else {
        Write-Host 'No matching entries found.' -ForegroundColor Green
    }
}

function Export-Results {
    param([object[]]$Results)

    if ($Results.Count -eq 0) { return }
    $answer = Read-Host 'Export matching log entries to file? (Y/N)'
    if ($answer -notmatch '(?i)^y(?:es)?$') { return }

    $defaultPath = Join-Path $env:USERPROFILE ("filtered-logs-{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    $path = Read-Host "Output path [default: $defaultPath]"
    if ([string]::IsNullOrWhiteSpace($path)) { $path = $defaultPath }

    $content = foreach ($entry in $Results) { $entry.Text; '' }
    [System.IO.File]::WriteAllLines($path, [string[]]$content, [Text.UTF8Encoding]::new($false))
    Write-Host "Exported successfully: $path" -ForegroundColor Green
}

# Main Execution Flow
try {
    if (-not [string]::IsNullOrWhiteSpace($PodName)) {
        $script:TempFilePath = Fetch-PodLogs -Pod $PodName -Ns $Namespace -ContainerName $Container -UseTimestamps $AddKubectlTimestamps
        $resolvedPath = $script:TempFilePath
    }
    else {
        $resolvedPath = Read-ExistingLogPath -InitialPath $LogPath
    }

    Write-Host "Reading log output from $resolvedPath ..." -ForegroundColor Cyan
    $allEntries = @(Read-LogEntries -Path $resolvedPath)

    if ($allEntries.Count -eq 0) { throw 'No timestamped log entries were detected.' }
    $referenceTime = Get-ReferenceTime -Entries $allEntries

    Write-Host "Parsed Total Entries: $($allEntries.Count)" -ForegroundColor Green

    while ($true) {
        Write-Host ''
        Write-Host '===================================================' -ForegroundColor Cyan
        Write-Host ' INTERACTIVE LOG ANALYSIS & FILTER MENU' -ForegroundColor Cyan
        Write-Host '===================================================' -ForegroundColor Cyan
        Write-Host '  1. Error Name & Category Summarized Report'
        Write-Host '  2. Error Breakdown Grouped by User ID & Task ID'
        Write-Host '  3. Log Level Breakdown (ERROR, WARN, INFO, DEBUG)'
        Write-Host '  4. Filter by Specific Log Level (e.g. ERROR, WARN)'
        Write-Host '  5. Filter Summary by User ID or Task ID'
        Write-Host '  6. Filter Summary by Logger / Class Name'
        Write-Host '  7. View Full Complete Logs for Specific Error/Logger (Raw Output)'
        Write-Host '  8. Search Specific Word & Get Logs in Structured Format'
        Write-Host '  9. Change Time Reference Point'
        Write-Host ' 10. Reload Log Data'
        Write-Host '  Q. Quit'
        $menu = Read-Host 'Selection'

        switch ($menu.ToUpperInvariant()) {
            '1' {
                $hours = Read-Hours
                Show-ErrorGroupSummary -Entries $allEntries -ReferenceTime $referenceTime -Hours $hours
            }
            '2' {
                $hours = Read-Hours
                Show-UserAndTaskErrorSummary -Entries $allEntries -ReferenceTime $referenceTime -Hours $hours
            }
            '3' {
                $hours = Read-Hours
                Show-LogLevelBreakdown -Entries $allEntries -ReferenceTime $referenceTime -Hours $hours
            }
            '4' {
                $lvl = Read-Host 'Enter Log Level (ERROR, WARN, INFO, DEBUG)'
                $hours = Read-Hours
                $items = @(Get-FilteredEntries -Entries $allEntries -ReferenceTime $referenceTime -Hours $hours -LogLevel $lvl)
                Show-ResultsTable -Results $items -Title "Filtered by Level [$lvl]"
                Export-Results -Results $items
            }
            '5' {
                $uid = Read-Host 'Enter User ID (e.g. sand4157, s14155, or leave blank)'
                $tid = Read-Host 'Enter Task ID (e.g. 50849, 50658, or leave blank)'
                $hours = Read-Hours
                $items = @(Get-FilteredEntries -Entries $allEntries -ReferenceTime $referenceTime -Hours $hours -UserId $uid -TaskId $tid)
                Show-ResultsTable -Results $items -Title "Filtered by User [$uid] / Task [$tid]"
                Export-Results -Results $items
            }
            '6' {
                $hours = Read-Hours
                $logger = Select-LoggerFromList -Entries $allEntries -ReferenceTime $referenceTime -Hours $hours
                if (-not [string]::IsNullOrWhiteSpace($logger)) {
                    Show-LoggerLogLevelBreakdown -Entries $allEntries -ReferenceTime $referenceTime -Hours $hours -LoggerName $logger
                }
                $items = @(Get-FilteredEntries -Entries $allEntries -ReferenceTime $referenceTime -Hours $hours -LoggerName $logger)
                Show-ResultsTable -Results $items -Title "Filtered by Logger [$logger]"
                Export-Results -Results $items
            }
            '7' {
                $hours = Read-Hours
                $logger = Select-LoggerFromList -Entries $allEntries -ReferenceTime $referenceTime -Hours $hours
                if (-not [string]::IsNullOrWhiteSpace($logger)) {
                    Show-LoggerLogLevelBreakdown -Entries $allEntries -ReferenceTime $referenceTime -Hours $hours -LoggerName $logger
                }
                $lvl = Read-Host 'Enter Log Level filter (e.g. ERROR, WARN, or press Enter for ALL)'
                $items = @(Get-FilteredEntries -Entries $allEntries -ReferenceTime $referenceTime -Hours $hours -LoggerName $logger -LogLevel $lvl)
                if ($items.Count -eq 0 -and -not [string]::IsNullOrWhiteSpace($logger)) {
                    $items = @(Get-FilteredEntries -Entries $allEntries -ReferenceTime $referenceTime -Hours $hours -LogLevel $lvl -SearchText $logger)
                }
                Show-FullLogEntries -Results $items -Title "Full Raw Logs for [$logger]"
                Export-Results -Results $items
            }
            '8' {
                Show-StructuredWordSearch -Entries $allEntries -ReferenceTime $referenceTime
            }
            '9' { 
                $referenceTime = Get-ReferenceTime -Entries $allEntries 
            }
            '10' {
                Write-Host 'Reloading log data ...' -ForegroundColor Cyan
                if (-not [string]::IsNullOrWhiteSpace($PodName)) {
                    if ($script:TempFilePath -and (Test-Path $script:TempFilePath)) {
                        Remove-Item $script:TempFilePath -Force -ErrorAction SilentlyContinue
                    }
                    $script:TempFilePath = Fetch-PodLogs -Pod $PodName -Ns $Namespace -ContainerName $Container -UseTimestamps $AddKubectlTimestamps
                    $resolvedPath = $script:TempFilePath
                }
                $allEntries = @(Read-LogEntries -Path $resolvedPath)
                $referenceTime = Get-ReferenceTime -Entries $allEntries
                Write-Host "Reloaded. Parsed Total Entries: $($allEntries.Count)" -ForegroundColor Green
            }
            'Q' { return }
            default { Write-Host 'Invalid selection.' -ForegroundColor Yellow }
        }
    }
}
finally {
    if ($script:TempFilePath -and (Test-Path $script:TempFilePath)) {
        Remove-Item $script:TempFilePath -Force -ErrorAction SilentlyContinue
    }
}