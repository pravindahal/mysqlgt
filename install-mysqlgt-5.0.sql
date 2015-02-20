-- Create the Schema
CREATE SCHEMA IF NOT EXISTS `mysqlgt`;

-- Setup a user for internal use only with an unknown random password
-- CREATE USER `mysqlgt`@`*internal-only*`;
-- UPDATE mysql.`user` SET `Password` = PASSWORD(MD5(RAND())) WHERE `user` = 'mysqlgt' AND `Host` = "*internal-only*";

-- Setup mysqlgt tables and procedures
CREATE TABLE IF NOT EXISTS `mysqlgt`.`db_grant` (
    `Host` char(60) COLLATE utf8_bin NOT NULL DEFAULT '',
    `Db` char(64) COLLATE utf8_bin NOT NULL DEFAULT '',
    `User` char(16) COLLATE utf8_bin NOT NULL DEFAULT '',
    `Table_priv` set('Select','Insert','Update','Delete','Create','Drop','Grant','References','Index','Alter','Create View','Show view','Trigger') CHARACTER SET utf8 NOT NULL DEFAULT '',
    PRIMARY KEY (`Host`,`Db`,`User`),
    KEY `User` (`User`)
) 
ENGINE=MyISAM 
DEFAULT CHARSET=utf8 
COLLATE=utf8_bin;

CREATE TABLE IF NOT EXISTS `mysqlgt`.`log` (
    `idlog` INT(10) UNSIGNED NOT NULL AUTO_INCREMENT,
	`timestamp` TIMESTAMP,
	`user` char(77), # 16 + 1 + 60
	`destination` char(194), # 64 + 1 + 64 + 1 + 64
    `log` TEXT,
    PRIMARY KEY (`idlog`)
)
ENGINE = InnoDB
DEFAULT CHARACTER SET = utf8
COLLATE = utf8_general_ci;


DROP PROCEDURE IF EXISTS `mysqlgt`.`gtSIMPLIFY_DATA`;
DELIMITER //
CREATE DEFINER = `mysqlgt`@`*internal-only*` 
PROCEDURE `mysqlgt`.`gtSIMPLIFY_DATA` (
    IN tbl_priv set('Select','Insert','Update','Delete','Create','Drop','Grant','References','Index','Alter','Create View','Show view','Trigger','All'),
    IN new_db_dot_table_dot_column char(194),  # 64 + 1 + 64 + 1 + 64
    IN new_user_at_host char(77), # 16 + 1 + 60
    OUT new_table_priv set('Select','Insert','Update','Delete','Create','Drop','Grant','References','Index','Alter','Create View','Show view','Trigger'),
    OUT new_db char(64),
    OUT new_table_name char(64),
    OUT new_column_name char(64),
    OUT new_user char(16),
    OUT new_host char(60),
    OUT invoker_user char(16),
    OUT invoker_host char(60),
    OUT allowed_operations set('Select','Insert','Update','Delete','Create','Drop','Grant','References','Index','Alter','Create View','Show view','Trigger')
)
SQL SECURITY DEFINER
BEGIN
    DECLARE grant_s_priv, grant_u_priv, grant_d_priv, grant_i_priv TEXT;
    
    #break user@host to user and host
    SET new_user = replace(substring(substring_index(new_user_at_host, '@', 1), length(substring_index(new_user_at_host, '@', 1 - 1)) + 1), '@', '');
    SET new_host = replace(substring(substring_index(new_user_at_host, '@', 2), length(substring_index(new_user_at_host, '@', 2 - 1)) + 1), '@', '');
    
    #break db.tablename.columnname to db, tablename and columnname
    SET new_db = replace(substring(substring_index(new_db_dot_table_dot_column, '.', 1), length(substring_index(new_db_dot_table_dot_column, '.', 1 - 1)) + 1), '.', '');
    SET new_table_name = replace(substring(substring_index(new_db_dot_table_dot_column, '.', 2), length(substring_index(new_db_dot_table_dot_column, '.', 2 - 1)) + 1), '.', '');
    SET new_column_name = replace(substring(substring_index(new_db_dot_table_dot_column, '.', 3), length(substring_index(new_db_dot_table_dot_column, '.', 3 - 1)) + 1), '.', '');
    
    IF (new_db = '') OR (new_table_name = '') THEN
        DROP TABLE `Parameter_not_in_expected_format_db.table_column`;		
    END IF;
    
    #get invoker_user and invoker_host
    SET invoker_user = replace(substring(substring_index(USER(), '@', 1), length(substring_index(USER(), '@', 1 - 1)) + 1), '@', '');
    SET invoker_host = replace(substring(substring_index(USER(), '@', 2), length(substring_index(USER(), '@', 2 - 1)) + 1), '@', '');
  
    #read allowed operations
    SELECT '' INTO allowed_operations;
    SELECT `Table_priv` INTO allowed_operations FROM mysqlgt.db_grant WHERE (`User`=invoker_user OR `User`='') AND (`Host`=invoker_host OR `Host`='%') AND (`Db`=new_db);
    
    #if requested grant is 'all', set it to all grants (no point of this now, however could come handy in the future)
    IF find_in_set('all', tbl_priv) THEN
        SET new_table_priv = 'Select,Insert,Update,Delete,Create,Drop,References,Index,Alter,Create View,Show view,Trigger';
    ELSE
        SET new_table_priv = tbl_priv;
    END IF;
    
