#!/bin/bash

# A script to automate the build process for the MediaRemoteAdapter framework.

# Exit immediately if a command exits with a non-zero status.
set -e

# --- Configuration ---
BUILD_DIR="build"
# Get the directory where the script is located, which is the project root.
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

# --- Functions ---

# Function to print usage instructions
usage() {
    echo "Usage: $0 [clean|build]"
    echo "  build (default): Configures and compiles the framework."
    echo "  clean: Removes the build directory to start fresh."
    exit 1
}

# Function to remove the build directory
clean() {
    echo "🧹 Cleaning build directory..."
    if [ -d "$PROJECT_ROOT/$BUILD_DIR" ]; then
        rm -rf "$PROJECT_ROOT/$BUILD_DIR"
        echo "Build directory '$BUILD_DIR' removed."
    else
        echo "Build directory '$BUILD_DIR' does not exist. Nothing to clean."
    fi
}

# Function to build the project using CMake
build() {
    echo "🚀 Starting build process..."

    # Create build directory if it doesn't exist
    mkdir -p "$PROJECT_ROOT/$BUILD_DIR"

    # Navigate into the build directory
    cd "$PROJECT_ROOT/$BUILD_DIR"

    # Run CMake to configure the project
    echo "⚙️  Configuring with CMake..."
    cmake ..

    # Run the build
    echo "🛠️  Building with CMake..."
    cmake --build .

    # Navigate back to the project root
    cd "$PROJECT_ROOT"

    # Get the absolute path to the built framework
    FRAMEWORK_PATH=$(realpath "$PROJECT_ROOT/$BUILD_DIR/src/MediaRemoteAdapter.framework")

    echo ""
    echo "✅ Build successful!"
    echo "   MediaRemoteAdapter.framework is located at: $FRAMEWORK_PATH"
}

# --- Main Script Logic ---

# If no arguments are provided, the default action is 'build'
ACTION=${1:-build}

case "$ACTION" in
    build)
        build
        ;;
    clean)
        clean
        ;;
    *)
        echo "Error: Invalid command '$ACTION'"
        usage
        ;;
esac

exit 0 