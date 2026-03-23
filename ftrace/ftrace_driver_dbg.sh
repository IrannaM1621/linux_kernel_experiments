#!/bin/bash
# ==============================================================================
#  ftrace_driver_debug.sh
#  Author : Iranna Mundaganur
#  GitHub : https://github.com/irannam  (update with your actual handle)
#
#  Linux kernel driver function tracer — powered by ftrace.
#
#  Automatically traces every function call inside a loaded kernel driver.
#  Does NOT load or unload the module. Safe to run on a live system.
#
# ------------------------------------------------------------------------------
#  WHY THIS SCRIPT EXISTS
#
#  The manual ftrace workflow has a dangerous footgun:
#    If you forget set_ftrace_filter, ftrace captures EVERY kernel function.
#    That is millions of events per second — your log is unreadable and your
#    system degrades. This script always sets the filter to your driver only.
#
# ------------------------------------------------------------------------------
#  USAGE
#
#
# ------------------------------------------------------------------------------
#  USAGE
#
#    sudo ./ftrace_driver_debug.sh <driver> [duration_seconds] [tracer]
#
#  <driver> — any of these forms:
#    my_driver                              bare module name
#    my_driver.ko                           .ko filename
#    /home/user/build/my_driver.ko          full path to .ko
#
#  duration_seconds
#    0   → MANUAL mode: tracing runs until you press Enter  ← NEW
#    N   → TIMED mode: stops automatically after N seconds
#    (default = 0, manual mode)
#
#  EXAMPLES
#    sudo ./ftrace_driver_debug.sh my_driver          # manual stop
#    sudo ./ftrace_driver_debug.sh my_driver 0        # manual stop (explicit)
#    sudo ./ftrace_driver_debug.sh my_driver 30       # auto-stop after 30s
#    sudo ./ftrace_driver_debug.sh /path/to/my_driver.ko 0 function_graph
#
#  TRACERS
#    function_graph  call graph with entry/exit timestamps + duration (default)
#    function        flat list of every function call with CPU + timestamp
#
# ------------------------------------------------------------------------------
#  COLLECTION MODES
#
#  MANUAL (duration=0)  — recommended for interactive debugging
#    - Tracing runs indefinitely
#    - Live elapsed timer + event count shown every 5 seconds
#    - Press Enter when you have captured enough
#    - Useful when you don't know how long the operation will take
#
#  TIMED (duration=N)
#    - Tracing runs for exactly N seconds then stops automatically
#    - Event count shown every 5 seconds during countdown
#    - Useful for scripted / CI / automated captures
#
# ------------------------------------------------------------------------------
#  IMPORTANT — WHAT CAN AND CANNOT BE CAPTURED
#
#  CAN capture:
#    - Any driver function called AFTER the script starts tracing
#    - Background kernel threads / interrupt handlers in the driver
#    - Any operation triggered from userspace during the window
#
#  CANNOT capture:
#    - Anything that happened BEFORE the script started
#    - ftrace has no "record from boot" mode — the buffer only fills
#      while tracing_on=1
#    - For pre-script messages: check dmesg (the script saves it too)
#
# ------------------------------------------------------------------------------
#  OUTPUT
#    ./ftrace_logs/<driver>_YYYYMMDD_HHMMSS.log
#    Saved AFTER you stop tracing. Contains:
#      - All symbols traced, accepted filter, full trace output
#      - dmesg lines that appeared during the capture window only
#      - Buffer statistics per CPU
#
# ------------------------------------------------------------------------------
#  REQUIREMENTS
#    Kernel: CONFIG_FTRACE=y, CONFIG_KALLSYMS=y, CONFIG_DEBUG_FS=y
#    Access: root / sudo
#    Shell:  bash 4+
#    Driver: already loaded before running this script
#
# ------------------------------------------------------------------------------
#  SAFETY
#    trap cleanup EXIT — tracing is ALWAYS disabled on exit, Ctrl+C, or error.
#    The system is never left with ftrace running hot.
#
# ==============================================================================

