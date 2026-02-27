#!/bin/bash

set -e

TIMING_LOG="build_timing.log"
BUILD_LOG="mellanox_logs.txt"

log() {
    echo "========================================" | tee -a "$TIMING_LOG"
    echo "$1" | tee -a "$TIMING_LOG"
    echo "========================================" | tee -a "$TIMING_LOG"
}

run_make() {
    local label="$1"
    shift
    echo "" >> "$BUILD_LOG"
    echo "######## $label ########" >> "$BUILD_LOG"
    make "$@" 2>&1 | tee -a "$BUILD_LOG"
    return "${PIPESTATUS[0]}"
}

collect_cache_status() {
    local label="$1"
    echo "" >> "$BUILD_LOG"
    echo "######## CACHE STATUS after: $label ########" >> "$BUILD_LOG"

    local loaded=0 skipped=0 saved=0
    local loaded_list="" skipped_list=""

    while IFS= read -r logfile; do
        local base
        base=$(basename "$logfile" .log)
        if grep -q '\[ CACHE::LOADED \]' "$logfile" 2>/dev/null; then
            loaded=$((loaded + 1))
            loaded_list+="  $base"$'\n'
        fi
        if grep -q '\[ CACHE::SKIPPED \]' "$logfile" 2>/dev/null; then
            skipped=$((skipped + 1))
            skipped_list+="  $base"$'\n'
        fi
        if grep -q '\[ CACHE::SAVED \]' "$logfile" 2>/dev/null; then
            saved=$((saved + 1))
        fi
    done < <(find target -name '*.log' -newer "$TIMING_LOG" 2>/dev/null)

    {
        echo "  Cached (LOADED) : $loaded"
        echo "  Built  (SKIPPED): $skipped"
        echo "  Saved to cache  : $saved"
        if [ -n "$loaded_list" ]; then
            echo "  --- Cached packages ---"
            echo "$loaded_list"
        fi
        if [ -n "$skipped_list" ]; then
            echo "  --- Built packages ---"
            echo "$skipped_list"
        fi
    } | tee -a "$BUILD_LOG" | tee -a "$TIMING_LOG"
}

> "$TIMING_LOG"
> "$BUILD_LOG"

CERT_DIR="/auto/sw_system_project/sx_mlnx_os/mlnx_Secure_Boot/development/sonic_nvos_dev"
SIGNING_KEY="${CERT_DIR}/nv_sonic_key.pem"
SIGNING_CERT="${CERT_DIR}/nv_sonic_key_certificate.pem"

log "Starting configure step"
START_CONFIGURE=$(date +%s)

run_make "configure" \
    NOBULLSEYE=1 NOBUSTER=1 SONIC_BUILD_JOBS=8 PLATFORM=mellanox SONIC_CONFIG_MAKE_JOBS=16 \
    configure

END_CONFIGURE=$(date +%s)
CONFIGURE_DURATION=$((END_CONFIGURE - START_CONFIGURE))

log "Configure completed in ${CONFIGURE_DURATION}s ($(date -ud @${CONFIGURE_DURATION} +%H:%M:%S))"

log "Starting signed build step"
START_SIGNED=$(date +%s)

run_make "signed bin" \
    NOBULLSEYE=1 NOBUSTER=1 SONIC_BUILD_JOBS=8 SONIC_CONFIG_MAKE_JOBS=16 \
    SONIC_DPKG_CACHE_METHOD=cache \
    SECURE_UPGRADE_MODE="dev" \
    SECURE_UPGRADE_DEV_SIGNING_KEY="$SIGNING_KEY" \
    SECURE_UPGRADE_SIGNING_CERT="$SIGNING_CERT" \
    target/sonic-mellanox.bin

END_SIGNED=$(date +%s)
SIGNED_DURATION=$((END_SIGNED - START_SIGNED))

log "Signed build completed in ${SIGNED_DURATION}s ($(date -ud @${SIGNED_DURATION} +%H:%M:%S))"
collect_cache_status "signed bin"

