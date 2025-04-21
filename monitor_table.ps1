#Requires -Modules SqlServer
<#
.SYNOPSIS
Monitors a SQL Server table for new entries since the last run and logs them to an audit file.

.DESCRIPTION
This script connects to a specified SQL Server database, retrieves the last run timestamp
from a state table, queries a data table for new rows based on that timestamp, logs any
new rows found (as JSON) to a daily audit log file, and updates the state table with
the current run timestamp. It reads configuration from config.json and fetches the
SQL user password from Google Cloud Secret Manager.

.NOTES
Dependencies:
- PowerShell Module: SqlServer (Install-Module -Name SqlServer -Scope CurrentUser)
- Google Cloud SDK: gcloud command-line tool (authenticated)

Configuration:
- Place a 'config.json' file in the same directory as this script.
- config.json structure:
  {
    "SqlServerInstance": "your_server\\instance",
    "DatabaseName": "your_database",
    "DataTableName": "schema.your_data_table",
    "StateTableName": "schema.your_state_table",
    "MonitoringUserName": "your_sql_username",
    "GcpProjectId": "your-gcp-project-id",
    "GcpSecretName": "your-gcp-secret-name",
    "ScriptNameInStateTable": "unique_script_identifier",
    "LogDirectory": "./relative/path/to/logs"
  }
#>

param()

# --- Configuration and Setup ---
$scriptStartTime = Get-Date
Write-Host "Script started at $($scriptStartTime.ToString('yyyy-MM-dd HH:mm:ss'))"

# Get script's directory
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$configFile = Join-Path $scriptDir "config.json"
$appLogPath = $null
$auditLogPath = $null
$config = $null

function Write-Log {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        [Parameter(Mandatory=$false)]
        [string]$LogPath = $appLogPath # Default to app log
    )
    $timestamp = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    $logEntry = "$timestamp - $Message"
    try {
        Add-Content -Path $LogPath -Value $logEntry -ErrorAction Stop
    } catch {
        Write-Error "Failed to write to log file '$LogPath': $($_.Exception.Message)"
        # Attempt to write to console as fallback
        Write-Host $logEntry
    }
}

# Check for SqlServer module
if (-not (Get-Module -ListAvailable -Name SqlServer)) {
    Write-Warning "SqlServer module not found. Please install it using: Install-Module -Name SqlServer -Scope CurrentUser"
    # Optionally exit or prompt for installation
    # Read-Host "Press Enter to exit..."
    exit 1
}

# Read Configuration
if (-not (Test-Path $configFile)) {
    Write-Error "Configuration file not found: $configFile"
    exit 1
}
try {
    $config = Get-Content $configFile -Raw | ConvertFrom-Json -ErrorAction Stop
} catch {
    Write-Error "Failed to read or parse configuration file '$configFile': $($_.Exception.Message)"
    exit 1
}

# Validate essential config keys
$requiredKeys = @("SqlServerInstance", "DatabaseName", "DataSchema", "DataTableName", "StateSchema", "StateTableName", "MonitoringUserName", "GcpProjectId", "GcpSecretName", "ScriptNameInStateTable", "LogDirectory")
$missingKeys = $requiredKeys | Where-Object { -not $config.PSObject.Properties.Name.Contains($_) }
if ($missingKeys) {
    Write-Error "Missing required keys in config.json: $($missingKeys -join ', ')"
    exit 1
}

# Setup Logging
$logDirectory = Join-Path $scriptDir $config.LogDirectory
if (-not (Test-Path $logDirectory)) {
    try {
        New-Item -ItemType Directory -Path $logDirectory -Force -ErrorAction Stop | Out-Null
        Write-Host "Created log directory: $logDirectory"
    } catch {
        Write-Error "Failed to create log directory '$logDirectory': $($_.Exception.Message)"
        exit 1
    }
}
$appLogPath = Join-Path $logDirectory "app.log"
$auditLogDateSuffix = (Get-Date -UFormat "%Y-%m-%d") # UTC date for audit log filename
$auditLogPath = Join-Path $logDirectory "audit-log-$auditLogDateSuffix.log"

Write-Log -Message "--- Script Run Started ---"