set -euo pipefail

# ── Colours ($'...' ANSI C quoting — ESC bytes are real, not literal \033) ───
BOLD=$'\033[1m';  RST=$'\033[0m';   GRN=$'\033[1;32m'; YLW=$'\033[1;33m'
RED=$'\033[1;31m'; CYN=$'\033[0;36m'; BLU=$'\033[1;34m'; DIM=$'\033[2m'
MAG=$'\033[1;35m'; WHT=$'\033[1;37m'; UL=$'\033[4m'

# ── Input normalisation ───────────────────────────────────────────────────────
# Accept bare name, .ko filename, or full /path/to/driver.ko
RAW_INPUT="${1:-}"
DURATION="${2:-0}"      # 0 = run until user presses Enter  |  N = stop after N seconds
TRACER="${3:-function_graph}"
DRIVER_NAME="$(basename "${RAW_INPUT}" .ko)"

# Remember .ko path for nm/modinfo diagnostics if a file was provided
KO_PATH=""
if [[ "${RAW_INPUT}" == *.ko && -f "${RAW_INPUT}" ]]; then
    KO_PATH="${RAW_INPUT}"
elif [[ "${RAW_INPUT}" == *.ko && -f "$(pwd)/${RAW_INPUT}" ]]; then
    KO_PATH="$(pwd)/${RAW_INPUT}"
fi

# ── Paths ─────────────────────────────────────────────────────────────────────
DEBUGFS="/sys/kernel/debug"
TRACEFS="${DEBUGFS}/tracing"
LOG_DIR="$(pwd)/ftrace_logs"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
LOG_FILE="${LOG_DIR}/${DRIVER_NAME}_${TIMESTAMP}.log"
TRACE_FILE="${TRACEFS}/trace"

# ── Print helpers ─────────────────────────────────────────────────────────────
info()   { printf "  ${BLU}[INFO]${RST}  %s\n"  "$*"; }
ok()     { printf "  ${GRN}[ OK ]${RST}  %s\n"  "$*"; }
warn()   { printf "  ${YLW}[WARN]${RST}  %s\n"  "$*"; }
err()    { printf "  ${RED}[FAIL]${RST}  %s\n"  "$*" >&2; }
detail() { printf "  ${DIM}        %s${RST}\n"  "$*"; }
diag()   { printf "  ${MAG}[DIAG]${RST}  %s\n"  "$*"; }
kv()     { printf "  ${DIM}  %-30s${RST} ${WHT}%s${RST}\n" "$1" "$2"; }
indent() { sed 's/^/          /'; }
hline()  { printf "  ${DIM}%s${RST}\n" "$(printf '%.0s-' {1..60})"; }

