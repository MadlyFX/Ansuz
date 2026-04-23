@echo off
setlocal

set ODIN=odin

set INITIAL_PAGES=2000
set MAX_PAGES=65536
set /a INITIAL_BYTES=%INITIAL_PAGES% * 65536
set /a MAX_BYTES=%MAX_PAGES% * 65536

echo Building E2E Config Web...
%ODIN% build . -target:js_wasm32 -out:web\e2econfig.wasm -o:size ^
    -extra-linker-flags:"--export-table --import-memory --initial-memory=%INITIAL_BYTES% --max-memory=%MAX_BYTES%"

if %ERRORLEVEL% neq 0 (
    echo Build failed!
    exit /b 1
)

for /f "tokens=*" %%i in ('%ODIN% root') do set ODIN_ROOT=%%i
copy /y "%ODIN_ROOT%\core\sys\wasm\js\odin.js" web\odin.js > nul

echo Build complete!
echo Run a local server to test:
echo   cd web ^&^& python -m http.server 8080
echo   Then visit http://localhost:8080

endlocal
