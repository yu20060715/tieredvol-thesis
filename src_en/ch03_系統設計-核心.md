# Chapter 3 System Design (I): Architecture, Mapping, and Model

This chapter describes TieredVol's overall architecture and its mathematical core. Chapter 4
describes the advanced mechanisms and fault tolerance (borrowing, write cache, mirroring,
concurrency, management), Chapter 5 the implementation, and Chapter 6 the experimental
verification. This section proceeds in the order
"Architecture Overview (3.1) → Weighted Striping and Deterministic Mapping (3.2) → Bottleneck Model and Automatic Weights (3.3) →
Test Architecture Design (3.4)", with each section developed along "motivation → design → mathematics/algorithm → edge cases and
invariants → design trade-offs".

## 3.1 System Architecture Overview

### 3.1.1 Design Goals

As a dm target, TieredVol must simultaneously satisfy the following goals (some pull against each other and require trade-offs):

**Table 3.1** Design goals (G1–G7).

| # | Goal | Requirement |
|---|------|------|
| G1 | Determinism | The same logical address always lands on the same disk at the same position; reproducible and verifiable |
| G2 | Low hot-path cost | Mapping O(1), no shared lock, executable in constrained contexts such as hardirq |
| G3 | Performance | Overall throughput close to the bottleneck model bound (≈ Σsolo when weights match) |
| G4 | Correctness | Byte-exact distribution; `err=0`; correct read/write ordering |
| G5 | Dynamic balance | Can compensate when a slow disk temporarily degrades, without breaking G1 |
| G6 | Fault tolerance | Mirroring, rebuild, bad blocks, and concurrent-consistency hit the same target |
| G7 | Manageability | Single config source of truth, CRC verification, queryable counters |

### 3.1.2 Three-Layer Structure

TieredVol exists as a Linux Device Mapper target and, once attached, becomes a logical block device.
The overall architecture is organized into three layers:

- **Configuration layer (config / meta)**: single source of truth `/etc/tieredvol/<name>.conf`
  (INI format), describing the disk list, per-disk weights, chunk size, segment partitioning, mirror disks,
  bad-block records, and so on; at load time the core verifies integrity with CRC32C (§4.5).
- **Mapping layer (map)**: `tv_map_logical()` uses pure arithmetic to convert a logical address into
  `(disk, physical_offset)`; lock-free, stateless, O(1), safely callable from any context (hardirq,
  kthread, io_uring worker) (§3.2).
- **I/O layer**: writes go through the parallel-splitting submission path (split across disks into per-disk sub-bio) or are submitted
  directly to a single disk, with an optional write-cache (WC) buffer (§4.2); reads go through DM's remapping/split; mirroring (§4.3)
  and error handling are hooked onto the completion callback; weight borrowing (§4.1) intercepts whole-block writes on a slow disk under high load.

![Figure F3 TieredVol system architecture (figs/F3_architecture_en.svg)](figs/F3_architecture_en.svg)

> **Figure F3.** The upper half is the configuration and mapping layers (control flow, occasional); the lower half is the I/O layer (data flow,
> hot path). The counters and completion callbacks are the hooks for the Chapter 6 verification. Complete figure notes: see §4.5 and §5.7.

### 3.1.3 Core Design Philosophy

The foundation of the entire driver is a **function** from "logical address → (disk, physical address)", not a table.
This function is stateless, performs no lookups, and needs no index rebuild, so there is no shared lock on the I/O hot path. All dynamism
(slow-disk offload) is implemented as a **temporary exception** layered on top of the static layout (weight borrowing, §4.1),
**without breaking mapping determinism** (a compromise between G1 and G5). Any mechanism that would make "the same logical address land on different disks at different times"
(such as a dynamic disk-selection policy) is excluded—Chapter 2 already explained the historical lessons.

