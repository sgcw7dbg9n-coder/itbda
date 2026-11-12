@echo off
rem Stops the local PostgreSQL server started by start_postgres.bat.
pg_ctl -D "%USERPROFILE%\pgdata-itbda" stop
