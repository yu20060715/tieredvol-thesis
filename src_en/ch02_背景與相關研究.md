# Chapter 2 Background and Related Work

> **Chapter guide:** §2.1 establishes the technical background of the Linux storage stack and dm; §2.2 compares existing dm targets;
> §2.3 classifies heterogeneous/tiered storage approaches; §2.4 reviews performance models and dynamic-balancing research; §2.5 positions this thesis;
> §2.6 lists the references. The task of this chapter is to give the "choices" in Chapter 3 a sound basis.

## 2.1 The Linux Storage Stack

### 2.1.1 I/O Path Overview

The Linux I/O path, from top to bottom, is:

```
application (read/write)
  └─ VFS (virtual file system, inode/dentry cache)
      └─ file system (ext4 / xfs / btrfs …) → after mapping file logical blocks, issues struct bio
          └─ generic block layer (block_device, bio, request_queue, bio set)
              └─ I/O scheduler (mq-deadline, bfq, none — mostly none under multi-queue)
                  └─ device driver (nvme / ahci / virtio_blk …)
                      └─ physical device
```

The file system is responsible for translating "file → logical block"; the **block layer** queues logical-block
`bio`s into the `request_queue`; the device driver ultimately delivers them to the hardware. In the middle of this path,
there exists a stackable software layer — **Device Mapper (dm)** — that lets users stack "logical devices" on top of
"one or more physical (or virtual) devices," presenting a single block device to the layers above [1].

![Figure F2 The Linux storage stack and the position of Device Mapper (figs/F2_stack_en.svg)](figs/F2_stack_en.svg)

> **Figure F2 caption:** TieredVol resides in the dm layer below the generic block layer, splitting the upper-layer bio into
> per-disk sub-bios according to the weights and sending them to the lower-layer drivers (§3.2.6); dm's remapping and io_hints mechanisms are
> the interface prerequisites for achieving a lock-free, O(1), deterministic mapping (§3.2.5, §4.4).

### 2.1.2 The bio Model

The upper layer carries the information of one I/O operation in a `struct bio`: the starting logical sector (`bi_iter.bi_sector`),
the direction (`bio_data_dir()`: READ/WRITE), the length (`bi_iter.bi_size`, in bytes),
and the page segments. Upon receiving a bio, the dm target's `map()` has two categories of choices [6]:

1. **Rewrite and forward**: modify `bi_bdev` (the target device) and `bi_sector` (the offset), return
   `DM_MAPIO_REMAPPED`, and let dm core submit it;
2. **Handle itself**: clone into multiple sub-bios submitted in parallel, buffer, or complete directly, returning
   `DM_MAPIO_SUBMITTED`.

The typical requirement for a striping target is "one bio spanning multiple disks": it may split itself (parallel write path),
or use `dm_accept_partial_bio()` to hand the "portion that fits within the current disk region" back to dm core, which
re-invokes `map()` on the remainder (the cross-disk split is mainly borne by dm).

### 2.1.3 dm Target Lifecycle and Callbacks

A dm target implements the following core callbacks (`struct target_type`):

**Table 2.1.** dm target core callbacks

| Callback | Timing | Responsibility |
|------|------|------|
| `ctr()` | `dmsetup create` | Parse parameters, initialize data structures, set `io_hints` and `max_io_len` |
| `map()` | Each arriving bio | Decide which disk and offset to forward to (hot path, must be fastest) |
| `end_io()` | bio completion | Statistics, error handling, DEGRADED marking |
| `status()` | `dmsetup status` | Output weights, counters, status |
| `message()` | `dmsetup message` | Runtime commands (switch policy, trigger rebuild, query mirror) |
| `dtr()` | `dmsetup remove` | Release resources, persist state |

In addition, `ctr()` can use `dm_set_target_max_io_len()` to limit the maximum bio size entering `map()`
(a striping target sets it to one stripe length), and through `io_hints` informs the upper layer of the recommended
`chunk_sectors`, `io_min`, and `io_opt`, so that the file system issues large aligned I/O.

