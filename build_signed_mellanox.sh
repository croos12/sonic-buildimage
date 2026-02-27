#!/bin/bash

set -e

log() {
    echo "========================================" | tee -a build_timing.log
    echo "$1" | tee -a build_timing.log
    echo "========================================" | tee -a build_timing.log
}

> build_timing.log

CERT_DIR="/auto/sw_system_project/sx_mlnx_os/mlnx_Secure_Boot/development/sonic_nvos_dev"
SIGNING_KEY="${CERT_DIR}/nv_sonic_key.pem"
SIGNING_CERT="${CERT_DIR}/nv_sonic_key_certificate.pem"

log "Starting configure step"
START_CONFIGURE=$(date +%s)

make NOBULLSEYE=1 NOBUSTER=1 SONIC_BUILD_JOBS=8 PLATFORM=mellanox SONIC_CONFIG_MAKE_JOBS=16 configure

END_CONFIGURE=$(date +%s)
CONFIGURE_DURATION=$((END_CONFIGURE - START_CONFIGURE))

log "Configure completed in ${CONFIGURE_DURATION}s ($(date -ud @${CONFIGURE_DURATION} +%H:%M:%S))"

log "Starting signed build step"
START_SIGNED=$(date +%s)

make NOBULLSEYE=1 NOBUSTER=1 SONIC_BUILD_JOBS=8 SONIC_CONFIG_MAKE_JOBS=16 \
    SONIC_DPKG_CACHE_METHOD=cache \
    SECURE_UPGRADE_MODE="dev" \
    SECURE_UPGRADE_DEV_SIGNING_KEY="$SIGNING_KEY" \
    SECURE_UPGRADE_SIGNING_CERT="$SIGNING_CERT" \
    target/sonic-mellanox.bin

END_SIGNED=$(date +%s)
SIGNED_DURATION=$((END_SIGNED - START_SIGNED))

log "Signed build completed in ${SIGNED_DURATION}s ($(date -ud @${SIGNED_DURATION} +%H:%M:%S))"

log "Removing signed bin before RPC build"
rm -f target/sonic-mellanox.bin

log "Starting signed RPC build step"
START_RPC=$(date +%s)

make NOBULLSEYE=1 NOBUSTER=1 SONIC_BUILD_JOBS=8 SONIC_CONFIG_MAKE_JOBS=16 \
    SONIC_DPKG_CACHE_METHOD=cache \
    SECURE_UPGRADE_MODE="dev" \
    SECURE_UPGRADE_DEV_SIGNING_KEY="$SIGNING_KEY" \
    SECURE_UPGRADE_SIGNING_CERT="$SIGNING_CERT" \
    ENABLE_SYNCD_RPC=y \
    target/sonic-mellanox.bin

END_RPC=$(date +%s)
RPC_DURATION=$((END_RPC - START_RPC))

log "Signed RPC build completed in ${RPC_DURATION}s ($(date -ud @${RPC_DURATION} +%H:%M:%S))"

echo ""
echo "========================================" | tee -a build_timing.log
echo "SUMMARY" | tee -a build_timing.log
echo "========================================" | tee -a build_timing.log
echo "Configure    : ${CONFIGURE_DURATION}s ($(date -ud @${CONFIGURE_DURATION} +%H:%M:%S))" | tee -a build_timing.log
echo "Signed bin   : ${SIGNED_DURATION}s ($(date -ud @${SIGNED_DURATION} +%H:%M:%S))" | tee -a build_timing.log
echo "Signed RPC   : ${RPC_DURATION}s ($(date -ud @${RPC_DURATION} +%H:%M:%S))" | tee -a build_timing.log
TOTAL=$((CONFIGURE_DURATION + SIGNED_DURATION + RPC_DURATION))
echo "Total        : ${TOTAL}s ($(date -ud @${TOTAL} +%H:%M:%S))" | tee -a build_timing.log
echo "========================================" | tee -a build_timing.log
