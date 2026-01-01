@echo off
echo Building Erathia Terrain Native (Windows)...

if not exist "build" mkdir build
cd build

cmake -G "Visual Studio 17 2022" -A x64 ..
cmake --build . --config Debug
cmake --build . --config Release

cd ..
echo Build complete! Binaries in bin/
pause
