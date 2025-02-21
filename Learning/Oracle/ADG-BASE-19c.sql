--  https://docs.oracle.com/en/database/oracle/oracle-database/19/sbydb/creating-oracle-data-guard-physical-standby.html#GUID-B511FB6E-E3E7-436D-94B5-071C37550170
--  Step by Step Guide on Creating Physical Standby Using RMAN DUPLICATE...FROM ACTIVE DATABASE (Doc ID 1075908.1)

-------------Primary Database---------------------------------------------------- 
-- FRA preparation ------------------------------------------------------------
mkdir -p /u01/app/oracle/fast_recovery_area
-- chown -R oracle:oinstall /u01/app/oracle/fast_recovery_area
chmod -R 750 /u01/app/oracle/fast_recovery_area
ALTER SYSTEM SET db_recovery_file_dest_size=10G SCOPE=BOTH;
ALTER SYSTEM SET db_recovery_file_dest='/u01/app/oracle/fast_recovery_area' SCOPE=BOTH;

-- check force logging
SELECT name,log_mode,force_logging FROM v$database;
-- enable force logging
ALTER DATABASE FORCE LOGGING;

-- Primary: add standby redo log -- best practice
-- ALTER DATABASE ADD STANDBY LOGFILE ('/u01/app/oracle/fast_recovery_area/slog1.log') SIZE 500M;
-- ALTER DATABASE ADD STANDBY LOGFILE ('/u01/app/oracle/fast_recovery_area/slog2.log') SIZE 500M;
-- ALTER DATABASE ADD STANDBY LOGFILE ('/u01/app/oracle/fast_recovery_area/slog3.log') SIZE 500M;
-- ALTER DATABASE ADD STANDBY LOGFILE ('/u01/app/oracle/fast_recovery_area/slog4.log') SIZE 500M;
ALTER DATABASE ADD STANDBY LOGFILE THREAD 1
GROUP 4 ('/u01/app/oracle/fast_recovery_area/slog1.log') SIZE 500M,
GROUP 5 ('/u01/app/oracle/fast_recovery_area/slog2.log') SIZE 500M, 
GROUP 6 ('/u01/app/oracle/fast_recovery_area/slog3.log') SIZE 500M,
GROUP 7 ('/u01/app/oracle/fast_recovery_area/slog4.log') SIZE 500M;

-- configure parameters
ALTER SYSTEM SET DB_UNIQUE_NAME='ORCLCDB_PRIMARY' SCOPE=SPFILE;
ALTER SYSTEM SET LOG_ARCHIVE_CONFIG='DG_CONFIG=(ORCLCDB_PRIMARY,ORCLCDB_STANDBY)' SCOPE=SPFILE;
ALTER SYSTEM SET LOG_ARCHIVE_DEST_1='LOCATION=USE_DB_RECOVERY_FILE_DEST VALID_FOR=(ALL_LOGFILES,ALL_ROLES) DB_UNIQUE_NAME=ORCLCDB_PRIMARY' SCOPE=SPFILE;
ALTER SYSTEM SET LOG_ARCHIVE_DEST_2='SERVICE=ORCLCDB_STANDBY ASYNC VALID_FOR=(ONLINE_LOGFILES,PRIMARY_ROLE) DB_UNIQUE_NAME=ORCLCDB_STANDBY' SCOPE=SPFILE;
ALTER SYSTEM SET REMOTE_LOGIN_PASSWORDFILE=EXCLUSIVE SCOPE=SPFILE;
ALTER SYSTEM SET LOG_ARCHIVE_FORMAT='%t_%s_%r.arc' SCOPE=SPFILE;
ALTER SYSTEM SET FAL_SERVER=ORCLCDB_STANDBY SCOPE=SPFILE;
ALTER SYSTEM SET DB_FILE_NAME_CONVERT='/opt/oracle/oradata/ORCLCDB_STANDBY/','/opt/oracle/oradata/ORCLCDB/' SCOPE=SPFILE;
ALTER SYSTEM SET LOG_FILE_NAME_CONVERT='/opt/oracle/oradata/ORCLCDB_STANDBY/','/opt/oracle/oradata/ORCLCDB/' SCOPE=SPFILE;
-- ALTER SYSTEM SET DB_FILE_NAME_CONVERT='/opt/oracle/oradata/ORCLCDB_STANDBY/','/opt/oracle/oradata/ORCLCDB_PRIMARY/' SCOPE=SPFILE;
-- ALTER SYSTEM SET LOG_FILE_NAME_CONVERT='/opt/oracle/oradata/ORCLCDB_STANDBY/','/opt/oracle/oradata/ORCLCDB_PRIMARY/' SCOPE=SPFILE;
ALTER SYSTEM SET STANDBY_FILE_MANAGEMENT=AUTO SCOPE=SPFILE;

