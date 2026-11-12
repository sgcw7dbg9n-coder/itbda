@echo off
rem Opens RStudio using R from the r-env conda environment. Run it from
rem Anaconda Prompt so the environment's DLLs (libxml2, libpq, GSL) are on PATH;
rem RStudio started from the Start menu cannot load rvest, RPostgres or topicmodels.
rem   open_rstudio.bat q2_lda\q2_lda.Rproj
setlocal
call conda activate r-env || exit /b 1
set "RSTUDIO_WHICH_R=%CONDA_PREFIX%\lib\R\bin\x64\R.exe"

set "RSTUDIO_EXE=%ProgramFiles%\RStudio\rstudio.exe"
if not exist "%RSTUDIO_EXE%" set "RSTUDIO_EXE=%LOCALAPPDATA%\Programs\RStudio\rstudio.exe"
if not exist "%RSTUDIO_EXE%" (
  echo RStudio was not found. Install it, or edit RSTUDIO_EXE in this file.
  exit /b 1
)
start "" "%RSTUDIO_EXE%" %*
