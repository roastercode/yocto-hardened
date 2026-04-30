# HPC Cluster Benchmark Procedure

This document is the reference procedure for deploying and benchmarking
the full HPC cluster. Run this after every significant change to validate
before pushing to GitHub. **Never push without running this.**

---

## Reference benchmark script

Save as `~/bin/hpc-benchmark.sh` and run after every build.

```bash
#!/bin/bash
# hpc-benchmark.sh — full HPC cluster deploy + benchmark
# Run after every significant change. Never push without this.

set -e

SSH="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i ~/.ssh/hpclab_admin"
FTRFS_KO=$(find ~/yocto/poky/build-qemu-arm64/tmp/work/qemuarm64-poky-linux/ftrfs-module/ -name "ftrfs.ko" | tail -1)
DEPLOY=~/yocto/poky/build-qemu-arm64/tmp/deploy/images/qemuarm64
MASTER_IMG=$(ls -t $DEPLOY/hpc-arm64-master-qemuarm64-*.ext4 | head -1)
COMPUTE_IMG=$(ls -t $DEPLOY/hpc-arm64-compute-qemuarm64-*.ext4 | head -1)

echo "=== Deploying ==="
echo "ftrfs.ko: $FTRFS_KO"
echo "master:   $MASTER_IMG"
echo "compute:  $COMPUTE_IMG"

# 1. Stop VMs
sudo virsh destroy arm64-master 2>/dev/null || true
sudo virsh destroy arm64-compute01 2>/dev/null || true
sudo virsh destroy arm64-compute02 2>/dev/null || true
sudo virsh destroy arm64-compute03 2>/dev/null || true
sleep 3

# 2. Deploy fresh images
sudo cp $MASTER_IMG /var/lib/libvirt/images/hpc-arm64/arm64-master.ext4
for node in compute01 compute02 compute03; do
    sudo cp $COMPUTE_IMG /var/lib/libvirt/images/hpc-arm64/arm64-${node}.ext4
done

# 3. Inject ftrfs.ko into all nodes
sudo mount -o loop /var/lib/libvirt/images/hpc-arm64/arm64-master.ext4 /mnt/arm64-master
sudo mkdir -p /mnt/arm64-master/lib/modules/7.0.0/updates
sudo cp $FTRFS_KO /mnt/arm64-master/lib/modules/7.0.0/updates/ftrfs.ko
echo "master ftrfs.ko: $(md5sum /mnt/arm64-master/lib/modules/7.0.0/updates/ftrfs.ko | cut -d' ' -f1)"
sudo umount /mnt/arm64-master

for node in compute01 compute02 compute03; do
    sudo mount -o loop /var/lib/libvirt/images/hpc-arm64/arm64-${node}.ext4 /mnt/arm64-master
    sudo mkdir -p /mnt/arm64-master/lib/modules/7.0.0/updates
    sudo cp $FTRFS_KO /mnt/arm64-master/lib/modules/7.0.0/updates/ftrfs.ko
    echo "arm64-${node}" | sudo tee /mnt/arm64-master/etc/hostname > /dev/null
    echo "${node} ftrfs.ko: $(md5sum /mnt/arm64-master/lib/modules/7.0.0/updates/ftrfs.ko | cut -d' ' -f1)"
    sudo umount /mnt/arm64-master
done

# 4. Start VMs
sudo virsh start arm64-master
sudo virsh start arm64-compute01
sudo virsh start arm64-compute02
sudo virsh start arm64-compute03
echo "Waiting 90s for boot..."
sleep 90

# 5. Start Slurm on master
$SSH hpcadmin@192.168.56.10 "
sudo /etc/init.d/munge start
sudo mkdir -p /var/log/slurm /var/lib/slurm
sudo chown slurm:slurm /var/log/slurm /var/lib/slurm
sudo -u slurm slurmctld
sleep 3
sinfo
"

# 6. Push slurm.conf from master to compute nodes, start slurmd
$SSH hpcadmin@192.168.56.10 "cat /etc/slurm/slurm.conf" > /tmp/slurm.conf

for i in 11 12 13; do
    cat /tmp/slurm.conf | $SSH hpcadmin@192.168.56.${i} "
sudo /etc/init.d/munge start
sudo mkdir -p /var/log/slurm /var/lib/slurm/slurmd
sudo chown slurm:slurm /var/log/slurm /var/lib/slurm /var/lib/slurm/slurmd
sudo tee /etc/slurm/slurm.conf > /dev/null
sudo slurmd
" &
done
wait
sleep 5
$SSH hpcadmin@192.168.56.10 "sinfo -N -l"

# 7. Mount FTRFS on all nodes
for i in 10 11 12 13; do
    $SSH hpcadmin@192.168.56.${i} "
sudo insmod /lib/modules/7.0.0/updates/ftrfs.ko 2>/dev/null || true
sudo dd if=/dev/zero of=/tmp/ftrfs.img bs=4096 count=16384 2>/dev/null
sudo mkfs.ftrfs /tmp/ftrfs.img
sudo modprobe loop
sudo losetup /dev/loop0 /tmp/ftrfs.img
sudo mount -t ftrfs /dev/loop0 /data
dmesg | grep ftrfs | grep -v 'loading out-of-tree'
" &
done
wait

# 8. Benchmark
echo ""
echo "=== BENCHMARK RESULTS ==="
$SSH hpcadmin@192.168.56.10 "
echo '--- job submission latency ---'
time srun --nodes=1 hostname
time srun --nodes=1 hostname
time srun --nodes=1 hostname
echo '--- 3-node parallel job ---'
time srun --nodes=3 --ntasks=3 hostname
echo '--- 9-job throughput ---'
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
```