## 2.2 Existing Device Mapper Targets

Comparison of the targets in the dm ecosystem most directly relevant to this thesis:

**Table 2.2.** Comparison of existing dm targets

| target | Behavior | Heterogeneous-disk problem |
|--------|------|-----------|
| `linear` | Multiple disks linearly concatenated into one contiguous large volume [3] | Does not distribute I/O; a single bio lands on only one disk, leaving other disks idle |
| `striped` | Equal-weight striping: fixed chunks distributed round-robin to each disk in order [2] | **Assumes all disks are equally fast**; under heterogeneous disks the slowest disk is the bottleneck and fast disks are held back |
| `mirror` | Synchronous mirroring (RAID1): writes replicated, reads pick either | Pursues reliability; no weights, no performance awareness |
| `raid` | Multiple RAID levels (0/1/5/6/10) [5] | Striping portion is the same as `striped`; equal-weight assumption |
| `cache` | Two-tier cache of fast SSD + slow HDD [4] | Only fast/slow two tiers; no multi-disk weight distribution; depends on hit ratio |
| `snapshot`/`thin` | Snapshots, thin provisioning | Data protection/provisioning, not performance distribution |

**Key observation**: `striped` (sharing its origin with hardware RAID0) is the target most directly related to the heterogeneous-disk problem,
but it fixes the weights at `1:1:…:1`. TieredVol in this thesis is a generalization of `striped` — it allows
**different weights per disk**, so that the allocation ratio matches the actual performance of each disk while preserving striping's parallelism advantage,
and on top of that adds mirroring and fault tolerance (the capabilities of `mirror`/`raid`) and dynamic balancing (a new mechanism).

## 2.3 Heterogeneous and Tiered Storage Approaches

### 2.3.1 Hardware Layer

- **Hardware RAID controllers**: RAID 0 (striping) and RAID 5/6/10 are all based on equal-weight striping,
  assuming disk arrays of identical type and speed; the controllers are expensive and lack weight awareness for "mixing heterogeneous disks."
- **Enterprise storage (SAN/NAS)**: e.g., NetApp FlexVol/Tiered Storage, Dell Storage Spaces
  (Storage Spaces provides mirror/parity; some versions have tiering). These are mostly closed-source, enterprise-grade,
  and lack open in-kernel implementations and academic reproducibility.
- **The academic paradigm of tiered storage — AutoRAID**: HP's AutoRAID ([11]) automatically tiers
  data between a "fast disk layer (mirrored) and a slow disk layer (RAID5)" within a disk array. It is the
  academic origin of this thesis's "two-tier cache family": in essence it is **hot-data placement**, not multi-disk weighted parallelism.

### 2.3.2 Software Layer

- **Linux MD (mdraid)**: analogous to dm `striped`; stripes with equal weights; RAID5/6 divide work equally.
- **dm-cache**: uses SSD as the fast disk and HDD as the slow disk; the cache hit ratio determines effectiveness; in essence it is
  "hot-data placement," not "parallel distribution" [4].
- **bcache**: an independent implementation functionally equivalent to dm-cache (author Kent Overstreet) [7]; likewise a two-tier cache,
  and it does not handle multi-disk parallel weights.
- **flashcache / Intel CAS**: industrial implementations that use SSDs as caches at the block layer
  (Facebook flashcache [14], Intel Cache Acceleration Software), also belonging to the two-tier cache family;
  flashcache itself is a dm target and can be regarded as a precedent for "doing SSD caching inside dm."
- **ZFS (OpenZFS)**: combines disks via vdev striping (RAIDZ/mirroring) [8]; L2ARC uses SSDs for read caching.
  ZFS likewise has no weight awareness for heterogeneous vdevs; tiering relies on cache hits and allocation policies rather than pure throughput optimization.
