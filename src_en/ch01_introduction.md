# Chapter 1 Introduction

> **Chapter guide:** §1.1 explains the research motivation (heterogeneous-drive
> coexistence and existing limitations); §1.2 defines the four subproblems P1–P4 and
> their verification methods; §1.3 scopes the research and defines terminology; §1.4
> lists the five contributions; §1.5 ties together the whole-document map with the
> traceability matrix "Goal → Design → Implementation → Verification"; §1.6 describes
> the thesis organization.

## 1.1 Research Background

### 1.1.1 The Reality of Heterogeneous Storage Coexistence

In modern systems, a single host mounting multiple storage devices with **widely
varying performance** is the norm rather than the exception. The actual devices on
this thesis's experimental platform illustrate the point:

**Table 1.1.** Heterogeneous drives on the experimental platform (sorted by solo, descending)

| Device | Interface | Sequential write (measured solo) | Ratio vs. slowest drive |
|--------|-----------|---------------------------------|-------------------------|
| WD SN750 NVMe | PCIe3.0 x4 (CPU-direct) | ~2.0–2.1 GB/s | ~10× |
| P3 Plus NVMe | PCIe2.0 x4 (PCH) | ~1.5 GB/s | ~7× |
| MX500 SATA SSD | SATA 3 | ~0.52 GB/s | ~2.5× |
| WD Blue SATA SSD | SATA 3 | ~0.22–0.27 GB/s | 1× |

If a traditional mechanical HDD is added (sequential write is commonly only
~0.1–0.2 GB/s), the gap between fast and slow drives can reach **tens of times**.
These devices coexist because of the combined effect of hardware, cost, and usage
scenarios:

![Figure F1: the reality of heterogeneous storage coexistence (figs/F1_motivation_en.svg)](figs/F1_motivation_en.svg)

> **Figure F1.** Left: schematic of the experimental platform host (CPU-direct vs
> PCH/DMI). Right: the relative speeds of the four drives (fastest ≈10× the slowest).
> The two bands below represent the existing limitation and the motivation of this
> study, respectively.

- **Cost**: per-unit-capacity prices follow NVMe > SATA SSD > HDD. With a limited
  budget, users tend to choose "a few fast NVMe drives + many inexpensive slow
  drives" rather than an all-high-speed fleet.
- **Existing hardware**: the interface resources provided by motherboards are
  limited and heterogeneous——the number of CPU-direct PCIe lanes is fixed, the
  southbridge (PCH) shares bandwidth over the DMI upstream link, and the SATA
  interface capacity is far lower than PCIe. Drives that are already installed do
  not disappear just because "a faster drive arrives," so old and new devices
  naturally coexist.
- **Use-case differences**: hot vs. cold data, random small I/O vs. large
  sequential I/O, latency-sensitive applications vs. capacity-focused backups——
  different workloads inherently demand different things from storage, so a
  heterogeneous configuration is, to some degree, a reasonable choice.

### 1.1.2 Existing Limitations in Heterogeneous Environments

Operating systems (and the file systems, databases, and applications layered on top)
treat every disk by default as an **independent, performance-symmetric** device.
This causes two practical problems:

1. **Manual management burden**: users must decide for themselves which drive stores
   each piece of data. Once data placement is unbalanced, fast drives sit idle while
   slow drives are congested, and overall performance is dragged down by the slowest
   device; manually migrating data is both time-consuming and error-prone.
2. **Mismatched striping assumptions**: to make multiple drives work together,
   software commonly uses **striping**——assigning data to drives in turn in
   fixed-size chunks. Classic striping (hardware RAID 0, Linux `dm-striped` [2], LVM
   striped [9]) **assumes equal-speed drives**. On heterogeneous drives, equal-weight
   striping feeds a fixed proportion of data (an equal amount) to the slow drive,
   making it the bottleneck and dragging the fast drives down: even if a fast drive
   receives only a small share of the data, the throughput of the whole I/O pipeline
   is limited by the slow drive's write time for its portion.

### 1.1.3 Device Mapper and Existing Targets

Linux provides **Device Mapper** (dm), a stackable block-device framework that allows
multiple physical devices to be combined into one logical device in software (see
Chapter 2). Existing targets each solve part of the problem:

- `linear`: **linearly concatenates** multiple drives into one large volume——but it
  does not distribute I/O, so other drives sit idle while one drive is busy;
- `striped`: **equal-weight striping**——assumes equal-speed drives; on heterogeneous
  drives the slowest drive becomes the bottleneck;
