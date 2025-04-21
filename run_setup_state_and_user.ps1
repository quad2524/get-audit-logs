#Requires -Modules SqlServer
<#
.SYNOPSIS
Reads configuration, prompts for a temporary password, replaces placeholders in setup_state_and_user.sql, and executes it.
.DESCRIPTION
This script automates the setup of the state table, monitoring login, and user.
It reads configuration from config.json, securely prompts for a temporary password
needed *only* for the initial 'CREATE LOGIN' statement, modifies the
setup_state_and_user.sql script, and executes it against the target database
using Invoke-Sqlcmd with Windows Authentication. The temporary password variable
is cleared after use.
#>
param()

# Get the directory where the script is located
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Construct the full path to the config file and SQL script
$ConfigPath = Join-Path -Path $ScriptDir -ChildPath "config.json"
$SqlScriptPath = Join-Path -Path $ScriptDir -ChildPath "setup_state_and_user.sql"

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
if (-not $Config.SqlServerInstance -or -not $Config.DatabaseName -or -not $Config.StateSchema -or -not $Config.StateTableName -or -not $Config.DataSchema -or -not $Config.DataTableName -or -not $Config.MonitoringUserName) {
    Write-Error "Configuration file is missing required values (SqlServerInstance, DatabaseName, StateSchema, StateTableName, DataSchema, DataTableName, MonitoringUserName)."
    exit 1
}

# Read the SQL script content
Write-Host "Reading SQL script from $SqlScriptPath..."
$SqlScriptContent = Get-Content -Path $SqlScriptPath -Raw

# Prompt securely for the temporary password for initial login creation
Write-Host "The setup_state_and_user.sql script requires a password for the initial 'CREATE LOGIN' statement."
Write-Host "This password is temporary and only used for this setup step."
$SecurePassword = Read-Host -Prompt "Enter a temporary password for SQL login '$($Config.MonitoringUserName)'" -AsSecureString

# Convert SecureString to plain text *only* for replacement
$PlainTextPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
    [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecurePassword)
)

# Replace placeholders
Write-Host "Replacing placeholders in SQL script..."
# Escape single quotes in the password for SQL compatibility
$SqlEscapedPassword = $PlainTextPassword -replace "'", "''"
$ModifiedSqlScript = $SqlScriptContent -replace '\{\{DatabaseName\}\}', $Config.DatabaseName `
                                       -replace '\{\{StateSchema\}\}', $Config.StateSchema `
                                       -replace '\{\{StateTableName\}\}', $Config.StateTableName `
                                       -replace '\{\{DataSchema\}\}', $Config.DataSchema `
                                       -replace '\{\{DataTableName\}\}', $Config.DataTableName `
                                       -replace '\{\{MonitoringUserName\}\}', $Config.MonitoringUserName `
                                       -replace '\{\{MonitoringUserPassword\}\}', $SqlEscapedPassword

# Clear the plain text password variable immediately after use
Clear-Variable PlainTextPassword
Clear-Variable SqlEscapedPassword

# Execute the modified SQL script against the target database
Write-Host "Executing setup_state_and_user.sql against $($Config.SqlServerInstance) (Database: $($Config.DatabaseName))..."
try {
    Invoke-Sqlcmd -ServerInstance $Config.SqlServerInstance -Database $Config.DatabaseName -Query $ModifiedSqlScript -TrustServerCertificate -ErrorAction Stop
    Write-Host "Successfully executed setup_state_and_user.sql."
}
catch {
    Write-Error "Error executing setup_state_and_user.sql: $($_.Exception.Message)"
    # Clear secure password variable in case of error too
    Clear-Variable SecurePassword
    exit 1
}
finally {
    # Ensure the secure password variable is cleared even if script exits unexpectedly after replacement
    Clear-Variable SecurePassword
}

Write-Host "State and user setup script finished."