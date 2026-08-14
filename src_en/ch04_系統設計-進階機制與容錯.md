# Chapter 4 System Design (II): Advanced Mechanisms and Fault Tolerance

> **Chapter guide:** §4.1 Weight Borrowing (dynamic rebalancing); §4.2 Write
> Coalescing (small-write merging); §4.3 Mirroring and Rebuild (fault
> tolerance); §4.4 Concurrency Consistency; §4.5 Configuration and Management;
> §4.6 summarizes all key trade-offs of this chapter (and Chapter 3) in a
> design decision log. Appendix B records the failures and fixes during
> development.

Chapter 3 established the "static core" of the architecture, weighted striping
mapping, and the bottleneck model. This chapter stacks all dynamic and
fault-tolerance mechanisms on top of it: Weight Borrowing (§4.1), Write
Coalescing (§4.2), Mirroring and Rebuild (§4.3), Concurrency and Consistency
(§4.4), and Configuration and Management (§4.5). Governing principle: **all
dynamism is a "temporary exception on top of a static deterministic layout"
that never violates the mapping function of Chapter 3**.

## 4.1 Weight Borrowing

### 4.1.1 Motivation

Static weights assume that weights match performance over long time scales. In
reality, a slow drive may temporarily become slower (SLC exhaustion, drive
busyness, wear degradation). Both extreme solutions are infeasible:

- If data is still fed to the slow drive according to weight → the slow drive
  becomes the bottleneck and drags down the whole system;
- If disk selection becomes dynamic (adaptive policy, choosing the least busy
  drive on the fly by load) → the address determinism is broken, and it is
  measurably imbalanced (-44%, see §6.3.3).

Compromise: **preserve the static weight layout and temporarily offload only a
few "whole-block" writes** — normal data still follows the deterministic
mapping; only the anomalous condition "slow drive under high load" triggers the
exception path.

### 4.1.2 Mechanism Design

- **Trigger condition**: a drive's in-flight bytes ≥ `borrow_watermark_kb`,
  **and** the pending write is whole-block aligned. Block granularity =
  `chunk_size/8` (1 M chunk → 128 KB block). Both conditions are required:
  borrow only under high load (to avoid lookup overhead on the normal path);
  borrow only whole blocks (borrow regions are allocated at block granularity,
  for atomicity).
- **Destination disk selection**: the least-loaded drive (excluding itself,
  DEGRADED drives, and those without free space in the borrow region), written
  to its over-provisioned borrow region.
- **Recording**: a per-block table records `(dst_disk, dst_sector)`. Reads and
  rewrites (`need==0`) always resolve via lookup to the same destination — **a
  borrowed block is always readable back**.
- **Off semantics**: `borrow_off` only stops **new** borrowing; lookup and
  rewrite are unaffected by the switch (they do not check `enabled`), so
  turning it off does not affect the consistency of already-borrowed data.
- **Atomicity**: borrow-region allocation is all-or-none (whole block), to
  avoid partial allocation causing table inconsistency.
- **Persistence**: on remove, the table is saved to `<config>.borrow`
  (v2 table, 16 B/entry, version marked by magic); on rebuild it is loaded, so
  addresses are consistent across reloads (experiment: 4 G write + verify 0
  errors, mapping restored after reload).

### 4.1.3 Consistency Invariants

1. **Borrow resolution closure**: any read/rewrite of a borrowed block always
   resolves to the borrow region (lookup does not depend on runtime switches
   such as `borrow_off` or `watermark`);
2. **All-or-nothing**: the borrow region is allocated and released at block
   granularity as the minimum unit;
3. **Critical section**: table operations and the corresponding I/O submission
   are inside the same critical section, avoiding "recorded in the table but
   I/O not submitted" or the reverse;
4. **Relationship to the static mapping**: borrowing is an **exception list**
   on top of the static mapping. Normal addresses still follow the O(1)
   formula of §3.2; only borrowed blocks go through the table lookup. The two
   are switched by "block alignment + slow drive under high load"; the
   exception count is orders of magnitude smaller than the normal mapping, so
   the lookup cost is negligible and the deterministic layout is unchanged.

