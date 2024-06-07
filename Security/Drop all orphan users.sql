-- Drop all orphan users
-- Part of the SQL Server DBA Toolbox at https://github.com/DavidSchanzer/Sql-Server-DBA-Toolbox
-- This script creates a stored procedure sp_Drop_OrphanedUsers in the master database, which it then calls using sp_ineachdb, resulting
-- in the dropping of all orphan users in this instance.

USE [master];
GO
CREATE PROC dbo.sp_Drop_OrphanedUsers
AS
BEGIN
    SET NOCOUNT ON;

    -- get orphaned users  
    DECLARE @user VARCHAR(MAX);

    DECLARE c_orphaned_user CURSOR LOCAL FAST_FORWARD FOR
    SELECT name
    FROM sys.database_principals
    WHERE type IN ( 'G', 'S', 'U' )
          AND [sid] NOT IN
              (
                  SELECT [sid] FROM sys.server_principals WHERE type IN ( 'G', 'S', 'U' )
              )
          AND name NOT IN ( 'dbo', 'guest', 'INFORMATION_SCHEMA', 'sys', 'MS_DataCollectorInternalUser' );

    OPEN c_orphaned_user;

    FETCH NEXT FROM c_orphaned_user
    INTO @user;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        -- alter schemas for user 
        DECLARE @schema_name VARCHAR(MAX);

        DECLARE c_schema CURSOR LOCAL FAST_FORWARD FOR
        SELECT name
        FROM sys.schemas
        WHERE USER_NAME(principal_id) = @user;

        OPEN c_schema;

        FETCH NEXT FROM c_schema
        INTO @schema_name;

        WHILE (@@FETCH_STATUS = 0)
        BEGIN
            DECLARE @sql_schema VARCHAR(MAX);

            SELECT @sql_schema = 'ALTER AUTHORIZATION ON SCHEMA::[' + @schema_name + '] TO [dbo]';

            PRINT @sql_schema;

            EXEC (@sql_schema);

            FETCH NEXT FROM c_schema
            INTO @schema_name;
        END;

        CLOSE c_schema;

        DEALLOCATE c_schema;

        -- alter roles for user 
        DECLARE @dp_name VARCHAR(MAX);

        DECLARE c_database_principal CURSOR LOCAL FAST_FORWARD FOR
        SELECT name
        FROM sys.database_principals
        WHERE type = 'R'
              AND USER_NAME(owning_principal_id) = @user;

        OPEN c_database_principal;

        FETCH NEXT FROM c_database_principal
        INTO @dp_name;

        WHILE (@@FETCH_STATUS = 0)
        BEGIN
            DECLARE @sql_database_principal VARCHAR(MAX);

            SELECT @sql_database_principal = 'ALTER AUTHORIZATION ON ROLE::[' + @dp_name + '] TO [dbo]';

            PRINT @sql_database_principal;

            EXEC (@sql_database_principal);

            FETCH NEXT FROM c_database_principal
            INTO @dp_name;
        END;

        CLOSE c_database_principal;
        DEALLOCATE c_database_principal;

        -- drop roles for user 
        DECLARE @role_name VARCHAR(MAX);

        DECLARE c_role CURSOR LOCAL FAST_FORWARD FOR
        SELECT dp.name --,USER_NAME(member_principal_id)
        FROM sys.database_role_members drm
            INNER JOIN sys.database_principals dp
                ON dp.principal_id = drm.role_principal_id
        WHERE USER_NAME(drm.member_principal_id) = @user;

        OPEN c_role;

        FETCH NEXT FROM c_role
        INTO @role_name;

        WHILE (@@FETCH_STATUS = 0)
        BEGIN
            DECLARE @sql_role VARCHAR(MAX);

            SELECT @sql_role = 'exec sp_droprolemember N''' + @role_name + ''', N''' + @user + '''';

            PRINT @sql_role;

            EXEC (@sql_role);

            FETCH NEXT FROM c_role
            INTO @role_name;
        END;

        CLOSE c_role;

        DEALLOCATE c_role;

        -- drop user
        DECLARE @sql_user VARCHAR(MAX);

        SET @sql_user = 'DROP USER [' + @user + ']';

        PRINT @sql_user;

        EXEC (@sql_user);

        FETCH NEXT FROM c_orphaned_user
        INTO @user;
    END;

    CLOSE c_orphaned_user;

    DEALLOCATE c_orphaned_user;

    SET NOCOUNT OFF;
END;
GO
-- mark stored procedure as a system stored procedure
EXEC sys.sp_MS_marksystemobject sp_Drop_OrphanedUsers;
GO

USE [master];
GO
EXEC dbo.sp_ineachdb @command = 'EXEC sp_Drop_OrphanedUsers;';
GO
