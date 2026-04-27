#!/bin/bash
# ftrfs-iobench.sh -- FTRFS I/O benchmark on HPC compute nodes
#
# Measures filesystem-level I/O performance on FTRFS-mounted compute nodes.
# Designed to establish a pre-v4 baseline for detecting regressions
# introduced by format changes (item 4b: v4 bump + Shannon entropy).
#
# Metrics:
#   M1  Sequential write + fsync   (4 MB, bs=4K)
#   M2  Sequential read cold       (4 MB after drop_caches)
#   M4  Stat bulk                  (100 files, find + xargs stat)
#   M5  Small random write + fsync (50 x 64B with conv=fsync each)
#
# M3 (mount cycle) is intentionally OMITTED in v1 because the compute
# image uses overlayfs with /data as upper layer -- unmounting /data
# would break /etc.
#
# Targets all compute nodes (compute01/02/03) and aggregates results.
# Per-metric: 10 runs default, reports min/median/max/stddev.
#
# Output:
#   - stdout: ASCII table (immediate)
#   - --md PATH: Markdown report (default: Documentation/iobench-baseline-YYYY-MM-DD.md)
#   - --json PATH: JSON dump (default: /tmp/ftrfs-iobench-<timestamp>.json)
#
# Usage:
#   bin/ftrfs-iobench.sh                        # default: 10 runs, all compute, md+json
#   bin/ftrfs-iobench.sh --runs 3               # quick smoke test
#   bin/ftrfs-iobench.sh --node 192.168.56.11   # single node
#   bin/ftrfs-iobench.sh --no-md --no-json      # stdout only

set -euo pipefail

# ============================================================
# Defaults
# ============================================================
RUNS=10
NODES_DEFAULT="192.168.56.11 192.168.56.12 192.168.56.13"
NODES=""
EMIT_MD=1
EMIT_JSON=1
MD_PATH=""
JSON_PATH=""
QUIET=0
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i $HOME/.ssh/hpclab_admin"
SSH_USER="hpcadmin"

# ============================================================
# Argument parsing
# ============================================================
while [[ $# -gt 0 ]]; do
    case "$1" in
        --runs)     RUNS="$2"; shift 2;;
        --node)     NODES="$2"; shift 2;;
        --md)       MD_PATH="$2"; shift 2;;
        --json)     JSON_PATH="$2"; shift 2;;
        --no-md)    EMIT_MD=0; shift;;
        --no-json)  EMIT_JSON=0; shift;;
        --quiet)    QUIET=1; shift;;
        -h|--help)  sed -n '2,30p' "$0"; exit 0;;
        *) echo "Unknown option: $1" >&2; exit 2;;
    esac
done

[[ -z "$NODES" ]] && NODES="$NODES_DEFAULT"

# Timestamps
TS=$(date +%Y-%m-%d-%H%M%S)
TS_HUMAN=$(date "+%Y-%m-%d %H:%M:%S")
DATE_ISO=$(date +%Y-%m-%d)

# Default output paths
[[ -z "$MD_PATH" ]] && MD_PATH="Documentation/iobench-baseline-${DATE_ISO}.md"
[[ -z "$JSON_PATH" ]] && JSON_PATH="/tmp/ftrfs-iobench-${TS}.json"

