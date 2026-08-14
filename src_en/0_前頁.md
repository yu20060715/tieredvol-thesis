# Front Matter: Abstract, Notation, and Abbreviations

## 摘要 (Chinese Abstract)

Heterogeneous storage coexistence (NVMe and SATA, fast and slow drives mixed) is the
norm in modern computer systems, yet existing striping technologies (hardware RAID 0,
Linux `dm-striped`, LVM striped) all assume equal-speed drives, so on heterogeneous
drives the slowest drive becomes the bottleneck and drags down aggregate throughput.
This thesis presents **TieredVol**——a Linux kernel (Device Mapper) heterogeneous-disk
storage system centered on **weighted striping**: the administrator assigns each drive
a weight proportional to its performance, TieredVol distributes I/O evenly across all
drives according to these weights, and a **deterministic table-free O(1) arithmetic
mapping** guarantees that the distribution is byte-exact, reproducible, and lock-free
on the hot path.

We derive a bottleneck performance model `T(W) = minᵢ(soloᵢ × ΣW/wᵢ)` and prove that
aggregate throughput equals the sum of the per-drive rates when weights are
proportional to the speed ratios; on this basis we implement the `auto_weight` tool,
which automatically finds near-optimal weights from measurement, and handles weight
correction under the shared bus (PCH DMI) (DMI-aware). On top of this, weight
borrowing (a deterministic exception path for temporarily degraded slow drives),
write coalescing, synchronous mirroring, bad-region rebuild, and concurrency
consistency are integrated into a single target.

On a real B85 heterogeneous platform (CPU-direct NVMe + PCH NVMe + two SATA SSDs)
with 1–4 drive configurations, we verify with three measurement protocols
(steady-state drain / cold / cold with idle): the model hits within ±5% in
weight-matched steady-state scenarios; auto_weight's **model bound** reaches 99.6% of
the sum of the per-drive rates (measured 93.7%, S4 deviation -5.9%), a 70.6%
improvement over equal weights. We also reveal three hardware insights of general
value to storage system design——the PCIe slot (x1/x4) makes the solo of the same NVMe
differ by 3.7×, the PCH DMI upstream bandwidth wall caps three-drive concurrent
writes at "solo_A + DMI", and NVMe SLC-cache transients produce measurement
artifacts. Throughout, `err=0` and an 8 G crc32c verification report zero errors.

**關鍵字 (Chinese keywords)**: Device Mapper, heterogeneous storage, weighted
striping, bottleneck model, deterministic mapping, storage cache

## Abstract

Heterogeneous storage coexistence (NVMe and SATA, fast and slow drives mixed) is the
norm in modern systems, yet existing striping technologies (hardware RAID 0, Linux
`dm-striped`, LVM striped) assume equal-speed drives, causing the slowest drive to
bottleneck aggregate throughput. This thesis presents **TieredVol**, a Linux kernel
(Device Mapper) heterogeneous-disk storage system centered on **weighted striping**:
the administrator assigns each drive a weight proportional to its performance, and
TieredVol distributes I/O across all drives according to these weights, backed by a
**deterministic, table-free O(1) arithmetic mapping** that is byte-exact, reproducible,
and lock-free on the hot path.

We derive a bottleneck performance model `T(W) = minᵢ(soloᵢ · ΣW/wᵢ)` and prove that
total throughput equals the sum of per-drive sequential rates when weights are
proportional to speeds. On this basis we implement the `auto_weight` tool for
near-optimal weight selection from measurement, plus a DMI-aware weight correction for
shared upstream buses (PCH DMI). Weight borrowing (a deterministic exception path for
temporarily degraded slow drives), write coalescing, synchronous mirroring, bad-region
rebuild, and concurrency consistency are integrated into a single target.

On a real B85 platform (CPU-direct NVMe + PCH NVMe + two SATA SSDs) with 1–4 drive
configurations and three measurement protocols (steady-state drain / cold SLC-fresh /
cold with idle), the model predicts within ±5% for weight-matched steady-state
configurations; auto_weight's model bound reaches 99.6% of the sum-of-solos
throughput (measured 93.7%, -5.9% on S4; 70.6% over equal weights). We also reveal
three hardware
insights of general value: the PCIe slot (x1 vs x4) changes a single NVMe's solo by
3.7×, the PCH DMI upstream wall caps three-drive writes at `solo_A + DMI`, and NVMe
SLC-cache transients produce measurement artifacts. Throughout, `err=0` and an 8 G
crc32c verify reports zero mismatches.

**Keywords**: Device Mapper, heterogeneous storage, weighted striping, bottleneck
model, deterministic mapping, storage cache

## Notation

**Table T10.** Notation

| Symbol | Meaning |
|--------|---------|
| n | number of drives |
| W = (w₁,…,wₙ) | weight vector; wᵢ is the weight of drive i (a positive integer) |
| ΣW | total weight = Σᵢ wᵢ |
| c | chunk size (fixed at 1 MB in this thesis) |
| soloᵢ | sequential write rate of drive i when it exclusively owns the interface (measured baseline) |
| T(W) | total striped-write throughput under weight vector W |
| stripe_size | length of one weight-allocation cycle = Σᵢ wᵢ × c |
| boundary[i] | cumulative boundary of the drive region within a stripe = Σ_{j<i} w_j × c |
| 𝒟 | the set of drives on the shared bus (DMI) |
| DMI_Budget | measured available DMI upstream bandwidth (~1300 MB/s) |
| block_size | borrow granularity = chunk_size/8 (1 M chunk → 128 KB) |
| P1/P2/P3 | measurement protocols: steady-state drain / cold / cold with 60 s idle |

## Abbreviations

**Table T11.** Abbreviations

| Abbreviation | Full form |
|--------------|-----------|
| dm / DM | Device Mapper |
| DMI | Direct Media Interface (southbridge upstream bus) |
| PCH | Platform Controller Hub (southbridge) |
| NVMe | Non-Volatile Memory Express |
| SATA | Serial ATA |
| SLC / TLC | Single / Triple-Level Cell |
| WC | Write Coalescing (write cache) |
| MIR | Mirror (mirrored volume) |
| RAID | Redundant Array of Independent Disks |
| LVM | Logical Volume Manager |
| bio | block I/O (kernel block I/O structure) |
| kref | kernel reference counter |
| CRC32C | Castagnoli CRC-32 checksum |
| libaio | Linux Asynchronous I/O library |
| io_uring | Linux high-performance asynchronous I/O framework |
| O(1) | constant-time complexity |
