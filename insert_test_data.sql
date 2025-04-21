-- insert_test_data.sql
-- Inserts sample data into the main data table.
-- Assumes the database and table already exist.

-- Switch context to the target database
USE [{{DatabaseName}}];
GO

-- Insert a sample row into the data table
INSERT INTO [dbo].[{{DataTableName}}] ([TimestampUTC], [DataValue])
VALUES (GETUTCDATE(), 'Test data inserted at ' + CONVERT(VARCHAR, GETUTCDATE(), 121));
GO

-- Insert another sample row
INSERT INTO [dbo].[{{DataTableName}}] ([TimestampUTC], [DataValue])
VALUES (GETUTCDATE(), 'Another test record added via script.');
GO

PRINT 'Test data inserted into [dbo].[{{DataTableName}}] in database [{{DatabaseName}}].';
GO