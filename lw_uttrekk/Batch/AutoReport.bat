REM This batch file executes a series of R scripts that queries LabWare and writes report files
@echo off
setlocal EnableExtensions EnableDelayedExpansion

REM File version. Use this to compare against the latest GitHub version.
REM Version 1.0.1

REM ==================================================
REM Resolve Batch, Repo, and Environment directories
REM ==================================================
set "BATCH_DIR=%~dp0"
REM %~dp0 is the directory of the batch file
REM so BATCH_DIR is the directory of this batch file

REM Set the path to the Prod/Test directory. This will be ENV_DIR
for %%I in ("%BATCH_DIR%\..") do set "ENV_DIR=%%~fI"
REM Then extract the name Test or Prod from that path and store this in ENV_NAME
for %%I in ("%ENV_DIR%") do set "ENV_NAME=%%~nxI"

REM Get also the name of the root dir directly above Prod/Test
for %%I in ("%ENV_DIR%\..") do set "ROOT_DIR=%%~fI"

REM ==================================================
REM Load environment variables from Config/config.env
REM ==================================================
set "CONFIG_FILE=%ENV_DIR%\Config\config.env"
if not exist "%CONFIG_FILE%" (
  echo ERROR: Missing config file %CONFIG_FILE%
  exit /b 1
)

for /f "usebackq eol=# delims=" %%A in ("%CONFIG_FILE%") do (
    if not "%%A"=="" set "%%A"
)

REM Expose ENV name to R so that the output files will be written to the correct directory
set "RUN_ENV=%ENV_NAME%"

REM ==================================================
REM Derive paths
REM ==================================================
set "SCRIPT_PATH=%ROOT_DIR%\%ENV_NAME%\Scripts"
set "LOG_PATH=%ROOT_DIR%\%ENV_NAME%\Log"

set "R_EXE=d:\R\R-4.3.0\bin\Rscript.exe"
if not exist "%R_EXE%" (
  echo ERROR: Rscript not found at %R_EXE%
  exit /b 1
)

set "LOG=%LOG_PATH%\batch-status.log"

REM ===== Execution =====

REM call the run subroutine defined below
call :run Test_base.R
call :run Test_uttrekk.R
call :run HCV.R
call :run GAS.R
call :run virus_dashboard.R

endlocal
exit /b 0

REM ==================================================
REM Subroutine
REM ==================================================
:run
"%R_EXE%" "%SCRIPT_PATH%\%1"
set "ERR=%errorlevel%"

REM ISO-like timestamp (locale-independent)
for /f %%T in ('wmic os get localdatetime ^| find "."') do set DTS=%%T
set TS=%DTS:~0,4%-%DTS:~4,2%-%DTS:~6,2%-%DTS:~8,2%-%DTS:~10,2%-%DTS:~12,2%

if %ERR% neq 0 (
  echo %TS%: %1 FAILED >> "%LOG%"
) else (
  echo %TS%: %1 OK >> "%LOG%"
)

exit /b
