# Appendix A Measurement Protocols and Configuration

> This appendix collects the "operational details" used in the main text that would interrupt the narrative: step-by-step instructions for the three protocols, config examples for the main tables, toolchain usage, and counter interpretation. All data in Chapter 6 was produced by these fixed procedures, guaranteeing reproducibility.

## A.1 Operational Details of the Three-Protocol Measurements

The following fio parameters are shared on all platforms:
`--direct=1 --ioengine=libaio --iodepth=32 --numjobs=1`.

### A.1.1 P1 Drain State (steady-state)

Purpose: fill the NVMe SLC band, then measure TLC steady-state; reproducible and free of SLC transient interference.
The drain volume and the measurement volume **can be separate** — the key to the drain state is that "the SLC is exhausted," so first fill the SLC with the drain volume (write ≥64 G, then discard), then create the measurement volume, reset counters, and measure (the main table uses a 20 G volume for S4 and a 100 G volume for the stacked-disk table; the volume capacity only needs to accommodate the measurement writes, and the P1 measurement write is always 16 G, so the measurement volume is smaller and does not need to carry the drained amount).

```bash
# 1) Drain volume (capacity ≥ drained amount): first write ≥64 G (discarded) to fill the SLC
dmsetup create tv_drain --table "0 <sectors> tieredvol /etc/tieredvol/tv_drain.conf"
fio --name=drain --filename=/dev/mapper/tv_drain --rw=write --bs=1M --size=64G \
    --direct=1 --ioengine=libaio --iodepth=32
dmsetup remove tv_drain
# 2) Measurement volume: create volume → reset counters → write 16 G (P1 data source)
dmsetup create tv_s4 --table "0 <sectors> tieredvol /etc/tieredvol/tv_s4.conf"
fio --name=meas --filename=/dev/mapper/tv_s4 --rw=write --bs=1M --size=16G \
    --direct=1 --ioengine=libaio --iodepth=32
# 3) Verify distribution
dmsetup status tv_s4
# 4) Read 16 G
fio --name=read --filename=/dev/mapper/tv_s4 --rw=read --bs=1M --size=16G \
    --direct=1 --ioengine=libaio --iodepth=32
```

### A.1.2 P2 Cold State (SLC-fresh)

Purpose: the **maximum** value when data lands in the SLC band (fast-disk-dominant scenario); **not reproducible**, used only for qualitative comparison (e.g., the auto-weight ladder).

```bash
# Reboot (or wait ≥ a few minutes for the SLC to fully recharge), then directly run a short-write measurement
fio --name=meas --filename=/dev/mapper/tv_xx --rw=write --bs=1M --size=8G \
    --direct=1 --ioengine=libaio --iodepth=32
```

### A.1.3 P3 Cold State + 60 s Idle

Purpose: a 60 s idle gap between rounds lets the P3 Plus's SLC recharge, making the cold-state short write **reproducible**; the main table (S1–S3/MIR) uses this protocol.

```bash
for size in 8 8 8; do
    fio --name=meas --filename=/dev/mapper/tv_xx --rw=write --bs=1M \
        --size=${size}G --direct=1 --ioengine=libaio --iodepth=32
    sleep 60   # SLC recharge idle
done
# Take the median of three runs
```

### A.1.4 4 K Small Writes and WC Comparison

4 K (`< chunk_size`) small bios go through the `-EAGAIN` branch and **bypass WC** (§4.2), so a 4 K measurement is the small-write path with "WC off"; to measure the value of WC coalescing you need to toggle `wc_enabled` for comparison:

```bash
# (a) WC coalescing comparison (W1–W4, wc_suite.sh; wc_enabled=1 vs 0)
echo Y | sudo tee /sys/module/tieredvol/parameters/wc_enabled   # or N
fio --name=wc --filename=/dev/mapper/tv_xx --rw=write --bs=4K --size=1G \
    --iodepth=1 --direct=1 --ioengine=libaio
# Final build tv_s2: wc=on 4K 612 MiB/s; wc=off 4K 500 MiB/s (14 before the fix, see §6.5)

# (b) 4 K random comparison (§6.4.2 Table 6.12, B@x4): 4 K bypasses WC, the cost is in stripe splitting
fio --name=rnd --filename=/dev/mapper/tv_xx --rw=randwrite --bs=4K --size=8G \
    --direct=1 --ioengine=libaio --iodepth=32 --numjobs=1

# (c) 4 K small write vs LVM (§6.4.1, 8/13 old topology B@x1, 2 G): TieredVol 511 vs LVM 676
fio --name=sq4k --filename=/dev/mapper/tv_xx --rw=write --bs=4K --size=2G \
    --direct=1 --ioengine=libaio --iodepth=32
```