```
  ┌──────────────┐
  │  /etc/tieredvol/<name>.conf  (INI + CRC32C)
  └──────┬───────┘
         │ ctr() load, verify
  ┌──────▼───────┐
  │  meta        │   segment / weight / disk list
  └──────┬───────┘
  ┌──────▼───────┐   WRITE                     READ
  │  map()       │──► WC buffer / parallel split ──► DM remap/split
  │  tv_map_     │    (across disks → per-disk sub-bio)  │
  │  logical()   │◄── completion cb: count/error/badmark/  │
  └──────┬───────┘    mirror retry                        │
         ▼                                                │
  disk0  disk1  …  disk n-1  (+ mirror disk) ─────────────┘
```

### 3.1.4 Data Flow and Control Flow

- **Data flow (per bio)**: `map()` → (WC buffer or direct) → parallel split/single-disk forward →
  physical disk → `end_io()` completion callback (counting, error handling, mirror retry).
- **Control flow (occasional)**: `message()` (switch policy, trigger rebuild, query mirror),
  `status()` (counters), deferred work (WC timeout flush, mirror retry, rebuild
  kthread, borrow persistence).
- The counters (per-disk `wr=/rd= ops/bytes`, `err`, borrow/mirror counts) are the key interface for the
  correctness verification in Chapter 6.

## 3.2 Weighted Striping and Deterministic Mapping

### 3.2.1 Problem and Definitions

Given n disks, a weight vector W=(w₁,…,wₙ), and a chunk size c, we wish to slice the logical space into equal-length chunks
and allocate them to the disks in proportion to the weights, so that the distribution ratio of long writes exactly equals the weight ratio, and the mapping satisfies three properties:

- **P-determinism (Deterministic)**: the same logical address always lands on the same disk at the same position.
- **P-O(1)**: completed by constant-time arithmetic (no lookup, no index).
- **P-exactness (Exact)**: every logical byte belongs to exactly one disk (no holes, no overlaps).

### 3.2.2 Stripe and Segment

Within one weight-allocation cycle, each disk takes wᵢ chunks according to its weight, for a total of

```
stripe_size = Σᵢ wᵢ × c          … (3.1)
```

The logical space is sliced into equal-length stripes; within each stripe, disk 0 occupies the first w₀ chunks, disk 1 the next w₁ chunks, and so on.
In this way, for long writes across any whole number of stripes, the byte ratio received by each disk strictly equals the weight ratio.

**Segment**: when disk capacities differ (or a disk runs out of capacity), the space is divided into multiple segments.
Each segment has a fixed disk set, weights, and logical range `[logical_begin, logical_end)`.
For example, after a 1 TB segment with weights [6:3:2:1], a segment containing only the first 3 disks can follow (the smaller-capacity disk drops out),
and then a segment containing only disk 0 (leaving the largest disk). Segments are ordered by `logical_begin`;
the core verifies in ctr(): (a) they are ordered and non-overlapping; (b) each segment satisfies the
`stripe_size = Σ weight×chunk` invariant.

**Design trade-off**: why segments rather than "globally adjusting weights by capacity"?—per-disk weights are usually determined by performance
(the solo ratio), whereas capacity is another dimension; segments make "performance weights" and "capacity partitioning" orthogonal, so an administrator can
tune them independently, and the approach also avoids global equal weights wasting capacity on already-exhausted disks.

### 3.2.3 Mapping Algorithm

```
Input: logical address L (bytes, from the volume start)
Step 1 (segment selection): binary search the segment array for seg such that
      L ∈ [seg.logical_begin, seg.logical_end)
Step 2 (stripe location): let base = L − seg.logical_begin
      stripe_no  = base ÷ seg.stripe_size        (integer division)
      stripe_off = base mod seg.stripe_size       (remainder)
Step 3 (disk selection): cumulative boundary (depends only on the weights; precomputed at ctr() or computed on the spot)
      boundary[0] = 0
      boundary[i] = Σ_{j<i} w_j × c
      pick i such that boundary[i] ≤ stripe_off < boundary[i+1]
Step 4 (physical address):
      physical_offset = stripe_no × w_i × c + (stripe_off − boundary[i])
      sector = physical_offset >> 9
Output: (disk i, sector)
```

