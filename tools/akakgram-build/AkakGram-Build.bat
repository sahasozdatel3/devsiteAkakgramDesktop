@echo off
chcp 65001 >nul
setlocal
title AkakGram - сборка Telegram.exe

set "HERE=%~dp0"
set "PS1=%HERE%build.ps1"
set "TMPPS1=%TEMP%\akakgram_build_new.ps1"
set "RAW=https://raw.githubusercontent.com/sahasozdatel3/devsiteAkakgramDesktop/dev/tools/akakgram-build/build.ps1"

echo.
echo   Проверяю обновления помощника на GitHub...
powershell -NoProfile -ExecutionPolicy Bypass -Command "try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -UseBasicParsing -Uri '%RAW%?t=%RANDOM%' -OutFile '%TMPPS1%' } catch { exit 1 }"
if not errorlevel 1 (
	copy /y "%TMPPS1%" "%PS1%" >nul
	echo   Помощник обновлён до последней версии.
) else (
	echo   Не удалось скачать обновление, использую локальную копию.
)

if exist "%PS1%" goto run

echo.
echo   Файл build.ps1 не найден и скачать его не получилось.
echo   Проверьте интернет и запустите батник снова.
echo.
pause
exit /b 1

:run
powershell -NoProfile -ExecutionPolicy Bypass -Command "& ([scriptblock]::Create([IO.File]::ReadAllText('%PS1%',[Text.Encoding]::UTF8)))"

echo.
pause
endlocal