-- check log mode
SELECT log_mode FROM v$database;
--or
ARCHIVE LOG LIST;
-- enable archive log
SHUTDOWN IMMEDIATE;
STARTUP MOUNT;
ALTER DATABASE ARCHIVELOG;
ALTER DATABASE OPEN;

-- create standby controlfile
ALTER DATABASE CREATE STANDBY CONTROLFILE AS '/u01/app/oracle/fast_recovery_area/ORCLCDB_STANDBY.ctl';
-- or
RMAN> RUN {
    allocate channel d1 type disk;
    backup current controlfile for standby format '/u01/app/oracle/fast_recovery_area/ORCLCDB_STANDBY.ctl';
    release channel d1;
}

-- create pfile for standby database
CREATE PFILE='/u01/app/oracle/fast_recovery_area/ORCLCDB_STANDBY.ora' FROM SPFILE;

-- listener.ora
LISTENER =
  (DESCRIPTION_LIST =
    (DESCRIPTION =
      (ADDRESS = (PROTOCOL = TCP)(HOST = 192.168.56.110)(PORT = 1521))
    )
  )
-- ALTER SYSTEM SET LOCAL_LISTENER='(ADDRESS=(PROTOCOL=TCP)(HOST=192.168.56.110)(PORT=1521))' SCOPE=BOTH;

-- tnsnames.ora
ORCLCDB_PRIMARY =
  (DESCRIPTION =
    (ADDRESS = (PROTOCOL = TCP)(HOST = 192.168.56.110)(PORT = 1521))
    (CONNECT_DATA =
      (SERVER = DEDICATED)
      (SERVICE_NAME = ORCLCDB_PRIMARY)
    )
  )

ORCLCDB_STANDBY =
  (DESCRIPTION =
    (ADDRESS_LIST =
      (ADDRESS = (PROTOCOL = TCP)(HOST = 192.168.56.109)(PORT = 1521))
    )
    (CONNECT_DATA =
      (SERVER = DEDICATED)
      (SERVICE_NAME = ORCLCDB_STANDBY)
    )
  )

ORCLPDB1 =
  (DESCRIPTION =
    (ADDRESS = (PROTOCOL = TCP)(HOST = 192.168.56.110)(PORT = 1521))
    (CONNECT_DATA =
      (SERVER = DEDICATED)
      (SERVICE_NAME = ORCLPDB1)
    )
  )
------Standby Database----------------------------------------------------  
-- listener.ora
LISTENER =
  (DESCRIPTION_LIST =
    (DESCRIPTION =
      (ADDRESS = (PROTOCOL = TCP)(HOST = 192.168.56.109)(PORT = 1521))
    )
  )

SID_LIST_LISTENER =
  (SID_LIST =
    (SID_DESC =
      (GLOBAL_DBNAME = ORCLCDB_STANDBY)
      (DB_HOME = /u01/app/oracle/product/19.3.0.0/dbhome_1)
      (SID_NAME = ORCLCDB_STANDBY)
    )
  )
  
