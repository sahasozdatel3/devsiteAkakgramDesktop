# AkakGram Build: интерактивная сборка Telegram.exe для Windows (x64).
# Запускается через AkakGram-Build.bat. Файл в UTF-8, читается запускающим батником.

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8

$RepoUrl = 'https://github.com/sahasozdatel3/devsiteAkakgramDesktop.git'
$DefaultBranch = 'dev'
$DefaultBuildRoot = 'C:\TBuild'
$TestApiId = '17349'
$TestApiHash = '344583e45741c457fe1862106095a5eb'
$MsvcPinned = '14.44'
$SdkVersion = '10.0.26100.0'
$CMakeMin = [version]'3.25'

$script:LogFile = $null

# ---------- вывод ----------

function Write-Line([string]$text = '', [string]$color = 'Gray') {
    Write-Host $text -ForegroundColor $color
    if ($script:LogFile) {
        Add-Content -Path $script:LogFile -Value $text -Encoding UTF8
    }
}

function Write-Title([string]$text) {
    Write-Line ''
    Write-Line ('=' * 70) 'DarkCyan'
    Write-Line ('  ' + $text) 'Cyan'
    Write-Line ('=' * 70) 'DarkCyan'
}

function Write-Ok([string]$text) { Write-Line ('  [ OK ] ' + $text) 'Green' }
function Write-Warn([string]$text) { Write-Line ('  [ !! ] ' + $text) 'Yellow' }
function Write-Bad([string]$text) { Write-Line ('  [ нет ] ' + $text) 'Red' }
function Write-Note([string]$text) { Write-Line ('         ' + $text) 'DarkGray' }

function Ask-Text([string]$question, [string]$default) {
    $answer = Read-Host ('  ' + $question + ' [' + $default + ']')
    if ([string]::IsNullOrWhiteSpace($answer)) { return $default }
    return $answer.Trim()
}

function Ask-Yes([string]$question, [bool]$default = $true) {
    $hint = if ($default) { 'Д/н' } else { 'д/Н' }
    while ($true) {
        $answer = (Read-Host ('  ' + $question + ' (' + $hint + ')')).Trim().ToLower()
        if ($answer -eq '') { return $default }
        if ($answer -in @('д', 'да', 'y', 'yes')) { return $true }
        if ($answer -in @('н', 'нет', 'n', 'no')) { return $false }
    }
}

function Format-Gb([double]$bytes) {
    return ('{0:N1} ГБ' -f ($bytes / 1GB))
}

function Format-Span([TimeSpan]$span) {
    if ($span.TotalHours -ge 1) {
        return ('{0} ч {1} мин' -f [int][math]::Floor($span.TotalHours), $span.Minutes)
    }
    return ('{0} мин {1} с' -f [int][math]::Floor($span.TotalMinutes), $span.Seconds)
}

# ---------- состояние компьютера ----------

function Get-Machine([string]$driveLetter) {
    $os = Get-CimInstance Win32_OperatingSystem
    $cpu = Get-CimInstance Win32_Processor
    $threads = ($cpu | Measure-Object -Property NumberOfLogicalProcessors -Sum).Sum
    $disk = Get-CimInstance Win32_LogicalDisk -Filter ("DeviceID='" + $driveLetter + ":'")
    return [pscustomobject]@{
        CpuName = ($cpu | Select-Object -First 1).Name.Trim()
        Threads = [int]$threads
        RamTotal = [double]$os.TotalVisibleMemorySize * 1KB
        RamFree = [double]$os.FreePhysicalMemory * 1KB
        DiskFree = if ($disk) { [double]$disk.FreeSpace } else { 0.0 }
        DiskSize = if ($disk) { [double]$disk.Size } else { 0.0 }
    }
}

function Refresh-Path {
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = $machine + ';' + $user
}

# ---------- проверка программ ----------

