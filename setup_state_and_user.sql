-- setup_state_and_user.sql
-- Creates the state table, login, user, and grants permissions within the specified database.

-- Ensure the script operates within the correct database context
USE [{{DatabaseName}}];
GO

-- Check if the state table exists and create it if it doesn't
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[{{StateSchema}}].[{{StateTableName}}]') AND type in (N'U'))
BEGIN
    CREATE TABLE [{{StateSchema}}].[{{StateTableName}}] (
        [ScriptName] VARCHAR(100) PRIMARY KEY,
        [LastRunTimestampUTC] DATETIME2 NULL -- Allow NULL or specific old date
    );
    PRINT 'Table [{{StateSchema}}].[{{StateTableName}}] created in database [{{DatabaseName}}].';

    -- Insert the initial state for the monitoring script
    -- Use a very old date to ensure the first run fetches all relevant data
    INSERT INTO [{{StateSchema}}].[{{StateTableName}}] ([ScriptName], [LastRunTimestampUTC])
    VALUES ('MonitorScript', '1970-01-01T00:00:00');
    PRINT 'Initial state for ''MonitorScript'' inserted into [{{StateSchema}}].[{{StateTableName}}].';
END
ELSE
BEGIN
    PRINT 'Table [{{StateSchema}}].[{{StateTableName}}] already exists in database [{{DatabaseName}}].';
    -- Optionally, check if the 'MonitorScript' row exists and insert if missing
    IF NOT EXISTS (SELECT 1 FROM [{{StateSchema}}].[{{StateTableName}}] WHERE [ScriptName] = 'MonitorScript')
    BEGIN
        INSERT INTO [{{StateSchema}}].[{{StateTableName}}] ([ScriptName], [LastRunTimestampUTC])
        VALUES ('MonitorScript', '1970-01-01T00:00:00');
        PRINT 'Initial state for ''MonitorScript'' inserted into [{{StateSchema}}].[{{StateTableName}}] as it was missing.';
    END
END
GO

-- Create the SQL Server Login if it doesn't exist
-- Note: The password here is a placeholder. The actual password management should be secure (e.g., using environment variables or secrets management).
IF NOT EXISTS (SELECT name FROM sys.sql_logins WHERE name = N'{{MonitoringUserName}}')
BEGIN
    CREATE LOGIN [{{MonitoringUserName}}] WITH PASSWORD = N'{{MonitoringUserPassword}}'; -- Placeholder password
    PRINT 'Login [{{MonitoringUserName}}] created.';
END
ELSE
BEGIN
    PRINT 'Login [{{MonitoringUserName}}] already exists.';
END
GO

-- Create the Database User for the login if it doesn't exist
IF NOT EXISTS (SELECT name FROM sys.database_principals WHERE name = N'{{MonitoringUserName}}')
BEGIN
    CREATE USER [{{MonitoringUserName}}] FOR LOGIN [{{MonitoringUserName}}];
    PRINT 'User [{{MonitoringUserName}}] created in database [{{DatabaseName}}].';
END
ELSE
BEGIN
    PRINT 'User [{{MonitoringUserName}}] already exists in database [{{DatabaseName}}].';
END
GO

-- Grant necessary permissions to the user
GRANT SELECT ON [{{DataSchema}}].[{{DataTableName}}] TO [{{MonitoringUserName}}];
GRANT SELECT, INSERT, UPDATE ON [{{StateSchema}}].[{{StateTableName}}] TO [{{MonitoringUserName}}];
PRINT 'Permissions granted to user [{{MonitoringUserName}}] on tables [{{DataSchema}}].[{{DataTableName}}] and [{{StateSchema}}].[{{StateTableName}}].';
GO