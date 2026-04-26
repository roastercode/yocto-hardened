#!/bin/bash
# hpc-benchmark.sh — full HPC cluster deploy + benchmark
# Run after every significant build. Never push without this.

set -e

SSH="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i ~/.ssh/hpclab_admin"
DEPLOY=~/yocto/poky/build-qemu-arm64/tmp/deploy/images/qemuarm64
RESEARCH_IMG=$DEPLOY/hpc-arm64-research-qemuarm64.squashfs
LIBVIRT_DIR=/var/lib/libvirt/images/hpc-arm64

# Cluster topology: hostname IP (must match slurm.conf and /etc/hosts in image)
NODES_ALL=("arm64-master:192.168.56.10" "arm64-compute01:192.168.56.11" "arm64-compute02:192.168.56.12" "arm64-compute03:192.168.56.13")
NODES_COMPUTE=("arm64-compute01:192.168.56.11" "arm64-compute02:192.168.56.12" "arm64-compute03:192.168.56.13")

echo "================================================================"
echo " HPC Cluster Benchmark -- $(date)"
echo "================================================================"
echo "research image: $RESEARCH_IMG"
echo "libvirt dir:    $LIBVIRT_DIR"
echo "nodes:          ${NODES_ALL[@]}"
echo ""

# 1. Stop VMs
echo "[1/7] Stopping VMs..."
for entry in "${NODES_ALL[@]}"; do
    name="${entry%%:*}"
    sudo virsh destroy "$name" 2>/dev/null || true
done
sleep 3

# 2. Deploy research image (one squashfs per VM) + ensure libvirt XML
#    points to squashfs with proper kernel cmdline (rootfstype=squashfs ro
#    + ftrfs.hostname=<name> for the in-image init script).
echo "[2/7] Deploying research image to libvirt..."
for entry in "${NODES_ALL[@]}"; do
    name="${entry%%:*}"
    sudo cp "$RESEARCH_IMG" "$LIBVIRT_DIR/${name}.squashfs"
    sudo chown qemu:qemu "$LIBVIRT_DIR/${name}.squashfs"

    # Patch the libvirt XML if not already pointing at squashfs.
    # Idempotent: only writes if a change is needed.
    XMLTMP=$(mktemp)
    sudo virsh dumpxml --inactive "$name" > "$XMLTMP" 2>/dev/null
    if grep -q "${name}.ext4" "$XMLTMP"; then
        sed -i "s|${name}.ext4|${name}.squashfs|g" "$XMLTMP"
        sed -i "s|<cmdline>root=/dev/vda rw mem=512M|<cmdline>root=/dev/vda ro rootfstype=squashfs ftrfs.hostname=${name} mem=512M|" "$XMLTMP"
        sudo virsh define "$XMLTMP" >/dev/null
        echo "  ${name}: XML updated to squashfs + ftrfs.hostname=${name}"
    else
        echo "  ${name}: XML already configured"
    fi
    rm -f "$XMLTMP"
done

# 3. Start VMs
echo "[3/7] Starting VMs..."
for entry in "${NODES_ALL[@]}"; do
    name="${entry%%:*}"
    sudo virsh start "$name" >/dev/null
done
echo "  Waiting 60s for boot..."
sleep 60

# 4. Per-node post-boot setup: hostname (cmdline-driven, manual fallback),
#    overlay /etc (since the Yocto preinit wrapper does not run reliably
#    on this kernel boot path), and FTRFS partition on /dev/vdb.
echo "[4/7] Setting hostname + overlay /etc + FTRFS on all nodes..."
for entry in "${NODES_ALL[@]}"; do
    name="${entry%%:*}"
    ip="${entry##*:}"
    $SSH hpcadmin@${ip} "sudo bash -s" << REMOTE_SETUP_EOF &
set -e

# Apply hostname (idempotent)
CURRENT=\$(hostname)
if [ "\$CURRENT" != "${name}" ]; then
    hostname "${name}"
fi