function Find-Vs {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (-not (Test-Path $vswhere)) { return $null }
    $path = & $vswhere -latest -prerelease -products * `
        -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
        -property installationPath 2>$null
    if ([string]::IsNullOrWhiteSpace($path)) { return $null }
    return ($path | Select-Object -First 1).Trim()
}

function Get-CMakeVersion {
    $cmake = Get-Command cmake -ErrorAction SilentlyContinue
    if (-not $cmake) { return $null }
    $line = (& cmake --version 2>$null | Select-Object -First 1)
    if ($line -match '(\d+\.\d+(\.\d+)?)') { return [version]$Matches[1] }
    return $null
}

function Get-PythonVersion {
    $python = Get-Command python -ErrorAction SilentlyContinue
    if (-not $python) { return $null }
    $text = (& python --version 2>&1 | Select-Object -First 1)
    if ("$text" -match '(\d+\.\d+(\.\d+)?)') { return [version]$Matches[1] }
    return $null
}

function Install-WithWinget([string]$id, [string]$title) {
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $winget) {
        Write-Bad ('winget не найден, установите «' + $title + '» вручную.')
        return $false
    }
    Write-Line ('  Устанавливаю «' + $title + '» через winget...') 'Gray'
    & winget install --id $id -e --accept-package-agreements --accept-source-agreements | Out-Host
    $code = $LASTEXITCODE
    Refresh-Path
    return ($code -eq 0)
}

function Install-VsCpp {
    $installer = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer'
    $vswhere = Join-Path $installer 'vswhere.exe'
    $existing = $null
    if (Test-Path $vswhere) {
        $existing = & $vswhere -latest -prerelease -products * -property installationPath 2>$null
    }
    if (-not [string]::IsNullOrWhiteSpace($existing)) {
        $existing = ($existing | Select-Object -First 1).Trim()
        $setup = Join-Path $installer 'setup.exe'
        Write-Line ('  Добавляю компоненты C++ в уже установленную Visual Studio: ' + $existing) 'Gray'
        Write-Note 'Появится окно Windows с просьбой разрешить изменения, нажмите «Да».'
        Write-Note 'Установка займёт 10–30 минут и скачает около 8–10 ГБ.'
        $args = @('modify', '--installPath', ('"' + $existing + '"'),
            '--add', 'Microsoft.VisualStudio.Workload.NativeDesktop',
            '--includeRecommended', '--passive', '--norestart')
        try {
            $proc = Start-Process -FilePath $setup -ArgumentList $args -Wait -PassThru -Verb RunAs
            return ($proc.ExitCode -eq 0 -or $proc.ExitCode -eq 3010)
        } catch {
            Write-Bad 'Установка отменена или не удалась.'
            return $false
        }
    }
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $winget) {
        Write-Bad 'winget не найден: установите Visual Studio Community вручную.'
        return $false
    }
    Write-Line '  Устанавливаю Visual Studio Build Tools с C++ (без лишней оболочки)...' 'Gray'
    Write-Note 'Появится окно Windows с просьбой разрешить изменения, нажмите «Да».'
    Write-Note 'Установка займёт 10–30 минут и скачает около 8–10 ГБ.'
    & winget install --id Microsoft.VisualStudio.2022.BuildTools -e --accept-package-agreements --accept-source-agreements `
        --override '--add Microsoft.VisualStudio.Workload.VCTools --includeRecommended --passive --norestart' | Out-Host
    return ($LASTEXITCODE -eq 0)
}