END //
DELIMITER ;



DROP PROCEDURE IF EXISTS `mysqlgt`.`gtGRANT`;
DELIMITER //
CREATE DEFINER = `mysqlgt`@`*internal-only*` 
PROCEDURE `mysqlgt`.`gtGRANT` (
    IN new_table_priv set('Select','Insert','Update','Delete','Create','Drop','Grant','References','Index','Alter','Create View','Show view','Trigger','All'),
    IN new_db_dot_table_dot_column char(194),  # 64 + 1 + 64 + 1 + 64
    IN new_user_at_host char(77) # 16 + 1 + 60
)
MODIFIES SQL DATA
SQL SECURITY DEFINER
BEGIN
  
    DECLARE error_message TEXT;
    DECLARE error_message_128 VARCHAR(128);
    DECLARE allowed INT;
    DECLARE allowed_operations_table, new_table_priv_processed set('Select','Insert','Update','Delete','Create','Drop','Grant','References','Index','Alter','Create View','Show view','Trigger');
    DECLARE operation_temp, allowed_operations_column, new_column_priv_processed, current_column_priv set('Select','Insert','Update','References');

    CALL `mysqlgt`.`gtSIMPLIFY_DATA`(
        new_table_priv, new_db_dot_table_dot_column, new_user_at_host, 
        @new_priv_processed, @new_db, @new_table_name, @new_column_name, 
        @new_user, @new_host, @invoker_user, @invoker_host, @allowed_operations
    );
    
    SELECT '' INTO new_table_priv_processed;
    SELECT '' INTO new_column_priv_processed;
    SELECT '' INTO allowed_operations_table;
    SELECT '' INTO allowed_operations_column;
    SELECT '' INTO current_column_priv;
    
    SELECT `Column_priv` INTO current_column_priv FROM `mysql`.`tables_priv` WHERE `Host`=@new_host AND `Db`=@new_db AND `User`=@new_user AND `Table_name`=@new_table_name;
    
    IF @new_column_name = '' THEN
        SELECT @allowed_operations INTO allowed_operations_table;
        SELECT @new_priv_processed INTO new_table_priv_processed;
        SELECT ((allowed_operations_table & new_table_priv_processed) = new_table_priv_processed) INTO allowed;
    ELSE
        IF find_in_set('Select', @allowed_operations) THEN 
            SELECT 'Select' INTO operation_temp;
            SELECT operation_temp | allowed_operations_column INTO allowed_operations_column;
        END IF;
        IF find_in_set('Insert', @allowed_operations) THEN 
            SELECT 'Insert' INTO operation_temp;
            SELECT operation_temp | allowed_operations_column INTO allowed_operations_column;
        END IF;
        IF find_in_set('Update', @allowed_operations) THEN 
            SELECT 'Update' INTO operation_temp;
            SELECT operation_temp | allowed_operations_column INTO allowed_operations_column;
        END IF;
        IF find_in_set('References', @allowed_operations) THEN 
            SELECT 'References' INTO operation_temp;
            SELECT operation_temp | allowed_operations_column INTO allowed_operations_column;
        END IF;
        
        SELECT @new_priv_processed INTO new_column_priv_processed;
        SELECT ((allowed_operations_column & new_column_priv_processed) = new_column_priv_processed) INTO allowed;
    END IF;
    
    #if allowed, insert to mysql internal table and log
    IF allowed = 1 THEN
        INSERT INTO `mysql`.`tables_priv` VALUES(@new_host,@new_db,@new_user,@new_table_name,CURRENT_USER(),CURRENT_TIMESTAMP(),new_table_priv_processed,new_column_priv_processed) 
            ON DUPLICATE KEY UPDATE `Table_priv` = (`Table_priv` | new_table_priv_processed), `Column_priv` = (current_column_priv | new_column_priv_processed), `Timestamp` = CURRENT_TIMESTAMP(), `Grantor` = CURRENT_USER();
        IF @new_column_name != '' THEN
            INSERT INTO `mysql`.`columns_priv` VALUES(@new_host,@new_db,@new_user,@new_table_name,@new_column_name,CURRENT_TIMESTAMP(),new_column_priv_processed)
                ON DUPLICATE KEY UPDATE `Column_priv` = (`Column_priv` | new_column_priv_processed), `Timestamp` = CURRENT_TIMESTAMP();
        END IF;
        INSERT INTO `mysqlgt`.`log` VALUES(NULL,CURRENT_TIMESTAMP(),CONCAT(@invoker_user,'@',@invoker_host),new_db_dot_table_dot_column,CONCAT('user granted ', new_table_priv_processed, ' to ', @new_user, '@', @new_host, ' on  ', new_db_dot_table_dot_column));
    ELSE
        SET error_message = CONCAT(@invoker_user,'@',@invoker_host,' is not allowed to grant ', new_table_priv_processed, ', only allowed to grant ', @allowed_operations);
        INSERT INTO `mysqlgt`.`log` VALUES(NULL,CURRENT_TIMESTAMP(),CONCAT(@invoker_user,'@',@invoker_host),new_db_dot_table_dot_column,error_message);
		DROP TABLE `Error_see_mysqlgt_log`;
    END IF;

