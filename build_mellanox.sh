#!/bin/bash

set -eo pipefail

BUILD_LOG="mellanox_logs.txt"
COMMON_MAKE_OPTS="NOBULLSEYE=1 NOBUSTER=1 SONIC_BUILD_JOBS=8 SONIC_CONFIG_MAKE_JOBS=16"
CACHE_OPTS="SONIC_DPKG_CACHE_METHOD=cache SONIC_DPKG_CACHE_SOURCE=/builds2/croos/cache"

usage() {
    echo "Usage: $0 <steps>"
    echo ""
    echo "Steps are letters executed in the order given:"
    echo "  c  Configure"
    echo "  b  Unsigned bin build"
    echo "  r  RPC bin build"
    echo "  a  ASAN bin build"
    echo ""
    echo "Examples:"
    echo "  $0 cb      # Configure then build"
    echo "  $0 cbr     # Configure, build, RPC"
    echo "  $0 cbra    # Configure, build, RPC, ASAN"
    echo "  $0 a       # ASAN only (assumes already configured)"
    echo "  $0 br      # Build then RPC (assumes already configured)"
    exit 1
}

[[ $# -lt 1 ]] && usage

STEPS="$1"

if [[ "$STEPS" =~ [^cbra] ]]; then
    echo "Error: invalid step character in '$STEPS'"
    echo "Valid steps: c (configure), b (bin), r (rpc), a (asan)"
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

> "$BUILD_LOG"

for (( i=0; i<${#STEPS}; i++ )); do
    step="${STEPS:$i:1}"
    case "$step" in
        c)
            log "Starting configure step"
            START_CONFIGURE=$(date +%s)

            run_make "configure" \
                $COMMON_MAKE_OPTS PLATFORM=mellanox \
                configure

            END_CONFIGURE=$(date +%s)
            CONFIGURE_DURATION=$((END_CONFIGURE - START_CONFIGURE))
            log "Configure completed in ${CONFIGURE_DURATION}s ($(date -ud @${CONFIGURE_DURATION} +%H:%M:%S))"
            ;;

        b)
            log "Starting unsigned build step"
            START_BUILD=$(date +%s)

            run_make "unsigned bin" \
                $COMMON_MAKE_OPTS $CACHE_OPTS \
                target/sonic-mellanox.bin

            END_BUILD=$(date +%s)
            BUILD_DURATION=$((END_BUILD - START_BUILD))
            log "Unsigned build completed in ${BUILD_DURATION}s ($(date -ud @${BUILD_DURATION} +%H:%M:%S))"
            ;;

        r)
            log "Removing unsigned bin before RPC build"
            rm -f target/sonic-mellanox.bin

            log "Starting RPC build step"
            START_RPC=$(date +%s)

            run_make "RPC bin" \
                $COMMON_MAKE_OPTS $CACHE_OPTS \
                ENABLE_SYNCD_RPC=y \
                target/sonic-mellanox.bin

            END_RPC=$(date +%s)
            RPC_DURATION=$((END_RPC - START_RPC))
            log "RPC build completed in ${RPC_DURATION}s ($(date -ud @${RPC_DURATION} +%H:%M:%S))"
            ;;

        a)
            log "Removing bin before ASAN build"
            rm -f target/sonic-mellanox.bin

            log "Starting ASAN build step"
            START_ASAN=$(date +%s)

            run_make "ASAN bin" \
                $COMMON_MAKE_OPTS $CACHE_OPTS \
                ENABLE_ASAN=y \
                target/sonic-mellanox.bin

            END_ASAN=$(date +%s)
            ASAN_DURATION=$((END_ASAN - START_ASAN))
            log "ASAN build completed in ${ASAN_DURATION}s ($(date -ud @${ASAN_DURATION} +%H:%M:%S))"
            ;;
    esac
done

echo ""
echo "========================================" | tee -a "$BUILD_LOG"
echo "TIMING SUMMARY" | tee -a "$BUILD_LOG"
echo "========================================" | tee -a "$BUILD_LOG"
[[ -n "$CONFIGURE_DURATION" ]] && echo "Configure    : ${CONFIGURE_DURATION}s ($(date -ud @${CONFIGURE_DURATION} +%H:%M:%S))" | tee -a "$BUILD_LOG"
[[ -n "$BUILD_DURATION" ]]     && echo "Unsigned bin : ${BUILD_DURATION}s ($(date -ud @${BUILD_DURATION} +%H:%M:%S))" | tee -a "$BUILD_LOG"
[[ -n "$RPC_DURATION" ]]       && echo "RPC bin      : ${RPC_DURATION}s ($(date -ud @${RPC_DURATION} +%H:%M:%S))" | tee -a "$BUILD_LOG"
[[ -n "$ASAN_DURATION" ]]      && echo "ASAN bin     : ${ASAN_DURATION}s ($(date -ud @${ASAN_DURATION} +%H:%M:%S))" | tee -a "$BUILD_LOG"
TOTAL=$(( ${CONFIGURE_DURATION:-0} + ${BUILD_DURATION:-0} + ${RPC_DURATION:-0} + ${ASAN_DURATION:-0} ))
echo "Total        : ${TOTAL}s ($(date -ud @${TOTAL} +%H:%M:%S))" | tee -a "$BUILD_LOG"
echo "========================================" | tee -a "$BUILD_LOG"

echo ""
echo "CACHE SUMMARY" | tee -a "$BUILD_LOG"
echo "========================================" | tee -a "$BUILD_LOG"
find target -name '*.log' -exec grep -l 'CACHE::LOADED' {} + 2>/dev/null | xargs -n1 basename | sed 's/\.log$//' | sort -u | tee -a "$BUILD_LOG"
echo "Total cached: $(find target -name '*.log' -exec grep -l 'CACHE::LOADED' {} + 2>/dev/null | wc -l)" | tee -a "$BUILD_LOG"
echo "========================================" | tee -a "$BUILD_LOG"