log "Removing signed bin before RPC build"
rm -f target/sonic-mellanox.bin

log "Starting signed RPC build step"
START_RPC=$(date +%s)

run_make "signed RPC bin" \
    NOBULLSEYE=1 NOBUSTER=1 SONIC_BUILD_JOBS=8 SONIC_CONFIG_MAKE_JOBS=16 \
    SONIC_DPKG_CACHE_METHOD=cache \
    SECURE_UPGRADE_MODE="dev" \
    SECURE_UPGRADE_DEV_SIGNING_KEY="$SIGNING_KEY" \
    SECURE_UPGRADE_SIGNING_CERT="$SIGNING_CERT" \
    ENABLE_SYNCD_RPC=y \
    target/sonic-mellanox.bin

END_RPC=$(date +%s)
RPC_DURATION=$((END_RPC - START_RPC))

log "Signed RPC build completed in ${RPC_DURATION}s ($(date -ud @${RPC_DURATION} +%H:%M:%S))"
collect_cache_status "signed RPC bin"

echo ""
echo "========================================" | tee -a "$TIMING_LOG"
echo "TIMING SUMMARY" | tee -a "$TIMING_LOG"
echo "========================================" | tee -a "$TIMING_LOG"
echo "Configure    : ${CONFIGURE_DURATION}s ($(date -ud @${CONFIGURE_DURATION} +%H:%M:%S))" | tee -a "$TIMING_LOG"
echo "Signed bin   : ${SIGNED_DURATION}s ($(date -ud @${SIGNED_DURATION} +%H:%M:%S))" | tee -a "$TIMING_LOG"
echo "Signed RPC   : ${RPC_DURATION}s ($(date -ud @${RPC_DURATION} +%H:%M:%S))" | tee -a "$TIMING_LOG"
TOTAL=$((CONFIGURE_DURATION + SIGNED_DURATION + RPC_DURATION))
echo "Total        : ${TOTAL}s ($(date -ud @${TOTAL} +%H:%M:%S))" | tee -a "$TIMING_LOG"
echo "========================================" | tee -a "$TIMING_LOG"

echo ""
echo "========================================" | tee -a "$TIMING_LOG"
echo "OVERALL CACHE SUMMARY" | tee -a "$TIMING_LOG"
echo "========================================" | tee -a "$TIMING_LOG"

total_loaded=0
total_skipped=0
total_saved=0
all_loaded=""
all_skipped=""

while IFS= read -r logfile; do
    base=$(basename "$logfile" .log)
    if grep -q '\[ CACHE::LOADED \]' "$logfile" 2>/dev/null; then
        total_loaded=$((total_loaded + 1))
        all_loaded+="  $base"$'\n'
    fi
    if grep -q '\[ CACHE::SKIPPED \]' "$logfile" 2>/dev/null; then
        total_skipped=$((total_skipped + 1))
        all_skipped+="  $base"$'\n'
    fi
    if grep -q '\[ CACHE::SAVED \]' "$logfile" 2>/dev/null; then
        total_saved=$((total_saved + 1))
    fi
done < <(find target -name '*.log' 2>/dev/null)

{
    echo "Packages loaded from cache : $total_loaded"
    echo "Packages built from source : $total_skipped"
    echo "Packages saved to cache    : $total_saved"
    if [ -n "$all_loaded" ]; then
        echo ""
        echo "--- Cached packages ---"
        echo "$all_loaded"
    fi
    if [ -n "$all_skipped" ]; then
        echo ""
        echo "--- Built packages ---"
        echo "$all_skipped"
    fi
} | tee -a "$TIMING_LOG" | tee -a "$BUILD_LOG"

echo "========================================" | tee -a "$TIMING_LOG"
echo ""
echo "Full build log: $BUILD_LOG"
echo "Timing + cache summary: $TIMING_LOG"