> The 4 K "small-write win/loss" conclusion depends on the test type: **sequential 4 K small writes (WC off bypass)** are ~1.32x faster on LVM under the old topology B@x1 (§6.4.1); **random 4 K** is +16% on TieredVol under B@x4 (§6.4.2); with WC on, 4 K writes are first coalesced into large writes and then submitted (self-comparison 612 vs 500 MiB/s, §6.5), and once coalesced they take the large-block path and are not compared as small writes.

## A.2 Main-Table Config Examples (B@x4 + D Topology)
> Disks are specified by **by-id**; the weights are DMI-aware weights (§3.3.3). Actual by-id values depend on the system, represented here by placeholders. sectors are obtained with `blockdev --getsz <dev>`.

### A.2.1 `tv_s2.conf` (A+B, weights 37:27, stripe 64 MB)

```ini
chunk_size = 1048576
segment.0.disks = /dev/disk/by-id/<A>, /dev/disk/by-id/<B>
segment.0.weights = 37, 27
segment.0.logical_begin = 0
segment.0.logical_end = <sectors_A_B_sizes>
```

### A.2.2 `tv_s3.conf` (A+B+C, weights 64:30:10, stripe 104 MB)

```ini
chunk_size = 1048576
segment.0.disks = /dev/disk/by-id/<A>, /dev/disk/by-id/<B>, /dev/disk/by-id/<C>
segment.0.weights = 64, 30, 10
segment.0.logical_begin = 0
segment.0.logical_end = <sectors_A_B_C_sizes>
```

### A.2.3 `tv_s4.conf` (A+B+C+D, weights 64:27:9:4, stripe 104 MB)

```ini
chunk_size = 1048576
segment.0.disks = /dev/disk/by-id/<A>, /dev/disk/by-id/<B>, /dev/disk/by-id/<C>, /dev/disk/by-id/<D>
segment.0.weights = 64, 27, 9, 4
segment.0.logical_begin = 0
segment.0.logical_end = <sectors_A_B_C_D_sizes>
```

### A.2.4 `tv_mir.conf` (A+B → mirror C, weights 37:27)

```ini
chunk_size = 1048576
segment.0.disks = /dev/disk/by-id/<A>, /dev/disk/by-id/<B>
segment.0.weights = 37, 27
segment.0.mirror_disk = <C>
segment.0.logical_begin = 0
segment.0.logical_end = <sectors_A_B_sizes>
```

## A.3 Toolchain Usage (L4 of Chapter 5 §5.8)

**Table A.1 Toolchain Usage**

| Tool | Usage | Output |
|------|------|------|
| `scripts/raw_solo.sh <dev>…` | measure 8 G sequential write per disk | per-disk solo (drain state/cold state) |
| `scripts/auto_weight.sh` | brute-force enumeration from solos (base 2..40, ±1, cap 128) | near-optimal weight vectors |
| `scripts/stack_retest.sh <conf>` | three-protocol measurement + counter verification | throughput + distribution comparison |
| `scripts/final_s4.sh` | final P1 drain-state measurement of S4; record one point per 1 GB during the drain phase (the F12 curve data source is the 60 s-recharge protocol, see §6.1.2) | main-table S4 data + F12 flat-curve CSV (`docs/data/slc_curve_*.txt`) |
| `scripts/borrow_verify.sh` | slow-disk degradation + 4 G verify + reload | borrow durability and recovery |
| `scripts/wc_suite.sh` | `wc_enabled` 1/0 comparison (4 K coalescing) | WC 4K improvement (612 vs 500 MiB/s) |
| `scripts/rebuild_min.sh` | minimal rebuild procedure | rebuild progress and recovery |
| `scripts/multi_vol_suite.sh` / `shared_ctl.sh` / `disjoint_suite.sh` | multi-volume concurrency/shared disks/disjoint disks | performance isolation and resource contention |
| `scripts/install_boot.sh` | automatic loading at boot | boot sequence |