# --- Fetch Secret ---
$password = $null
try {
    Write-Log -Message "Fetching secret '$($config.GcpSecretName)' from GCP project '$($config.GcpProjectId)'..."
    $gcloudResult = gcloud secrets versions access latest --secret="$($config.GcpSecretName)" --project="$($config.GcpProjectId)" --format="get(payload.data)" 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "gcloud command failed: $gcloudResult"
    }
    # Decode Base64 password
    $passwordBytes = [System.Convert]::FromBase64String($gcloudResult)
    $password = [System.Text.Encoding]::UTF8.GetString($passwordBytes)
    Write-Log -Message "Successfully fetched and decoded secret."
    # Clear the result variable to avoid accidental exposure
    Clear-Variable gcloudResult
} catch {
    Write-Error "Failed to fetch or decode secret '$($config.GcpSecretName)': $($_.Exception.Message)"
    Write-Log -Message "ERROR: Failed to fetch or decode secret '$($config.GcpSecretName)': $($_.Exception.Message)"
    Write-Log -Message "--- Script Run Finished (with errors) ---"
    exit 1
}

if (-not $password) {
     Write-Error "Password could not be retrieved from Secret Manager."
     Write-Log -Message "ERROR: Password could not be retrieved from Secret Manager."
     Write-Log -Message "--- Script Run Finished (with errors) ---"
     exit 1
}

# --- SQL Operations ---
$newRowsFound = 0
$sqlErrorOccurred = $false
$errorMessage = ""

# Add diagnostic output before connection attempt
Write-Host "Attempting to connect to database: $($Config.DatabaseName) on instance: $($Config.SqlServerInstance)"

