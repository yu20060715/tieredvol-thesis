# Chapter 5 Implementation

> **Chapter guide:** §5.1 Module Overview (files/lines/parameters/data
> structures); §5.2 Mapping and Striping; §5.3 Borrowing; §5.4 WC; §5.5
> Mirroring and Rebuild; §5.6 Concurrency; §5.7 Configuration and Management;
> §5.8 Testing and Toolchain. Each section corresponds one-to-one with the
> design sections of Chapters 3 and 4, and marks the "load-bearing walls" —
> invariants whose modification breaks correctness.

This chapter describes the concrete implementation of TieredVol: module
structure, data structures, key flows, and the four-layer test architecture,
mapping one-to-one to the designs of Chapters 3 and 4. Cross-referencing the
driver source and `docs/DESIGN.md`, the reader obtains the explanation of the
"load-bearing walls" (design invariants whose modification breaks correctness).

## 5.1 Module Overview

### 5.1.1 Build and Load

The driver is built as a single module `tieredvol` (the `Makefile`:
`all: module`, `test: test_map test_stripe_kernel`), hooked into the dm
framework via `module_init`/`module_exit`:

```
MODULE_LICENSE("GPL")
MODULE_DESCRIPTION("Weighted striped dm target for tiered storage")
MODULE_VERSION("5.0.0")
```

Runtime parameters (`module_param`, modifiable on the fly via
`/sys/module/tieredvol/parameters/`):

**Table 5.1.** Runtime module parameters

| Parameter | Type | Description |
|------|------|------|
| `wc_enabled` | bool | Enable write coalescing (default Y) |
| `log_size` | uint | Number of entries in the log ring buffer (default 512, a power of 2) |

### 5.1.2 Module Files and Responsibilities

The driver consists of 15 .c and 2 .h files, about 4700 lines:

**Table 5.2.** Module files and responsibilities

| File | Lines | Responsibility |
|------|------|------|
| `tieredvol_core.c` | 797 | Module entry, ctr/dtr, main `map()` flow, completion callbacks, DEGRADED handling |
| `tieredvol_meta.c` | 749 | config parsing/validation/CRC32C, segment/disk/weight structures, save |
| `tieredvol_mirror.c` | 706 | Mirror writes/read retry/rebuild |
| `tieredvol_borrow.c` | 441 | Weight borrowing: trigger, disk selection, per-block table, persistence |
| `tieredvol_msg_mirror.c` | 330 | Mirror-related dmsetup messages |
| `tieredvol_wc.c` | 211 | Write coalescing buffer and flush |
| `tieredvol_stripe.c` | 210 | Stripe boundary computation, parallel split helpers |
| `tieredvol_sysfs.c` | 147 | sysfs management interface |
| `tieredvol_badmap.c` | 144 | Bad-region bitmap, zero-fill, persistence |
| `tieredvol_msg_stats.c` | 133 | Statistics counter output |
| `tieredvol_map.c` | 127 | **Mapping core `tv_map_logical()`** |
| `tieredvol_msg_policy.c` | 121 | policy messages (static/random, borrow switch) |
| `tieredvol_msg_config.c` | 85 | config messages |
| `tieredvol_message.c` | 60 | Message dispatch |
| `tieredvol_log.c` | 51 | Logging (ring buffer) |
| `tieredvol.h` | 379 | Shared data structures and declarations |
| `tieredvol_msg.h` | 40 | Message interface declarations |

### 5.1.3 Core Data Structures (`tieredvol.h`)

```
struct tv_segment {
    u64 logical_begin, logical_end;   // logical range (left-closed, right-open, bytes)
    u64 stripe_size;                  // = Σ weight×chunk (validated in ctr)
    u32 disk_count;                   // number of participating drives
    u32 weights[];                    // weight vector W
    int policy;                       // -1 inherit / 0 static / 2 random
    int mirror_disk;                  // seg0_mirror (-1 means none)
    …  (bad-region bitmap reference, WC grouping state, statistics counters)
}

struct tv_meta {
    u32 chunk_size;                   // allocation unit (fixed 1 MB in this thesis)
    u32 n_segments;                   // number of segments (≤ 3 in practice)
    struct tv_segment *segs[];        // sorted by logical_begin
    int runtime_policy;               // global policy
    u32 runtime_borrow_watermark_kb;  // borrow watermark (KB)
    …   (drive list, by-id paths, statistics, borrow table header)
}

struct tv_io_stats {
    atomic64_t rd_ops, rd_bytes;      // read counters
    atomic64_t wr_ops, wr_bytes;      // write counters
    atomic64_t err;                   // error counter
    atomic64_t in_flight_bytes;       // watermark used to trigger borrowing
}

struct tv_borrow_entry {              // borrow table entry (u8+u8+u64, 16 B/entry after alignment)
    u8  valid;                        // 1 = borrowed out
    u8  dst_disk;                     // destination disk index
    u64 dst_sector;                   // sector address in the borrow region
};
// block_size = chunk_size/8 (1 M chunk → 128 KB block)
```

