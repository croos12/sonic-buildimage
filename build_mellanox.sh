#!/bin/bash

set -eo pipefail

BUILD_LOG="mellanox_logs.txt"
COMMON_MAKE_OPTS="NOBULLSEYE=1 NOBUSTER=1 SONIC_BUILD_JOBS=8 SONIC_CONFIG_MAKE_JOBS=16"
CACHE_OPTS="SONIC_DPKG_CACHE_METHOD=cache SONIC_DPKG_CACHE_SOURCE=/builds2/croos/cache"

CERT_DIR="/auto/sw_system_project/sx_mlnx_os/mlnx_Secure_Boot/development/sonic_nvos_dev"
SIGNING_OPTS="SECURE_UPGRADE_MODE=dev SECURE_UPGRADE_DEV_SIGNING_KEY=${CERT_DIR}/nv_sonic_key.pem SECURE_UPGRADE_SIGNING_CERT=${CERT_DIR}/nv_sonic_key_certificate.pem"

usage() {
    echo "Usage: $0 <steps>"
    echo ""
    echo "Steps are letters executed in the order given:"
    echo "  c  Configure"
    echo "  b  Unsigned bin build"
    echo "  s  Signed bin build (cleans kernel debs/cache first)"
    echo "  r  RPC bin build"
    echo "  a  ASAN bin build"
    echo ""
    echo "Examples:"
    echo "  $0 cb      # Configure then build"
    echo "  $0 cbr     # Configure, build, RPC"
    echo "  $0 cbra    # Configure, build, RPC, ASAN"
    echo "  $0 cs      # Configure, signed build"
    echo "  $0 csr     # Configure, signed build, RPC"
    echo "  $0 a       # ASAN only (assumes already configured)"
    echo "  $0 br      # Build then RPC (assumes already configured)"
    exit 1
}

[[ $# -lt 1 ]] && usage

STEPS="$1"

if [[ "$STEPS" =~ [^cbsra] ]]; then
    echo "Error: invalid step character in '$STEPS'"
    echo "Valid steps: c (configure), b (bin), s (signed bin), r (rpc), a (asan)"
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

clean_system_override_stamps() {
    local count=0
    for f in target/debs/bookworm/libnl-*-install; do
        [ -e "$f" ] && rm -f "$f" && count=$((count + 1))
    done
    if [ "$count" -gt 0 ]; then
        echo "Removed $count stale libnl install stamp(s)" | tee -a "$BUILD_LOG"
    fi
}

stamp_non_kernel_installs() {
    log "Creating install stamps for existing non-kernel packages"

    local ref_file count=0
    ref_file=$(find target/python-wheels -name "*.whl" -print -quit 2>/dev/null)

    if [ -n "$ref_file" ] && [ .platform -nt "$ref_file" ]; then
        touch -r "$ref_file" .platform
        echo "Reset .platform timestamp to match existing build artifacts" | tee -a "$BUILD_LOG"
    fi

    for f in target/debs/bookworm/*.deb; do
        [ -f "$f" ] || continue
        case "$(basename "$f")" in
            linux-headers-*|linux-image-*|linux-kbuild-*) continue ;;
            libnl-*) continue ;;
        esac
        touch -r "$f" "${f}-install"
        count=$((count + 1))
    done

    for f in target/python-wheels/bookworm/*.whl; do
        [ -f "$f" ] || continue
        touch -r "$f" "${f}-install"
        count=$((count + 1))
    done

    echo "Stamped $count install markers" | tee -a "$BUILD_LOG"
}

> "$BUILD_LOG"

for (( i=0; i<${#STEPS}; i++ )); do
    step="${STEPS:$i:1}"
    case "$step" in
        c)
            log "Starting configure step"
            START_CONFIGURE=$(date +%s)

            PLATFORM_REF=""
            if [ -f .platform ] && [ "$(cat .platform)" = "mellanox" ]; then
                PLATFORM_REF=$(mktemp)
                touch -r .platform "$PLATFORM_REF"
            fi

            run_make "configure" \
                $COMMON_MAKE_OPTS PLATFORM=mellanox \
                configure

            if [ -n "$PLATFORM_REF" ] && [ -f "$PLATFORM_REF" ]; then
                touch -r "$PLATFORM_REF" .platform
                rm -f "$PLATFORM_REF"
            fi

            END_CONFIGURE=$(date +%s)
            CONFIGURE_DURATION=$((END_CONFIGURE - START_CONFIGURE))
            log "Configure completed in ${CONFIGURE_DURATION}s ($(date -ud @${CONFIGURE_DURATION} +%H:%M:%S))"
            ;;

        b)
            clean_system_override_stamps
            log "Starting unsigned build step"
            START_BUILD=$(date +%s)

            run_make "unsigned bin" \
                $COMMON_MAKE_OPTS $CACHE_OPTS \
                target/sonic-mellanox.bin

            END_BUILD=$(date +%s)
            BUILD_DURATION=$((END_BUILD - START_BUILD))
            log "Unsigned build completed in ${BUILD_DURATION}s ($(date -ud @${BUILD_DURATION} +%H:%M:%S))"
            ;;

        s)
            clean_kernel_artifacts
            stamp_non_kernel_installs
            clean_system_override_stamps

            log "Removing bin before signed build"
            rm -f target/sonic-mellanox.bin

            log "Starting signed build step"
            START_SIGNED=$(date +%s)

            run_make "signed bin" \
                $COMMON_MAKE_OPTS $CACHE_OPTS \
                $SIGNING_OPTS \
                target/sonic-mellanox.bin

            END_SIGNED=$(date +%s)
            SIGNED_DURATION=$((END_SIGNED - START_SIGNED))
            log "Signed build completed in ${SIGNED_DURATION}s ($(date -ud @${SIGNED_DURATION} +%H:%M:%S))"
            ;;

        r)
            clean_system_override_stamps
            log "Removing bin before RPC build"
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
            clean_system_override_stamps
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
[[ -n "$SIGNED_DURATION" ]]    && echo "Signed bin   : ${SIGNED_DURATION}s ($(date -ud @${SIGNED_DURATION} +%H:%M:%S))" | tee -a "$BUILD_LOG"
[[ -n "$RPC_DURATION" ]]       && echo "RPC bin      : ${RPC_DURATION}s ($(date -ud @${RPC_DURATION} +%H:%M:%S))" | tee -a "$BUILD_LOG"
[[ -n "$ASAN_DURATION" ]]      && echo "ASAN bin     : ${ASAN_DURATION}s ($(date -ud @${ASAN_DURATION} +%H:%M:%S))" | tee -a "$BUILD_LOG"
TOTAL=$(( ${CONFIGURE_DURATION:-0} + ${BUILD_DURATION:-0} + ${SIGNED_DURATION:-0} + ${RPC_DURATION:-0} + ${ASAN_DURATION:-0} ))
echo "Total        : ${TOTAL}s ($(date -ud @${TOTAL} +%H:%M:%S))" | tee -a "$BUILD_LOG"
echo "========================================" | tee -a "$BUILD_LOG"

echo ""
echo "CACHE SUMMARY" | tee -a "$BUILD_LOG"
echo "========================================" | tee -a "$BUILD_LOG"
find target -name '*.log' -exec grep -l 'CACHE::LOADED' {} + 2>/dev/null | xargs -n1 basename | sed 's/\.log$//' | sort -u | tee -a "$BUILD_LOG"
echo "Total cached: $(find target -name '*.log' -exec grep -l 'CACHE::LOADED' {} + 2>/dev/null | wc -l)" | tee -a "$BUILD_LOG"
echo "========================================" | tee -a "$BUILD_LOG"