# Mount overlay /etc if not already mounted (so we can write to /etc/hostname,
# /etc/slurm/slurm.conf, etc.). Skipped if /etc is already an overlay.
if ! mount | grep -q "overlay on /etc type overlay"; then
    mkdir -p /run/overlay-etc/upper /run/overlay-etc/work /run/overlay-etc/lower
    mount -o bind,ro /etc /run/overlay-etc/lower 2>/dev/null || true
    mount -n -t overlay \\
        -o upperdir=/run/overlay-etc/upper \\
        -o lowerdir=/etc \\
        -o workdir=/run/overlay-etc/work \\
        -o index=off,xino=off,redirect_dir=off,metacopy=off \\
        overlay /etc
fi

echo "${name}" > /etc/hostname

# Format and mount FTRFS on /dev/vdb (real partition, not loopback)
mkdir -p /data
if ! mount | grep -q "/dev/vdb on /data"; then
    mkfs.ftrfs /dev/vdb >/dev/null
    mount -t ftrfs /dev/vdb /data
fi
REMOTE_SETUP_EOF
done
wait

# 5. Start munge + slurmctld on master
echo "[5/7] Starting munge + slurmctld on master..."
$SSH hpcadmin@192.168.56.10 "sudo bash -s" << 'MASTER_EOF'
set -e
mkdir -p /var/log/slurm /var/lib/slurm
chown slurm:slurm /var/log/slurm /var/lib/slurm
/etc/init.d/munge start >/dev/null
sudo -u slurm slurmctld
sleep 3
sinfo
MASTER_EOF

# 6. Push slurm.conf + start munge + slurmd on compute nodes.
#    Use scp + ssh in two steps because piping content into ssh while
#    also using a heredoc creates stdin conflict (the heredoc wins,
#    the piped content is lost).
echo "[6/7] Starting compute nodes..."
$SSH hpcadmin@192.168.56.10 "cat /etc/slurm/slurm.conf" > /tmp/slurm.conf

SCP="scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i ~/.ssh/hpclab_admin"

for entry in "${NODES_COMPUTE[@]}"; do
    name="${entry%%:*}"
    ip="${entry##*:}"
    # Step 1: copy slurm.conf to the compute node's /tmp
    $SCP /tmp/slurm.conf hpcadmin@${ip}:/tmp/slurm.conf >/dev/null
    # Step 2: ssh + heredoc to install conf and start slurmd
    $SSH hpcadmin@${ip} "sudo bash -s" << 'COMPUTE_EOF' &
set -e
mkdir -p /var/log/slurm /var/lib/slurm/slurmd
chown slurm:slurm /var/log/slurm /var/lib/slurm /var/lib/slurm/slurmd
/etc/init.d/munge start >/dev/null
cp /tmp/slurm.conf /etc/slurm/slurm.conf
slurmd
COMPUTE_EOF
done
wait
sleep 5
$SSH hpcadmin@192.168.56.10 "sinfo -N -l"

# 7. (placeholder, was FTRFS mount; now done in phase 4 with /dev/vdb)
echo "[7/7] FTRFS already mounted on /dev/vdb in phase 4 (real partition)."

# 8. Slurm benchmark (capture + ASCII table)
#
# Mesures capturées via /proc/uptime (BusyBox-compatible) côté master.
# Toute la sortie Slurm est redirigée vers /dev/null pendant la mesure;
# seule une ligne RESULTS=... est exfiltrée vers le host pour parsing.
echo ""
echo "[8/8] Running Slurm benchmark on master (4 setup phases + Slurm + FS bench)..."

