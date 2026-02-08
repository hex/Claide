#!/bin/bash
# ABOUTME: Terminal emulator benchmark measuring throughput, escape sequence handling, and memory.
# ABOUTME: Run inside each terminal to compare. Results saved to /tmp/termbench/results/.

set -euo pipefail

BENCH_DIR="/tmp/termbench"
DATA_DIR="$BENCH_DIR/data"
RESULTS_DIR="$BENCH_DIR/results"
ITERATIONS=5

# -- Detect terminal name --
# Walk the process tree to find the hosting app. $TERM_PROGRAM is unreliable
# because some terminals (e.g. Claide) set it to Apple_Terminal for OSC 7.
detect_terminal() {
    local pid=$$
    while [[ "$pid" -gt 1 ]]; do
        local name
        name=$(ps -o comm= -p "$pid" 2>/dev/null | xargs basename 2>/dev/null) || break
        case "$name" in
            Claide|Ghostty|iTerm2|Alacritty|WezTerm|kitty|Terminal)
                echo "$name"; return ;;
        esac
        pid=$(ps -o ppid= -p "$pid" 2>/dev/null | xargs) || break
    done
    # Fallback to TERM_PROGRAM
    echo "${TERM_PROGRAM:-unknown}"
}

TERMINAL="${1:-$(detect_terminal)}"

# -- Colors --
bold="\033[1m"
dim="\033[2m"
reset="\033[0m"
cyan="\033[36m"
green="\033[32m"
yellow="\033[33m"

info()  { printf "${cyan}${bold}>>>${reset} %s\n" "$1"; }
ok()    { printf "${green}${bold} ok${reset} %s\n" "$1"; }

# -- Generate test data (once) --
setup_data() {
    mkdir -p "$DATA_DIR" "$RESULTS_DIR"

    if [[ ! -f "$DATA_DIR/sequential.txt" ]] || [[ ! -f "$DATA_DIR/dense_ascii.txt" ]] \
       || [[ ! -f "$DATA_DIR/ansi_colors.txt" ]] || [[ ! -f "$DATA_DIR/unicode.txt" ]]; then
        info "Generating test data (one-time setup)..."

        # 1) Sequential numbers (~7MB)
        seq 1 1000000 > "$DATA_DIR/sequential.txt"
        ok "sequential.txt ($(du -h "$DATA_DIR/sequential.txt" | cut -f1 | xargs))"

        # 2) Dense ASCII (~10MB)
        base64 < /dev/urandom | head -c 10000000 > "$DATA_DIR/dense_ascii.txt"
        ok "dense_ascii.txt ($(du -h "$DATA_DIR/dense_ascii.txt" | cut -f1 | xargs))"

        # 3) ANSI color stress test (~5MB of colored output)
        python3 -c "
import random
colors = list(range(31, 37)) + list(range(91, 97))
lines = []
for i in range(100000):
    c = random.choice(colors)
    lines.append(f'\033[{c}mLine {i}: The quick brown fox jumps over the lazy dog\033[0m')
print('\n'.join(lines))
" > "$DATA_DIR/ansi_colors.txt"
        ok "ansi_colors.txt ($(du -h "$DATA_DIR/ansi_colors.txt" | cut -f1 | xargs))"

        # 4) Unicode stress (~3MB, CJK + emoji + combining chars)
        python3 -c "
import random
cjk = [chr(c) for c in range(0x4E00, 0x4F00)]
emoji = [chr(c) for c in range(0x1F600, 0x1F650)]
lines = []
for i in range(50000):
    chars = ''.join(random.choices(cjk + emoji, k=40))
    lines.append(f'{i:06d} {chars}')
print('\n'.join(lines))
" > "$DATA_DIR/unicode.txt"
        ok "unicode.txt ($(du -h "$DATA_DIR/unicode.txt" | cut -f1 | xargs))"

        info "Test data ready."
    fi
}

# -- Timing helper (returns milliseconds) --
# Uses a single python3 process for timing and subprocess for execution.
# Writes benchmark output to /dev/tty (the controlling terminal).
time_ms() {
    python3 -c "
import time, subprocess, sys
tty = open('/dev/tty', 'wb')
start = time.monotonic()
subprocess.run(sys.argv[1:], stdout=tty, stderr=subprocess.DEVNULL)
end = time.monotonic()
tty.close()
print(round((end - start) * 1000, 1))
" "$@"
}

