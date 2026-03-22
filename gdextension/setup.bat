@echo off
echo === Station Mirny - GDExtension Setup ===
echo.

REM Проверяем git
where git >nul 2>nul
if %errorlevel% neq 0 (
    echo ERROR: Git не найден. Установи Git: https://git-scm.com/download/win
    pause
    exit /b 1
)

REM Проверяем scons
where scons >nul 2>nul
if %errorlevel% neq 0 (
    echo ERROR: SCons не найден. Выполни: pip install scons
    pause
    exit /b 1
)

echo [1/3] Клонируем godot-cpp (займёт пару минут)...
if not exist "godot-cpp" (
    git clone https://github.com/godotengine/godot-cpp.git --branch godot-4.3-stable --depth 1
) else (
    echo godot-cpp уже есть, пропускаем.
)

echo.
echo [2/3] Скачиваем FastNoiseLite.h...
if not exist "src\FastNoiseLite.h" (
    curl -L -o src\FastNoiseLite.h https://raw.githubusercontent.com/Auburn/FastNoiseLite/master/Cpp/FastNoiseLite.h
    if %errorlevel% neq 0 (
        echo ERROR: Не удалось скачать FastNoiseLite.h
        echo Скачай вручную: https://github.com/Auburn/FastNoiseLite/blob/master/Cpp/FastNoiseLite.h
        echo Положи в папку src\
        pause
        exit /b 1
    )
) else (
    echo FastNoiseLite.h уже есть, пропускаем.
)

echo.
echo [3/3] Собираем библиотеку...
scons platform=windows target=template_debug
if %errorlevel% neq 0 (
    echo.
    echo ERROR: Сборка не удалась.
    echo Убедись что Visual Studio установлен и запусти из
    echo "x64 Native Tools Command Prompt for VS 2022"
    pause
    exit /b 1
)

echo.
echo === ГОТОВО! ===
echo Файл: bin\station_mirny.windows.template_debug.x86_64.dll
echo Скопируй папку bin\ и station_mirny.gdextension в проект Godot.
pause