- `mirror`: **synchronous mirroring**——prioritizes reliability over performance;
- `cache`: a **two-tier cache** with SSDs as the fast tier and HDDs as the slow
  tier——essentially "hot-data placement" rather than "parallel throughput
  allocation."

**No existing target performs weight-based allocation for the "performance
disparity" of heterogeneous drives.** Equal-weight striping treats the performance
disparity as nonexistent; two-tier caching reduces it to just two classes (fast/slow)
and relies on the cache hit rate.

### 1.1.4 Research Motivation

This study therefore proposes **TieredVol**: a dm target centered on **weighted
striping**. The administrator assigns each drive a weight
**proportional** to its performance (e.g., 10:5:2:1), and TieredVol distributes I/O
across the drives according to these weights, so that:

- **every write is distributed in parallel across all drives**, rather than "hot data
  to fast drives, cold data to slow drives"——fundamentally preventing the slow drive
  from bearing an entire write stream alone;
- **the slow drive receives only the proportion matching its capability**; fast
  drives do more, slow drives do less, pushing aggregate throughput toward the
  theoretical bound given by the "bottleneck model";
- weight selection is supported by a **mathematical model and tooling**, rather than
  empirical tuning.

## 1.2 Problem Definition

The core problem addressed by this thesis splits into four subproblems, each with a
clearly defined method of verification:

**P1: Weighted striping and deterministic mapping.**
Given n drives, a weight vector W=(w₁,…,wₙ), and a chunk size c, how can logical
addresses be divided across the drives in proportion to their weights? The mapping
must simultaneously satisfy:
- **determinism**: the same logical address always lands on the same position of the
  same drive (reproducible and verifiable);
- **O(1)**: accomplished with constant-time arithmetic (no table lookups, no
  indices), keeping the hot path lock-free and callable from constrained contexts
  such as hardirq;
- **byte-exactness**: every logical byte belongs to exactly one drive (the
  distribution can be verified exactly).

**P2: Performance modeling.** What is the upper bound on aggregate throughput for a
heterogeneous drive set? Can it be **predicted precisely** from each drive's
sequential performance (solo) and the weights? Furthermore, how should weights be
chosen to reach the bound?

**P3: Dynamic balancing.** Weights and actual performance can drift apart over time
(slow drives aging, fast-drive SLC depletion, drive load drift). Can a few writes be
temporarily offloaded (borrowed) **without breaking the deterministic layout**, to
compensate for a slow drive's temporary degradation?

> **This item is positioned as a supporting/conditional mechanism**: its primary claim is the
> consistency invariants that preserve the deterministic layout plus persistence/reload recovery
> (the correctness layer); the performance benefit holds only when a slow drive is the true
> bottleneck and is topology-dependent (§6.5). The headline claims remain P1, P2, and P4.

**P4: Multi-device management and fault tolerance.** Can mirroring, rebuild,
bad-region handling, concurrency consistency, and small-write performance all be
integrated into **a single target**, without introducing any additional errors along
the way (err=0)?

## 1.3 Scope and Terminology

The scope of this study is defined as follows:

- **Focus on sequential throughput**: the most direct benefit of heterogeneous-drive
  cooperation is in large sequential I/O (where striping excels). Random small I/O
  (4 K class) is examined in a comparative manner (Chapter 6, §6.4) but is not a
  primary claim.
- **Single host, single dm target**: distributed storage, multiple hosts, and network
  storage are out of scope.
- **Software layer only**: no hardware changes and no modification of the kernel
  block-layer scheduler; everything is done inside the dm target.
- **Validation platform**: 1–4 drive configurations on a real B85 platform with a
  Linux kernel serve as the validation environment.
- **Supporting mechanism (borrow) positioning**: weight borrowing is an exception
  path over the deterministic layout; its claim is primarily mechanism **correctness**
  (consistency invariants, persistence, and reload recovery), and its performance
  benefit is a **conditional auxiliary**—it holds only when a slow drive is the true
  bottleneck and is topology-dependent (§6.5).

Key terminology used in this thesis:

**Table 1.2.** Key terminology definitions