![Figure F6 Weight Borrowing flow (figs/F6_borrow_en.svg)](figs/F6_borrow_en.svg)

> **Figure F6.** The trigger condition (whole-block alignment + slow drive
> under high load) splits I/O into two paths — most writes take the normal
> O(1) deterministic mapping, while a few whole-block writes take the borrow
> region exception path. The two bands at the bottom converge on the borrow
> closure and persistence invariants of §4.1.3.

### 4.1.4 Correspondence with Chapter 6

The verification focus of borrowing is not throughput (it is a "life raft for
failure/degradation"), but **correctness and consistency**: exact placement,
4 G verify 0 errors, mapping restored after reload, and borrowed data still
readable after turning it off (§6.5).

## 4.2 Write Coalescing (WC)

### 4.2.1 Motivation

Parallel striping writes are most efficient with "large blocks"; but the upper
layer may feed small 4 K writes in. If every 4 K were split into per-disk
sub-bios, the bio management cost (clone/advance/submit/endio) would far exceed
the data itself. WC **buffers small writes in groups by stripe**, accumulating
them into a full stripe before flushing — trading "delayed landing" for
"coalescing efficiency".

### 4.2.2 Buffering and Flush

- **Buffering condition**: `wc_enabled`, direction is WRITE, the segment is
  valid, and `disk_count > 1` (single-disk segments are not buffered and are
  submitted directly).
- **Grouping key**: `(segment, stripe_no)`. Bios crossing stripe boundaries
  are cut in half by DM first (§3.2.5); WC buffers only the cut bios, ensuring
  every entry is within the same stripe.
- **Flush timing**:

**Table 4.1.** WC Flush trigger timing

| Condition | Behavior |
|------|------|
| Accumulated ≥ stripe_size | Synchronous flush |
| Stripe switch (new stripe_no) | Flush old stripe first, then buffer the new one |
| 1 jiffy timeout | Asynchronous flush (`system_wq`) |
| READ bio received | **Flush first** (read-order guarantee) |
| device destroy | Forced flush |

- **Flush content**: splice the entries into a batch; each entry takes the
  original parallel/single-disk submission path, and mirroring is added before
  submission (§4.3).

![Figure F7 Write Coalescing (WC) path (figs/F7_wc_en.svg)](figs/F7_wc_en.svg)

> **Figure F7.** A READ flushes first (the read-order load-bearing wall); a
> WRITE is routed by the buffering condition — qualifying writes enter the
> (segment, stripe_no) grouped buffer, triggered by the five flush timings;
> non-qualifying writes (including small 4 K writes) return -EAGAIN and take
> the direct path. Flush replay and direct submission share the same
> parallel/single-disk logic.

### 4.2.3 Consistency Semantics

- **Read-order guarantee (load-bearing wall)**: any READ must first call
  `tv_wc_flush()`, so WC **does not change the read/write order** — this is the
  only guarantee of the invariant "reads return the latest data"; changing this
  = read-order error.
- **Bypass path (-EAGAIN)**: bios that do not meet the buffering condition
  return `-EAGAIN` and take the direct path without entering WC. This explains
  the performance behavior of small 4 K writes: **a 4 K bio < chunk_size, so it
  does not meet the whole-block condition and bypasses WC** (the conditional
  branch in `tieredvol_wc.c`); 4 K performance is determined mainly by the
  striping split cost and the placement distribution (§6.4).
- **Flush replay**: at flush time, each entry recomputes its
  parallel/single-disk path, sharing the same logic as direct submission, so
  the two paths cannot diverge in behavior.

### 4.2.4 Limitations (Honest Statement)

WC is a **delayed-flush** cache: data before flush exists only in memory.
**On power loss, buffered data that has not landed is lost.** The implementation
in this thesis provides no crash guarantee for power-loss consistency; those
who require strict durability should disable WC (`wc_enabled=N`) or rely on the
upper layer (filesystem barrier/fsync). This is one of the limitations listed
in §6.6 (the cost-benefit trade-off of WC power-loss consistency).

## 4.3 Mirroring and Rebuild

### 4.3.1 Per-Segment Mirror

Each segment can designate one mirror drive (`seg0_mirror=idx`); the mirror
drive cannot be any of that segment's primary drives, and each segment has at
most one mirror.

**Write**: the original WRITE still follows the weighted striping path; in
parallel, a copy is made with `bio_alloc_clone()` fire-and-forget to the mirror
drive (`mirror_sec = logical − seg_begin`):

- the clone uses a mempool (pool size 128) to guarantee no OOM, and does
  **not block the original bio**;
- on completion, `mirror_write_ops++` / `mirror_errors++` (queryable
  statistics);
- mirror writes do not enter the WC buffer (submitted directly), running in
  parallel with the primary.

**Read and retry**: when a primary read fails, if there is a pending mirror
write for that location, wait (every 1 ms, at most 32 give-up attempts) for it
to drain, then retry from the mirror (the flow uses the pending record of §4.4).
Past the give-up count, the read gives up to avoid waiting indefinitely.

### 4.3.2 Rebuild and Badmap

- **Rebuild**: a kthread walks the static mapping chunk by chunk, "read
  primary → write mirror"; synchronous I/O + `wait_for_completion`; on failure,
  backoff (starting at 10 ms, doubling up to 1 s); progress reported every
  10 MB.
- **Badmap**: per-disk chunk bitmap (`n_chunks = disk_sectors/chunk`). Reads
  of bad blocks complete with zero-fill (read as zeros); writes to bad blocks
  are skipped directly (`bio_endio`). WRITE errors mark the chunk bad
  automatically in the completion callback; persisted into the config as a
  range string (`badmap_<disk>=a-b,c`), compressed and written back at kernel
  save time.
- **rebuild_badmap**: the handling of bad regions during rebuild fixed an
  implementation bug (compound page caused incorrect `bi_size` computation);
  after the fix, `1 recovered, 0 failed` and no hang.

### 4.3.3 Mirror Cost Analysis

The mirror write is submitted in parallel with the primary, so the bottleneck
is the mirror drive's own write rate: total write time ≈ max(primary path
time, mirror drive time). In the experiments, the M volume write ≈457 MB/s,
reaching ~88% of mirror drive C's own solo rate (≈517) — the bottleneck is the
mirror drive (SATA), not primary coalescing (in the 8/12 control, primary
aggregation was 2390 vs. mirror volume 463, a ~81% reduction, from the same
cause); 4 K writes drop more (-52%) due to the COW cost; reads have almost 0%
additional cost (reads are not duplicated).