-- tnsnames.ora
ORCLCDB_PRIMARY =
  (DESCRIPTION =
    (ADDRESS = (PROTOCOL = TCP)(HOST = 192.168.56.110)(PORT = 1521))
    (CONNECT_DATA =
      (SERVER = DEDICATED)
      (SERVICE_NAME = ORCLCDB_PRIMARY)
    )
  )

ORCLCDB_STANDBY =
  (DESCRIPTION =
    (ADDRESS_LIST =
      (ADDRESS = (PROTOCOL = TCP)(HOST = 192.168.56.109)(PORT = 1521))
    )
    (CONNECT_DATA =
      (SERVER = DEDICATED)
      (SERVICE_NAME = ORCLCDB_STANDBY)
    )
  )

ORCLPDB1 =
  (DESCRIPTION =
    (ADDRESS = (PROTOCOL = TCP)(HOST = 192.168.56.110)(PORT = 1521))
    (CONNECT_DATA =
      (SERVER = DEDICATED)
      (SERVICE_NAME = ORCLPDB1)
    )
  )

-- directories preparation
mkdir -p /u01/app/oracle/fast_recovery_area
chmod -R 750 /u01/app/oracle/fast_recovery_area

mkdir -p /u01/app/oracle/oradata/ORCLCDB_STANDBY
chmod -R 750 /u01/app/oracle/oradata/ORCLCDB_STANDBY

mkdir -p /opt/oracle/admin/ORCLCDB_STANDBY/adump
chmod -R 750 /opt/oracle/admin/ORCLCDB_STANDBY
chmod -R 750 /opt/oracle/admin/ORCLCDB_STANDBY/adump

---- copy ORCLCDB_STANDBY.ctl, ORCLCDB_STANDBY.ora, password file:orapwORCLCDB_STANDBY to standby host -----

-- modify ORCLCDB_STANDBY.ora
*.audit_file_dest='/opt/oracle/admin/ORCLCDB_STANDBY/adump'
-- *.audit_sys_operations=false
-- *.audit_trail='none'
-- *.commit_logging='batch'
-- *.commit_wait='nowait'
-- *.compatible='19.0.0'
*.control_files='/opt/oracle/oradata/ORCLCDB_STANDBY/control01.ctl','/opt/oracle/oradata/ORCLCDB_STANDBY/control02.ctl'
-- *.db_block_size=8192
*.db_file_name_convert='/opt/oracle/oradata/ORCLCDB/','/opt/oracle/oradata/ORCLCDB_STANDBY/'
-- *.db_name='ORCLCDB'
-- *.db_recovery_file_dest_size=10737418240
-- *.db_recovery_file_dest='/u01/app/oracle/fast_recovery_area'
*.db_unique_name='ORCLCDB_STANDBY'
-- *.diagnostic_dest='/opt/oracle'
*.dispatchers='(PROTOCOL=TCP) (SERVICE=ORCLCDB_STANDBYXDB)'
-- *.enable_pluggable_database=true
-- *.fal_client=''
*.fal_server='ORCLCDB_PRIMARY'
-- *.filesystemio_options='setall'
*.local_listener='(ADDRESS = (PROTOCOL = TCP)(HOST = 192.168.56.109)(PORT = 1521))'
-- *.log_archive_config='DG_CONFIG=(ORCLCDB_PRIMARY,ORCLCDB_STANDBY)'
*.log_archive_dest_1='LOCATION=USE_DB_RECOVERY_FILE_DEST VALID_FOR=(ALL_LOGFILES,ALL_ROLES) DB_UNIQUE_NAME=ORCLCDB_STANDBY'
*.log_archive_dest_2='SERVICE=ORCLCDB_PRIMARY ASYNC VALID_FOR=(ONLINE_LOGFILES,PRIMARY_ROLE) DB_UNIQUE_NAME=ORCLCDB_PRIMARY'
-- *.log_archive_format='%t_%s_%r.arc'
*.log_file_name_convert='/opt/oracle/oradata/ORCLCDB/','/opt/oracle/oradata/ORCLCDB_STANDBY/'
-- *.nls_language='AMERICAN'
-- *.nls_territory='AMERICA'
-- *.open_cursors=300
-- *.pga_aggregate_target=384m
-- *.processes=300
-- *.remote_login_passwordfile='EXCLUSIVE'
-- *.sga_target=1152m
-- *.standby_file_management='AUTO'
-- *.undo_tablespace='UNDOTBS1'