**Derivation**: `stripe_no × w_i × c` is "the bytes already written to disk i across all preceding complete stripes";
`stripe_off − boundary[i]` is "the offset within disk i's region in the current stripe"; their sum is the
physical offset on disk i. This mapping is pure arithmetic (add/sub/mul/div), with no memory table lookup and no locks; segment selection is O(log m) (m is the number of segments,
in practice ≤ 3), and disk selection is O(n) (n is the number of disks, in practice ≤ 4, reducible to O(1) via a precomputed boundary).

**Example**: weights [6:1], c = 1 MB, stripe = 7 MB.

**Table 3.2** Mapping-calculation example (weights [6:1], chunk 1 MB).

| Logical address L | Calculation | Result |
|-----------|---------|------|
| 0 | stripe_no=0, off=0 ∈[0,6M) | disk0, offset 0 |
| 6 MB | off=6M ∈[6M,7M) | disk1, offset 0 |
| 7 MB | stripe_no=1, off=0 | disk0, offset 1×6M+0 = 6 MB |
| 6 MB + 4 MB = 10 MB | stripe_no=1, off=3M | disk0, offset 6M+3M = 9 MB |
| 7 MB + 6 MB = 13 MB | stripe_no=1, off=6M | disk1, offset 1M + 0 = 1 MB |

![Figure F4 Weighted-stripe mapping illustration (figs/F4_mapping_en.svg)](figs/F4_mapping_en.svg)

> **Figure F4.** Visualization of the landing positions for weights [3:1], c=1 MB, stripe=4 MB. Each logical chunk
> lands via (3.1) on the fixed physical offset of a unique disk; the same color is the same stripe; per stripe, disk 0 receives
> 3 chunks and disk 1 receives 1 chunk.

### 3.2.4 Edge Cases and Invariants

**Table 3.3** Mapping edge cases.

| Case | Behavior | Rationale |
|------|------|------|
| Exactly at a disk-region boundary (off == boundary[i]) | Falls into disk i (left-closed, right-open interval) | Interval defined as `[boundary[i], boundary[i+1])` |
| bio spans multiple disk regions | Parallel split (§3.2.6) or `dm_accept_partial_bio` | see §3.2.5 |
| bio crosses a stripe boundary | DM cuts the first half; the latter half is re-mapped | `max_io_len = stripe` |
| Write length is not an integer multiple of the stripe | The residual chunks fall into the leading disks per the formula | Determinism: the residual is likewise byte-exact |
| boundary between segments | binary search hits the subsequent segment | segments do not overlap and cover the whole space |

**Load-bearing invariants (disturbing them means a bug)**:
1. segments must be ordered by `logical_begin`, non-overlapping, and cover the complete logical space;
2. each segment's `stripe_size` must equal `Σ weight×chunk`;
3. the `map.length` and `map.offset` formulas in Step 4 must consistently use the same weight and chunk;
4. the boundary calculation of the cross-disk split (§3.2.5) must agree with the boundary in Step 3.

### 3.2.5 Cooperating with the DM Contract

To let the DM core correctly handle bios that cross stripe/disk-region boundaries:

- `dm_set_target_max_io_len(stripe_sectors)`: bios entering `map()` have length ≤ one stripe,
  ensuring any bio crosses at most one stripe boundary.
- `io_hints`: `chunk_sectors = stripe`, `io_min = min(w×c)`, `io_opt = stripe`,
  guiding the upper layer to issue large I/O in units of a stripe.
- A bio crossing disk regions uses `dm_accept_partial_bio(bio, len)` to hand back "the portion that fits in the current disk region" to
  the DM core to re-enter `map()`, and the remaining portion continues automatically—**the cross-disk split is mostly borne by DM,
  and the driver does not split read bios itself**; only the write path splits on its own to pursue parallel throughput (next section).

