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

make NOBULLSEYE=1 NOBUSTER=1 SONIC_BUILD_JOBS=8 PLATFORM=nvidia-bluefield PLATFORM_ARCH=arm64 SONIC_CONFIG_MAKE_JOBS=16 configure

END_CONFIGURE=$(date +%s)
CONFIGURE_DURATION=$((END_CONFIGURE - START_CONFIGURE))

log "Configure completed in ${CONFIGURE_DURATION}s ($(date -ud @${CONFIGURE_DURATION} +%H:%M:%S))"

log "Starting build step"
START_BUILD=$(date +%s)

make NOBULLSEYE=1 NOBUSTER=1 SONIC_BUILD_JOBS=8 SONIC_CONFIG_MAKE_JOBS=16 \
    SONIC_DPKG_CACHE_METHOD=cache \
    target/sonic-nvidia-bluefield.bfb

END_BUILD=$(date +%s)
BUILD_DURATION=$((END_BUILD - START_BUILD))

log "Build bfb completed in ${BUILD_DURATION}s ($(date -ud @${BUILD_DURATION} +%H:%M:%S))"

log "Starting build bin step"
START_BUILD_BIN=$(date +%s)

make NOBULLSEYE=1 NOBUSTER=1 SONIC_BUILD_JOBS=8 SONIC_CONFIG_MAKE_JOBS=16 \
    SONIC_DPKG_CACHE_METHOD=cache \
    target/sonic-nvidia-bluefield.bin

END_BUILD_BIN=$(date +%s)
BUILD_BIN_DURATION=$((END_BUILD_BIN - START_BUILD_BIN))

log "Build bin completed in ${BUILD_BIN_DURATION}s ($(date -ud @${BUILD_BIN_DURATION} +%H:%M:%S))"

CERT_DIR="/auto/sw_system_project/sx_mlnx_os/mlnx_Secure_Boot/development/sonic_nvos_dev"
SIGNING_KEY="${CERT_DIR}/nv_sonic_key.pem"
SIGNING_CERT="${CERT_DIR}/nv_sonic_key_certificate.pem"

log "Removing unsigned bfb and bin before signed builds"
rm -f target/sonic-nvidia-bluefield.bfb
rm -f target/sonic-nvidia-bluefield.bin

log "Starting signed bfb build step"
START_SIGNED_BFB=$(date +%s)

make NOBULLSEYE=1 NOBUSTER=1 SONIC_BUILD_JOBS=8 SONIC_CONFIG_MAKE_JOBS=16 \
    SONIC_DPKG_CACHE_METHOD=cache \
    SECURE_UPGRADE_MODE="dev" \
    SECURE_UPGRADE_DEV_SIGNING_KEY="$SIGNING_KEY" \
    SECURE_UPGRADE_SIGNING_CERT="$SIGNING_CERT" \
    target/sonic-nvidia-bluefield.bfb

END_SIGNED_BFB=$(date +%s)
SIGNED_BFB_DURATION=$((END_SIGNED_BFB - START_SIGNED_BFB))

log "Signed bfb completed in ${SIGNED_BFB_DURATION}s ($(date -ud @${SIGNED_BFB_DURATION} +%H:%M:%S))"

log "Starting signed bin build step"
START_SIGNED_BIN=$(date +%s)

make NOBULLSEYE=1 NOBUSTER=1 SONIC_BUILD_JOBS=8 SONIC_CONFIG_MAKE_JOBS=16 \
    SONIC_DPKG_CACHE_METHOD=cache \
    SECURE_UPGRADE_MODE="dev" \
    SECURE_UPGRADE_DEV_SIGNING_KEY="$SIGNING_KEY" \
    SECURE_UPGRADE_SIGNING_CERT="$SIGNING_CERT" \
    target/sonic-nvidia-bluefield.bin

END_SIGNED_BIN=$(date +%s)
SIGNED_BIN_DURATION=$((END_SIGNED_BIN - START_SIGNED_BIN))

log "Signed bin completed in ${SIGNED_BIN_DURATION}s ($(date -ud @${SIGNED_BIN_DURATION} +%H:%M:%S))"

echo ""
echo "========================================" | tee -a build_timing.log
echo "SUMMARY" | tee -a build_timing.log
echo "========================================" | tee -a build_timing.log
echo "Configure   : ${CONFIGURE_DURATION}s ($(date -ud @${CONFIGURE_DURATION} +%H:%M:%S))" | tee -a build_timing.log
echo "Build bfb   : ${BUILD_DURATION}s ($(date -ud @${BUILD_DURATION} +%H:%M:%S))" | tee -a build_timing.log
echo "Build bin   : ${BUILD_BIN_DURATION}s ($(date -ud @${BUILD_BIN_DURATION} +%H:%M:%S))" | tee -a build_timing.log
echo "Signed bfb  : ${SIGNED_BFB_DURATION}s ($(date -ud @${SIGNED_BFB_DURATION} +%H:%M:%S))" | tee -a build_timing.log
echo "Signed bin  : ${SIGNED_BIN_DURATION}s ($(date -ud @${SIGNED_BIN_DURATION} +%H:%M:%S))" | tee -a build_timing.log
TOTAL=$((CONFIGURE_DURATION + BUILD_DURATION + BUILD_BIN_DURATION + SIGNED_BFB_DURATION + SIGNED_BIN_DURATION))
echo "Total       : ${TOTAL}s ($(date -ud @${TOTAL} +%H:%M:%S))" | tee -a build_timing.log
echo "========================================" | tee -a build_timing.log