- **LVM cache / in-kernel zram**: LVM provides a cache tool (fast/slow two tiers) [9]; zram uses memory compression
  as a cache — both belong to the two-tier cache family.

### 2.3.3 Classification Summary

Existing approaches can be classified into two broad categories:

**Table 2.3.** Classification of heterogeneous/tiered storage approaches

| Category | Representatives | Goal | Heterogeneous-disk handling |
|------|------|------|-----------|
| Striping (parallel throughput) | RAID0, dm-striped, MD, ZFS vdev | Let multiple disks work in parallel and multiply throughput | **Equal-weight assumption; loses fidelity under heterogeneity** |
| Tiered caching (hot-data placement) | dm-cache, bcache, ZFS L2ARC, LVM cache | Put hot data on the fast disk | Only fast/slow two tiers; depends on hit ratio |

TieredVol is a **weighted generalization** of the first category: it does not move data between "fast/slow," but instead lets **every write be
distributed in parallel across all disks according to the weights**, fundamentally avoiding a slow disk alone bearing entire write streams. For scenarios with "large performance differences,"
weighted striping utilizes the aggregate bandwidth of all disks more directly than "equal-weight striping" or "two-tier caching."

## 2.4 Related Performance Models and Work

### 2.4.1 The Bottleneck-Disk Model

The upper bound of parallel write throughput on heterogeneous disks can be described by the "bottleneck-disk" model: given a weight vector W, total weight ΣW,
and each disk's sequential write rate soloᵢ, the theoretical total throughput T is limited by the **disk that saturates first**:

> **T(W) = minᵢ ( soloᵢ × ΣW / wᵢ )**　　　… (2.1)

Intuition: disk i receives a fraction wᵢ/ΣW of the total data; if the total throughput is T, disk i bears T×wᵢ/ΣW, which must not exceed soloᵢ,
hence `T ≤ soloᵢ×ΣW/wᵢ` holds for all i, and the bottleneck is the one with the smallest value. When the weights are proportional to the solo rates
(wᵢ ∝ soloᵢ), all terms are equal and `T = Σsoloᵢ`, reaching the theoretical upper bound. Chapter 3, §3.3 gives the proof.

This model is consistent with the classical "system bottleneck/resource queuing" view: the total throughput of a multi-resource parallel system is limited by the tightest resource
(similar to `min-plus` aggregation; also consistent with the Gray & Shenoy rule of thumb that "throughput is limited by the slowest resource" [13]).
The discussion of the throughput upper bound of RAID striping traces back to the motivation of the RAID foundation paper [12] for striping's
"parallel throughput." This thesis's contribution is to bring this down to **measurable weight allocation for heterogeneous disks**,
and to add corrections for two practical disturbance factors:

1. **Shared upstream bus (DMI)**: disks attached through the southbridge share upstream bandwidth; each disk's "perceived bottleneck" holds, but the
   "shared-resource bottleneck" appears earlier → DMI-aware weights (§3.3.3).
2. **SLC cache transient**: short NVMe writes land in the SLC region; solo measurements and short-write results drift with the cache state →
   steady-state drain measurement protocol (§6.1.2).

### 2.4.2 Related Work on Striping and Dynamic Balancing

- The degradation of **equal-weight striping** (the RAID0 family) under heterogeneous disks has broad industrial consensus, but most solutions are "replace the slow disk"
  or "partition into groups," and open weighted targets are rare.
- **Dynamic disk selection** (picking the idlest disk on the fly based on load/EMA) seems intuitively optimal, but it destroys address determinism:
  the same logical address lands on different disks at different times, making address consistency across cache/snapshot/reboot hard to maintain.
  This thesis once implemented an EMA three-factor adaptive policy and measured imbalance (−44%), confirming that path is infeasible,
  and instead adopted "**static layout + exception-based borrowing**" (§4.1): the normal path keeps determinism, and only whole-block writes under high load on slow disks
  undergo controlled offload, achieving both determinism and dynamic balancing.