| Term | Definition |
|------|------------|
| stripe | one weight-allocation cycle: the sum of wᵢ chunks taken by each drive per its weight |
| chunk | smallest unit of allocation (fixed at 1 MB in this thesis) |
| segment | a contiguous region of logical space with a fixed drive set and weights; multiple segments are used when capacity is insufficient |
| solo | sequential write rate of a single drive exclusively owning the interface (measured baseline) |
| steady-state drain state | the TLC steady-state rate measured after saturating the NVMe SLC cache by first writing a large amount of data |
| weight borrowing (borrow) | a mechanism that temporarily offloads whole writes to a fast drive's borrow region when the slow drive is heavily loaded |

## 1.4 Research Objectives and Contributions

This thesis designs, implements, and evaluates TieredVol, contributing the following
five points:

**Contribution 1: Weighted striping + deterministic table-free O(1) mapping.**
  Proposes a weighted distribution built from pure arithmetic (modulo division +
  cumulative boundary): no mapping table, no state, lock-free hot path, safely
  callable from any context. The distribution is byte-exact and reproducible;
  experiments use counters to verify that, for multiple weight sets, the distribution
  matches the weights exactly (Chapter 3, §3.2 and Chapter 6, §6.2).

**Contribution 2: Bottleneck performance model and automatic weight tool.**
  Proposes the aggregate-throughput model `T(W) = minᵢ(soloᵢ × ΣW/wᵢ)` and proves
  that `T = Σsoloᵢ` when weights are proportional to solo (Chapter 3, §3.3).
  Implements the `auto_weight` tool, which exhaustively searches for near-optimal
  weights from solo measurements; the model bound reaches 99%+ of Σsolo (measured
  93.7%, a 70.6% improvement over equal weights); it also handles weight correction
  under the shared bus (DMI) (DMI-aware, Chapter 3, §3.3.3). In the weight-matched
  steady-state main-table scenarios, the measured hit rate is within ±5% (the
  four-drive steady-state S4 reaches a -1.6% deviation); the auto_weight S4 deviation
  of -5.9% is an exception attributable to enumeration granularity; an additional
  -10.8% deviation was observed in a decay re-test with 6:1:1:1 weights (hardware
  decay, Chapter 6, §6.3).

**Contribution 3: Dynamic weight borrowing (borrow table).**
  Without breaking the deterministic layout, temporarily offloads slow-drive writes
  at a fine granularity (128 KB blocks); a per-block table records destinations, is
  persistent, and fully restores after reload (4 G verification, 0 errors).
  Resolves the conflict between "weight mismatch" and "dynamic drive selection
  breaking determinism" (Chapter 4, §4.1 and Chapter 6, §6.5).
  This contribution claims **mechanism correctness**; the performance gain is a
  **conditional auxiliary** (holds only when a slow drive is the true bottleneck and
  is topology-dependent, §6.5).

**Contribution 4: Multi-device management and fault-tolerance integration.**
  Synchronous mirroring, bad-region rebuild (rebuild_badmap), pending-write/read
  concurrency consistency, and small-write write coalescing (WC) are integrated into
  a single target, throughout with `err=0` and crc32c 8 G verify 0 mismatch
  (Chapter 4, §4.2–4.4 and Chapter 6, §6.2).

**Contribution 5: Four-tier test architecture and performance analysis on a real
heterogeneous platform.**
  Builds a four-tier verification architecture——"unit tests → kernel simulation →
  volume creation with dmsetup → fio integration" (Chapter 5, §5.8)——and reveals
  three hardware insights of general value to storage system design on a real B85
  platform:
  (1) the PCIe slot (x1 vs x4) makes the solo of the same NVMe differ by 3.7×;
  (2) the PCH DMI upstream bandwidth wall (~1300 MB/s) caps three-drive concurrent
      writes at "solo_A + DMI", with drive C only adding capacity; after DMI-aware
      weights (§3.3.3) lower the DMI drives' share, the four-drive concurrent-write
      bottleneck returns to drive A (S4 steady-state -1.6% hit), showing that the
      "shared-bus budget" must be incorporated into weight design;
  (3) NVMe SLC-cache transients create measurement artifacts in cold-state short
      writes, which must be eliminated with the drain-state protocol
      (Chapter 6, §6.3–6.6).

## 1.5 Traceability Matrix (Goal → Design → Implementation → Verification)

The matrix below maps the seven design goals of Chapter 3, §3.1.1, one-to-one onto
the design, implementation, testing, and experimental evidence in subsequent
chapters. During the oral defense or review, any goal can be traced along this matrix
to "how it was done" and "where the evidence is."

**Table 1.3.** Traceability matrix (Goal → Design → Implementation → Verification)