# Determine repo root for relative MD_PATH
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Resolve MD path against repo root if relative
if [[ ! "$MD_PATH" = /* ]]; then
    MD_PATH="$REPO_ROOT/$MD_PATH"
fi

# ============================================================
# Worker script (runs on each compute node)
# Variables substituted by host: __RUNS__
# ============================================================
WORKER_SCRIPT='#!/bin/sh
set -eu
RUNS=__RUNS__
DIR=/data/iobench

# Sanity: /data must be FTRFS, not tmpfs (state can degrade between runs).
# Without this guard, the bench would silently measure tmpfs throughput.
FS_TYPE=$(awk "\$2 == \"/data\" {fs=\$3} END{print fs}" /proc/mounts)
if [ "$FS_TYPE" != "ftrfs" ]; then
    echo "ERROR: /data is not FTRFS (found: $FS_TYPE)" >&2
    exit 2
fi

rm -rf "$DIR" 2>/dev/null || true
mkdir -p "$DIR"
sync

drop_caches() {
    echo 3 > /proc/sys/vm/drop_caches
}

ts_ns() {
    # BusyBox date(1) lacks %N (nanoseconds). Read monotonic
    # uptime from /proc/uptime instead. Resolution: 10ms.
    read u _ < /proc/uptime
    echo "$u"
}

dt_seconds() {
    awk "BEGIN{printf \"%.6f\", $2 - $1}"
}

# M1: Sequential write + fsync (4 MB, bs=4K, conv=fsync)
for i in $(seq 1 $RUNS); do
    # Cleanup previous iteration file to keep inode pressure low
    if [ $i -gt 1 ]; then
        rm -f "$DIR/seq_$((i - 1))"
    fi
    rm -f "$DIR/seq_$i"
    sync
    drop_caches
    T0=$(ts_ns)
    dd if=/dev/zero of="$DIR/seq_$i" bs=4K count=256 2>/dev/null
    sync
    T1=$(ts_ns)
    DT=$(dt_seconds "$T0" "$T1")
    echo "M1 $i $DT 1048576"
done

# M2: Sequential read cold (drop_caches then read; reuses last M1 file)
SEQFILE="$DIR/seq_$RUNS"
for i in $(seq 1 $RUNS); do
    sync
    drop_caches
    T0=$(ts_ns)
    dd if="$SEQFILE" of=/dev/null bs=4K 2>/dev/null
    T1=$(ts_ns)
    DT=$(dt_seconds "$T0" "$T1")
    echo "M2 $i $DT 1048576"
done

# M4: Stat bulk 100 files (find + xargs stat, cold cache each run)
for i in $(seq 1 $RUNS); do
    rm -rf "$DIR/m4_$i"
    mkdir -p "$DIR/m4_$i"
    j=1
    while [ $j -le 100 ]; do
        touch "$DIR/m4_$i/file_$j"
        j=$((j + 1))
    done
    sync
    drop_caches
    T0=$(ts_ns)
    find "$DIR/m4_$i" -type f | xargs stat > /dev/null
    T1=$(ts_ns)
    DT=$(dt_seconds "$T0" "$T1")
    echo "M4 $i $DT 100"
    rm -rf "$DIR/m4_$i"
    sync
done

# M5: Small random write + fsync (50 x 64B); each fsync stresses SB writeback
for i in $(seq 1 $RUNS); do
    rm -rf "$DIR/m5_$i"
    mkdir -p "$DIR/m5_$i"
    sync
    drop_caches
    T0=$(ts_ns)
    j=1
    while [ $j -le 10 ]; do
        dd if=/dev/urandom of="$DIR/m5_$i/small_$j" bs=64 count=1 2>/dev/null
        sync
        j=$((j + 1))
    done
    T1=$(ts_ns)
    DT=$(dt_seconds "$T0" "$T1")
    echo "M5 $i $DT 10"
    rm -rf "$DIR/m5_$i"
    sync
done

rm -rf "$DIR"
sync
echo "DONE"
'

WORKER_SCRIPT="${WORKER_SCRIPT//__RUNS__/$RUNS}"

# ============================================================
# Collect node metadata
# ============================================================
collect_node_meta() {
    local node="$1"
    ssh $SSH_OPTS "${SSH_USER}@${node}" '
echo "HOSTNAME=$(hostname)"
echo "KERNEL=$(uname -r)"
echo "ARCH=$(uname -m)"
echo "FTRFS_KO_MD5=$(md5sum /lib/modules/$(uname -r)/updates/ftrfs.ko 2>/dev/null | cut -d" " -f1)"
echo "FTRFS_IMG_SIZE=$(stat -c %s /tmp/ftrfs.img 2>/dev/null || echo 0)"
echo "FTRFS_MOUNT=$(grep ftrfs /proc/mounts | head -n 1)"
'
}

# ============================================================
# Run worker on a node, collect raw measurements
# ============================================================
run_node() {
    local node="$1"
    echo "$WORKER_SCRIPT" | ssh $SSH_OPTS "${SSH_USER}@${node}" "sudo tee /tmp/ftrfs-iobench-worker > /dev/null && sudo chmod +x /tmp/ftrfs-iobench-worker"
    ssh $SSH_OPTS "${SSH_USER}@${node}" "sudo /tmp/ftrfs-iobench-worker"
}

# ============================================================
# Statistics: min, median, max, stddev from a list of floats
# ============================================================
stats() {
    awk '
    { a[NR] = $1; sum += $1; n++ }
    END {
        if (n == 0) { print "0 0 0 0"; exit }
        for (i = 1; i <= n; i++)
            for (j = i+1; j <= n; j++)
                if (a[i] > a[j]) { t = a[i]; a[i] = a[j]; a[j] = t }
        min = a[1]; max = a[n]
        if (n % 2 == 1) median = a[(n+1)/2]
        else            median = (a[n/2] + a[n/2+1]) / 2
        mean = sum / n
        sq = 0
        for (i = 1; i <= n; i++) sq += (a[i] - mean) * (a[i] - mean)
        stddev = sqrt(sq / n)
        printf "%.6f %.6f %.6f %.6f\n", min, median, max, stddev
    }'
}

# ============================================================
# MAIN
# ============================================================
TMPDIR=$(mktemp -d -t ftrfs-iobench-XXXXXX)
trap 'rm -rf "$TMPDIR"' EXIT

[[ $QUIET -eq 0 ]] && {
    echo "================================================================"
    echo " FTRFS I/O Benchmark -- $TS_HUMAN"
    echo "================================================================"
    echo "Nodes  : $NODES"
    echo "Runs   : $RUNS per metric"
    echo ""
}

declare -A NODE_META
for node in $NODES; do
    [[ $QUIET -eq 0 ]] && echo "[*] Collecting metadata from $node..."
    NODE_META[$node]="$(collect_node_meta $node)"
    [[ $QUIET -eq 0 ]] && echo "[*] Running benchmark on $node ($RUNS runs x 4 metrics)..."
    run_node $node > "$TMPDIR/raw-$node.log"
    if ! grep -q "^DONE$" "$TMPDIR/raw-$node.log"; then
        echo "ERROR: node $node did not reach DONE marker" >&2
        cat "$TMPDIR/raw-$node.log" >&2
        exit 1
    fi
done

# ============================================================
# Aggregate per metric across all nodes
# ============================================================
for metric in M1 M2 M4 M5; do
    : > "$TMPDIR/values-$metric.txt"
    for node in $NODES; do
        : > "$TMPDIR/values-$metric-$node.txt"
        case "$metric" in
            M1|M2) awk -v m="$metric" '$1 == m { printf "%.6f\n", 1.0 / $3 }' "$TMPDIR/raw-$node.log" >> "$TMPDIR/values-$metric-$node.txt" ;;
            M4)    awk -v m="$metric" '$1 == m { printf "%.6f\n", $3 }' "$TMPDIR/raw-$node.log" >> "$TMPDIR/values-$metric-$node.txt" ;;
            M5)    awk -v m="$metric" '$1 == m { printf "%.6f\n", $3 * 1000 / 10 }' "$TMPDIR/raw-$node.log" >> "$TMPDIR/values-$metric-$node.txt" ;;
        esac
        cat "$TMPDIR/values-$metric-$node.txt" >> "$TMPDIR/values-$metric.txt"
    done
    read MIN MEDIAN MAX STDDEV < <(cat "$TMPDIR/values-$metric.txt" | stats)
    eval "${metric}_MIN=$MIN"
    eval "${metric}_MEDIAN=$MEDIAN"
    eval "${metric}_MAX=$MAX"
    eval "${metric}_STDDEV=$STDDEV"
done

# ============================================================
# OUTPUT 1: ASCII table to stdout
# ============================================================
if [[ $QUIET -eq 0 ]]; then
    echo ""
    echo "================================================================"
    echo " Results (aggregated across all nodes, $RUNS runs each)"
    echo "================================================================"
    printf "%-4s  %-28s  %10s  %10s  %10s  %10s  %-10s\n" "ID" "Metric" "Min" "Median" "Max" "Stddev" "Unit"
    printf "%-4s  %-28s  %10s  %10s  %10s  %10s  %-10s\n" "----" "----------------------------" "----------" "----------" "----------" "----------" "----------"
    printf "%-4s  %-28s  %10.3f  %10.3f  %10.3f  %10.3f  %-10s\n" "M1" "Write seq + fsync (4MB)"      "$M1_MIN" "$M1_MEDIAN" "$M1_MAX" "$M1_STDDEV" "MB/s"
    printf "%-4s  %-28s  %10.3f  %10.3f  %10.3f  %10.3f  %-10s\n" "M2" "Read seq cold (4MB)"          "$M2_MIN" "$M2_MEDIAN" "$M2_MAX" "$M2_STDDEV" "MB/s"
    printf "%-4s  %-28s  %10.3f  %10.3f  %10.3f  %10.3f  %-10s\n" "M4" "Stat bulk (100 files)"        "$M4_MIN" "$M4_MEDIAN" "$M4_MAX" "$M4_STDDEV" "seconds"
    printf "%-4s  %-28s  %10.3f  %10.3f  %10.3f  %10.3f  %-10s\n" "M5" "Small write + fsync (10x64B)" "$M5_MIN" "$M5_MEDIAN" "$M5_MAX" "$M5_STDDEV" "ms/file"
    echo "================================================================"
fi

# ============================================================
# OUTPUT 2: Markdown
# ============================================================
if [[ $EMIT_MD -eq 1 ]]; then
    mkdir -p "$(dirname "$MD_PATH")"
    {
        echo "# FTRFS I/O Benchmark"
        echo ""
        echo "**Date:** $TS_HUMAN"
        echo "**Nodes:** $NODES"
        echo "**Runs per metric:** $RUNS"
        echo ""
        echo "## Environment"
        echo ""
        for node in $NODES; do
            echo "### Node $node"
            echo ""
            echo '```'
            echo "${NODE_META[$node]}"
            echo '```'
            echo ""
        done
        echo "## Results (aggregated across all nodes)"
        echo ""
        echo "| ID | Metric                       | Min     | Median  | Max     | Stddev  | Unit    |"
        echo "|----|------------------------------|---------|---------|---------|---------|---------|"
        printf "| M1 | Write seq + fsync (4MB)      | %7.3f | %7.3f | %7.3f | %7.3f | MB/s    |\n" "$M1_MIN" "$M1_MEDIAN" "$M1_MAX" "$M1_STDDEV"
        printf "| M2 | Read seq cold (4MB)          | %7.3f | %7.3f | %7.3f | %7.3f | MB/s    |\n" "$M2_MIN" "$M2_MEDIAN" "$M2_MAX" "$M2_STDDEV"
        printf "| M4 | Stat bulk (100 files)        | %7.3f | %7.3f | %7.3f | %7.3f | seconds |\n" "$M4_MIN" "$M4_MEDIAN" "$M4_MAX" "$M4_STDDEV"
        printf "| M5 | Small write + fsync (10x64B) | %7.3f | %7.3f | %7.3f | %7.3f | ms/file |\n" "$M5_MIN" "$M5_MEDIAN" "$M5_MAX" "$M5_STDDEV"
        echo ""
        echo "## Methodology"
        echo ""
        echo "- **M1**: dd if=/dev/zero of=/data/iobench/seq bs=4K count=1024 conv=fsync"
        echo "  Stresses write path + journal RS event + SB writeback with parity."
        echo "- **M2**: drop_caches then dd if=seq of=/dev/null bs=4K"
        echo "  Stresses readahead path + CRC32 verification."
        echo "- **M4**: 100 touch + sync + drop_caches + find | xargs stat"
        echo "  Stresses inode RS encode/decode path (each inode 256B, iomap + CRC32)."
        echo "- **M5**: 10 x (dd if=/dev/urandom bs=64 count=1 + sync)"
        echo "  Worst-case bitmap dirty + SB writeback. Each fsync writes the SB."
        echo ""
        echo "## Notes"
        echo ""
        echo "- M3 (mount cycle) is intentionally omitted in v1: the compute image"
        echo "  uses overlayfs with /data as upper layer, so unmounting /data would"
        echo "  break /etc."
        echo "- Each measurement is taken after drop_caches for cold-cache discipline."
        echo "- Aggregation: $RUNS runs * $(echo $NODES | wc -w) nodes = $((RUNS * $(echo $NODES | wc -w))) samples per metric."
        echo "- ftrfsd peer is active during measurement; fsync triggers RS events to master."
        echo "- **FTRFS v3 limit observed**: single-file writes are capped at ~2 MB"
        echo "  (524 blocks of 4K) on TCG aarch64. M1/M2 use 1 MB to stay safely below."
        echo "- **M5 saturation**: 50 successive small writes + sync trigger journal RS"
        echo "  saturation around iteration 40-45 on TCG. Limited to 10 iterations to keep"
        echo "  the bench reliable. Re-evaluate with v4 format -- if the limit changes,"
        echo "  M5 should be reset accordingly."
    } > "$MD_PATH"
    [[ $QUIET -eq 0 ]] && echo "Markdown report : $MD_PATH"
fi

# ============================================================
# OUTPUT 3: JSON
# ============================================================
if [[ $EMIT_JSON -eq 1 ]]; then
    {
        echo "{"
        echo "  \"timestamp\": \"$TS_HUMAN\","
        echo "  \"runs_per_metric\": $RUNS,"
        echo "  \"nodes\": ["
        first=1
        for node in $NODES; do
            [[ $first -eq 0 ]] && echo ","
            printf "    \"%s\"" "$node"
            first=0
        done
        echo ""
        echo "  ],"
        # Helper: emit comma-separated samples from a file.
        emit_samples() {
            local f="$1"
            awk 'BEGIN{first=1} {
                if (first) { printf "%s", $1; first=0 }
                else       { printf ", %s", $1 }
            }' "$f"
        }
        # Helper: emit a full metric object with stats + samples.
        emit_metric() {
            local m="$1" unit="$2" trail="$3"
            local min="$4" median="$5" max="$6" stddev="$7"
            printf "    \"%s\": {\n" "$m"
            printf "      \"min\": %.6f,\n" "$min"
            printf "      \"median\": %.6f,\n" "$median"
            printf "      \"max\": %.6f,\n" "$max"
            printf "      \"stddev\": %.6f,\n" "$stddev"
            printf "      \"unit\": \"%s\",\n" "$unit"
            printf "      \"samples\": ["
            emit_samples "$TMPDIR/values-$m.txt"
            printf "],\n"
            printf "      \"samples_per_node\": {\n"
            local first_n=1
            for n in $NODES; do
                [[ $first_n -eq 0 ]] && printf ",\n"
                printf "        \"%s\": [" "$n"
                emit_samples "$TMPDIR/values-$m-$n.txt"
                printf "]"
                first_n=0
            done
            printf "\n      }\n"
            printf "    }%s\n" "$trail"
        }
        echo "  \"results\": {"
        emit_metric "M1" "MB/s"    "," "$M1_MIN" "$M1_MEDIAN" "$M1_MAX" "$M1_STDDEV"
        emit_metric "M2" "MB/s"    "," "$M2_MIN" "$M2_MEDIAN" "$M2_MAX" "$M2_STDDEV"
        emit_metric "M4" "seconds" "," "$M4_MIN" "$M4_MEDIAN" "$M4_MAX" "$M4_STDDEV"
        emit_metric "M5" "ms/file" ""  "$M5_MIN" "$M5_MEDIAN" "$M5_MAX" "$M5_STDDEV"
        echo "  }"
        echo "}"
    } > "$JSON_PATH"
    [[ $QUIET -eq 0 ]] && echo "JSON dump       : $JSON_PATH"
fi

[[ $QUIET -eq 0 ]] && echo "================================================================"
exit 0