## 2.5 Positioning of This Work

**Table 2.4.** Positioning comparison between this thesis and existing approaches

| Aspect | Existing approaches | TieredVol |
|------|----------|-----------|
| Allocation unit | Equal-weight chunk | **Weighted chunk** |
| Mapping | Division/table lookup | **O(1) table-free arithmetic mapping (deterministic)** |
| Performance awareness | None | **Bottleneck model (2.1) + auto_weight** |
| Shared upstream bus | Not handled | **DMI-aware weights** |
| Dynamic balancing | None (or dynamic disk selection breaking determinism) | **weight borrowing (exception on a static layout)** |
| Fault tolerance | Separate targets (mirror/raid) | **Built-in mirror/rebuild/badmap** |
| Verification | Benchmark testing | **Four-layer test architecture** |

This thesis fills the gap of "weighted, performance-aware, fault-tolerant" heterogeneous-disk striping dm targets,
and validates the model and implementation with complete measurements on a real heterogeneous platform (B85 + 4 disks).

## Chapter Summary

Chapter 2 completed the background presentation: the Linux storage stack and the Device Mapper framework (§2.1–2.2), a comparison of existing
stripe/tier/mirror targets (§2.3), related performance models and measurement literature (§2.4), and the positioning of this thesis
(§2.5). Chapters 3 through 5 will present the design and implementation in sequence, and Chapter 6 answers
the model claims of §2.4 with measurements on this platform.

## 2.6 References

[1] The Linux Kernel Documentation — Device Mapper (online documentation).
    https://www.kernel.org/doc/html/latest/admin-guide/device-mapper/index.html
[2] The Linux Kernel Documentation — dm-striped (online documentation).
    https://www.kernel.org/doc/html/latest/admin-guide/device-mapper/striped.html
[3] The Linux Kernel Documentation — dm-linear (online documentation).
    https://www.kernel.org/doc/html/latest/admin-guide/device-mapper/linear.html
[4] The Linux Kernel Documentation — dm-cache (online documentation).
    https://www.kernel.org/doc/html/latest/admin-guide/device-mapper/cache.html
[5] The Linux Kernel Documentation — dm-raid: MD RAID over DM (online documentation).
    https://www.kernel.org/doc/html/latest/admin-guide/device-mapper/raid.html
[6] The Linux Kernel — block layer and bio core source code: `block/bio.c`,
    `include/linux/bio.h`, `include/linux/blk_types.h` (kernel v5.x sources).
[7] Overstreet, K. — bcache: A Linux block-layer cache (project documentation).
    https://bcache.evilpiepirate.org/
[8] OpenZFS — vdev, RAIDZ, and L2ARC documentation (project documentation).
    https://openzfs.org/wiki/Main_Page
[9] LVM2 — Linux Logical Volume Manager (project documentation).
    https://sourceware.org/lvm2/
[10] Axboe, J. — Efficient I/O with io_uring (vendor technical whitepaper).
     https://kernel.dk/io_uring.pdf
[11] Wilkes, J., Golding, R., Staelin, C., Sullivan, T. — The HP AutoRAID
     Hierarchical Storage System. ACM Transactions on Computer Systems (TOCS),
     14(1):108–136, 1996.
[12] Patterson, D., Gibson, G., Katz, R. — A Case for Redundant Arrays of
     Inexpensive Disks (RAID). In Proc. ACM SIGMOD, pp. 109–116, 1988.
[13] Gray, J., Shenoy, P. — Rules of Thumb in Data Engineering.
     Microsoft Research Technical Report MSR-TR-99-100, 2000.
[14] Bohan, M. (Facebook) — flashcache: A general purpose writeback block cache
     for Linux. https://github.com/facebookarchive/flashcache

> Note: The main text cites this section's numbering as [n]. At final typesetting, the "author, year,
> source, DOI/URL" fields and formal links will be completed per the school format.
