#!/bin/bash

set -eo pipefail

BUILD_LOG="bluefield_logs.txt"
COMMON_MAKE_OPTS="NOBULLSEYE=1 NOBUSTER=1 SONIC_BUILD_JOBS=8 SONIC_CONFIG_MAKE_JOBS=16"
CACHE_OPTS="SONIC_DPKG_CACHE_METHOD=cache SONIC_DPKG_CACHE_SOURCE=/builds2/croos/cache"

CERT_DIR="/auto/sw_system_project/sx_mlnx_os/mlnx_Secure_Boot/development/sonic_nvos_dev"
SIGNING_OPTS="SECURE_UPGRADE_MODE=dev SECURE_UPGRADE_DEV_SIGNING_KEY=${CERT_DIR}/nv_sonic_key.pem SECURE_UPGRADE_SIGNING_CERT=${CERT_DIR}/nv_sonic_key_certificate.pem"

usage() {
    echo "Usage: $0 <steps>"
    echo ""
    echo "Steps are letters executed in the order given:"
    echo "  c  Configure"
    echo "  b  BFB build"
    echo "  s  Signed BFB build (cleans kernel debs/cache first)"
    echo "  n  BIN build"
    echo ""
    echo "Examples:"
    echo "  $0 cb      # Configure then BFB"
    echo "  $0 cbn     # Configure, BFB, BIN"
    echo "  $0 cs      # Configure, signed BFB"
    echo "  $0 csn     # Configure, signed BFB, BIN"
    echo "  $0 b       # BFB only (assumes already configured)"
    exit 1
}

[[ $# -lt 1 ]] && usage

STEPS="$1"

if [[ "$STEPS" =~ [^cbsn] ]]; then
    echo "Error: invalid step character in '$STEPS'"
    echo "Valid steps: c (configure), b (bfb), s (signed bfb), n (bin)"
    exit 1
fi

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

clean_kernel_artifacts() {
    log "Cleaning kernel debs and cache entries for fresh signed build"

    local count=0
    for dir in target/debs/*/; do
        for f in "${dir}"linux-headers-* "${dir}"linux-image-* "${dir}"linux-kbuild-*; do
            [ -e "$f" ] && rm -f "$f" && count=$((count + 1))
        done
    done

    for f in target/cache/linux-headers-*.tgz target/cache/linux-image-*.tgz target/cache/linux-kbuild-*.tgz; do
        [ -e "$f" ] && rm -f "$f" && count=$((count + 1))
    done

    local cache_src="${SONIC_DPKG_CACHE_SOURCE:-/builds2/croos/cache}"
    for f in "${cache_src}"/linux-headers-*.tgz "${cache_src}"/linux-image-*.tgz "${cache_src}"/linux-kbuild-*.tgz; do
        [ -e "$f" ] && rm -f "$f" && count=$((count + 1))
    done

    echo "Removed $count kernel-related file(s)" | tee -a "$BUILD_LOG"
}

> "$BUILD_LOG"

for (( i=0; i<${#STEPS}; i++ )); do
    step="${STEPS:$i:1}"
    case "$step" in
        c)
            log "Starting configure step"
            START_CONFIGURE=$(date +%s)

            run_make "configure" \
                $COMMON_MAKE_OPTS \
                PLATFORM=nvidia-bluefield PLATFORM_ARCH=arm64 \
                configure

            END_CONFIGURE=$(date +%s)
            CONFIGURE_DURATION=$((END_CONFIGURE - START_CONFIGURE))
            log "Configure completed in ${CONFIGURE_DURATION}s ($(date -ud @${CONFIGURE_DURATION} +%H:%M:%S))"
            ;;

        b)
            log "Starting BFB build step"
            START_BFB=$(date +%s)

            run_make "bfb" \
                $COMMON_MAKE_OPTS $CACHE_OPTS \
                target/sonic-nvidia-bluefield.bfb

            END_BFB=$(date +%s)
            BFB_DURATION=$((END_BFB - START_BFB))
            log "BFB build completed in ${BFB_DURATION}s ($(date -ud @${BFB_DURATION} +%H:%M:%S))"
            ;;

        s)
            clean_kernel_artifacts

            log "Starting signed BFB build step"
            START_SIGNED=$(date +%s)

            run_make "signed bfb" \
                $COMMON_MAKE_OPTS $CACHE_OPTS \
                $SIGNING_OPTS \
                target/sonic-nvidia-bluefield.bfb

            END_SIGNED=$(date +%s)
            SIGNED_DURATION=$((END_SIGNED - START_SIGNED))
            log "Signed BFB build completed in ${SIGNED_DURATION}s ($(date -ud @${SIGNED_DURATION} +%H:%M:%S))"
            ;;

        n)
            log "Starting BIN build step"
            START_BIN=$(date +%s)

            run_make "bin" \
                $COMMON_MAKE_OPTS $CACHE_OPTS \
                target/sonic-nvidia-bluefield.bin

            END_BIN=$(date +%s)
            BIN_DURATION=$((END_BIN - START_BIN))
            log "BIN build completed in ${BIN_DURATION}s ($(date -ud @${BIN_DURATION} +%H:%M:%S))"
            ;;
    esac
done

echo ""
echo "========================================" | tee -a "$BUILD_LOG"
echo "TIMING SUMMARY" | tee -a "$BUILD_LOG"
echo "========================================" | tee -a "$BUILD_LOG"
[[ -n "$CONFIGURE_DURATION" ]] && echo "Configure    : ${CONFIGURE_DURATION}s ($(date -ud @${CONFIGURE_DURATION} +%H:%M:%S))" | tee -a "$BUILD_LOG"
[[ -n "$BFB_DURATION" ]]       && echo "BFB build    : ${BFB_DURATION}s ($(date -ud @${BFB_DURATION} +%H:%M:%S))" | tee -a "$BUILD_LOG"
[[ -n "$SIGNED_DURATION" ]]    && echo "Signed BFB   : ${SIGNED_DURATION}s ($(date -ud @${SIGNED_DURATION} +%H:%M:%S))" | tee -a "$BUILD_LOG"
[[ -n "$BIN_DURATION" ]]       && echo "BIN build    : ${BIN_DURATION}s ($(date -ud @${BIN_DURATION} +%H:%M:%S))" | tee -a "$BUILD_LOG"
TOTAL=$(( ${CONFIGURE_DURATION:-0} + ${BFB_DURATION:-0} + ${SIGNED_DURATION:-0} + ${BIN_DURATION:-0} ))
echo "Total        : ${TOTAL}s ($(date -ud @${TOTAL} +%H:%M:%S))" | tee -a "$BUILD_LOG"
echo "========================================" | tee -a "$BUILD_LOG"

echo ""
echo "CACHE SUMMARY" | tee -a "$BUILD_LOG"
echo "========================================" | tee -a "$BUILD_LOG"
find target -name '*.log' -exec grep -l 'CACHE::LOADED' {} + 2>/dev/null | xargs -n1 basename | sed 's/\.log$//' | sort -u | tee -a "$BUILD_LOG"
echo "Total cached: $(find target -name '*.log' -exec grep -l 'CACHE::LOADED' {} + 2>/dev/null | wc -l)" | tee -a "$BUILD_LOG"
echo "========================================" | tee -a "$BUILD_LOG"