function Check-Tools {
    $result = [ordered]@{ Ok = $true; VsPath = $null; Msvc = $false; Sdk = $false }

    Write-Line '  Проверяю, что установлено на вашем компьютере:' 'White'

    if (Get-Command git -ErrorAction SilentlyContinue) {
        Write-Ok 'Git найден.'
    } else {
        Write-Bad 'Git не найден.'
        if ((Ask-Yes 'Установить Git автоматически?') -and (Install-WithWinget 'Git.Git' 'Git') `
            -and (Get-Command git -ErrorAction SilentlyContinue)) {
            Write-Ok 'Git установлен.'
        } else { $result.Ok = $false }
    }

    $python = Get-PythonVersion
    if ($python) {
        Write-Ok ('Python ' + $python + ' найден.')
        if ($python.Major -ne 3 -or $python.Minor -lt 8) {
            Write-Warn 'Нужен Python 3.x (рекомендуется 3.10).'
        }
    } else {
        Write-Bad 'Python не найден.'
        if ((Ask-Yes 'Установить Python 3.10 автоматически?') `
            -and (Install-WithWinget 'Python.Python.3.10' 'Python 3.10') -and (Get-PythonVersion)) {
            Write-Ok 'Python установлен.'
        } else { $result.Ok = $false }
    }

    $cmake = Get-CMakeVersion
    if ($cmake -and $cmake -ge $CMakeMin) {
        Write-Ok ('CMake ' + $cmake + ' найден (нужен ' + $CMakeMin + ' или новее).')
    } else {
        if ($cmake) { Write-Bad ('CMake ' + $cmake + ' слишком старый, нужен ' + $CMakeMin + ' или новее.') }
        else { Write-Bad 'CMake не найден.' }
        $newer = $false
        if (Ask-Yes 'Установить свежий CMake автоматически?') {
            if (Install-WithWinget 'Kitware.CMake' 'CMake') {
                $cmake = Get-CMakeVersion
                $newer = ($cmake -and $cmake -ge $CMakeMin)
            }
        }
        if ($newer) { Write-Ok ('CMake ' + $cmake + ' готов.') } else { $result.Ok = $false }
    }

    $vs = Find-Vs
    if (-not $vs) {
        Write-Bad 'Visual Studio с компонентами C++ не найдена.'
        if ((Ask-Yes 'Установить компоненты C++ автоматически?') -and (Install-VsCpp)) {
            $vs = Find-Vs
        }
    }
    if ($vs) {
        $result.VsPath = $vs
        Write-Ok ('Visual Studio с компонентами C++ найдена: ' + $vs)
        $msvcDir = Join-Path $vs 'VC\Tools\MSVC'
        if ((Test-Path $msvcDir) -and (Get-ChildItem $msvcDir -Directory |
                Where-Object { $_.Name -like ($MsvcPinned + '*') })) {
            $result.Msvc = $true
            Write-Ok ('Набор инструментов MSVC ' + $MsvcPinned + ' на месте.')
        } else {
            Write-Warn ('MSVC ' + $MsvcPinned + ' не установлен, соберу с тем, что есть.')
            Write-Note 'Для поддержки Windows 7 установите компонент MSVC v14.44 в Visual Studio Installer.'
        }
    } else {
        Write-Bad 'Visual Studio с «Разработкой классических приложений на C++» не найдена.'
        Write-Note 'Скачайте Visual Studio Community: https://visualstudio.microsoft.com/'
        Write-Note 'и отметьте «Разработка классических приложений на C++».'
        $result.Ok = $false
    }

    $sdkDir = Join-Path ${env:ProgramFiles(x86)} ('Windows Kits\10\Include\' + $SdkVersion)
    if (Test-Path $sdkDir) {
        $result.Sdk = $true
        Write-Ok ('Windows SDK ' + $SdkVersion + ' найден.')
    } else {
        Write-Warn ('Windows SDK ' + $SdkVersion + ' не найден.')
        Write-Note 'Установите его через Visual Studio Installer, иначе сборка может не пройти.'
    }

    return $result
}

# ---------- окружение Visual Studio ----------

function Import-VsEnvironment([string]$vsPath, [bool]$pinMsvc) {
    $vcvars = Join-Path $vsPath 'VC\Auxiliary\Build\vcvars64.bat'
    if (-not (Test-Path $vcvars)) { throw ('Не найден файл ' + $vcvars) }
    $flag = if ($pinMsvc) { ' -vcvars_ver=' + $MsvcPinned } else { '' }
    $tmp = Join-Path $env:TEMP 'akakgram_vcvars.bat'
    $lines = @('@echo off', ('call "' + $vcvars + '"' + $flag + ' >nul'), 'set')
    [IO.File]::WriteAllLines($tmp, $lines, [Text.Encoding]::ASCII)
    $dump = & cmd.exe /c $tmp
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    foreach ($line in $dump) {
        $i = $line.IndexOf('=')
        if ($i -gt 0) {
            $name = $line.Substring(0, $i)
            $value = $line.Substring($i + 1)
            Set-Item -Path ('Env:' + $name) -Value $value -ErrorAction SilentlyContinue
        }
    }
}

# ---------- запуск шагов ----------

function Invoke-Step([string]$title, [string]$commandLine, [string]$workDir) {
    Write-Title $title
    Write-Note ('Команда: ' + $commandLine)
    Write-Note ('Папка:   ' + $workDir)
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $tmp = Join-Path $env:TEMP 'akakgram_step.bat'
    $lines = @('@echo off', ('cd /d "' + $workDir + '"'), $commandLine, 'exit /b %errorlevel%')
    [IO.File]::WriteAllLines($tmp, $lines, [Text.Encoding]::ASCII)
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    & cmd.exe /c $tmp 2>&1 | ForEach-Object {
        $text = "$_"
        Write-Host $text
        if ($script:LogFile) { Add-Content -Path $script:LogFile -Value $text -Encoding UTF8 }
    }
    $code = $LASTEXITCODE
    $ErrorActionPreference = $previous
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    $watch.Stop()
    if ($code -ne 0) {
        Write-Bad ('Шаг завершился с ошибкой (код ' + $code + ') за ' + (Format-Span $watch.Elapsed) + '.')
        Write-Note ('Полный журнал: ' + $script:LogFile)
        Write-Note 'Скопируйте последние 30–50 строк журнала и пришлите, чтобы разобраться.'
        throw 'Сборка остановлена.'
    }
    Write-Ok ('Готово за ' + (Format-Span $watch.Elapsed) + '.')
}

# ---------- основной сценарий ----------

Clear-Host
Write-Title 'AkakGram: сборка Telegram.exe для Windows'
Write-Line ''
Write-Line '  Этот помощник сам соберёт приложение из исходников. Ничего не будет' 'White'
Write-Line '  сделано без вашего согласия: сначала я покажу план, сколько это займёт' 'White'
Write-Line '  места, памяти и времени, и только потом спрошу, начинать ли.' 'White'

# 1. выбор варианта
Write-Title 'Шаг 1. Что собираем?'
Write-Line '  1) Debug x64   (рекомендуется)  Быстрее собирается, меньше места.' 'White'
Write-Note 'Exe получается крупнее и чуть медленнее, но для проверки подходит.'
Write-Line '  2) Release x64                  Готовая «боевая» версия.' 'White'
Write-Note 'Собирается заметно дольше и нагружает компьютер сильнее.'
Write-Line '  3) Только проект                Пересобрать, если библиотеки уже готовы.' 'White'
Write-Note 'Пропускает самый долгий шаг. Нужна ранее выполненная подготовка.'
Write-Line '  0) Выход' 'White'

$variant = $null
while (-not $variant) {
    $choice = (Read-Host '  Ваш выбор (0-3)').Trim()
    switch ($choice) {
        '1' { $variant = @{ Config = 'Debug'; SkipLibs = $false; Name = 'Debug x64' } }
        '2' { $variant = @{ Config = 'Release'; SkipLibs = $false; Name = 'Release x64' } }
        '3' { $variant = @{ Config = 'Debug'; SkipLibs = $true; Name = 'Debug x64, только проект' } }
        '0' { Write-Line '  Выход. Ничего не изменено.' 'Gray'; return }
        default { Write-Warn 'Введите число от 0 до 3.' }
    }
}

# 2. параметры
Write-Title 'Шаг 2. Параметры'
Write-Note 'Папка сборки: короткий путь без пробелов и русских букв.'
$buildRoot = Ask-Text 'Папка сборки' $DefaultBuildRoot
while ($buildRoot -match '\s' -or $buildRoot -match '[^\x00-\x7F]' -or $buildRoot.Length -lt 4) {
    Write-Warn 'Путь не должен содержать пробелов и не-латинских символов.'
    $buildRoot = Ask-Text 'Папка сборки' $DefaultBuildRoot
}
$buildRoot = [IO.Path]::GetFullPath($buildRoot).TrimEnd('\')
$driveLetter = $buildRoot.Substring(0, 1)
$branch = Ask-Text 'Ветка репозитория' $DefaultBranch

Write-Line ''
Write-Note 'API ID и API Hash нужны приложению для доступа к серверу.'
Write-Note 'Свои можно получить на https://my.telegram.org. Для проверки подойдут тестовые.'
$apiId = Ask-Text 'API ID' $TestApiId
$apiHash = Ask-Text 'API Hash' $TestApiHash

# 3. состояние компьютера
$machine = Get-Machine $driveLetter
$ramGb = $machine.RamTotal / 1GB
$freeRamGb = $machine.RamFree / 1GB
$jobs = [int][math]::Max(1, [math]::Min($machine.Threads, [math]::Floor($freeRamGb / 2)))

if ($variant.SkipLibs) {
    $needDiskGb = 12
    $needDiskText = 'около 6–12 ГБ'
} elseif ($variant.Config -eq 'Release') {
    $needDiskGb = 60
    $needDiskText = 'около 50–60 ГБ'
} else {
    $needDiskGb = 50
    $needDiskText = 'около 40–50 ГБ'
}

Write-Title 'Шаг 3. Ваш компьютер и что понадобится'
Write-Line ('  Процессор:  ' + $machine.CpuName + ', потоков: ' + $machine.Threads) 'White'
Write-Line ('  Память:     всего ' + ('{0:N1}' -f $ramGb) + ' ГБ, сейчас свободно ' + ('{0:N1}' -f $freeRamGb) + ' ГБ') 'White'
Write-Line ('  Диск ' + $driveLetter + ':     свободно ' + (Format-Gb $machine.DiskFree) + ' из ' + (Format-Gb $machine.DiskSize)) 'White'
Write-Line ''
Write-Line '  Что потребуется (оценки ориентировочные, у вас может отличаться):' 'White'
Write-Line ('    Место на диске:     ' + $needDiskText) 'Gray'
Write-Line '    Оперативная память: в пике 8–12 ГБ (линковка Qt самая тяжёлая) ' 'Gray'
Write-Line '    Процессор:          будет загружен почти на 100% много минут' 'Gray'
Write-Line ('    Потоков сборки:     ' + $jobs + ' (подобрано по вашей свободной памяти)') 'Gray'

$blockers = 0
if ($machine.DiskFree / 1GB -lt $needDiskGb) {
    Write-Bad ('На диске ' + $driveLetter + ': мало места: нужно около ' + $needDiskGb + ' ГБ, свободно ' + (Format-Gb $machine.DiskFree) + '.')
    $blockers++
} else {
    Write-Ok 'Места на диске достаточно.'
}
if ($ramGb -lt 16) {
    Write-Bad ('Оперативной памяти меньше 16 ГБ (' + ('{0:N1}' -f $ramGb) + ' ГБ): сборка может упасть.')
    $blockers++
} elseif ($freeRamGb -lt 8) {
    Write-Warn ('Свободно всего ' + ('{0:N1}' -f $freeRamGb) + ' ГБ памяти. Закройте браузер и игры, иначе сборка замедлится.')
} else {
    Write-Ok 'Оперативной памяти достаточно.'
}

# 4. проверка программ
Write-Title 'Шаг 4. Нужные программы'
$tools = Check-Tools
if (-not $tools.Ok) { $blockers++ }

if ($blockers -gt 0) {
    Write-Line ''
    Write-Bad 'Есть проблемы выше. Исправьте их и запустите помощник снова.'
    return
}

# 5. план
$cloneDir = Join-Path $buildRoot 'tdesktop'
$stateFile = Join-Path $buildRoot '.akakgram_libs_ready'
$libsDone = Test-Path $stateFile
$clonePresent = Test-Path (Join-Path $cloneDir '.git')
$configured = Test-Path (Join-Path $cloneDir 'out\Telegram.slnx')

Write-Title 'Шаг 5. План: что именно произойдёт'
Write-Line ('  Вариант:       ' + $variant.Name) 'White'
Write-Line ('  Папка сборки:  ' + $buildRoot) 'White'
Write-Line ('  Репозиторий:   ' + $RepoUrl + ' (ветка ' + $branch + ')') 'White'
Write-Line ''
Write-Line '  Порядок работы:' 'White'

$planSteps = @()
if ($clonePresent) {
    $planSteps += @{ N = 'Скачивание кода'; T = 'уже скачан, будет обновлён до последней версии ветки'; D = '' }
} else {
    $planSteps += @{ N = 'Скачивание кода'; T = '5–15 минут'; D = '+ ~2 ГБ (код вместе с подмодулями)' }
}
if ($variant.SkipLibs) {
    $planSteps += @{ N = 'Библиотеки'; T = 'пропускаются (по вашему выбору)'; D = '' }
} elseif ($libsDone) {
    $planSteps += @{ N = 'Библиотеки'; T = 'уже подготовлены, шаг пропускается'; D = '' }
} else {
    $planSteps += @{ N = 'Библиотеки (Qt, FFmpeg, OpenSSL и др.)'; T = '1–3 часа, самый долгий шаг, делается один раз'; D = '+ ~30–40 ГБ' }
}
$planSteps += @{ N = 'Настройка проекта (CMake)'; T = '1–3 минуты'; D = '+ ~0.5 ГБ' }
$planSteps += @{ N = ('Компиляция ' + $variant.Config); T = '20–60 минут в первый раз'; D = '+ ~6–12 ГБ' }
$planSteps += @{ N = 'Итог'; T = 'покажу путь к Telegram.exe и предложу скопировать его на рабочий стол'; D = '' }

$i = 1
foreach ($step in $planSteps) {
    Write-Line ('   ' + $i + '. ' + $step.N) 'Cyan'
    Write-Note ('Время: ' + $step.T)
    if ($step.D) { Write-Note ('Диск:  ' + $step.D) }
    $i++
}
Write-Line ''
Write-Line '  Важно знать:' 'White'
Write-Note '• Компьютер будет сильно нагружен. Лучше не запускать игры и тяжёлые программы.'
Write-Note '• Окно нельзя закрывать. Если прервёте, запустите помощник снова: сделанное сохранится.'
Write-Note '• Весь вывод сохраняется в журнал в папке сборки (build-журнал), он пригодится при ошибке.'
Write-Note '• Ваши API ID и Hash остаются только в этом компьютере, никуда не отправляются.'
Write-Line ''

if (-not (Ask-Yes 'Начать сборку?' $true)) {
    Write-Line '  Отменено. Ничего не изменено.' 'Gray'
    return
}

# 6. выполнение
New-Item -ItemType Directory -Force -Path $buildRoot | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $buildRoot 'ThirdParty') | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $buildRoot 'Libraries') | Out-Null
$script:LogFile = Join-Path $buildRoot ('akakgram-build-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')
Write-Line ('  Журнал: ' + $script:LogFile) 'DarkGray'