try {
    # Define SQL Connection Parameters
    $sqlParams = @{
        ServerInstance = $config.SqlServerInstance
        Database       = $config.DatabaseName
        Username       = $config.MonitoringUserName
        Password       = $password
        QueryTimeout   = 60 # seconds
        ErrorAction    = 'Stop'
        TrustServerCertificate = $true # Added to trust self-signed/untrusted certs
    }

    # 1. Get Last Run Timestamp
    Write-Log -Message "Connecting to SQL Server '$($config.SqlServerInstance)' database '$($config.DatabaseName)'..."
    $stateQuery = "SELECT LastRunTimestampUTC FROM [$($config.StateSchema)].[$($config.StateTableName)] WHERE ScriptName = '$($config.ScriptNameInStateTable)';"
    Write-Log -Message "Executing query: $stateQuery"
    $lastRunResult = Invoke-Sqlcmd @sqlParams -Query $stateQuery

    # Add diagnostic SQL query after successful connection
    $CurrentDatabase = Invoke-Sqlcmd -ServerInstance $Config.SqlServerInstance -Database $Config.DatabaseName -Username $Config.MonitoringUserName -Password $password -TrustServerCertificate -Query "SELECT DB_NAME() AS CurrentDB" | Select-Object -ExpandProperty CurrentDB
    Write-Host "Successfully connected to database: $CurrentDatabase"

    # Add table existence check
    $TableExists = Invoke-Sqlcmd -ServerInstance $Config.SqlServerInstance -Database $Config.DatabaseName -Username $Config.MonitoringUserName -Password $password -TrustServerCertificate -Query "SELECT COUNT(*) AS TableCount FROM sys.objects WHERE object_id = OBJECT_ID(N'[$($Config.StateSchema)].[$($Config.StateTableName)]') AND type in (N'U')" | Select-Object -ExpandProperty TableCount
    if ($TableExists -eq 1) {
        Write-Host "Table '[$($Config.StateSchema)].[$($Config.StateTableName)]' found in database '$CurrentDatabase'."
    } else {
        Write-Host "Table '[$($Config.StateSchema)].[$($Config.StateTableName)]' NOT found in database '$CurrentDatabase'."
    }


    $lastRunTimestampUTC = if ($lastRunResult -and $lastRunResult.LastRunTimestampUTC -ne [System.DBNull]::Value) {
        # Ensure it's treated as DateTime and Kind is UTC
        [DateTime]::SpecifyKind($lastRunResult.LastRunTimestampUTC, [DateTimeKind]::Utc)
    } else {
        Write-Log -Message "No previous run timestamp found for '$($config.ScriptNameInStateTable)'. Using default."
        [DateTime]::SpecifyKind([DateTime]'1970-01-01T00:00:00', [DateTimeKind]::Utc) # Default old date
    }
    $lastRunTimestampSqlFormatted = $lastRunTimestampUTC.ToString("yyyy-MM-ddTHH:mm:ss.fff") # Format for SQL comparison
    Write-Log -Message "Last run timestamp (UTC): $($lastRunTimestampSqlFormatted)"

    # 2. Get Current UTC Time (BEFORE querying data)
    $currentRunTimestampUTC = (Get-Date).ToUniversalTime()
    $currentRunTimestampSqlFormatted = $currentRunTimestampUTC.ToString("yyyy-MM-ddTHH:mm:ss.fff") # Format for SQL update
    Write-Log -Message "Current run timestamp (UTC): $($currentRunTimestampSqlFormatted)"

    # 3. Query New Data
    # Assuming the data table has a 'TimestampUTC' column of a suitable date/time type
    $dataQuery = "SELECT * FROM [$($config.DataSchema)].[$($config.DataTableName)] WHERE TimestampUTC > '$($lastRunTimestampSqlFormatted)';"
    Write-Log -Message "Executing query: $dataQuery"
    $newData = Invoke-Sqlcmd @sqlParams -Query $dataQuery

    # 4. Process & Log New Data
    if ($newData) {
        $newRowsFound = $newData.Count
        Write-Log -Message "Found $newRowsFound new row(s)."
        Write-Log -Message "Logging new rows to audit log: $auditLogPath"
        foreach ($row in $newData) {
            # Select only desired columns for logging
            # Select only desired columns for logging, formatting TimestampUTC
            $rowData = $row | Select-Object ID, @{Name='TimestampUTC'; Expression={$_.TimestampUTC.ToString('yyyy-MM-ddTHH:mm:ssZ')}}, DataValue
            # Convert selected data to JSON
            $jsonRow = $rowData | ConvertTo-Json -Depth 5 -Compress
            # Append JSON to the daily audit log file
            Add-Content -Path $auditLogPath -Value $jsonRow
        }
    } else {
        Write-Log -Message "No new rows found since last run."
    }

    # 5. Update State Table
    # Use the timestamp captured *before* the data query
    $updateStateQuery = @"
IF EXISTS (SELECT 1 FROM [$($config.StateSchema)].[$($config.StateTableName)] WHERE ScriptName = '$($config.ScriptNameInStateTable)')
    UPDATE [$($config.StateSchema)].[$($config.StateTableName)]
    SET LastRunTimestampUTC = '$($currentRunTimestampSqlFormatted)' -- Using pre-query timestamp
    WHERE ScriptName = '$($config.ScriptNameInStateTable)';
ELSE
    INSERT INTO [$($config.StateSchema)].[$($config.StateTableName)] (ScriptName, LastRunTimestampUTC)
    VALUES ('$($config.ScriptNameInStateTable)', '$($currentRunTimestampSqlFormatted)'); -- Using pre-query timestamp
"@
    # Alternative using GETUTCDATE() if preferred and server time is reliable:
    # $updateStateQuery = @"
# IF EXISTS (SELECT 1 FROM [$($config.StateSchema)].[$($config.StateTableName)] WHERE ScriptName = '$($config.ScriptNameInStateTable)')
#     UPDATE [$($config.StateSchema)].[$($config.StateTableName)] SET LastRunTimestampUTC = GETUTCDATE() WHERE ScriptName = '$($config.ScriptNameInStateTable)';
# ELSE
#     INSERT INTO [$($config.StateSchema)].[$($config.StateTableName)] (ScriptName, LastRunTimestampUTC) VALUES ('$($config.ScriptNameInStateTable)', GETUTCDATE());
# "@
    Write-Log -Message "Executing query: $updateStateQuery"
    Invoke-Sqlcmd @sqlParams -Query $updateStateQuery

    Write-Log -Message "Successfully updated state table for '$($config.ScriptNameInStateTable)'."

} catch {
    $sqlErrorOccurred = $true
    $errorMessage = "SQL Operation Error: $($_.Exception.Message) ScriptStackTrace: $($_.ScriptStackTrace)"
    Write-Error $errorMessage
    Write-Log -Message "ERROR: $errorMessage"
} finally {
    # Securely clear the password variable
    if (Test-Path variable:password) {
        Clear-Variable password -ErrorAction SilentlyContinue
    }
}

# --- Final Logging ---
$scriptEndTime = Get-Date
$duration = $scriptEndTime - $scriptStartTime
$status = if ($sqlErrorOccurred) { "Failed" } else { "Success" }

Write-Log -Message "--- Script Run Finished ---"
Write-Log -Message "Status: $status"
Write-Log -Message "Duration: $($duration.ToString())"
Write-Log -Message "New rows processed: $newRowsFound"
if ($sqlErrorOccurred) {
    Write-Log -Message "Error Details: $errorMessage"
}

Write-Host "Script finished at $($scriptEndTime.ToString('yyyy-MM-dd HH:mm:ss')). Duration: $($duration.ToString()). Status: $status. New Rows: $newRowsFound."

# Exit with appropriate code
if ($sqlErrorOccurred) {
    exit 1
} else {
    exit 0
}