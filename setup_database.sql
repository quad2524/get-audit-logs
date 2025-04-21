-- setup_database.sql
-- Creates the database and the main data table if they don't exist.

-- Check if the database exists and create it if it doesn't
IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = N'{{DatabaseName}}')
BEGIN
    CREATE DATABASE [{{DatabaseName}}];
    PRINT 'Database [{{DatabaseName}}] created.';
END
ELSE
BEGIN
    PRINT 'Database [{{DatabaseName}}] already exists.';
END
GO

-- Switch context to the newly created or existing database
USE [{{DatabaseName}}];
GO

-- Check if the data table exists and create it if it doesn't
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[{{DataSchema}}].[{{DataTableName}}]') AND type in (N'U'))
BEGIN
    CREATE TABLE [{{DataSchema}}].[{{DataTableName}}] (
        [ID] INT IDENTITY(1,1) PRIMARY KEY,
        [TimestampUTC] DATETIME2 NOT NULL DEFAULT GETUTCDATE(), -- Store insertion time in UTC
        [DataValue] VARCHAR(255) NULL -- Example data column
        -- Add other data columns as needed
    );
    PRINT 'Table [{{DataSchema}}].[{{DataTableName}}] created in database [{{DatabaseName}}].';
END
ELSE
BEGIN
    PRINT 'Table [{{DataSchema}}].[{{DataTableName}}] already exists in database [{{DatabaseName}}].';
END
GO