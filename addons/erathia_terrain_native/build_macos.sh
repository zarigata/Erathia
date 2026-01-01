#!/bin/bash
echo "Building Erathia Terrain Native (macOS)..."

mkdir -p build
cd build

cmake -DCMAKE_BUILD_TYPE=Debug ..
cmake --build .

cmake -DCMAKE_BUILD_TYPE=Release ..
cmake --build .

cd ..
echo "Build complete! Binaries in bin/"