> Why doesn't the read path parallel-split on its own? Read splitting is cheap (DM re-entering map() completes it), and parallel splitting exists for
> "write throughput"; under a deep queue, reads are naturally parallelized across many bios, with no need for per-bio parallel splitting.

### 3.2.6 Parallel Write Path

When a WRITE bio crosses multiple disk regions within a single stripe (`tv_stripe_calc_boundaries()` computes
`li − fi + 1 > 1`), `tv_parallel_submit()` clones the bio into per-disk sub-bios
and submits them in parallel, so that fast disks are not held back by slow ones:

```
tv_parallel_submit(orig, segments):
    pending = n_sub_bio
    completed = 0
    for each sub: 
        sub = bio_alloc_clone(orig)        // shared page, zero-copy
        bio_advance(sub, position to the disk region)
        sub->bi_end_io = tv_parallel_end_io
        submit_bio(sub)
```

**Completion semantics (exactly once)** is guaranteed by a three-part mechanism:
- `atomic pending`: tracks the number of sub-bios not yet completed;
- `kref`: the lifetime of the block (the private data of the original bio);
- `cmpxchg(completed, 0, 1)`: **only the last-completing sub-bio executes endio + stops the timer + releases kref**.

**Two important implementation details**:
- The completion callback runs in hardirq: stopping the timer must use `del_timer()`, and **must never use
  `del_timer_sync()`** (the latter spins waiting for the timeout callback, deadlocking inside hardirq);
- If a sub-bio times out (timer timeout): `kref_get_unless_zero()` keeps the block alive,
  marks that disk DEGRADED, and completes the original bio via `cmpxchg`, avoiding indefinite blocking.

**Design trade-off**: the parallel write path is a path fully owned by the driver, bypassing DM's end_io; its sub-bio
errors do not enter the normal error statistics; disks are only marked DEGRADED via timeout. This is deliberate—write errors
are handled by badmap (§4.3.2) and the DEGRADED mark, and the timeout itself is also one of the trigger signal sources for slow-disk borrowing (§4.1).

## 3.3 Bottleneck Model and Automatic Weights

### 3.3.1 Bottleneck Model

**Theorem 3.1**. Given a weight vector W, total weight ΣW, and each disk's sequential write rate soloᵢ, the upper bound on the total throughput of striped writes is

> **T(W) = minᵢ ( soloᵢ × ΣW / wᵢ )**　　　… (3.2)

**Proof**. Disk i is allocated wᵢ/ΣW of the total data. If the total throughput is T, the rate borne by disk i is
`T × wᵢ/ΣW`. Disk i's rate ceiling is soloᵢ, so

> **T × wᵢ/ΣW ≤ soloᵢ　⇒　T ≤ soloᵢ × ΣW/wᵢ**　　(for all i)

Therefore `T ≤ minᵢ(soloᵢ × ΣW/wᵢ)`. When the **bottleneck drive (the disk that attains the minimum in (3.2)) is saturated**, the equality holds;
when weights match, all disks saturate simultaneously; when weights are mismatched, non-bottleneck disks may not be saturated, yet the equality still holds.
□□

**Corollary 3.1 (weights match ⇒ total throughput = sum of the disks)**. If the weights are proportional to solo
(∃k, wᵢ = k·soloᵢ), then each term

> **soloᵢ × ΣW/wᵢ = (wᵢ/k) × ΣW/wᵢ = ΣW/k**

All terms are equal, `T = ΣW/k = Σᵢ soloᵢ`. That is, when "weight ratio = speed ratio", striping "adds up" the
sequential rates of all disks—**this is the theoretical basis of auto_weight**.

**Corollary 3.2 (bottleneck-drive identification)**. The i* that attains (3.2) is the bottleneck drive; experiments (§6.3.1) show that
in the steady-state drain state, the 4-disk scenario at equal weights **6:1:1:1** hits `T = D×9 ≈ 1760` exactly, and D (the slowest disk) is the bottleneck.

