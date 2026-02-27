#!/bin/bash

set -eo pipefail

BUILD_LOG="bluefield_logs.txt"

log() {
    echo "========================================" | tee -a "$BUILD_LOG"
    echo "$1" | tee -a "$BUILD_LOG"
    echo "========================================" | tee -a "$BUILD_LOG"
}

run_make() {
    local label="$1"
    shift
    echo "" >> "$BUILD_LOG"
    echo "######## $label ########" >> "$BUILD_LOG"
    make "$@" 2>&1 | tee -a "$BUILD_LOG"
}

> "$BUILD_LOG"

log "Starting configure step"
START_CONFIGURE=$(date +%s)

run_make "configure" \
    NOBULLSEYE=1 NOBUSTER=1 SONIC_BUILD_JOBS=8 \
    PLATFORM=nvidia-bluefield PLATFORM_ARCH=arm64 SONIC_CONFIG_MAKE_JOBS=16 \
    configure

END_CONFIGURE=$(date +%s)
CONFIGURE_DURATION=$((END_CONFIGURE - START_CONFIGURE))

log "Configure completed in ${CONFIGURE_DURATION}s ($(date -ud @${CONFIGURE_DURATION} +%H:%M:%S))"

log "Starting build step"
START_BUILD=$(date +%s)

run_make "build bfb" \
    NOBULLSEYE=1 NOBUSTER=1 SONIC_BUILD_JOBS=8 SONIC_CONFIG_MAKE_JOBS=16 \
    SONIC_DPKG_CACHE_METHOD=cache \
    SONIC_DPKG_CACHE_SOURCE=/builds2/croos/cache \
    target/sonic-nvidia-bluefield.bfb

END_BUILD=$(date +%s)
BUILD_DURATION=$((END_BUILD - START_BUILD))

log "Build bfb completed in ${BUILD_DURATION}s ($(date -ud @${BUILD_DURATION} +%H:%M:%S))"

log "Starting build bin step"
START_BUILD_BIN=$(date +%s)

run_make "build bin" \
    NOBULLSEYE=1 NOBUSTER=1 SONIC_BUILD_JOBS=8 SONIC_CONFIG_MAKE_JOBS=16 \
    SONIC_DPKG_CACHE_METHOD=cache \
    SONIC_DPKG_CACHE_SOURCE=/builds2/croos/cache \
    target/sonic-nvidia-bluefield.bin

END_BUILD_BIN=$(date +%s)
BUILD_BIN_DURATION=$((END_BUILD_BIN - START_BUILD_BIN))

log "Build bin completed in ${BUILD_BIN_DURATION}s ($(date -ud @${BUILD_BIN_DURATION} +%H:%M:%S))"

echo ""
echo "========================================" | tee -a "$BUILD_LOG"
echo "TIMING SUMMARY" | tee -a "$BUILD_LOG"
echo "========================================" | tee -a "$BUILD_LOG"
echo "Configure   : ${CONFIGURE_DURATION:-0}s ($(date -ud @${CONFIGURE_DURATION:-0} +%H:%M:%S))" | tee -a "$BUILD_LOG"
echo "Build bfb   : ${BUILD_DURATION:-0}s ($(date -ud @${BUILD_DURATION:-0} +%H:%M:%S))" | tee -a "$BUILD_LOG"
echo "Build bin   : ${BUILD_BIN_DURATION:-0}s ($(date -ud @${BUILD_BIN_DURATION:-0} +%H:%M:%S))" | tee -a "$BUILD_LOG"
TOTAL=$(( ${CONFIGURE_DURATION:-0} + ${BUILD_DURATION:-0} + ${BUILD_BIN_DURATION:-0} ))
echo "Total       : ${TOTAL}s ($(date -ud @${TOTAL} +%H:%M:%S))" | tee -a "$BUILD_LOG"
echo "========================================" | tee -a "$BUILD_LOG"

echo ""
echo "CACHE SUMMARY" | tee -a "$BUILD_LOG"
echo "========================================" | tee -a "$BUILD_LOG"
find target -name '*.log' -exec grep -l 'CACHE::LOADED' {} + 2>/dev/null | xargs -n1 basename | sed 's/\.log$//' | sort -u | tee -a "$BUILD_LOG"
echo "Total cached: $(find target -name '*.log' -exec grep -l 'CACHE::LOADED' {} + 2>/dev/null | wc -l)" | tee -a "$BUILD_LOG"
echo "========================================" | tee -a "$BUILD_LOG"
