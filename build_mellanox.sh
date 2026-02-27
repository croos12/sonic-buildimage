#!/bin/bash

set -e

log() {
    echo "========================================" | tee -a build_timing.log
    echo "$1" | tee -a build_timing.log
    echo "========================================" | tee -a build_timing.log
}

> build_timing.log

log "Starting configure step"
START_CONFIGURE=$(date +%s)

make NOBULLSEYE=1 NOBUSTER=1 SONIC_BUILD_JOBS=8 PLATFORM=mellanox SONIC_CONFIG_MAKE_JOBS=16 configure

END_CONFIGURE=$(date +%s)
CONFIGURE_DURATION=$((END_CONFIGURE - START_CONFIGURE))

log "Configure completed in ${CONFIGURE_DURATION}s ($(date -ud @${CONFIGURE_DURATION} +%H:%M:%S))"

log "Starting unsigned build step"
START_BUILD=$(date +%s)

make NOBULLSEYE=1 NOBUSTER=1 SONIC_BUILD_JOBS=8 SONIC_CONFIG_MAKE_JOBS=16 \
    SONIC_DPKG_CACHE_METHOD=cache \
    target/sonic-mellanox.bin

END_BUILD=$(date +%s)
BUILD_DURATION=$((END_BUILD - START_BUILD))

log "Unsigned build completed in ${BUILD_DURATION}s ($(date -ud @${BUILD_DURATION} +%H:%M:%S))"

echo ""
echo "========================================" | tee -a build_timing.log
echo "SUMMARY" | tee -a build_timing.log
echo "========================================" | tee -a build_timing.log
echo "Configure    : ${CONFIGURE_DURATION}s ($(date -ud @${CONFIGURE_DURATION} +%H:%M:%S))" | tee -a build_timing.log
echo "Unsigned bin : ${BUILD_DURATION}s ($(date -ud @${BUILD_DURATION} +%H:%M:%S))" | tee -a build_timing.log
TOTAL=$((CONFIGURE_DURATION + BUILD_DURATION))
echo "Total        : ${TOTAL}s ($(date -ud @${TOTAL} +%H:%M:%S))" | tee -a build_timing.log
echo "========================================" | tee -a build_timing.log