## 5.2 Mapping and Striping Implementation

### 5.2.1 `tv_map_logical()` Pseudocode

```
tv_map_logical(meta, L) -> (disk, sector):
    seg = binary_search(meta->segs, L)          // L ∈ [seg.begin, seg.end)
    base = L − seg.logical_begin
    stripe_no  = base / seg.stripe_size
    stripe_off = base % seg.stripe_size
    off = stripe_off
    for i in 0 .. seg.disk_count−1:             // accumulate boundaries to find the disk
        if off < seg.weights[i] * meta.chunk_size:
            return (i, (stripe_no * seg.weights[i] * chunk_size
                       + off) >> 9)
        off -= seg.weights[i] * meta.chunk_size
```

Implementation highlights:

- Segment selection uses binary search; `stripe_size` is computed in ctr() and
  stored in the segment, so the hot path has zero computation.
- `tv_stripe_calc_boundaries()` (`tieredvol_stripe.c`) computes, from the bio
  range, the disk interval `[fi, li]` that the bio spans (for the parallel
  split check).
- `map()` for single-disk-interval bios: changes `bi_bdev` + `bi_sector` and
  returns `DM_MAPIO_REMAPPED`; for cross-disk-interval WRITEs:
  `tv_parallel_submit()` returns `DM_MAPIO_SUBMITTED`; for cross-stripe bios:
  `dm_accept_partial_bio()` hands them back to dm core for re-mapping (the
  driver does not split by itself).
- ctr() sets `dm_set_target_max_io_len(stripe_sectors)` and `io_hints`
  (`chunk_sectors=stripe`, `io_min=min(w×c)`, `io_opt=stripe`).

### 5.2.2 `tv_parallel_submit()` Completion Semantics

The triple guarantees "exactly-once completion" (§3.2.6):

```
per-block:
    atomic pending = 0          // sub-bio counter
    struct kref kref            // block lifetime
    atomic completed = 0

tv_parallel_end_io(sub):        // when each sub-bio completes (possibly in hardirq)
    if atomic_dec_and_test(pending):
        cmpxchg(completed, 0, 1)          // only the last one gets through
        endio(orig_bio)                   // original bio completes exactly once
        del_timer(&timer)                 // note: must not use del_timer_sync()
        kref_put(kref)

timeout_cb(timer):
    if kref_get_unless_zero(kref):
        mark the corresponding disk DEGRADED
        cmpxchg(completed, 0, 1)
        endio(orig_bio)
        del_timer(&timer)
        kref_put(kref)
```

**Two load-bearing walls**: (1) completion semantics (kref/timer/
`cmpxchg(completed,0,1)`, `del_timer` inside hardirq) — violating it causes
double completion/missed completion/deadlock/UAF; (2) boundary arithmetic —
violating it causes misaligned mapping and data written to the wrong disk.
Source-level rule (`DESIGN.md`): changing the parallel path or completion
semantics requires explaining the interaction with kref/timer.

## 5.3 Weight Borrowing Implementation

`tieredvol_borrow.c` (441 lines):

- **Trigger**: per-drive `in_flight_bytes ≥ borrow_watermark_kb` and the write
  is whole-block aligned (`block_size = chunk_size/8`). Borrow only under high
  load, avoiding lookup overhead on the normal path.
- **Disk selection**: take the least-loaded drive (excluding itself, DEGRADED
  drives, and those without free space in the borrow region).
- **Table**: per-block entry `(dst_disk, dst_sector)` (v2 table, 16 B/entry,
  marked by magic); lookup resolves reads and rewrites (`need==0`) to the same
  destination — **a borrowed block is always readable back**.
- **Consistency**: `borrow_off` only stops new borrowing (lookup does not
  check `enabled`); borrow-region allocation is all-or-none (whole block); I/O
  submission and table operations are in the same critical section.
- **Persistence**: on remove, saved to `<config>.borrow`; loaded on rebuild;
  addresses consistent across reloads.

Load-bearing-wall correspondence: changing borrow consistency (off still
resolves, all-or-none, `.borrow` save/load) causes data to be read/written to
the wrong disk or address drift across reloads.