SLURM_RAW=$($SSH hpcadmin@192.168.56.10 "sh -s" << 'REMOTE_EOF'
set -u

ts() { read u _ < /proc/uptime; echo $u; }
dt() { awk "BEGIN{printf \"%.3f\", $2 - $1}" $1 $2; }

# S1 -- job submission latency (1 node, 3 runs)
S1_VALS=""
for i in 1 2 3; do
    T0=$(ts)
    srun --nodes=1 hostname </dev/null >/dev/null 2>&1
    T1=$(ts)
    S1_VALS="$S1_VALS$(dt $T0 $T1) "
done

# S2 -- 3-node parallel job
T0=$(ts)
srun --nodes=3 --ntasks=3 hostname </dev/null >/dev/null 2>&1
T1=$(ts)
S2_VAL=$(dt $T0 $T1)

# S3 -- 9-job throughput (BusyBox sh compatible)
T0=$(ts)
sh -c '
srun --nodes=1 hostname </dev/null >/dev/null 2>&1 &
srun --nodes=1 hostname </dev/null >/dev/null 2>&1 &
srun --nodes=1 hostname </dev/null >/dev/null 2>&1 &
srun --nodes=1 hostname </dev/null >/dev/null 2>&1 &
srun --nodes=1 hostname </dev/null >/dev/null 2>&1 &
srun --nodes=1 hostname </dev/null >/dev/null 2>&1 &
srun --nodes=1 hostname </dev/null >/dev/null 2>&1 &
srun --nodes=1 hostname </dev/null >/dev/null 2>&1 &
srun --nodes=1 hostname </dev/null >/dev/null 2>&1 &
wait
'
T1=$(ts)
S3_VAL=$(dt $T0 $T1)

# S4 -- FTRFS write from Slurm job (functional, PASS/FAIL)
S4_STATUS=PASS
srun --nodes=3 --ntasks=3 sh -c 'echo $(hostname):$(date) | sudo tee /data/slurm-$(hostname).txt >/dev/null' </dev/null >/dev/null 2>&1 || S4_STATUS=FAIL
srun --nodes=3 --ntasks=3 sh -c 'cat /data/slurm-$(hostname).txt' </dev/null >/dev/null 2>&1 || S4_STATUS=FAIL

# Single line of results, parsed by host
echo "RESULTS|$S1_VALS|$S2_VAL|$S3_VAL|$S4_STATUS"
REMOTE_EOF
)

# Parse RESULTS line
RESULTS_LINE=$(echo "$SLURM_RAW" | grep '^RESULTS|' | head -1)
if [ -z "$RESULTS_LINE" ]; then
    echo "ERROR: Slurm benchmark did not return results line" >&2
    echo "Raw output:" >&2
    echo "$SLURM_RAW" >&2
    exit 1
fi

S1_VALS=$(echo "$RESULTS_LINE" | cut -d'|' -f2)
S2_VAL=$(echo "$RESULTS_LINE" | cut -d'|' -f3)
S3_VAL=$(echo "$RESULTS_LINE" | cut -d'|' -f4)
S4_STATUS=$(echo "$RESULTS_LINE" | cut -d'|' -f5)

# Compute min/median/max for S1
S1_STATS=$(echo "$S1_VALS" | awk '{
    n = NF
    for (i = 1; i <= n; i++) v[i] = $i
    asort(v)
    mn = v[1]; mx = v[n]
    if (n % 2) md = v[(n+1)/2]
    else md = (v[n/2] + v[n/2+1]) / 2
    printf "%.3f %.3f %.3f", mn, md, mx
}')
S1_MIN=$(echo "$S1_STATS" | cut -d' ' -f1)
S1_MED=$(echo "$S1_STATS" | cut -d' ' -f2)
S1_MAX=$(echo "$S1_STATS" | cut -d' ' -f3)

# Slurm Results table
echo ""
echo "================================================================"
echo " Slurm Benchmark Results"
echo "================================================================"
printf "%-4s  %-30s %10s %10s %10s  %s\n" "ID" "Metric" "Min" "Median" "Max" "Unit"
printf "%-4s  %-30s %10s %10s %10s  %s\n" "----" "------------------------------" "----------" "----------" "----------" "--------"
printf "%-4s  %-30s %10s %10s %10s  %s\n" "S1" "Job submit latency (1 node)" "$S1_MIN" "$S1_MED" "$S1_MAX" "seconds"
printf "%-4s  %-30s %10s %10s %10s  %s\n" "S2" "Parallel job (3 nodes)" "-" "$S2_VAL" "-" "seconds"
printf "%-4s  %-30s %10s %10s %10s  %s\n" "S3" "Throughput (9 jobs)" "-" "$S3_VAL" "-" "seconds"
printf "%-4s  %-30s %10s %10s %10s  %s\n" "S4" "FTRFS write from Slurm" "-" "$S4_STATUS" "-" "-"
echo "================================================================"

# I/O benchmark (separate ASCII table produced by ftrfs-iobench.sh)
echo ""
"$(dirname "$0")"/ftrfs-iobench.sh --runs 10

echo ""
echo "================================================================"
echo "Benchmark complete -- $(date)"
echo "================================================================"