$diskFreeBefore = $machine.DiskFree
$total = [Diagnostics.Stopwatch]::StartNew()

try {
    Import-VsEnvironment $tools.VsPath $tools.Msvc
    Write-Ok 'Окружение Visual Studio подключено.'

    if ($clonePresent) {
        Invoke-Step 'Обновление кода' ('git fetch origin ' + $branch + ' && git checkout ' + $branch + ' && git pull --ff-only origin ' + $branch + ' && git submodule update --init --recursive') $cloneDir
    } else {
        Invoke-Step 'Скачивание кода' ('git clone --recursive -b ' + $branch + ' ' + $RepoUrl + ' tdesktop') $buildRoot
    }

    if (-not $variant.SkipLibs -and -not $libsDone) {
        Invoke-Step 'Сборка библиотек (это надолго)' ('call "' + (Join-Path $cloneDir 'Telegram\build\prepare\win.bat') + '"') $buildRoot
        Set-Content -Path $stateFile -Value (Get-Date -Format 's') -Encoding ASCII
    }

    Invoke-Step 'Настройка проекта' ('call configure.bat x64 -D TDESKTOP_API_ID=' + $apiId + ' -D TDESKTOP_API_HASH=' + $apiHash) (Join-Path $cloneDir 'Telegram')

    Invoke-Step ('Компиляция Telegram (' + $variant.Config + ')') ('cmake --build out --config ' + $variant.Config + ' --target Telegram --parallel ' + $jobs) $cloneDir
} catch {
    Write-Line ''
    Write-Bad ('Остановлено: ' + $_.Exception.Message)
    return
}