## A.4 Counter Interpretation (`dmsetup status`)

Example output (after writing 16 G to volume tv_s2):

```
0 33554432 tieredvol
    w=37,27 c=1048576
    disk0: wr=9472/0x250000000 rd=0/0
    disk1: wr=6912/0x1B0000000 rd=0/0
    err=0 borrow=0 mirror_wr=0 mirror_rd=0 mirror_err=0
```

Interpretation rules:

- `wr=<ops>/<bytes>`: `ops` is the number of completed sub-bios and `bytes` is the cumulative byte count (after the 16 G write, disk0 = 9472 ops / 9.25 GiB and disk1 = 6912 ops / 6.75 GiB, a ratio of exactly 37:27); the remainder chunks fall on the front disks, which is expected (see §6.2.1).
- `err` must be 0 (integrity criterion); a non-zero value means a MISS/give-up/write-error event and requires investigation.
- `borrow`/`mirror_wr` and other counters are used to confirm triggering in the targeted tests (§6.5).

## A.5 Installation and Loading

```bash
# Build (kernel module; L1/L2 tests need no kernel)
make            # Produces tieredvol.ko
make test       # test_map + test_stripe_kernel (user space)
# Install
sudo insmod tieredvol.ko          # or copy to /lib/modules/... and use modprobe
# Auto-load at boot (scripts/install_boot.sh)
sudo cp tieredvol.ko /lib/modules/$(uname -r)/kernel/drivers/md/
sudo depmod -a
echo "tieredvol" | sudo tee /etc/modules-load.d/tieredvol.conf
# Create volume (config see §A.2)
sudo dmsetup create tv_s4 --table "0 <sectors> tieredvol /etc/tieredvol/tv_s4.conf"
# Filesystem
sudo mkfs.ext4 /dev/mapper/tv_s4 && sudo mount /dev/mapper/tv_s4 /mnt/tv
```

## A.6 Failure Drill (Rebuild / Bad-Drive Handling)

**Trigger rebuild**:

```bash
sudo dmsetup message tv_s4 0 rebuild         # Rebuild mirror from static mapping
dmsetup status tv_s4                          # Watch mirror_wr/progress counters
```

**Bad-drive / bad-region handling**:

```bash
# Check bad regions (badmap_<disk>=a-b,c in config)
cat /etc/tieredvol/tv_s4.conf | grep badmap
# Bad-region rebuild (read primary → write mirror, skipping bad blocks)
sudo dmsetup message tv_s4 0 rebuild_badmap
# Confirm no-hang and normal counters
dmsetup status tv_s4
```

**WC power-loss risk countermeasure**: for strict durability, disable WC before creating the volume

```bash
echo N | sudo tee /sys/module/tieredvol/parameters/wc_enabled
```

**Borrow verification (manual version of borrow_verify.sh)**: create slow-disk high load → confirm the `borrow` counter rises → `dmsetup remove` + recreate → confirm `.borrow` loads and data is readable.

## A.7 Measurement Pitfalls (Lessons from Being Fooled by Data)

1. **fio creates an ordinary file for a nonexistent `/dev/mapper/<name>`**: if `dmsetup ls` shows the device does not exist, fio creates a file of the same name on disk — giving fake reads (~5.5 GB/s) or fake ENOSPC. **Run `dmsetup ls` to confirm the device and `chmod 666` first**, then trust the fio numbers.
2. **`dmsetup message`'s result buffer is not printed**: always read counters/errors via `/sys/kernel/tieredvol/status`; it only reflects `tv_active_ctx` (the volume of the last ctr), so when multiple volumes coexist, verify per-disk counters instead via the write-sector increments in `/proc/diskstats`.
3. **Multi-line tables cannot use the `echo pw | sudo -S` prefix for `dmsetup create`** (stdin is consumed by sudo and the table ends up only half-sized) — first cache privileges with `sudo -S -v`, then run `sudo` directly; `dd` read from a pipe only transfers 64 KB (the pipe buffer), so use a file for large data.
4. **Do not `pkill -9` deep-queue direct I/O**: after SIGKILLing two 1M/d32 libaio fio jobs on 8/14, the AHCI/SATA controller was wedged (B85, Appendix B.7) — always fix a `--runtime` so that fio ends naturally.
