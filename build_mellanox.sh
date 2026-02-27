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

log "Starting unsigned build step"
START_BUILD=$(date +%s)

make NOBULLSEYE=1 NOBUSTER=1 SONIC_BUILD_JOBS=8 SONIC_CONFIG_MAKE_JOBS=16 \
    SONIC_DPKG_CACHE_METHOD=cache \
    target/sonic-mellanox.bin

END_BUILD=$(date +%s)
BUILD_DURATION=$((END_BUILD - START_BUILD))

log "Unsigned build completed in ${BUILD_DURATION}s ($(date -ud @${BUILD_DURATION} +%H:%M:%S))"

log "Cleaning unsigned artifacts before signed build"
rm -f target/sonic-mellanox.bin
rm -f target/debs/trixie/linux-image-*-unsigned_*.deb
rm -f target/debs/trixie/linux-headers-*.deb
rm -f target/debs/trixie/linux-kbuild-*.deb
rm -f target/sonic-mellanox.bin__mellanox__rfs.squashfs

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

echo ""
echo "========================================" | tee -a build_timing.log
echo "SUMMARY" | tee -a build_timing.log
echo "========================================" | tee -a build_timing.log
echo "Configure    : ${CONFIGURE_DURATION}s ($(date -ud @${CONFIGURE_DURATION} +%H:%M:%S))" | tee -a build_timing.log
echo "Unsigned bin : ${BUILD_DURATION}s ($(date -ud @${BUILD_DURATION} +%H:%M:%S))" | tee -a build_timing.log
echo "Signed bin   : ${SIGNED_DURATION}s ($(date -ud @${SIGNED_DURATION} +%H:%M:%S))" | tee -a build_timing.log
TOTAL=$((CONFIGURE_DURATION + BUILD_DURATION + SIGNED_DURATION))
echo "Total        : ${TOTAL}s ($(date -ud @${TOTAL} +%H:%M:%S))" | tee -a build_timing.log
echo "========================================" | tee -a build_timing.log