section() {
    local title="$1"
    local pad=$(( 54 - ${#title} ))
    (( pad < 2 )) && pad=2
    printf "\n${BOLD}${CYN}--- %s %s${RST}\n" \
        "$title" "$(printf '%*s' $pad | tr ' ' '-')"
}

twrite() {
    local file="$1" value="$2"
    if ! echo "$value" > "$file" 2>/dev/null; then
        err "Could not write '${value}' to ${file}"
        return 1
    fi
}

# ── Diagnostic helpers ────────────────────────────────────────────────────────

diag_ftrace_state() {
    diag "Current ftrace state:"
    hline
    kv "tracing_on:"       "$(cat ${TRACEFS}/tracing_on        2>/dev/null || echo N/A)"
    kv "current_tracer:"   "$(cat ${TRACEFS}/current_tracer    2>/dev/null || echo N/A)"
    kv "available_tracers:""$(cat ${TRACEFS}/available_tracers 2>/dev/null || echo N/A)"
    kv "set_ftrace_filter:" \
        "$(grep -v '^#\|^$' ${TRACEFS}/set_ftrace_filter 2>/dev/null | tr '\n' ' ' || echo empty)"
    kv "buffer_size_kb:"   "$(cat ${TRACEFS}/buffer_size_kb    2>/dev/null || echo N/A)"
    hline
}

diag_kernel_ftrace_config() {
    diag "Kernel ftrace config:"
    hline
    local cfg="/boot/config-$(uname -r)"
    if [[ -f "$cfg" ]]; then
        grep -E "^CONFIG_(FTRACE|FUNCTION_TRACER|FUNCTION_GRAPH|DYNAMIC_FTRACE|KALLSYMS|DEBUG_FS)" \
            "$cfg" 2>/dev/null | while read -r l; do kv "" "$l"; done
    elif [[ -f /proc/config.gz ]]; then
        zcat /proc/config.gz 2>/dev/null | \
            grep -E "^CONFIG_(FTRACE|FUNCTION_TRACER|FUNCTION_GRAPH|KALLSYMS|DEBUG_FS)" | \
            while read -r l; do kv "" "$l"; done
    else
        detail "Config not found. Try: zcat /proc/config.gz | grep FTRACE"
    fi
    hline
}

diag_kallsyms_all() {
    local mod="$1"
    diag "All /proc/kallsyms entries for [${mod}]:"
    hline
    local all; all=$(grep -w "\[${mod}\]" /proc/kallsyms 2>/dev/null || true)
    if [[ -z "$all" ]]; then
        detail "No entries at all — module may not be loaded or name differs."
        diag "Module names currently in kallsyms:"
        grep -oP '\[\K[^\]]+' /proc/kallsyms 2>/dev/null | sort -u | indent
    else
        diag "Symbol type breakdown:"
        echo "$all" | awk '{print $2}' | sort | uniq -c | sort -rn | \
            while read -r c t; do kv "  type '$t':" "${c} symbols"; done
        echo
        diag "Traceable t/T symbols:"
        echo "$all" | awk '($2=="t"||$2=="T"){print $3}' | sort | indent || detail "(none)"
        diag "Other types (not traceable):"
        echo "$all" | awk '($2!="t"&&$2!="T"){printf "  %s  %s\n",$2,$3}' | head -20 | indent
    fi
    hline
}

diag_buffer_stats() {
    diag "Buffer stats after collection:"
    hline
    kv "buffer_size_kb (per CPU):" "$(cat ${TRACEFS}/buffer_size_kb      2>/dev/null || echo N/A)"
    kv "buffer_total_size_kb:"     "$(cat ${TRACEFS}/buffer_total_size_kb 2>/dev/null || echo N/A)"
    if [[ -d "${TRACEFS}/per_cpu" ]]; then
        for cpu_dir in "${TRACEFS}"/per_cpu/cpu*/; do
            local cpu; cpu=$(basename "$cpu_dir")
            local sf="${cpu_dir}stats"
            [[ -f "$sf" ]] || continue
            printf "    ${DIM}[%s]${RST}\n" "$cpu"
            grep -E "entries|overrun|commit|dropped" "$sf" 2>/dev/null | \
                while read -r l; do detail "      $l"; done
        done
    fi
    hline
}

# ── Cleanup — always runs on EXIT (Ctrl+C, errors, normal exit) ───────────────
cleanup() {
    section "CLEANUP"
    info "Disabling tracing..."
    echo 0     > "${TRACEFS}/tracing_on"        2>/dev/null || true
    info "Clearing function filter..."
    echo       > "${TRACEFS}/set_ftrace_filter"  2>/dev/null || true
    info "Resetting tracer to nop..."
    echo "nop" > "${TRACEFS}/current_tracer"     2>/dev/null || true
    ok "Tracing disabled and filters cleared."
    kv "  tracing_on:"     "$(cat ${TRACEFS}/tracing_on     2>/dev/null || echo ?)"
    kv "  current_tracer:" "$(cat ${TRACEFS}/current_tracer 2>/dev/null || echo ?)"
}
trap cleanup EXIT

# ── STEP 0 — Argument validation ──────────────────────────────────────────────
section "STEP 0 — ARGUMENT CHECK"

if [[ -z "$DRIVER_NAME" ]]; then
    err "No driver name supplied."
    printf "\n  ${BOLD}Usage:${RST}  sudo %s <driver> [duration_seconds] [tracer]\n\n" "$0"
    printf "  Currently loaded modules:\n"
    lsmod | head -20 | indent
    exit 1
fi

[[ "$EUID" -ne 0 ]] && { err "Run as root: sudo $0 $*"; exit 1; }

info "Raw input : ${BOLD}${RAW_INPUT}${RST}"
info "Driver    : ${BOLD}${DRIVER_NAME}${RST}"
info "Duration  : ${BOLD}${DURATION}s${RST}"
info "Tracer    : ${BOLD}${TRACER}${RST}"
info "Log file  : ${BOLD}${LOG_FILE}${RST}"
[[ -n "$KO_PATH" ]] && info ".ko path  : ${BOLD}${KO_PATH}${RST}"

# ── STEP 1 — debugfs check ────────────────────────────────────────────────────
section "STEP 1 — DEBUGFS CHECK"

if mountpoint -q "${DEBUGFS}"; then
    ok "debugfs mounted at ${DEBUGFS}"
else
    warn "debugfs not mounted — attempting mount..."
    mount -t debugfs debugfs "${DEBUGFS}" || {
        err "Failed to mount debugfs."
        diag "Mount table:"; mount | indent
        diag_kernel_ftrace_config
        exit 1
    }
    ok "debugfs mounted."
fi

[[ -d "${TRACEFS}" ]] || {
    err "tracefs not found at ${TRACEFS} — CONFIG_FTRACE=y required."
    diag_kernel_ftrace_config; exit 1
}
ok "tracefs accessible at ${TRACEFS}"
kv "  tracing_on:"     "$(cat ${TRACEFS}/tracing_on     2>/dev/null || echo ?)"
kv "  current_tracer:" "$(cat ${TRACEFS}/current_tracer 2>/dev/null || echo ?)"
kv "  buffer_size_kb:" "$(cat ${TRACEFS}/buffer_size_kb 2>/dev/null || echo ?)"

# ── STEP 2 — Module check ─────────────────────────────────────────────────────
section "STEP 2 — DRIVER MODULE CHECK"

MODULE_FOUND=0
if lsmod | awk '{print $1}' | grep -qx "${DRIVER_NAME}"; then
    ok "Module '${DRIVER_NAME}' is loaded (exact match)."
    MODULE_FOUND=1
else
    ALT="${DRIVER_NAME//-/_}"
    if lsmod | awk '{print $1}' | grep -qx "${ALT}"; then
        ok "Module found as '${ALT}' (hyphen→underscore alias)."
        DRIVER_NAME="${ALT}"; MODULE_FOUND=1
    fi
fi

if [[ $MODULE_FOUND -eq 0 ]]; then
    err "Module '${DRIVER_NAME}' is NOT loaded."
    hline
    diag "Partial lsmod matches:"
    lsmod | grep -i "${DRIVER_NAME}" 2>/dev/null | indent || detail "(none)"
    diag "Full lsmod:"; lsmod | indent
    diag "dmesg mentions:"
    dmesg 2>/dev/null | grep -i "${DRIVER_NAME}" | tail -10 | indent || detail "(none)"
    [[ -n "$KO_PATH" ]] && { diag "modinfo:"; modinfo "$KO_PATH" 2>/dev/null | indent; }
    err "Load the driver first:  sudo insmod /path/to/${DRIVER_NAME}.ko"
    exit 1
fi

kv "  /sys/module entry:" "$(ls /sys/module/ 2>/dev/null | grep -x "${DRIVER_NAME}" || echo N/A)"
[[ -f "/sys/module/${DRIVER_NAME}/refcnt" ]]    && kv "  refcount:"  "$(cat /sys/module/${DRIVER_NAME}/refcnt)"
[[ -f "/sys/module/${DRIVER_NAME}/initstate" ]] && kv "  initstate:" "$(cat /sys/module/${DRIVER_NAME}/initstate)"

# ── STEP 3 — Tracer availability ──────────────────────────────────────────────
section "STEP 3 — TRACER AVAILABILITY CHECK"

AVAILABLE_TRACERS=$(cat "${TRACEFS}/available_tracers" 2>/dev/null || echo "")
info "Available tracers: ${DIM}${AVAILABLE_TRACERS}${RST}"

echo "$AVAILABLE_TRACERS" | grep -qw "$TRACER" || {
    err "Tracer '${TRACER}' not available on this kernel."
    diag_kernel_ftrace_config; exit 1
}
ok "Tracer '${TRACER}' available."

# ── STEP 4 — Symbol resolution ────────────────────────────────────────────────
section "STEP 4 — SYMBOL RESOLUTION"

info "Searching /proc/kallsyms for t/T symbols in [${DRIVER_NAME}]..."

SYMBOLS=$(awk -v mod="[${DRIVER_NAME}]" \
    '$4 == mod && ($2=="t" || $2=="T") {print $3}' \
    /proc/kallsyms | sort -u)

SYMBOL_COUNT=$(echo "$SYMBOLS" | grep -c '[^[:space:]]' || true)

if [[ -z "$SYMBOLS" || "$SYMBOL_COUNT" -eq 0 ]]; then
    err "No traceable function symbols found for '${DRIVER_NAME}'."
    hline
    ALL_SYMS=$(grep -w "\[${DRIVER_NAME}\]" /proc/kallsyms 2>/dev/null || true)
    if [[ -z "$ALL_SYMS" ]]; then
        detail "Module has ZERO entries in kallsyms — name mismatch?"
        diag "All module names in kallsyms:"
        grep -oP '\[\K[^\]]+' /proc/kallsyms 2>/dev/null | sort -u | indent
    else
        detail "Module IS in kallsyms but no t/T symbols — likely fully inlined."
        detail "Fix: add  ccflags-y += -O0 -fno-inline  to your Makefile, rebuild."
    fi
    diag_kallsyms_all "$DRIVER_NAME"
    [[ -n "$KO_PATH" ]] && { diag "nm output:"; nm "$KO_PATH" 2>/dev/null | grep -E ' [tT] ' | indent; }
    exit 1
fi

ok "Found ${BOLD}${MAG}${SYMBOL_COUNT}${RST} traceable function(s):"
echo "$SYMBOLS" | while read -r s; do printf "        ${DIM}%s${RST}\n" "$s"; done

ALL_COUNT=$(grep -cw "\[${DRIVER_NAME}\]" /proc/kallsyms 2>/dev/null || echo 0)
kv "  Total kallsyms entries:" "${ALL_COUNT}"
kv "  Traceable (t/T):"        "${SYMBOL_COUNT}"

# ── STEP 5 — Clear buffers ────────────────────────────────────────────────────
section "STEP 5 — CLEAR TRACE BUFFERS"

info "Disabling tracing before setup..."
twrite "${TRACEFS}/tracing_on" "0"
ok "Tracing disabled."

info "Clearing trace ring buffer..."
echo > "${TRACEFS}/trace" 2>/dev/null || true
ok "Trace buffer cleared."

if [[ -d "${TRACEFS}/per_cpu" ]]; then
    info "Clearing per-CPU buffers..."
    for cpu_buf in "${TRACEFS}"/per_cpu/cpu*/trace; do
        echo > "$cpu_buf" 2>/dev/null || true
    done
    ok "Per-CPU buffers cleared."
fi
kv "  buffer_size_kb:" "$(cat ${TRACEFS}/buffer_size_kb 2>/dev/null || echo N/A) KB"

# ── STEP 6 — Set tracer ───────────────────────────────────────────────────────
section "STEP 6 — SET TRACER"

info "Resetting to nop..."
twrite "${TRACEFS}/current_tracer" "nop"

info "Setting tracer to '${TRACER}'..."
twrite "${TRACEFS}/current_tracer" "${TRACER}" || {
    err "Failed to set tracer '${TRACER}'."
    diag_ftrace_state; diag_kernel_ftrace_config; exit 1
}
ok "Active tracer: ${BOLD}$(cat ${TRACEFS}/current_tracer)${RST}"

# ── STEP 7 — Set function filter ──────────────────────────────────────────────
section "STEP 7 — SET FUNCTION FILTER"

info "Writing ${SYMBOL_COUNT} symbol(s) to set_ftrace_filter..."
info "(Filter = driver functions only. Without it: millions of events/sec.)"

first=1
while IFS= read -r sym; do
    [[ -z "$sym" ]] && continue
    if [[ $first -eq 1 ]]; then
        echo "$sym" >  "${TRACEFS}/set_ftrace_filter" 2>/dev/null && first=0 || warn "Skipped: $sym"
    else
        echo "$sym" >> "${TRACEFS}/set_ftrace_filter" 2>/dev/null || warn "Skipped: $sym"
    fi
done <<< "$SYMBOLS"

ACCEPTED=$(grep -v "^#\|^$" "${TRACEFS}/set_ftrace_filter" 2>/dev/null | wc -l || echo 0)
ok "Kernel accepted ${BOLD}${MAG}${ACCEPTED}${RST} / ${SYMBOL_COUNT} function(s) into filter."

(( SYMBOL_COUNT > ACCEPTED )) && \
    warn "$(( SYMBOL_COUNT - ACCEPTED )) symbol(s) dropped (inlined/optimised out)."

[[ "$ACCEPTED" -eq 0 ]] && {
    err "Ftrace accepted 0 functions — nothing to trace."
    diag_kallsyms_all "$DRIVER_NAME"; diag_ftrace_state; exit 1
}

diag "Accepted filter entries:"
grep -v "^#\|^$" "${TRACEFS}/set_ftrace_filter" 2>/dev/null | indent
# ── STEP 8 — Enable tracing ───────────────────────────────────────────────────
section "STEP 8 — ENABLE TRACING"

DMESG_BEFORE=$(dmesg | wc -l)
TRACE_START_TIME=$(date +%s)

info "Enabling tracing..."
twrite "${TRACEFS}/tracing_on" "1"

[[ "$(cat ${TRACEFS}/tracing_on 2>/dev/null)" == "1" ]] || {
    err "tracing_on is not 1 — something blocked the enable."
    diag_ftrace_state; exit 1
}

ok "Tracing is ${GRN}${BOLD}ACTIVE${RST}"
echo

# ── Collection mode: timed OR manual ─────────────────────────────────────────
#
# DURATION=0  → manual mode: tracing runs until user presses Enter
# DURATION>0  → timed mode:  tracing runs for that many seconds
#
# In both modes:
#   - A live elapsed counter updates every second on the same line
#   - The buffer status (events captured so far) is shown every 5 seconds
#   - Ctrl+C is safe — trap cleanup EXIT disables tracing automatically
#
if [[ "$DURATION" -eq 0 ]]; then

    # ── Manual stop mode ──────────────────────────────────────────────────────
    printf "  ${YLW}${BOLD}  Manual mode — tracing is running indefinitely.${RST}\n"
    printf "  ${DIM}  Exercise your driver now in another terminal:${RST}\n"
    printf "  ${DIM}    cat /dev/%s${RST}\n"              "$DRIVER_NAME"
    printf "  ${DIM}    echo test > /dev/%s${RST}\n"      "$DRIVER_NAME"
    printf "  ${DIM}    dd if=/dev/%s bs=1 count=16${RST}\n\n" "$DRIVER_NAME"
    printf "  ${YLW}${BOLD}  Press ENTER at any time to stop tracing and save the log.${RST}\n\n"

    # Background ticker — updates elapsed time every second
    # Also prints a live event count every 5 seconds so you can see activity
    (
        secs=0
        while true; do
            sleep 1
            secs=$(( secs + 1 ))
            mins=$(( secs / 60 ))
            rem=$(( secs % 60 ))

            # Every second: update elapsed time on same line
            printf "\r  ${DIM}  Elapsed: %02d:%02d   tracing_on=%s${RST}   " \
                "$mins" "$rem" \
                "$(cat ${TRACEFS}/tracing_on 2>/dev/null || echo ?)"

            # Every 5 seconds: show how many events are in the buffer
            if (( secs % 5 == 0 )); then
                events=$(grep -c "^[^#[:space:]]" "${TRACEFS}/trace" 2>/dev/null || echo 0)
                printf "\r  ${DIM}  Elapsed: %02d:%02d   Events in buffer: %s${RST}   " \
                    "$mins" "$rem" "$events"
            fi
        done
    ) &
    TICKER_PID=$!

    # Wait for user to press Enter — read from /dev/tty so it works even
    # if stdin is redirected, and ignores any characters typed accidentally
    read -r -s < /dev/tty

    # Stop the ticker
    kill "$TICKER_PID" 2>/dev/null || true
    wait "$TICKER_PID" 2>/dev/null || true

    TRACE_END_TIME=$(date +%s)
    ACTUAL_DURATION=$(( TRACE_END_TIME - TRACE_START_TIME ))
    printf "\r  ${GRN}${BOLD}  Tracing stopped by user after %ds.${RST}%-35s\n" \
        "$ACTUAL_DURATION" ""

else

    # ── Timed mode ────────────────────────────────────────────────────────────
    printf "  ${YLW}${BOLD}  Collecting trace for %ds...${RST}\n" "$DURATION"
    printf "  ${DIM}  Exercise your driver in another terminal now:${RST}\n"
    printf "  ${DIM}    cat /dev/%s${RST}\n"              "$DRIVER_NAME"
    printf "  ${DIM}    echo test > /dev/%s${RST}\n\n"    "$DRIVER_NAME"

    for (( i=DURATION; i>0; i-- )); do
        if (( i % 5 == 0 )); then
            events=$(grep -c "^[^#[:space:]]" "${TRACEFS}/trace" 2>/dev/null || echo 0)
            printf "\r  ${DIM}  Time remaining: %3ds   Events captured: %s${RST}   " \
                "$i" "$events"
        else
            printf "\r  ${DIM}  Time remaining: %3ds   tracing_on=%s${RST}   " \
                "$i" "$(cat ${TRACEFS}/tracing_on 2>/dev/null || echo ?)"
        fi
        sleep 1
    done

    ACTUAL_DURATION=$DURATION
    printf "\r  ${GRN}${BOLD}  Collection window complete (%ds).${RST}%-35s\n" \
        "$ACTUAL_DURATION" ""
fi
section "STEP 9 — DISABLE TRACING"

info "Disabling tracing..."
echo 0 > "${TRACEFS}/tracing_on" 2>/dev/null || true
ok "Tracing disabled. Buffer is stable."

diag_buffer_stats

TRACE_LINES=$(grep -c "^[^#[:space:]]" "${TRACE_FILE}" 2>/dev/null || echo 0)
kv "  Non-comment trace lines:" "${TRACE_LINES}"

if [[ "$TRACE_LINES" -eq 0 ]]; then
    warn "Buffer empty — no calls captured."
    hline
    detail "1. Were driver functions called during the ${DURATION}s window?"
    detail "   → Exercise the driver while tracing is active."
    detail "2. Are functions inlined? Rebuild with: ccflags-y += -O0 -fno-inline"
    detail "3. Try flat tracer:  sudo $0 ${DRIVER_NAME} 10 function"
    hline
    head -20 "${TRACE_FILE}" 2>/dev/null | indent
    diag_ftrace_state
fi

# ── STEP 10 — Save logs ───────────────────────────────────────────────────────
section "STEP 10 — SAVE LOGS"

mkdir -p "${LOG_DIR}"
info "Writing log to: ${BOLD}${LOG_FILE}${RST}"

{
    printf "============================================================\n"
    printf " FTRACE DRIVER DEBUG LOG\n"
    printf "============================================================\n"
    printf " Driver       : %s\n"  "$DRIVER_NAME"
    printf " Raw input    : %s\n"  "$RAW_INPUT"
    printf " .ko path     : %s\n"  "${KO_PATH:-(not provided)}"
    printf " Tracer       : %s\n"  "$TRACER"
    printf " Duration     : %ss\n" "$DURATION"
    printf " Captured at  : %s\n"  "$(date)"
    printf " Kernel       : %s\n"  "$(uname -r)"
    printf " Host         : %s\n"  "$(hostname)"
    printf "============================================================\n\n"

    printf "============================================================\n"
    printf " SYMBOLS TRACED  (%d total)\n" "$SYMBOL_COUNT"
    printf "============================================================\n"
    echo "$SYMBOLS"
    printf "\n"

    printf "============================================================\n"
    printf " FTRACE ACCEPTED FILTER\n"
    printf "============================================================\n"
    grep -v "^#\|^$" "${TRACEFS}/set_ftrace_filter" 2>/dev/null || printf "(empty)\n"
    printf "\n"

    printf "============================================================\n"
    printf " TRACE OUTPUT\n"
    printf "============================================================\n"
    cat "${TRACE_FILE}" 2>/dev/null || printf "(empty)\n"
    printf "\n"

    printf "============================================================\n"
    printf " DMESG  (new lines during trace window)\n"
    printf "============================================================\n"
    dmesg | tail -n +"$DMESG_BEFORE" 2>/dev/null || printf "(none)\n"
    printf "\n"

    printf "============================================================\n"
    printf " END OF LOG\n"
    printf "============================================================\n"
} > "${LOG_FILE}" 2>&1

[[ -s "${LOG_FILE}" ]] || { err "Log file is empty."; exit 1; }

LOG_SIZE=$(du -h "${LOG_FILE}" | cut -f1)
ok "Log saved: ${BOLD}${LOG_FILE}${RST}  (${LOG_SIZE})"

DMESG_LINES=$(dmesg | tail -n +"$DMESG_BEFORE" | wc -l)

# ── Summary ───────────────────────────────────────────────────────────────────
section "SUMMARY"

printf "\n"
printf "  ${BOLD}%-24s${RST} %s\n"  "Driver:"          "${DRIVER_NAME}"
printf "  ${BOLD}%-24s${RST} %s\n"  "Tracer:"          "${TRACER}"
printf "  ${BOLD}%-24s${RST} %s\n"  "Duration:"        "${DURATION}s"
printf "  ${BOLD}%-24s${RST} %s\n"  "Symbols found:"   "${MAG}${SYMBOL_COUNT}${RST}"
printf "  ${BOLD}%-24s${RST} %s\n"  "Filter accepted:" "${MAG}${ACCEPTED}${RST}"
printf "  ${BOLD}%-24s${RST} %s\n"  "Trace lines:"     "${TRACE_LINES}"
printf "  ${BOLD}%-24s${RST} %s\n"  "New dmesg lines:" "${DMESG_LINES}"
printf "  ${BOLD}%-24s${RST} %s\n"  "Log file:"        "${LOG_FILE}"
printf "\n"

if [[ "$TRACE_LINES" -gt 0 ]]; then
    ok "Trace captured. Inspect with:"
    printf "  ${DIM}    less    %s${RST}\n"               "${LOG_FILE}"
    printf "  ${DIM}    grep    '<func>'   %s${RST}\n"    "${LOG_FILE}"
    printf "  ${DIM}    grep -A5 'TRACE OUTPUT' %s${RST}\n" "${LOG_FILE}"
else
    warn "Trace is empty — see suggestions above."
fi
printf "\n"
