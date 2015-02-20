-- Allow EXECUTE for 'test'@'localhost' on mysqlgt procedures
GRANT EXECUTE ON PROCEDURE `mysqlgt`.`gtREVOKE` TO 'test'@'localhost';
GRANT EXECUTE ON PROCEDURE `mysqlgt`.`gtGRANT` TO 'test'@'localhost';

-- Allow the user to reload privileges after updating grants
-- make sure you are comfortable giving this permission to the user
-- allows reloading of logs, replication sync and a few other reloads
GRANT RELOAD ON *.* TO 'test'@'localhost';

REPLACE INTO `mysqlgt`.`db_grant` (`Host`, `Db`, `User`, `Table_priv`) VALUES 
-- Allow SELECT,INSERT,UPDATE,DELETE GRANT for test@% on schema test
 ('%', 'test', 'test', 'select,insert,update,delete')
