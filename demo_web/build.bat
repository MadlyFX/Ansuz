@echo off
setlocal

:: Build OGUI Web Demo to WASM
:: Requires Odin compiler with js_wasm32 target support

set ODIN=odin

:: Memory configuration (in pages, 1 page = 64KB)
set INITIAL_PAGES=2000
set MAX_PAGES=65536

:: Calculate bytes
set /a INITIAL_BYTES=%INITIAL_PAGES% * 65536
set /a MAX_BYTES=%MAX_PAGES% * 65536

echo Building OGUI Web Demo...
%ODIN% build . -target:js_wasm32 -out:web\ogui_demo.wasm -o:size ^
    -extra-linker-flags:"--export-table --import-memory --initial-memory=%INITIAL_BYTES% --max-memory=%MAX_BYTES%"

if %ERRORLEVEL% neq 0 (
    echo Build failed!
    exit /b 1
)

:: Copy Odin JS runtime
for /f "tokens=*" %%i in ('%ODIN% root') do set ODIN_ROOT=%%i
copy /y "%ODIN_ROOT%\core\sys\wasm\js\odin.js" web\odin.js > nul

echo Build complete!
echo Open web\index.html in a browser, or run a local server:
echo   cd web ^&^& python -m http.server 8080
echo   Then visit http://localhost:8080

endlocal