END //
DELIMITER ;



DROP PROCEDURE IF EXISTS `mysqlgt`.`gtREVOKE`;
DELIMITER //
CREATE DEFINER = `mysqlgt`@`*internal-only*` 
PROCEDURE `mysqlgt`.`gtREVOKE` (
    IN unset_table_priv set('Select','Insert','Update','Delete','Create','Drop','Grant','References','Index','Alter','Create View','Show view','Trigger','All'),
    IN new_db_dot_table_dot_column char(194),  # 64 + 1 + 64 + 1 + 64
    IN new_user_at_host char(77) # 16 + 1 + 60
)
MODIFIES SQL DATA
SQL SECURITY DEFINER
BEGIN

    DECLARE val INT;
    DECLARE error_message TEXT;
    DECLARE error_message_128 VARCHAR(128);
    DECLARE current_table_priv, new_table_priv, revoked_priv, allowed_operations_table set('Select','Insert','Update','Delete','Create','Drop','Grant','References','Index','Alter','Create View','Show view','Trigger');
    DECLARE allowed INT;
    DECLARE revoked_column_priv, operation_temp, new_column_priv_column, new_column_priv_table, allowed_operations_column, current_column_priv_column, current_column_priv_table set('Select','Insert','Update','References');
    
    CALL `mysqlgt`.`gtSIMPLIFY_DATA`(
        unset_table_priv, new_db_dot_table_dot_column, new_user_at_host, 
        @unset_priv_processed, @new_db, @new_table_name, @new_column_name, 
        @new_user, @new_host, @invoker_user, @invoker_host, @allowed_operations
    );
    
    SELECT '' INTO current_table_priv;
    SELECT '' INTO current_column_priv_column;
    SELECT '' INTO current_column_priv_table;
    SELECT '' INTO allowed_operations_column;
    SELECT '' INTO revoked_column_priv;
    SELECT '' INTO revoked_priv;
    
    SELECT `Table_priv` INTO current_table_priv FROM `mysql`.`tables_priv` WHERE `Host`=@new_host AND `Db`=@new_db AND `User`=@new_user AND `Table_name`=@new_table_name;
    SELECT `Column_priv` INTO current_column_priv_column FROM `mysql`.`columns_priv` WHERE `Host`=@new_host AND `Db`=@new_db AND `User`=@new_user AND `Table_name`=@new_table_name AND `Column_name`=@new_column_name;
    SELECT `Column_priv` INTO current_column_priv_table FROM `mysql`.`tables_priv` WHERE `Host`=@new_host AND `Db`=@new_db AND `User`=@new_user AND `Table_name`=@new_table_name;
    
    
    IF @new_column_name = '' THEN
        SELECT current_column_priv_table INTO new_column_priv_table;
        
        SELECT @unset_priv_processed INTO new_table_priv;
        SELECT (current_table_priv & ~new_table_priv) INTO new_table_priv;
        SELECT (current_table_priv & ~new_table_priv) INTO revoked_priv;
        
        SELECT @allowed_operations INTO allowed_operations_table;
        SELECT ((revoked_priv & allowed_operations_table) = revoked_priv) INTO allowed;
    ELSE
        SELECT current_table_priv INTO new_table_priv;
        
        IF find_in_set('Select', @allowed_operations) THEN 
            SELECT 'Select' INTO operation_temp;
            SELECT operation_temp | allowed_operations_column INTO allowed_operations_column;
        END IF;
        IF find_in_set('Insert', @allowed_operations) THEN 
            SELECT 'Insert' INTO operation_temp;
            SELECT operation_temp | allowed_operations_column INTO allowed_operations_column;
        END IF;
        IF find_in_set('Update', @allowed_operations) THEN 
            SELECT 'Update' INTO operation_temp;
            SELECT operation_temp | allowed_operations_column INTO allowed_operations_column;
        END IF;
        IF find_in_set('References', @allowed_operations) THEN 
            SELECT 'References' INTO operation_temp;
            SELECT operation_temp | allowed_operations_column INTO allowed_operations_column;
        END IF;
    
        SELECT @unset_priv_processed INTO new_column_priv_column;
        SELECT (current_column_priv_column & ~new_column_priv_column) INTO new_column_priv_column;
        SELECT (current_column_priv_column & ~new_column_priv_column) INTO revoked_column_priv;
        
        SELECT @unset_priv_processed INTO new_column_priv_table;
        SELECT (current_column_priv_table & ~new_column_priv_table) INTO new_column_priv_table;
        
        SELECT ((revoked_column_priv & allowed_operations_column) = revoked_column_priv) INTO allowed;
        
    END IF;
    
    #if allowed, insert to mysql internal table and log
    IF allowed = 1 THEN
        IF new_table_priv = 0 AND new_column_priv_table = 0 THEN
            #if it is deleted and column is not blank, it automatically seems to set the Table_priv to '' while not deleting the row
            #so this works fine, however this needs to be tested with older version of MySQL
            DELETE FROM `mysql`.`tables_priv` WHERE `Host`=@new_host AND `Db`=@new_db AND `User`=@new_user AND `Table_name`=@new_table_name;
        ELSE
            INSERT INTO `mysql`.`tables_priv` VALUES(@new_host, @new_db, @new_user, @new_table_name, CURRENT_USER(), CURRENT_TIMESTAMP(), new_table_priv, new_column_priv_table)
                ON DUPLICATE KEY UPDATE `Table_priv` = new_table_priv, `Column_priv` = new_column_priv_table, `Timestamp` = CURRENT_TIMESTAMP(), `Grantor` = CURRENT_USER();
        END IF;
        
        IF @new_column_name != '' THEN
            IF new_column_priv_column = 0 THEN
                DELETE FROM `mysql`.`columns_priv` WHERE `Host`=@new_host and `Db`=@new_db and `User`=@new_user and `Table_name`=@new_table_name AND `Column_name`=@new_column_name;
            ELSE
                INSERT INTO `mysql`.`columns_priv` VALUES(@new_host,@new_db,@new_user,@new_table_name,@new_column_name,CURRENT_TIMESTAMP(),new_column_priv_column)
                    ON DUPLICATE KEY UPDATE `Column_priv` = new_column_priv_column, `Timestamp` = CURRENT_TIMESTAMP();
            END IF;
        END IF;
        
        INSERT INTO `mysqlgt`.`log` VALUES(NULL,CURRENT_TIMESTAMP(),CONCAT(@invoker_user,'@',@invoker_host),new_db_dot_table_dot_column,CONCAT('user revoked ', @unset_priv_processed, ' from ', @new_user, '@', @new_host, ' on ', new_db_dot_table_dot_column));
    ELSE
        SET error_message = CONCAT(@invoker_user, '@', @invoker_host, ' is not allowed to revoke ', revoked_priv, ', only allowed to revoke ', @allowed_operations);
        INSERT INTO `mysqlgt`.`log` VALUES(NULL,CURRENT_TIMESTAMP(),CONCAT(@invoker_user,'@',@invoker_host),new_db_dot_table_dot_column,error_message);
		DROP TABLE `Error_see_mysqlgt_log`;
    END IF;

END //
DELIMITER ;


-- Setup grants for the internal user so he can check permissions , insert to log and execute the procedures
GRANT INSERT ON `mysqlgt`.`log` TO `mysqlgt`@`*internal-only*`;
GRANT SELECT ON `mysqlgt`.`db_grant` TO `mysqlgt`@`*internal-only*`;
GRANT SELECT,INSERT,UPDATE,DELETE ON `mysql`.`tables_priv` TO `mysqlgt`@`*internal-only*`;
GRANT SELECT,INSERT,UPDATE,DELETE ON `mysql`.`columns_priv` TO `mysqlgt`@`*internal-only*`;
GRANT EXECUTE ON PROCEDURE `mysqlgt`.`gtSIMPLIFY_DATA` TO `mysqlgt`@`*internal-only*`;
GRANT EXECUTE ON PROCEDURE `mysqlgt`.`gtGRANT` TO `mysqlgt`@`*internal-only*`;
GRANT EXECUTE ON PROCEDURE `mysqlgt`.`gtREVOKE` TO `mysqlgt`@`*internal-only*`;