---

## Reference results (2026-04-17, arm64 QEMU kernel 7.0)

| Test | Result |
|------|--------|
| Job submission latency | ~0.25s average |
| 3-node parallel job | 0.34s |
| 9-job batch throughput | 4.37s total |
| FTRFS mount on 4 nodes | clean, zero RS errors |
| FTRFS write from Slurm | functional on all 3 compute nodes |

---

## Troubleshooting

### SSH refuses connection / asks for password

```bash
# Debug sshd on the node
sudo virsh console arm64-master
# In the VM:
/usr/sbin/sshd -d -p 2222 &
# From spartian-1:
ssh -p 2222 -i ~/.ssh/hpclab_admin -v hpcadmin@192.168.56.10
```

**Common causes:**
- `hpcadmin` shell is `/bin/bash` which does not exist → check `/etc/passwd`, must be `/bin/sh`
- `authorized_keys` missing → rebuild with `hpclab_admin.pub` in layer files
- `overlayfs-etc` resets `/etc` at boot → inject via image, not at runtime

### Slurmd "Unable to determine NodeName"

```bash
# slurm.conf on compute nodes is missing NodeName entries
# Push master's slurm.conf to compute nodes:
SSH="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i ~/.ssh/hpclab_admin"
$SSH hpcadmin@192.168.56.10 "cat /etc/slurm/slurm.conf" > /tmp/slurm.conf
for i in 11 12 13; do
    cat /tmp/slurm.conf | $SSH hpcadmin@192.168.56.${i} "sudo tee /etc/slurm/slurm.conf > /dev/null"
    $SSH hpcadmin@192.168.56.${i} "sudo slurmd"
done
```

### Munge fails to start

```bash
# munge.key missing — check:
sudo virsh console arm64-master
ls -la /etc/munge/munge.key
# Must exist, mode 0400, owned by munge
# If missing: rebuild with munge.key in layer files
```

### Nodes stuck in `unk*` state

```bash
SSH="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i ~/.ssh/hpclab_admin"
# Check slurmd log on a compute node
$SSH hpcadmin@192.168.56.11 "sudo slurmd > /tmp/slurmd.log 2>&1; sleep 1; cat /tmp/slurmd.log"
```

### BusyBox shell syntax errors

The image uses BusyBox `/bin/sh`. Bash-specific syntax is not supported:

```bash
# WRONG — bash only
for i in $(seq 1 9); do srun hostname & done; wait

# CORRECT — BusyBox compatible
sh -c '
srun --nodes=1 hostname &
srun --nodes=1 hostname &
wait
'
```
