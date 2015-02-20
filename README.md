Choobs MySQL Grants Toolkit
===========================

MySQL's [GRANT syntax](http://dev.mysql.com/doc/refman/5.0/en/grant.html "MySQL 5.0 Reference Manual") uses the WITH GRANT OPTION which lets you GRANT a permission to a user and then allows the user to GRANT that permission further. However a limitation of MySQL is that the option is automatically valid for **all** permissions you granted the user, not just the one that you specified with the WITH GRANT OPTION.

This means that the moment you use the WITH GRANT OPTION the user automatically can give his permissions and the power to GRANT to another user. In effect with the help of another user the current user can gain all the permissions of the other user.

This toolkit restricts the GRANT OPTION by adding a layer of checking which means you can only apply grants for a specific set of permissions (wether you have them or not).

You can therefore limit the propagation of permissions between users to a well defined set of permissions and databases/tables.

##Documentation

MySQL stores table privileges in mysql.tables_priv and column privileges in mysql.columns_priv internally. However, since GRANT statement has the aforementioned issue, we avoid giving actual GRANT permissions to the users. 
Instead, we give EXECUTE privilege to custom procedures which do what the GRANT/REVOKE statements do after checking if the user is allowed to grant the privilege. The list of privileges the user is allowed to grant is stored in a custom table. The users don't actually have the GRANT privilege, so they can't bypass the security using GRANT statement.

#### Compatibility
Limited testing was done on MySQL and MariaDB. In principle any MySQL compatible database server version 5.0 and later should work. Please let us know if you have any issues with your database.

#### Setup
Use the install-mysqlgt-5.0.sql for MySQL version >=5.0 and <5.5 and install-mysqlgt-5.5.sql for MySQL version >=5.5. The script must be run as root.

After you run it, a new schema mysqlgt is created with tables mysqlgt.db_grant and mysqlgt.log and new procedures mysqlgt.gtSIMPLIFY_DATA, mysqlgt.gtGRANT and mysqlgt.gtREVOKE are created.

To allow a user (say test_user) to grant only the specified privileges:
 
 *  give EXECUTE permissions to the user to execute mysqlgt.gtGRANT and mysqlgt.gtREVOKE 
 *  insert a row in mysqlgt.db_grant specifying what table privileges a user is allowed to grant
 
##### Example:

In the following example, a user test_user@localhost is allowed to grant SELECT, UPDATE, INSERT and DELETE privileges on database test_db:

```sql
-- Allow EXECUTE for 'test_user'@'localhost' on mysqlgt procedures
GRANT EXECUTE ON PROCEDURE `mysqlgt`.`gtREVOKE` TO 'test_user'@'localhost';
GRANT EXECUTE ON PROCEDURE `mysqlgt`.`gtGRANT` TO 'test_user'@'localhost';

-- Allow the user to reload privileges after updating grants
-- make sure you are comfortable giving this permission to the user
-- allows reloading of logs, replication sync and a few other reloads
GRANT RELOAD ON *.* TO 'test_user'@'localhost';

REPLACE INTO `mysqlgt`.`db_grant` (`Host`, `Db`, `User`, `Table_priv`) VALUES 
-- Allow SELECT,INSERT,UPDATE,DELETE GRANT for test@% on schema test
 ('%', 'test_db', 'test_user', 'select,insert,update,delete')
```

Please note that in mysqlgt.db_grant, Host is set to '%'. Please check the [Known Issues](#known-issues) section for more information about why this is done here.

#### Usage
Now, the user (test_user) will be allowed to grant/revoke privileges to/from other users in the following ways:

```sql
CALL mysqlgt.gtGRANT  ( PERMISSIONS, DB.TABLE[.COLUMN], USER@HOST )
CALL mysqlgt.gtREVOKE ( PERMISSIONS, DB.TABLE[.COLUMN], USER@HOST )
```

##### Examples:
###### Table privileges:

```sql
CALL mysqlgt.gtGRANT  ( 'Delete,Insert,Update', 'mydb.mytable', 'myuser@hostname' );
CALL mysqlgt.gtREVOKE ( 'Update,Delete', 'mydb.mytable', 'myuser@hostname' );
```

###### Column privileges:

```sql
CALL mysqlgt.gtGRANT  ( 'Select,Insert,Update', 'mydb.mytable.mycol', 'myuser@hostname' );
CALL mysqlgt.gtREVOKE ( 'Select,Insert', 'mydb.mytable.mycol', 'myuser@hostname' );
```

##### Notes:

Please note that mysqlgt.gtGRANT and mysqlgt.gtREVOKE will not always replace single GRANT/REVOKE statement with a single call. Consider the following MySQL GRANT Statement:
```sql
GRANT SELECT (mycol1), INSERT (mycol1,mycol2), DELETE ON mydb.mytbl TO 'myuser'@'hostname';
```

Equavalent mysqlgt calls to acheive the above will be:
```sql
CALL mysqlgt.gtGRANT ( 'Select,Insert', 'mydb.mytable.mycol1', 'myuser@hostname' );
CALL mysqlgt.gtGRANT ( 'Insert', 'mydb.mytable.mycol2', 'myuser@hostname' );
CALL mysqlgt.gtGRANT ( 'Delete', 'mydb.mytable', 'myuser@hostname' );
```

Also, note that it currently only supports table and column privileges, it doesn't support database privileges. So, there is no equivalent for the following statement:
```sql
GRANT SELECT ON mydb.* TO 'myuser'@'hostname';
```
This feature is planned for future release.

#### Known Issues
Because using the function `CURRENT_USER()` returns the DEFINER inside of our PROCEDURE instead of the calling user. We were forced to use `USER()` which returns the connected user. However this introduces the following issue.

In the row in mysqlgt.db_grant, Host must be set to whatever the user connects with, not what is in the user db. If name resolve is enabled and you are in an intranet, it is possible that the server will get the hostname (instead of the IP) eg. user@my-pc-hostname instead of user@192.168.1.123

This can be an issue for configuration. The following approaches can be used to workaround this limitation:

 *  disable dns resolve on the MySQL server (add skip-name-resolve under [mysqld] in my.ini) and use static IPs for your users
 *  use the exact hostname of your user
 *  use % to match anything, the user will already be authenticated by MySQL according to its HOST rules

#### Contributing To Choobs MySQL Grants Toolkit

Since this is hosted on github:

**All issues and pull requests should be filed on the [choobs/mysqlgt](http://github.com/choobs/mysqlgt) repository.**

Thank you.

## Authors

 * Erik DeLamarter (erik.delamarter@choobs.com)
 * Pravin Dahal

## License

The Choobs MySQL Grants Toolkit is open-sourced software licensed under the [MIT license](http://opensource.org/licenses/MIT)