$total.Stop()

# 7. итог
$exe = Join-Path $cloneDir ('out\' + $variant.Config + '\Telegram.exe')
$after = Get-Machine $driveLetter
$used = $diskFreeBefore - $after.DiskFree

Write-Title 'Готово'
Write-Line ('  Всего времени: ' + (Format-Span $total.Elapsed)) 'White'
Write-Line ('  Занято на диске за эту сборку: ' + (Format-Gb ([math]::Max(0, $used)))) 'White'

if (Test-Path $exe) {
    $size = (Get-Item $exe).Length
    Write-Ok ('Telegram.exe: ' + $exe + ' (' + ('{0:N0}' -f ($size / 1MB)) + ' МБ)')
    if (Ask-Yes 'Скопировать Telegram.exe на рабочий стол?' $true) {
        $desktop = [Environment]::GetFolderPath('Desktop')
        Copy-Item $exe (Join-Path $desktop 'AkakGram.exe') -Force
        Write-Ok ('Скопировано: ' + (Join-Path $desktop 'AkakGram.exe'))
    }
    Write-Note 'Тема включается в Настройки, Оформление, «Night».'
    if (Ask-Yes 'Открыть папку с файлом?' $true) {
        Start-Process explorer.exe ('/select,"' + $exe + '"')
    }
} else {
    Write-Warn ('Сборка закончилась, но файл не найден: ' + $exe)
    Write-Note ('Проверьте журнал: ' + $script:LogFile)
}
