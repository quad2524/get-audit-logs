#Requires -Modules SqlServer
<#
.SYNOPSIS
Reads configuration, replaces placeholders in insert_test_data.sql, and executes it.
.DESCRIPTION
This script automates inserting test data into the monitoring table. It reads
configuration from config.json, modifies the insert_test_data.sql script
accordingly, and then executes it against the target database using
Invoke-Sqlcmd with Windows Authentication.
#>
param()

# Get the directory where the script is located
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Construct the full path to the config file and SQL script
$ConfigPath = Join-Path -Path $ScriptDir -ChildPath "config.json"
$SqlScriptPath = Join-Path -Path $ScriptDir -ChildPath "insert_test_data.sql"

# Check if config file exists
if (-not (Test-Path -Path $ConfigPath -PathType Leaf)) {
    Write-Error "Configuration file not found: $ConfigPath"
    exit 1
}

# Check if SQL script file exists
if (-not (Test-Path -Path $SqlScriptPath -PathType Leaf)) {
    Write-Error "SQL script file not found: $SqlScriptPath"
    exit 1
}

# Read and parse the configuration file
Write-Host "Reading configuration from $ConfigPath..."
$Config = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json

# Validate required config values
if (-not $Config.SqlServerInstance -or -not $Config.DatabaseName -or -not $Config.DataSchema -or -not $Config.DataTableName) {
    Write-Error "Configuration file is missing required values (SqlServerInstance, DatabaseName, DataSchema, DataTableName)."
    exit 1
}

# Read the SQL script content
Write-Host "Reading SQL script from $SqlScriptPath..."
$SqlScriptContent = Get-Content -Path $SqlScriptPath -Raw

# Replace placeholders
Write-Host "Replacing placeholders in SQL script..."
$ModifiedSqlScript = $SqlScriptContent -replace '\{\{DatabaseName\}\}', $Config.DatabaseName `
                                       -replace '\{\{DataSchema\}\}', $Config.DataSchema `
                                       -replace '\{\{DataTableName\}\}', $Config.DataTableName

# Execute the modified SQL script against the target database
Write-Host "Executing insert_test_data.sql against $($Config.SqlServerInstance) (Database: $($Config.DatabaseName))..."
try {
    Invoke-Sqlcmd -ServerInstance $Config.SqlServerInstance -Database $Config.DatabaseName -Query $ModifiedSqlScript -TrustServerCertificate -ErrorAction Stop
    Write-Host "Successfully executed insert_test_data.sql."
}
catch {
    Write-Error "Error executing insert_test_data.sql: $($_.Exception.Message)"
    exit 1
}

Write-Host "Test data insertion script finished."