![Figure F5 Bottleneck-model geometry illustration (figs/F5_bottleneck_en.svg)](figs/F5_bottleneck_en.svg)

> **Figure F5.** The left half shows each disk's `soloᵢ×ΣW/wᵢ` horizontal line under weight mismatch ([6:1:1:1]);
> the lowest line is the bottleneck (D, which receives only 1/9 of the data yet still caps total throughput at `D×9`); the right half shows weights ∝ solo
> (Corollary 3.1), where all lines coincide at `Σsolo`, with no bottleneck disk. The plotted data are illustrative values (for the geometry only);
> for the corresponding measurements, see §6.3.1 (`T = D×9 ≈ 1760`).

### 3.3.2 auto_weight: Exhaustive Automatic Weights

In practice, the stable solo cannot be known a priori (it is affected by SLC, the slot, and wear), so `scripts/auto_weight.sh`
derives the weights in a measurement-driven way:

1. **Measure solo**: run a sequential write of 8 G (1 M block, libaio, depth 32) on each disk independently and take the average;
   measured with a fixed protocol (the drain state, or the cold state plus a 60 s idle gap; see §6.1.2) to avoid misjudgment from SLC bands.
2. **Integer normalization**: using the slowest disk's solo as the baseline, first estimate each disk's weight as `wᵢ ≈ base × soloᵢ/solo_min`.
3. **Exhaustive search**: for a base base ∈ [2, 40], vary each weight by ±1 between `floor` and `ceil`,
   enumerating all candidate weight vectors globally; compute `T` for each candidate via (3.2) and take the largest—equivalently, "make each disk's
   `soloᵢ×ΣW/wᵢ` as equal as possible, maximizing the weakest disk's utilization". A cap (weight ceiling 128) is also applied
   to prevent any single disk's weight from becoming too large.
4. **Verification**: rebuild the volume with the candidate weights and measure, confirming that the distribution is exact and the throughput is close to the model.

In the experiments (§6.3.2), the weights produced by auto_weight make the write ladder strictly monotonic; S2/S3 deviate from the model
within ±3% (S4 −5.9%, enumeration granularity; see §6.3.2); S4 improves by 70.6% over the equal weights 6:1:1:1
(3006 vs 1762 MB/s), and the model bound reaches 99.6% of Σsolo (measured: 93.7%).

**Design trade-off**: why exhaustive search rather than a closed-form solution?—(3.2) is a max-min problem, and a closed-form solution would require precise measurement;
but weights must be integers (chunk allocation proceeds in units of chunks), and the integer space leaves searchable slack between "approximate speed ratio" and
"exact distribution"; with n≤4 and base≤40, the exhaustive-search space is tiny (second-scale),
and it can incorporate constraints such as the cap, so exhaustive search guarantees optimality.

### 3.3.3 DMI-aware Weights (Shared Upstream Bus)

(3.2) assumes each disk exclusively owns its interface; but SATA disks and the NVMe disks that route through the PCH share the **southbridge DMI upstream bandwidth**.
On the measurement platform, the DMI measures ~1300 MB/s. If weights are allocated in proportion to solo (B, C, D all route through the DMI),
the combined B+C+D traffic would exceed the DMI ceiling and contend for bandwidth, and the actual throughput would fall far below the model (the proportional weights measure
[64:47:16] at only 2561 MB/s).

**Fix**: treat the DMI as a shared device. Let 𝒟 be the set of DMI disks and A the CPU-attached disk (not going through the DMI,
with weight w_A and solo_A). Require the sum of the DMI disks' weights to be bounded:

> **Σ_{i∈𝒟} w_i ≤ DMI_Budget × w_A / solo_A**　　　… (3.3)

**Derivation**: if total throughput is bottlenecked by A, `T = solo_A × ΣW/w_A`. The rate borne by the DMI disks is
`T × Σ_{𝒟}w_i/ΣW = solo_A × Σ_{𝒟}w_i/w_A`. Requiring it to be ≤ DMI_Budget yields (3.3).

