#Requires -Modules SqlServer
<#
.SYNOPSIS
Reads configuration, replaces placeholders in setup_database.sql, and executes it against the master database.
.DESCRIPTION
This script automates the initial database creation process. It reads connection
and naming details from config.json, modifies the setup_database.sql script
accordingly, and then executes it using Invoke-Sqlcmd with Windows Authentication.
It connects to the 'master' database to ensure the CREATE DATABASE command can be executed.
#>
param()

# Get the directory where the script is located
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Construct the full path to the config file
$ConfigPath = Join-Path -Path $ScriptDir -ChildPath "config.json"
$SqlScriptPath = Join-Path -Path $ScriptDir -ChildPath "setup_database.sql"

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

# Execute the modified SQL script against the master database
Write-Host "Executing setup_database.sql against $($Config.SqlServerInstance) (master database)..."
try {
    Invoke-Sqlcmd -ServerInstance $Config.SqlServerInstance -Database "master" -Query $ModifiedSqlScript -TrustServerCertificate -ErrorAction Stop
    Write-Host "Successfully executed setup_database.sql."
}
catch {
    Write-Error "Error executing setup_database.sql: $($_.Exception.Message)"
    exit 1
}

Write-Host "Database setup script finished."