@echo off
chcp 65001 >nul
setlocal
title AkakGram - сборка Telegram.exe

set "HERE=%~dp0"
set "PS1=%HERE%build.ps1"
set "RAW=https://raw.githubusercontent.com/sahasozdatel3/devsiteAkakgramDesktop/dev/tools/akakgram-build/build.ps1"

if exist "%PS1%" goto run

echo.
echo   Файл build.ps1 не найден рядом с этим батником. Скачиваю с GitHub...
powershell -NoProfile -ExecutionPolicy Bypass -Command "try { Invoke-WebRequest -UseBasicParsing -Uri '%RAW%' -OutFile '%PS1%' } catch { exit 1 }"
if not errorlevel 1 goto run

echo.
echo   Не удалось скачать build.ps1.
echo   Скачайте папку tools\akakgram-build целиком из репозитория
echo   и запустите AkakGram-Build.bat из неё.
echo.
pause
exit /b 1

:run
powershell -NoProfile -ExecutionPolicy Bypass -Command "& ([scriptblock]::Create([IO.File]::ReadAllText('%PS1%',[Text.Encoding]::UTF8)))"

echo.
pause
endlocal