Substituting the measurement platform (DMI_Budget≈1300, solo_A≈2070, design-phase estimates; the final measurements were
2064, §6.1.3): with w_A=64, `Σ_{𝒟}w_i ≤ 40.2`.
Shares are then allocated by each disk's solo proportion: for 3 disks, taking B:C ≈ 1520:517 and scaling yields the DMI-aware weights
**[64:30:10]**; for 4 disks, adding D back according to C:D ≈ 517:223 gives **[64:27:9:4]**.
Experiments confirm that [64:30:10] reaches 3370 MB/s, **+32%** over the proportional weights; moreover
`S3_max = solo_A + DMI_Budget ≈ 3364` hits the expectation of (3.3) exactly.
The four-disk [64:27:9:4] is likewise confirmed by measurement (§6.3.1): the combined B+C+D traffic is held within the DMI budget,
and the bottleneck returns to disk A (`solo_A×104/64 ≈ 2064×104/64 ≈ 3354`; measured 3300, a −1.6% deviation)
—(3.3) is a sufficient condition for "converting the shared-resource
bottleneck back into a single-disk bottleneck", and once converted, the model (3.2) holds again.

**Pedagogical implication**: (3.2) is "each disk's self-perceived bottleneck", while the DMI is a "shared bottleneck". When the shared bus
becomes the stricter constraint, weight allocation must be governed by the shared-resource budget ((3.3)) rather than by each disk's solo proportion—
this applies to any system in which multiple disks share an upstream bus (southbridge, PCIe switch, NVMe-oF links).

## 3.4 Test Architecture Design

To balance "unit-level correctness" and "integration-level realism", four layers of tests are designed—from the bottom layer's determinism verification
up to the top layer's real-hardware throughput:

**Table 3.4** Four-layer test architecture design.

| Layer | Tool | What is verified | Environment |
|----|------|----------|------|
| L1 Unit | `tests/test_map.c` (501 assertions) | Mapping formula, weight distribution, remainder, determinism | Userspace (no kernel needed) |
| L2 Kernel simulation | `tests/test_stripe_kernel.c` (27 items) | Stripe boundaries, parallel split, completion semantics | Userspace simulation |
| L3 dmsetup volume build | Real volume build + `dmsetup status` counters | Byte-exact distribution, err=0, cross reload | Kernel (real devices) |
| L4 Integration | fio benchmarks + scripts (borrow_verify/stack_retest/multi_vol_suite…) | Throughput, model hit, durability | Kernel (real devices) |

**Design rationale**: L1/L2 compile in userspace (`make test`), giving a fast development loop and the ability to exhaustively cover the mapping's
edge cases; L3's counter verification is the key means for establishing correctness—after each volume is written, comparing each disk's `wr=<bytes>`
against the weight ratio can **confirm the distribution byte-by-byte**; L4 is where performance and the model are verified.
Each layer has its own job, avoiding the situation of "only black-box testing with fio, where an error leaves you unable to tell whether it is a mapping or a device problem".
Implementation details: see Chapter 5, §5.8.

## Chapter Summary

Chapter 3 answers the **design** of P1 (weighted striping + deterministic mapping) and P2 (performance modeling):
- Weighted-stripe mapping (3.2): divides the logical space evenly by weights; O(1), table-free, byte-exact, deterministic;
- Bottleneck model (3.3): `T = minᵢ(soloᵢ×ΣW/wᵢ)`; when weights are proportional to solo, `Σsoloᵢ` is attained
  (Corollary 3.1); weights can be found by exhaustive search via `auto_weight`, and the DMI-aware fix handles the shared bus;
- Test architecture design (3.4): four layers, each with its own job.

The designs of P3 (weight borrowing) and P4 (fault tolerance/management) are given in Chapter 4; Chapter 5 presents the implementation of both designs,
and Chapter 6 verifies the model and the implementation.