# -- Run a single benchmark N times, return median --
bench() {
    local label="$1"
    shift
    local times=()

    # Warmup run (primes disk cache)
    "$@" > /dev/null 2>&1

    for ((i = 1; i <= ITERATIONS; i++)); do
        printf '\033[2J\033[H' > /dev/tty  # Clear screen between runs
        local ms
        ms=$(time_ms "$@")
        times+=("$ms")
        printf '\033[2J\033[H' > /dev/tty
        printf "  ${dim}run %d: %s ms${reset}\n" "$i" "$ms"
    done

    # Compute median and average
    local sorted avg median
    sorted=$(printf '%s\n' "${times[@]}" | sort -n)
    avg=$(printf '%s\n' "${times[@]}" | awk '{s+=$1} END {printf "%.1f", s/NR}')
    median=$(printf '%s\n' "${times[@]}" | sort -n | awk "NR==$(( (ITERATIONS + 1) / 2 )){print}")

    printf "  ${bold}median: %s ms  avg: %s ms${reset}\n" "$median" "$avg"
    echo "$label,$TERMINAL,$median,$avg,$(printf '%s\n' "${times[@]}" | tr '\n' '|' | sed 's/|$//')" >> "$RESULTS_FILE"
}

# -- Memory measurement --
measure_memory() {
    local pid app_name mem_kb
    app_name="$TERMINAL"

    # Find the terminal process
    pid=$(pgrep -x "$app_name" 2>/dev/null | head -1 || true)
    if [[ -z "$pid" ]]; then
        # Try case-insensitive match on the app bundle name
        pid=$(ps aux | grep -i "[${app_name:0:1}]${app_name:1}" | head -1 | awk '{print $2}' || true)
    fi

    if [[ -n "$pid" ]]; then
        mem_kb=$(ps -o rss= -p "$pid" 2>/dev/null | xargs)
        local mem_mb
        mem_mb=$(awk "BEGIN {printf \"%.1f\", $mem_kb / 1024}")
        printf "  ${bold}RSS: %s MB${reset} (pid %s)\n" "$mem_mb" "$pid"
        echo "memory,$TERMINAL,$mem_mb,$mem_mb,$mem_kb" >> "$RESULTS_FILE"
    else
        printf "  ${yellow}Could not find process for %s${reset}\n" "$app_name"
        echo "memory,$TERMINAL,N/A,N/A,N/A" >> "$RESULTS_FILE"
    fi
}

# -- Main --
main() {
    setup_data

    RESULTS_FILE="$RESULTS_DIR/${TERMINAL}.csv"
    echo "test,terminal,median_ms,avg_ms,raw_runs" > "$RESULTS_FILE"

    printf "\n${bold}Terminal Benchmark${reset}\n"
    printf "Terminal: ${cyan}${bold}%s${reset}\n" "$TERMINAL"
    printf "Iterations: %d\n\n" "$ITERATIONS"

    info "Test 1/5: Sequential text throughput (seq 1..1M)"
    bench "sequential" cat "$DATA_DIR/sequential.txt"
    echo

    info "Test 2/5: Dense ASCII throughput (10MB base64)"
    bench "dense_ascii" cat "$DATA_DIR/dense_ascii.txt"
    echo

    info "Test 3/5: ANSI color escape throughput (100K colored lines)"
    bench "ansi_colors" cat "$DATA_DIR/ansi_colors.txt"
    echo

    info "Test 4/5: Unicode throughput (CJK + emoji, 50K lines)"
    bench "unicode" cat "$DATA_DIR/unicode.txt"
    echo

    info "Test 5/5: Memory usage"
    measure_memory
    echo

    printf "${green}${bold}Results saved to:${reset} %s\n\n" "$RESULTS_FILE"

    # -- Summary table if multiple results exist --
    local csv_count
    csv_count=$(ls "$RESULTS_DIR"/*.csv 2>/dev/null | wc -l | xargs)
    if [[ "$csv_count" -gt 1 ]]; then
        info "Comparison across $csv_count terminals:"
        printf "\n%-20s %10s %10s %10s %10s %10s\n" "Terminal" "Seq(ms)" "ASCII(ms)" "ANSI(ms)" "Unicode(ms)" "RSS(MB)"
        printf "%-20s %10s %10s %10s %10s %10s\n" "--------" "-------" "---------" "--------" "-----------" "-------"
        for f in "$RESULTS_DIR"/*.csv; do
            local name seq_v ascii_v ansi_v uni_v mem_v
            name=$(basename "$f" .csv)
            seq_v=$(awk -F, '/^sequential/ {print $3}' "$f")
            ascii_v=$(awk -F, '/^dense_ascii/ {print $3}' "$f")
            ansi_v=$(awk -F, '/^ansi_colors/ {print $3}' "$f")
            uni_v=$(awk -F, '/^unicode/ {print $3}' "$f")
            mem_v=$(awk -F, '/^memory/ {print $3}' "$f")
            printf "%-20s %10s %10s %10s %10s %10s\n" "$name" "$seq_v" "$ascii_v" "$ansi_v" "$uni_v" "$mem_v"
        done
        echo
    fi
}

main
