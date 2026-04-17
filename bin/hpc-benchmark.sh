#!/bin/bash
# hpc-benchmark.sh — full HPC cluster deploy + benchmark
# Run after every significant build. Never push without this.

set -e

SSH="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i ~/.ssh/hpclab_admin"
FTRFS_KO=$(find ~/yocto/poky/build-qemu-arm64/tmp/work/qemuarm64-poky-linux/ftrfs-module/ -name "ftrfs.ko" | tail -1)
DEPLOY=~/yocto/poky/build-qemu-arm64/tmp/deploy/images/qemuarm64
MASTER_IMG=$(ls -t $DEPLOY/hpc-arm64-master-qemuarm64-*.ext4 | head -1)
COMPUTE_IMG=$(ls -t $DEPLOY/hpc-arm64-compute-qemuarm64-*.ext4 | head -1)

echo "================================================================"
echo " HPC Cluster Benchmark -- $(date)"
echo "================================================================"
echo "ftrfs.ko: $FTRFS_KO"
echo "master:   $MASTER_IMG"
echo "compute:  $COMPUTE_IMG"
echo ""

# 1. Stop VMs
echo "[1/8] Stopping VMs..."
sudo virsh destroy arm64-master 2>/dev/null || true
sudo virsh destroy arm64-compute01 2>/dev/null || true
sudo virsh destroy arm64-compute02 2>/dev/null || true
sudo virsh destroy arm64-compute03 2>/dev/null || true
sleep 3

# 2. Deploy fresh images
echo "[2/8] Deploying images..."
sudo cp $MASTER_IMG /var/lib/libvirt/images/hpc-arm64/arm64-master.ext4
for node in compute01 compute02 compute03; do
    sudo cp $COMPUTE_IMG /var/lib/libvirt/images/hpc-arm64/arm64-${node}.ext4
done

# 3. Inject ftrfs.ko
echo "[3/8] Injecting ftrfs.ko..."
sudo mount -o loop /var/lib/libvirt/images/hpc-arm64/arm64-master.ext4 /mnt/arm64-master
sudo mkdir -p /mnt/arm64-master/lib/modules/7.0.0/updates
sudo cp $FTRFS_KO /mnt/arm64-master/lib/modules/7.0.0/updates/ftrfs.ko
echo "  master: $(md5sum /mnt/arm64-master/lib/modules/7.0.0/updates/ftrfs.ko | cut -d' ' -f1)"
sudo umount /mnt/arm64-master

for node in compute01 compute02 compute03; do
    sudo mount -o loop /var/lib/libvirt/images/hpc-arm64/arm64-${node}.ext4 /mnt/arm64-master
    sudo mkdir -p /mnt/arm64-master/lib/modules/7.0.0/updates
    sudo cp $FTRFS_KO /mnt/arm64-master/lib/modules/7.0.0/updates/ftrfs.ko
    echo "arm64-${node}" | sudo tee /mnt/arm64-master/etc/hostname > /dev/null
    echo "  ${node}: $(md5sum /mnt/arm64-master/lib/modules/7.0.0/updates/ftrfs.ko | cut -d' ' -f1)"
    sudo umount /mnt/arm64-master
done

# 4. Start VMs
echo "[4/8] Starting VMs..."
sudo virsh start arm64-master
sudo virsh start arm64-compute01
sudo virsh start arm64-compute02
sudo virsh start arm64-compute03
echo "  Waiting 90s for boot..."
sleep 90

# 5. Start Slurm on master
echo "[5/8] Starting Slurm controller..."
$SSH hpcadmin@192.168.56.10 "
sudo /etc/init.d/munge start
sudo mkdir -p /var/log/slurm /var/lib/slurm
sudo chown slurm:slurm /var/log/slurm /var/lib/slurm
sudo -u slurm slurmctld
sleep 3
sinfo
"

# 6. Push slurm.conf + start slurmd on compute nodes
echo "[6/8] Starting compute nodes..."
$SSH hpcadmin@192.168.56.10 "cat /etc/slurm/slurm.conf" > /tmp/slurm.conf

for i in 11 12 13; do
    cat /tmp/slurm.conf | $SSH hpcadmin@192.168.56.${i} "
sudo /etc/init.d/munge start
sudo mkdir -p /var/log/slurm /var/lib/slurm/slurmd
sudo chown slurm:slurm /var/log/slurm /var/lib/slurm /var/lib/slurm/slurmd
sudo tee /etc/slurm/slurm.conf > /dev/null
sudo slurmd
" 2>/dev/null &
done
wait
sleep 5
$SSH hpcadmin@192.168.56.10 "sinfo -N -l"

# 7. Mount FTRFS on all nodes
echo "[7/8] Mounting FTRFS on all nodes..."
for i in 10 11 12 13; do
    $SSH hpcadmin@192.168.56.${i} "
sudo insmod /lib/modules/7.0.0/updates/ftrfs.ko 2>/dev/null || true
sudo dd if=/dev/zero of=/tmp/ftrfs.img bs=4096 count=16384 2>/dev/null
sudo mkfs.ftrfs /tmp/ftrfs.img
sudo modprobe loop
sudo losetup /dev/loop0 /tmp/ftrfs.img
sudo mount -t ftrfs /dev/loop0 /data
dmesg | grep ftrfs | grep -v 'loading out-of-tree'
" 2>/dev/null &
done
wait

# 8. Benchmark
echo ""
echo "[8/8] Running benchmark..."
echo "================================================================"
$SSH hpcadmin@192.168.56.10 "
echo '--- job submission latency ---'
time srun --nodes=1 hostname
time srun --nodes=1 hostname
time srun --nodes=1 hostname
echo '--- 3-node parallel job ---'
time srun --nodes=3 --ntasks=3 hostname
echo '--- 9-job throughput (BusyBox sh compatible) ---'
time sh -c '
srun --nodes=1 hostname &
srun --nodes=1 hostname &
srun --nodes=1 hostname &
srun --nodes=1 hostname &
srun --nodes=1 hostname &
srun --nodes=1 hostname &
srun --nodes=1 hostname &
srun --nodes=1 hostname &
srun --nodes=1 hostname &
wait
'
echo '--- FTRFS write from Slurm job ---'
srun --nodes=3 --ntasks=3 sh -c 'echo \$(hostname):\$(date) | sudo tee /data/slurm-\$(hostname).txt'
srun --nodes=3 --ntasks=3 cat /data/slurm-\$(hostname).txt
"
echo "================================================================"
echo "Benchmark complete -- $(date)"