## 4.4 Concurrency and Consistency

### 4.4.1 Data Structures

- **pending-write ring** (protected by the `tv_pw_lock` spinlock): records
  in-progress writes (including mirror writes), used when retrying on read
  errors to decide whether "an unfinished write may still exist at this
  location".
- **pending-read ring** (protected by the `tv_pending_lock` spinlock):
  per-CPU lockless, records ranges currently being read, for error-handling
  tracing.

### 4.4.2 Semantics (Three Outcomes)

**Table 4.2.** Concurrency consistency — semantics of the three outcomes

| Case | Behavior |
|------|------|
| **MISS** | The read error location has no corresponding pending record → report the error directly or take the mirror retry path |
| **give-up** | Waiting for the mirror write to drain exceeds 32 give-up attempts → give up and report the error (avoids waiting indefinitely) |
| **full** | When the ring is full, an implementation-defined reject/overwrite policy prevents structure overflow from corrupting consistency |

Counters reflect these events via `err`; throughout the experiments `err=0`
(§6.2).

### 4.4.3 Lock-Free Hot Path Without Shared Locks

The mapping itself is lock-free (§3.2); the mirror hot path uses per-CPU rings
+ atomics; the only shared spinlock is on the cold path of
completion/error handling. The multi-volume concurrency experiment (§6.2.3)
shows that two volumes whose "driver state is not shared" achieve isolated
concurrency performance (±2%), confirming no lock contention on the hot path.

## 4.5 Configuration and Management

