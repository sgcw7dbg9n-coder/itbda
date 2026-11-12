@echo off
rem Starts a local PostgreSQL server from the r-env conda environment and
rem creates the itbda database on first use. No admin rights are needed.
rem Run in Anaconda Prompt after "conda activate r-env" and keep the window open.
setlocal
set "PGDATA=%USERPROFILE%\pgdata-itbda"

where pg_ctl >nul 2>&1 || (
  echo pg_ctl not found. Run "conda activate r-env" first, then "conda install -c conda-forge postgresql".
  exit /b 1
)

if not exist "%PGDATA%\PG_VERSION" (
  echo Creating a new database cluster in %PGDATA% ...
  initdb -D "%PGDATA%" -U postgres -A trust -E UTF8 --no-locale || exit /b 1
)

pg_ctl -D "%PGDATA%" status >nul 2>&1 || (
  pg_ctl -D "%PGDATA%" -l "%PGDATA%\server.log" -w start || exit /b 1
)

psql -U postgres -h localhost -tAc "SELECT 1 FROM pg_database WHERE datname = 'itbda'" | findstr "1" >nul || createdb -U postgres -h localhost itbda
echo PostgreSQL is running on localhost:5432 (user postgres, database itbda).