```
// write path (borrow decision)
tv_map_logical / WRITE block address L:
    d = static_map(L)                        // the O(1) deterministic mapping of §3.2
    if disk[d].in_flight_bytes >= watermark and L is whole-block aligned:
        dst = least-loaded drive (excluding itself/DEGRADED/borrow region full)
        alloc block (all-or-none);  lock(borrow_lock)
        write to dst.borrow_region
        borrow_tab[L/block].set(dst, sector) // 16 B/entry, magic, v2
        unlock(borrow_lock); endio(orig)
        return                        // exception path completes
    normal path: parallel/single-disk submission (no table lookup)

// read / rewrite (need==0)
tv_map_logical / READ or rewrite L:
    b = borrow_tab.lookup(L/block)
    if b hit: resolve to b.dst / b.sector      // borrow closure: does not check borrow_off
    else:      static_map(L)               // normal deterministic mapping
```



## 5.4 Write Coalescing Implementation

`tieredvol_wc.c` (211 lines):

- Grouped by `(segment, stripe_no)`, entries are a linked list, and
  `accumulated` tracks the accumulated amount.
- **Buffering condition**: `wc_enabled && WRITE && segment valid &&
  disk_count > 1`; otherwise return `-EAGAIN` → direct path. **Small 4 K writes
  (bio < chunk) therefore bypass WC**, which is the implementation root of the
  4 K performance behavior (§6.4).
- **Flush**: same conditions as §4.2.2; at flush, splice entries → batch,
  each entry reruns the parallel/single-disk path, and calls
  `tv_mirror_handle()` before submission (guaranteeing mirror consistency).
- **Read-order load-bearing wall**: when `bio_data_dir() != WRITE`, first
  `tv_wc_flush()` — violating this invariant = reading stale data.

```
tv_wc_try_buffer(bio):
    if !wc_enabled or not WRITE or disk_count<=1:  return -EAGAIN
    group into the linked list by (segment, stripe_no)
    accumulated += bio_size
    if accumulated >= stripe_size: tv_wc_flush()   // synchronous
    else: schedule_delayed_work(flush, 1 jiffy)    // asynchronous
    return DM_MAPIO_SUBMITTED
```

## 5.5 Mirroring and Rebuild Implementation

`tieredvol_mirror.c` (706 lines):

- **Write**: `tv_mirror_handle()` duplicates to the mirror drive with
  `bio_alloc_clone()` fire-and-forget (`mirror_sec = logical − seg_begin`); a
  mempool (pool size 128) prevents OOM; `tv_pw_add()` records the pending
  write; success/failure updates `mirror_write_ops/errors`.
- **Read-error retry**: `tv_read_retry_work()` first calls
  `tv_pw_is_pending()` (at most 32 × 1 ms give-up attempts) to wait for the
  mirror write to drain, then clones and re-reads from the mirror; beyond that,
  it gives up.
- **rebuild**: a kthread walks the static map chunk by chunk, "read primary →
  write mirror"; synchronous I/O + `wait_for_completion`; on failure, backoff
  (10 ms doubling up to 1 s); progress reported every 10 MB.
- **rebuild_badmap**: fixed the `bi_size` computation bug caused by compound
  pages; bad-region rebuild gives `1 recovered, 0 failed` and no hang.

`tieredvol_badmap.c` (144 lines): per-disk chunk bitmap (`n_chunks = disk_sectors/
chunk`); bad-block reads zero-fill, bad-block writes are skipped; WRITE errors
are marked bad automatically in the completion callback; persisted as
`badmap_<disk>=a-b,c` in the config, compressed and written back at kernel save.

```
// mirror write (fire-and-forget, in parallel with the primary)
tv_mirror_handle(bio):
    clone = bio_alloc_clone(mempool)            // pool size 128 prevents OOM
    locate clone to the mirror drive: mirror_sec = logical − seg_begin
    tv_pw_add(clone)                            // pending ring, for read retry to wait on
    submit clone                               // success/failure updates mirror_write_ops/errors

// read-error retry
tv_read_retry_work(bio):
    for i in 1..32:
        if tv_pw_is_pending(corresponding clone): msleep(1)   // wait for the mirror write to drain
        else: break
    clone and re-read from the mirror; success → return; beyond that, give up

// rebuild (kthread, walks the static map chunk by chunk)
rebuild_kthread:
    for chunk in map:                             // static mapping, deterministic order
        read(primary) → write(mirror)             // synchronous I/O + wait_for_completion
        on failure → backoff (10 ms doubling to 1 s) retry
        report progress every 10 MB
```



## 5.6 Concurrency and Consistency Implementation

- pending-write ring: protected by the `tv_pw_lock` spinlock; pending-read
  ring: `tv_pending_lock` spinlock, per-CPU lockless.
- Ring full, MISS, and give-up timeout all have well-defined semantics
  (§4.4.2), reflected in the `err` counter.
- The hot path (mapping, single-disk submission, WC buffering) has **no shared
  locks**; the only shared spinlock is on the error/completion cold path — the
  multi-volume concurrency experiment (§6.2.3) benefits from this (±2%
  isolation).