| Goal | Design (ch03/04) | Implementation (ch05) | Test tooling | Experimental evidence (ch06) |
|------|------------------|-----------------------|--------------|------------------------------|
| G1 determinism | §3.2 table-free O(1) mapping | §5.2 `tv_map_logical` | `test_map.c` (501) + L3 counters | §6.2.1 byte-exact distribution |
| G2 low hot-path cost | §3.2.3 pure arithmetic, lock-free | §5.2 hot path | `test_map`/`test_stripe_kernel` | §6.2.3 concurrent isolation ±2% |
| G3 performance | §3.3 bottleneck model | §5.8 `auto_weight.sh` | L4 fio | §6.3 model hits within ±5% in weight-matched scenarios |
| G4 correctness | §3.2.4 load-bearing invariant + §5.2.2 completion semantics | §5.2 | L1/L2/L3 | §6.2.2 `err=0`, crc32c 0 mismatch |
| G5 dynamic balancing | §4.1 weight borrowing | §5.3 borrow | `borrow_verify.sh` | §6.5 4 G verify/reload |
| G6 fault tolerance | §4.3–4.4 mirroring/rebuild/concurrency | §5.5–5.6 | `rebuild_min.sh`, fault injection | §6.2.2 no-hang |
| G7 manageability | §4.5 config/sysfs/counters | §5.7 | `msg_probe.sh` | §6.2 counter verification |

> This table also serves as a scope-control tool: any new feature that cannot be
> matched to a goal and its verification in this table is outside the scope of this
> thesis (cf. §1.3).

### Three-Level Alignment: Problem → Contribution → Goal

Below the matrix, we provide a three-level "problem–contribution–goal" alignment that
ties together the four subproblems of §1.2, the five contributions of §1.4, and the
seven goals of §3.1.1, so that no layer has anything "extra or missing":

**Table 1.4.** Three-level alignment of Problem → Contribution → Goal

| Problem (§1.2) | Corresponding contribution (§1.4) | Corresponding goals (§3.1.1) |
|----------------|-----------------------------------|------------------------------|
| P1 weighted striping + deterministic mapping | Contribution 1 | G1 determinism, G2 low hot-path cost |
| P2 performance modeling and weight selection | Contribution 2 | G3 performance |
| P3 dynamic balancing (without breaking determinism) | Contribution 3 | G5 dynamic balancing |
| P4 multi-device management and fault tolerance | Contribution 4 | G4 correctness, G6 fault tolerance, G7 manageability |
| (verification methodology) | Contribution 5 | All (as evidence) |

> Contribution 5 is the "methodology and evidence" layer: it does not add a
> functional goal but provides a reproducible verification framework and platform
> insights for the other four (the libaio measurement choice corresponding to D10 in
> Chapter 4, §4.6 also belongs to this layer).

## 1.6 Thesis Organization

This thesis comprises seven chapters, organized as follows (the front matter contains
the abstract, notation, and abbreviations; Appendix A collects the detailed
measurement-protocol procedures and config examples):

- **Chapter 2**: background on the Linux storage stack and Device Mapper; a
  comparison of existing striping / tiered-cache / mirroring approaches; related
  performance models; and the positioning of this thesis.
- **Chapter 3**: TieredVol system design (I)——architecture overview; weighted
  striping and the deterministic mapping (full derivation); the bottleneck model and
  automatic weights (including DMI-aware); test-architecture design.
- **Chapter 4**: TieredVol system design (II)——advanced mechanisms and fault
  tolerance: weight borrowing, write coalescing, mirroring and rebuild, concurrency
  consistency, configuration and management.
- **Chapter 5**: TieredVol implementation——module structure, data structures, key
  flows, the four-tier test architecture, and the toolchain.
- **Chapter 6**: experiments and evaluation——environment and measurement-protocol
  definitions, correctness and determinism, performance and model validation,
  comparison against LVM, targeted tests, and a discussion of limitations.
- **Chapter 7**: conclusions and summary of contributions.

## Chapter Summary

This introduction defined the four subproblems (P1–P4), five contributions, and
seven goals that this thesis addresses, and laid out the whole-document map at a
glance with the "traceability matrix" and the "problem → contribution → goal
alignment table." The following chapters answer in turn: Chapters 3 and 4 cover the
design answering P1–P4; Chapter 5 presents the corresponding implementation;
Chapter 6 validates every claim with evidence from a real platform (including three
hardware insights of general value to storage design); and Chapter 7 summarizes the
thesis and ties together the discussions of limitations.
