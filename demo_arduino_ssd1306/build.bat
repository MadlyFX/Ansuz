@echo off
setlocal EnableDelayedExpansion

REM ====== Target Selection ======
REM Usage:  build.bat [target]
REM Targets:
REM   m4      - ARM Cortex-M4  (STM32L4, Feather M4, Nano 33 BLE, etc.)
REM   rp2040  - ARM Cortex-M0+ (Raspberry Pi Pico / RP2040)
REM Default: m4

set TARGET=%1
if "%TARGET%"=="" set TARGET=m4

if /i "%TARGET%"=="m4" goto :set_m4
if /i "%TARGET%"=="rp2040" goto :set_rp2040
echo Unknown target: %TARGET%
echo Valid targets: m4, rp2040
exit /b 1

:set_m4
set ODIN_MICROARCH=cortex-m4
set ODIN_EXTRA_FLAGS=
set DISPLAY_NAME=ARM Cortex-M4
goto :build

:set_rp2040
set ODIN_MICROARCH=cortex-m0plus
set ODIN_EXTRA_FLAGS=-target-features:soft-float
set DISPLAY_NAME=RP2040 (Cortex-M0+)
goto :build

:build
echo === Building OGUI for %DISPLAY_NAME% ===
if not exist build mkdir build

REM ====== Compile Odin UI Code ======
REM Produces an object file with C-callable exports: ogui_init, ogui_render_frame, etc.
REM
REM IMPORTANT: Before building, reduce FRAME_ARENA_SIZE in ogui\manager.odin
REM            from 256*1024 to 4*1024 for microcontroller targets.
REM
REM RP2040 notes:
REM   - Cortex-M0+ is ARMv6-M (Thumb-1 only, no hardware divide, no FPU)
REM   - 264KB SRAM — plenty for the ~80KB this demo needs
REM   - Odin's freestanding_arm32 with cortex-m0plus emits valid Thumb-1 code

echo Compiling Odin UI code for %DISPLAY_NAME%...
odin build odin_ui -target:freestanding_arm32 -microarch:%ODIN_MICROARCH% %ODIN_EXTRA_FLAGS% -no-crt -o:size -build-mode:obj -out:build\ogui_ui -vet
if errorlevel 1 (
    echo ERROR: Odin compilation failed
    exit /b 1
)

REM ====== Fix ARM ABI Attributes ======
REM Odin's freestanding_arm32 hardcodes the hard-float ABI tag in the ELF.
REM The RP2040 toolchain uses soft float. Since our exported C functions pass
REM no floats, the code is compatible — only the metadata is wrong.
REM Strip the .ARM.attributes section so the linker won't reject the mismatch.
if /i "%TARGET%"=="rp2040" (
    echo Patching ELF attributes for soft-float ABI...
    arm-none-eabi-objcopy --remove-section=.ARM.attributes build\ogui_ui.o build\ogui_ui.o
    if errorlevel 1 (
        echo ERROR: Failed to patch ELF attributes
        exit /b 1
    )
)

REM ====== Compile C Stubs ======
echo Compiling runtime stubs...
arm-none-eabi-gcc -mcpu=%ODIN_MICROARCH% -mthumb -c stubs.c -o build\stubs.o
if errorlevel 1 (
    echo ERROR: Failed to compile stubs
    exit /b 1
)

REM ====== Create Static Library ======
echo Creating static library...
arm-none-eabi-ar rcs build\libogui.a build\ogui_ui.o build\stubs.o
if errorlevel 1 (
    echo ERROR: Failed to create static library
    exit /b 1
)

echo.
echo === Build Complete (%DISPLAY_NAME%) ===
if exist "build\libogui.a" (
    for %%f in (build\libogui.a) do echo Library size: %%~zf bytes
)

echo.
echo Next steps:
echo   1. Copy build\libogui.a to your Arduino project's library path
echo   2. Add linker flags: -L. -logui
echo   3. Compile and upload the .ino sketch
echo.