## 5.7 Configuration, Management, and Counter Implementation

- `tieredvol_meta.c` (749 lines): INI parser + CRC32C validation; ctr()
  fail-closed on invalid parameters (removed adaptive policy values,
  out-of-range weights, duplicate drives, mirror overlapping a primary, wrong
  segment order, and so on); kernel save writes `.bak` first.
- `tieredvol_sysfs.c` + `tieredvol_msg_*.c`: sysfs attributes (e.g. `policy`
  read-only), `dmsetup message` (set_policy, set_seg_policy, borrow_off,
  mirror, stats, config).
- Statistics: per-drive `wr=/rd= ops/bytes`, `err`, borrow/mirror counts, for
  `dmsetup status` distribution verification (the correctness criterion of
  Chapter 6).

## 5.8 Testing and Tools

The implementation of the four-layer test architecture (§3.4):

**Table 5.3.** Four-layer test implementation

| Layer | File/Tool | Content |
|----|-----------|------|
| L1 unit | `tests/test_map.c` | 501 assertions: mapping formula, weight distribution, remainders, determinism |
| L2 core simulation | `tests/test_stripe_kernel.c` | 27 items: stripe boundaries, parallel split, completion semantics |
| L3 dmsetup | `scripts/stack_retest.sh`, `multi_vol_suite.sh`, `disjoint_suite.sh`, `shared_ctl.sh`, `msg_probe.sh` | Real volume creation, counter verification, multi-volume/shared-disk concurrency |
| L4 integration | `raw_solo.sh`, `auto_weight.sh`, `borrow_verify.sh`, `rebuild_min.sh`, `install_boot.sh` | solo measurement, weight search, borrow durability, rebuild, boot-time load |
| Static analysis | `make C=2 CHECK="sparse"` | sparse lock-context checking (caught the `tv_borrow_redirect` return-with-lock-held deadlock, Appendix B.6) |

`Makefile`: `all: module` (core), `test: test_map test_stripe_kernel` (L1/L2
need no kernel environment and can be compiled and run directly on the host —
fast development loop, can exhaustively enumerate mapping boundary cases).

> The toolchain (L4) is the methodological foundation of the experiments chapter
> (Chapter 6): `raw_solo.sh` produces each drive's solo measurement,
> `auto_weight.sh` derives weights from solos, `stack_retest.sh` runs the
> three-consortium measurement and counter verification, and `borrow_verify.sh`
> verifies borrow durability and reload recovery. All Chapter 6 data is produced
> by this toolchain under a fixed protocol, guaranteeing reproducibility.
> Operating details and config examples are in Appendix A.

## 5.9 Complexity and Cost Overview

The time/space costs of each path are summarized as follows (design
correspondence: §3.2.6, §4.1, §4.2, §4.3):

**Table 5.4.** Path complexity and cost overview

| Path | Time complexity | Space/Cost | Description |
|------|-----------|-----------|------|
| Hot-path mapping | O(1) (segment selection O(log m), m≤3) | table-free, stateless | Pure arithmetic; after boundary computation, disk selection is O(1) |
| Parallel split | O(n), n=drives≤4 | per-block atomic/kref | 1 sub-bio per drive (§3.2.6) |
| borrow lookup | O(1) table lookup | per-block 16 B/entry (v2) | only borrowed blocks take the lookup |
| borrow write | O(1) + borrow-region allocation | borrow-region over-provisioning | exception path, only a few whole-block writes |
| WC buffering | O(1) append | memory accumulating up to stripe_size | trades delayed landing for coalescing efficiency |
| WC flush | O(batch) | batch peak memory | shares the parallel/single-disk logic with direct submission |
| mirror write | O(1) clone | mempool pool 128 | fire-and-forget, in parallel with the primary |
| rebuild | O(total data) | single-chunk buffer | kthread, backoff retry, progress every 10 MB |
| rebuild_badmap | O(number of bad chunks) | per-disk badmap bitmap | compressed write-back to config |

> Trade-off summary: **all normal paths are O(1) with no shared locks**
> (performance claim G2); the cost of all "dynamic mechanisms" (borrowing, WC,
> mirror, rebuild) is concentrated on the **anomalous or initialization paths**
> and does not affect hot-path throughput — this is the implementation basis of
> the ±2% isolation in the §6.2.3 multi-volume concurrency result.

## Chapter Summary

Chapter 5 lands every design of Chapters 3 and 4 in about 4700 lines of code
(§5.1–§5.7), and provides a reproducible verification toolchain with the
four-layer test architecture (§5.8). The "load-bearing walls" established in
the implementation (invariants whose modification breaks correctness, §5.2.2)
and the failure records in Appendix B are the prerequisites for the credibility
of the Chapter 6 experiments — all measurements were performed on an
implementation already verified by L1/L2/L3.