-- set environment variable
export ORACLE_SID=ORCLCDB_STANDBY

-- -- connect to idle instance on standby host, create spfile
-- CREATE SPFILE FROM PFILE='/u01/app/oracle/fast_recovery_area/ORCLCDB_STANDBY.ora';
-- start database in nomount mode
STARTUP NOMOUNT pfile='/u01/app/oracle/fast_recovery_area/ORCLCDB_STANDBY.ora';

-- RMAN duplicate database
rman target sys/Welcome1#@ORCLCDB_PRIMARY auxiliary sys/Welcome1#@ORCLCDB_STANDBY

-- duplicate database
RMAN> run {
     duplicate target database for standby from active database;
}
-- RMAN
-- RMAN> CATALOG ARCHIVELOG '/u01/app/oracle/fast_recovery_area/slog1.log'; -- 将备库的日志文件添加到RMAN的catalog中
-- RMAN> CATALOG START WITH '/u01/app/oracle/fast_recovery_area/'; -- 将备库的日志文件添加到RMAN的catalog中

-- start redo apply
ALTER DATABASE RECOVER MANAGED STANDBY DATABASE USING CURRENT LOGFILE DISCONNECT FROM SESSION;

-- stop redo apply
ALTER DATABASE RECOVER MANAGED STANDBY DATABASE CANCEL;
-- open standby instance read-only
ALTER DATABASE OPEN;
-- restart redo apply
ALTER DATABASE RECOVER MANAGED STANDBY DATABASE USING CURRENT LOGFILE DISCONNECT FROM SESSION;
-- query database mode
SELECT DATABASE_ROLE, OPEN_MODE FROM V$DATABASE;

-- standby
ALTER DATABASE ADD STANDBY LOGFILE THREAD 1
GROUP 4 ('/u01/app/oracle/fast_recovery_area/slog1.log') SIZE 500M,
GROUP 5 ('/u01/app/oracle/fast_recovery_area/slog2.log') SIZE 500M,
GROUP 6 ('/u01/app/oracle/fast_recovery_area/slog3.log') SIZE 500M,
GROUP 7 ('/u01/app/oracle/fast_recovery_area/slog4.log') SIZE 500M;

-- Primary
ALTER SYSTEM ARCHIVE LOG CURRENT;










-- 备份数据文件,控制文件,归档日志
RMAN> run { 
              allocate channel d1 type disk; 
              backup format '/<PATH>/df_t%t_s%s_p%p'database; 
              backup current controlfile for standby format '/backups/PROD/sb_t%t_s%s_p%p';
              sql 'alter system archive log current'; 
              backup format '/<PATH>/al_t%t_s%s_p%p' archivelog all;
              release channel d1; 
           }

-- 查询数据文件,归档日志,控制文件大小
select DF.TOTAL/1048576 "DataFile Size Mb",
        LOG.TOTAL/1048576 "Redo Log Size Mb",
        CONTROL.TOTAL/1048576 "Control File Size Mb",
        (DF.TOTAL + LOG.TOTAL + CONTROL.TOTAL)/1048576 "Total Size Mb" from dual,
        (select sum(a.bytes) TOTAL from dba_data_files a) DF,
        (select sum(b.bytes) TOTAL from v$log b) LOG,
        (select sum((cffsz+1)*cfbsz) TOTAL from x$kcccf c) CONTROL;