@echo off
REM Open Raspberry Pi Imager with the Terra OS list.
REM Imager 1.8, 1.9, and 2.x all accept --repo.
set "REPO_URL=https://github.com/Super-Yojan/terra-image-gen/releases/latest/download/terra-os-list.json"
if defined TERRA_IMAGER_REPO_URL set "REPO_URL=%TERRA_IMAGER_REPO_URL%"
set "IMAGER=%ProgramFiles%\Raspberry Pi Imager\rpi-imager.exe"
if not exist "%IMAGER%" set "IMAGER=%LocalAppData%\Programs\Raspberry Pi Imager\rpi-imager.exe"
if not exist "%IMAGER%" (
  echo Raspberry Pi Imager was not found.
  echo Install it, then run:
  echo   rpi-imager.exe --repo %REPO_URL%
  exit /b 1
)
start "" "%IMAGER%" --repo "%REPO_URL%"
