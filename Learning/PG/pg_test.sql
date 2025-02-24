CREATE TABLESPACE test_tablespace OWNER postgres LOCATION '/var/lib/pgsql/test_tablespace';

CREATE TABLE t4 (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL
) TABLESPACE test_tablespace;

CREATE DATABASE test2 TABLESPACE test_tablespace;

CREATE TABLE t5 (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL
);

SELECT pg_relation_filepath('t5');