- **Config**: `/etc/tieredvol/<name>.conf` is the single source of truth; the
  dm table is minimal (`0 <sectors> tieredvol <config_path>`), with the whole
  layout in the config. The kernel loads and validates CRC32C; kernel save
  writes `.bak` first. **Invariant**: changing the config format = updating the
  kernel parser and the CRC algorithm **in two places in sync**, otherwise load
  fails or silent corruption occurs.
- **Parameter validation (fail-closed)**: ctr() rejects invalid parameters —
  removed adaptive policy values, out-of-range weights, duplicate drives,
  mirror drive overlapping a primary, wrong segment order, and so on.
- **sysfs / dmsetup message**: the management interface outputs weights and
  per-drive statistics; message commands include `show_mirror`, rebuild
  trigger, policy switch, and so on.
- **Statistics counters**: per-drive `wr=/rd= ops/bytes`, `err`, borrow
  counts, mirror counts (`mirror_wr/rd ops`, `mirror_err`) — the basis for the
  correctness verification in Chapter 6.

## 4.6 Design Decision Log

The following consolidates all key design trade-offs that appear in Chapter 3
and this chapter, for quick indexing at the defense and review (detailed
rationale in the corresponding sections):

**Table 4.3.** Design decision log (D1–D10)

| # | Decision | Rejected alternative | Rationale (evidence) |
|---|------|-----------|--------------------|
| D1 | Striping (weighted parallel) | Two-level cache / tiered placement | Every datum is distributed in parallel across all drives, not moving hot data by hit rate (§2.3) |
| D2 | Segment partitioning | Global capacity-proportional weighting | "Performance weights" and "capacity segments" are orthogonal and can be tuned independently (§3.2.2) |
| D3 | O(1) table-free arithmetic mapping | mapping table / dynamic index | Lock-free hot path, reproducible; for n≤4 the formula is cheaper than table lookup (§3.2.3) |
| D4 | Exhaustive auto_weight | Closed-form solution | Weights must be integers, a max-min problem, n is small; exhaustive search can incorporate constraints such as caps (§3.3.2) |
| D5 | DMI-aware weights | Pure solo-ratio weights | Shared-bus budget (§3.3); ratio weights measured at 2561 in practice (§6.3.4) |
| D6 | Static layout + borrowing | Dynamic disk selection (adaptive) | Determinism is not broken; adaptive measured -44% with C/D imbalance (§6.3.3) |
| D7 | Borrow granularity = chunk/8 | Whole-chunk borrowing | Fine granularity fills slow-drive gaps; atomicity guaranteed at block granularity (§4.1.2) |
| D8 | WC delayed flush | Write-through | Small-write coalescing efficiency; accepts the power-loss risk (can be disabled, §4.2.4) |
| D9 | Mirror built into the target | Separate dm-mirror | Single-target consistency, per-segment flexibility, fewer stacked layers (§4.3) |
| D10 | libaio depth 32 | io_uring deep queue [10] | Reflects real hardware limits and avoids inflating numbers (§6.1.2) |

> Decision principle: **all dynamism is a temporary exception on top of a
> deterministic layout** (D6). Any mechanism that could cause "the same logical
> address to land on different drives at different times" is excluded.
> The "pitfalls" and fix history of each decision are in Appendix B.

## Chapter Summary

Chapter 4 answers the **design** of P3 (Weight Borrowing) and P4 (fault
tolerance/management):
- Weight Borrowing (§4.1): temporarily offloads fine-grained blocks when a
  slow drive is under high load, restored across reloads via a persistent
  table, without breaking the deterministic layout;
- Write Coalescing (§4.2): delayed flush of small bios, -EAGAIN bypass for
  bio<chunk, balancing small-write performance and consistency claims;
- Mirroring/rebuild/badmap (§4.3) and concurrency consistency (§4.4):
  integrated into a single target, with `err=0` throughout;
- Configuration and Management (§4.5) and the Decision Log (§4.6): converge
  all Chapter 3 and Chapter 4 trade-offs into a defensible decision table.

Chapter 5 maps every design in this section and Chapter 3 to an implementation.
