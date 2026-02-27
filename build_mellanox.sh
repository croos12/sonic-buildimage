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
collect_cache_status "unsigned bin"

echo ""
echo "========================================" | tee -a "$TIMING_LOG"
echo "TIMING SUMMARY" | tee -a "$TIMING_LOG"
echo "========================================" | tee -a "$TIMING_LOG"
echo "Configure    : ${CONFIGURE_DURATION}s ($(date -ud @${CONFIGURE_DURATION} +%H:%M:%S))" | tee -a "$TIMING_LOG"
echo "Unsigned bin : ${BUILD_DURATION}s ($(date -ud @${BUILD_DURATION} +%H:%M:%S))" | tee -a "$TIMING_LOG"
TOTAL=$((CONFIGURE_DURATION + BUILD_DURATION))
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
