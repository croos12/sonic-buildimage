#!/bin/bash

set -eo pipefail

BUILD_LOG="mellanox_logs.txt"

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
    NOBULLSEYE=1 NOBUSTER=1 SONIC_BUILD_JOBS=8 PLATFORM=mellanox SONIC_CONFIG_MAKE_JOBS=16 \
    configure

END_CONFIGURE=$(date +%s)
CONFIGURE_DURATION=$((END_CONFIGURE - START_CONFIGURE))

log "Configure completed in ${CONFIGURE_DURATION}s ($(date -ud @${CONFIGURE_DURATION} +%H:%M:%S))"

log "Starting unsigned build step"
START_BUILD=$(date +%s)

run_make "unsigned bin" \
    NOBULLSEYE=1 NOBUSTER=1 SONIC_BUILD_JOBS=8 SONIC_CONFIG_MAKE_JOBS=16 \
    SONIC_DPKG_CACHE_METHOD=cache \
    target/sonic-mellanox.bin

END_BUILD=$(date +%s)
BUILD_DURATION=$((END_BUILD - START_BUILD))

log "Unsigned build completed in ${BUILD_DURATION}s ($(date -ud @${BUILD_DURATION} +%H:%M:%S))"

log "Removing unsigned bin before RPC build"
rm -f target/sonic-mellanox.bin

log "Starting RPC build step"
START_RPC=$(date +%s)

run_make "RPC bin" \
    NOBULLSEYE=1 NOBUSTER=1 SONIC_BUILD_JOBS=8 SONIC_CONFIG_MAKE_JOBS=16 \
    SONIC_DPKG_CACHE_METHOD=cache \
    ENABLE_SYNCD_RPC=y \
    target/sonic-mellanox.bin

END_RPC=$(date +%s)
RPC_DURATION=$((END_RPC - START_RPC))

log "RPC build completed in ${RPC_DURATION}s ($(date -ud @${RPC_DURATION} +%H:%M:%S))"

echo ""
echo "========================================" | tee -a "$BUILD_LOG"
echo "TIMING SUMMARY" | tee -a "$BUILD_LOG"
echo "========================================" | tee -a "$BUILD_LOG"
echo "Configure    : ${CONFIGURE_DURATION:-0}s ($(date -ud @${CONFIGURE_DURATION:-0} +%H:%M:%S))" | tee -a "$BUILD_LOG"
echo "Unsigned bin : ${BUILD_DURATION:-0}s ($(date -ud @${BUILD_DURATION:-0} +%H:%M:%S))" | tee -a "$BUILD_LOG"
echo "RPC bin      : ${RPC_DURATION:-0}s ($(date -ud @${RPC_DURATION:-0} +%H:%M:%S))" | tee -a "$BUILD_LOG"
TOTAL=$(( ${CONFIGURE_DURATION:-0} + ${BUILD_DURATION:-0} + ${RPC_DURATION:-0} ))
echo "Total        : ${TOTAL}s ($(date -ud @${TOTAL} +%H:%M:%S))" | tee -a "$BUILD_LOG"
echo "========================================" | tee -a "$BUILD_LOG"

echo ""
echo "CACHE SUMMARY" | tee -a "$BUILD_LOG"
echo "========================================" | tee -a "$BUILD_LOG"
find target -name '*.log' -exec grep -l 'CACHE::LOADED' {} + 2>/dev/null | xargs -n1 basename | sed 's/\.log$//' | sort -u | tee -a "$BUILD_LOG"
echo "Total cached: $(find target -name '*.log' -exec grep -l 'CACHE::LOADED' {} + 2>/dev/null | wc -l)" | tee -a "$BUILD_LOG"
echo "========================================" | tee -a "$BUILD_LOG"
