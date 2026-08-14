# Chapter 6 Experimental Evaluation

> **Chapter guide:** §6.1 defines the environment, the three measurement protocols, and the repeatability rules (**if the
> protocols are not kept distinct, the data will disagree**); §6.2 covers correctness and determinism; §6.3 performance and
> model verification (main tables plus three hardware insights); §6.4 comparison with LVM
> plus random I/O and mixed read/write workloads; §6.5 targeted tests; §6.6 limitations. Operational details are given in Appendix A.

This chapter builds on the design of Chapters 3 and 4 and the implementation of Chapter 5, verifying each claim on a real
heterogeneous platform. §6.1 defines the environment and measurement protocols (**the three protocols must be kept distinct**,
otherwise the data will disagree); §6.2 correctness and determinism; §6.3 performance and models; §6.4 comparison with LVM;
§6.5 targeted tests (borrow/mirror/WC/concurrency); §6.6 limitations.

## 6.1 Environment and Measurement Protocols

### 6.1.1 Hardware Platform

**Table 6.1.** Experimental Hardware Platform

| Component | Specification |
|------|------|
| Motherboard | MSI B85M-G43 (B85 chipset; measured PCH DMI upstream ~1300 MB/s; PCIe2.0 x1/x4 slots on PCH) |
| CPU | Intel Core i5-4570 (4C/4T, Haswell) |
| Memory | DDR3-1600 4 GB × 2 = 8 GB (dual channel) |
| Drive A | WD SN750 NVMe, connected via **CPU PCIe3.0 x4 direct link**, solo write ~2.0–2.1 GB/s |
| Drive B | P3 Plus NVMe, **PCH PCIe2.0 x4** (later phase of experiments), solo write ~1.5 GB/s |
| Drive C | MX500 SATA SSD, solo write ~0.52 GB/s |
| Drive D | WD Blue SATA SSD, solo write ~0.22–0.27 GB/s |

> **Slot topology decides everything:** with drive B in a PCH x1 slot, solo is only ~0.41 GB/s; in the x4 slot it reaches
> ~1.5 GB/s (3.7×, see §6.3.5). Therefore **all solo measurements are taken on the "final settled topology"**,
> and both the weights and the models assume that topology. Config files always specify drives by **by-id**, immune to nvme
> device-number drift.

![Figure F8 Experimental platform topology (figs/F8_platform_en.svg)](figs/F8_platform_en.svg)

> **Figure F8.** Drive A uses the CPU direct link; B/C/D go through the PCH (sharing DMI ≈1300 MB/s). The final weights
> [64:27:9:4] are DMI-aware (§3.3.3); C also serves as the mirror drive. The table below lists each drive's solo
> numbers alongside the weights (the measurement premise for the main tables in §6.1.3).

**Software environment:** Linux kernel (with dm framework support); fio 3.x; driver `tieredvol` v5.0.0.
Experiments run on an idle system with no other I/O load.

**Environment controls** (eliminating measurement noise; every experiment complies):

**Table 6.2.** Environment Controls

| Control | Method | Purpose |
|--------|------|------|
| CPU frequency | `cpupower frequency-set -g performance` (turbo state fixed) | Avoid frequency scaling affecting throughput |
| Interrupts/softirqs | Not pinned; record CPU utilization to confirm no anomalies | Avoid irq pinning introducing artificial differences |
| swap | `swapoff -a` before experiments; confirm no swap | Avoid memory paging skewing the timing |
| page cache | `--direct=1` | Bypass page cache, measure the device directly |
| background load | System idle, only the experiment process | Eliminate interference |
| repeatability | Every cell of the main tables and comparisons **takes the median of 3 runs**; re-measure if difference >5% | Counter residual SLC/thermal effects |

### 6.1.2 Measurement Protocols (Three)

NVMe SSDs have a built-in **SLC cache band** (writes land in SLC first, then move to TLC), so the rate of "short writes"
drifts substantially with how full the cache is—re-measuring the same volume in the same session can differ by 20%. To
obtain **reproducible** data, define three protocols and annotate them in every table:

**Table 6.3.** Definitions of the Three Measurement Protocols

| Protocol | Procedure | Purpose | When applicable |
|------|------|------|----------|
| **P1 drain state (steady-state)** | Create volume → first write **≥64 G drain** (discarded) to fill SLC → `dmsetup remove` + recreate to zero the counters → write **16 G measurement** → `dmsetup status` to verify distribution → read 16 G | Reproducible **TLC steady-state** data | Stacked-drive tables, model verification (free from SLC interference); main-table S4 uses a 20 G volume, stacked-drive uses 100 G volumes (volume capacity; measured write is always 16 G) |
| **P2 cold (SLC-fresh)** | After reboot/sufficient idle, short write; data lands in the SLC band | Maximum value of the fast drives under the **SLC margin** | auto_weight staircase (fast-drive-dominated scenarios) |
| **P3 cold state + 60 s idle** | Same as P2, but with **60 s idle between each round** to let the P3 Plus SLC recharge | Makes cold-state short writes **reproducible** | B@x4 main table (S1–S3/MIR) |

**Measurement command:** `fio --rw=write|read --bs=1M --size=8G --direct=1 --ioengine=libaio
--iodepth=32 --numjobs=1`.

> **Figure F12 (SLC smoothing curve, measured):** the x-axis is cumulative write volume (GB), the y-axis is instantaneous
> throughput (MB/s). The second measurement batch on the night of 8/14 (`docs/data/slc_curve_{20g,100g}.txt`) was taken
> under the **60 s recharge protocol** (60 s idle between each GB, a P3-class condition) and shows S4 under
> `[64:27:9:4]` (borrow off) **flat throughout, with no observable decay**: 20G carve, 80 points, mean **3278**
> (range 2798–3413); 100G carve, 40 points, mean **3137** (2829–3357), neither with any trend. The reason lies in the
> "**A-bound capping**" of §6.3.1—64:27:9:4 makes the bottleneck return to drive A, and A's steady-state solo (~2064) is the
> ceiling, so the aggregate 1M sequential write **hits the ceiling from the start** (`solo_A×104/64 ≈ 3354`), leaving no
> room for the SLC bonus to show. The SLC transient is only observable in configurations where "A is not the bottleneck"
> (e.g., the 8/12 cold-state stacked-drive run 1981→2661→2787→3091). **This figure demonstrates that the design intent of
> "the drain protocol eliminates the SLC artifact" has been achieved**—even though the 60 s recharge restores the SLC band,
> A-bound capping still keeps the aggregate write stably pinned at the ceiling, and the measurement is not disturbed by the
> SLC bonus.

![Figure F12 SLC flat curve (figs/F12_decay_en.svg)](figs/F12_decay_en.svg)

> **Figure F12.** The blue/green solid lines are the per-GB measured points of the 20G/100G carves under the 60 s recharge
> protocol (flat, no trend); the red dashed line is the model ceiling `solo_A×104/64 ≈ 3354`, and the measurements match it.
> Compared with the jittery curve of the 8/12 cold-state stacked-drive run (an SLC artifact, retired in Appendix B.2), this
> figure proves that **under an A-bound configuration even the 60 s recharge protocol (the condition most likely to expose
> the SLC bonus) stays flat**—the measurement is stable. Both the S4 main table (drain state P1) and F12 (60 s recharge, a
> P3-class condition) in the §6.1.2 tables sit at the ceiling, cross-validating that the two protocols agree.

**Why not io_uring:** io_uring + dm + deep queues inflate the throughput to levels that do not reflect the real hardware
limit (a common application pitfall [10]); libaio at depth 32 is enough to saturate all drives on this platform. All numbers
in the thesis are based on libaio, and §6.6 discusses this methodological choice.

**Criterion (distribution verification):** after each volume is written, use `dmsetup status` to read each drive's
`wr=<ops>/<bytes>` and compare against the weight ratio. Complete stripes are assigned **exactly** per the weights; the
residual chunks of an incomplete stripe fall into the leading drives per the mapping—this is a directly verifiable
consequence of the **deterministic O(1) mapping**, with each byte landing on exactly one drive.

### 6.1.3 Main Data Tables (B@x4 + D Topology, Core of the Thesis)

**Table 6.4.** Main Data Tables (S1–S4 / MIR)

| Volume | Drives | Weight | Write(MB/s) | Read(MB/s) | Protocol | Distribution Verification |
|----|------|------|-----------|-----------|------|----------|
| S1 | 1 (A) | 1 | 2080 | 3112 | P3 | A=100% |
| S2 | 2 (A+B) | 37:27 | **3547** | 3899 | P3 | 37:27 exact (cumulative 34.76G:25.37G) |
| S3 | 3 (A+B+C) | 64:30:10 | **3370** | 4323 | P3 | 64:30:10 exact |
| S4 | 4 (A+B+C+D) | 64:27:9:4 | **3300** | 4292 | P1 | 64:27:9:4 exact (A=10104M/B=4239M/C=1413M/D=628M) |
| MIR | 2 (A+B→C) | 37:27 | 457 | **3799** | P3 | mirror fully mirrored; read distribution A:B=4:3 exact, C=0 |

![Figure F9 Main-table write staircase (figs/F9_staircase_en.svg)](figs/F9_staircase_en.svg)

> **Figure F9.** Write throughput staircase of the main-table S1–S4/MIR (P1/P3 protocols, values finalized on the afternoon
> of 8/14). S2 3547 > S3 3370 because S3 hits the DMI wall (§6.3.4); S4 3300 is the drain-state value under the DMI-aware
> weights with the bottleneck returned to drive A (-1.6%, §6.3.1); MIR 457 is the dual-write cost of synchronous mirror
> writes.

> S4's `[64:27:9:4]` is the DMI-aware weight (§3.3.3), measured in the drain state (P1) at **3300/4292**,
> with the distribution matching chunk by chunk and zero error. The weights keep the combined B+C+D traffic within the DMI
> budget: in the drain state the B+C+D write share is ≈ **1269** MB/s (= 3300×40/104) < DMI 1300, so the bottleneck
> returns to drive A itself, and `T = solo_A×104/64 ≈ 2064×104/64 ≈ 3354` hits (deviation -1.6%, §6.3.1)—this is
> precisely the design goal of the DMI-aware weights: not letting non-A traffic exceed the DMI limit. **Note:** A carries
> ≈2031 (= 3300×64/104), only ~98% of solo_A, and B+C+D is also only ~2.4% short of the DMI limit, so both are near
> saturation; the measured 3300 is simultaneously slightly below the A model 3354 and the DMI model 3364, so "bottleneck
> returned to drive A" is the **intent** of the weight design rather than a reading that can be precisely distinguished from
> "DMI saturation." The cold (fresh) S4 write is 3091 (§6.4.1, due to the SLC transient). **S4 is measured with borrow
> off**: borrow-on redirects D's share to A's borrow area, aggravating A's bottleneck and dropping the write to ~2517
> (§6.5 B4; not a correct production choice). The MIR read 3799 was measured on `m_mir2.conf` (A:B=4:3), nearly the same
> ratio as the main-table 37:27. **Note:** S2 3547 > S3 3370—because S3 already hits the DMI wall (see §6.3.4); this is
> exactly the evidence that "the shared upstream bus is the stricter constraint," not a measurement error.

## 6.2 Correctness and Determinism

### 6.2.1 Byte-Exact Distribution

**Table 6.5.** Weight Distribution Counter Verification

| Weight | 16 G write counts | Ratio | Remarks |
|------|-------------|------|------|
| 6:1 | A=14044 MB, B=2340 MB | 6.0017:1 | Residual chunks all fall on A (leading drive); expected, not an error |
| 6:1:1:1 | A=10924, B=C=D=1820 MB | 6.002:1:1:1 | Same as above |
| 37:27 | 34.76 G : 25.37 G | exact | Cumulative large writes still exact |
| auto_weight groups | per weight | exact | Distribution under exhaustive weights still byte-correct |
| DMI-aware | per weight | exact | Distribution under manually scaled weights still correct |
| 64:27:9:4 (drain state) | A=10104/B=4239/C=1413/D=628 MB | exact | Matches the deterministic mapping chunk by chunk, zero error |
| 4:3:2 (D8) | per weight | exact | Byte-identical in both directions after remove/re-create |

Key point: **"correct weights" and "good performance" are two different things** (see §6.3.3)—an exact distribution only
proves the deterministic mapping is right; whether the weights match the speed ratios is what determines performance. Both
are verified by counters and are not conflated.

### 6.2.2 Integrity

- **crc32c 8 G write + verify**: 0 mismatch, `err=0` throughout (including after the WC small-write bug fix).
- **borrow persistence**: 4 G write + verify err=0; after `dmsetup remove`/recreate, loading the `.borrow` mapping restores
  state, and another 4 G verify still has 0 errors.
- **rebuild_badmap**: bad-region rebuild `1 recovered, 0 failed`, no hang.
- **D7 WC read-after-write** (`m_wc.conf`, A:B=64:36, chunk 1M, stripe 100M): a 4M 0xD5 write reads back all 0xD5
  immediately; overwriting [4M,8M) with 0x3C reads back all 0x3C; [0,4M) remains 0xD5; fio 6 G `--verify=pattern
  --do_verify=1` gives 0 mismatch, and a persistence re-read of 6 G gives 0 mismatch. This confirms that the "read triggers
  flush" semantics are correct (the WC buffer is not lost).
- **D8 deterministic reproduction** (`m_d.conf`, A:B:C=4:3:2, stripe 9M): after vol1 writes the ramp, `dmsetup remove` +
  re-create → read back byte-exact; vol2 overwrites with 0x3C and reproduces the same way; the same weights re-created give
  byte-identical results in both directions → **the mapping is a pure function (stateless, no randomness)**.
- **C5 mirror read retry (fail injection)** (`m_mir2.conf`, disk0=dAerr): mount a 1M dm-error window (41943040 sectors) at
  A[4G,4G+1M); reading volume [7168M,7169M) hits an A err → automatic fallback to the mirror → **successfully reads back
  byte-exact 0xD5** (the data must come from C's mirror region, verified with `cmp`). Known minor quirk: mirror-retry reads
  are not counted in per-disk `total_read_ops`.
- **C6 write error → automatic badmap + zero-fill** (`m_bad.conf`, single drive dAerr): writing 16 G hits EIO at the
  window → the badmap chunk (4096) is marked automatically; reading the bad chunk returns **all zeros** (zero-fill);
  rewriting the bad chunk **succeeds** (badmap skip, data stays 0); sysfs reports `err=1`.

### 6.2.3 Concurrent Multi-Volume

- **Concurrency of two volumes that share nothing at the driver level**: performance is isolated (±2%)—confirming the hot
  path has no shared locks (the design promise of §4.4.3).
- **Concurrent writes on shared drives drop ~40%**: purely drive-resource contention (when two volumes write the same fast
  drive concurrently, the two rates sum to ≈ the fast drive's solo), not a driver defect. This distinction matters for the
  "driver overhead" claim: overhead and drive contention are separable.

## 6.3 Performance

### 6.3.1 Bottleneck Model Hit

Per §3.3.1's `T = min(soloᵢ × ΣW/wᵢ)`, the measured hits across topologies and weights:

**Table 6.6.** Bottleneck Model Hits (Multiple Topologies, Multiple Weights)

| Scenario | Weight | Measured(MB/s) | Model(MB/s) | Deviation |
|------|------|-----------|-----------|------|
| Drain-state S4 | 6:1:1:1 | 1760 | D×9 ≈ 1760 | 0% |
| B@x4 S2 | 37:27 | 3547 | solo_A×64/37 ≈ 3571 | -0.7% |
| B@x4 S3 | 64:30:10 | 3370 | solo_A+DMI ≈ 3364 | +0.2% |
| **B@x4 S4 (drain state)** | **64:27:9:4** | **3300** | **solo_A×104/64 ≈ 3354** | **-1.6%** |
| Drain-state S1/S2/S3 | 6:1:1:1 | 1360/1667/1999 | each drive's solo dominates | close fit |

**Analysis:** the drain-state stacked drives (P1) are the purest model demonstration—

- Writes are **strictly monotonic 1360 → 1667 → 1999** as drives go from 1→2→3 (each added drive raises throughput);
- After adding the 4th drive D (the slowest), `T = D×9 ≈ 1760` **hits exactly (§3.2)**—D becomes the bottleneck, and 4
  drives no longer improve, even falling below 3 drives (1999). This is not degradation; it is what the model predicts:
  under weight 6:1:1:1, D's share (1/9) pins the total throughput to D's solo.
- **B@x4 S4 [64:27:9:4] (drain state, borrow off) measures 3300**: this weight is DMI-aware (§3.3.3); the combined B+C+D
  traffic is held within the DMI budget (≈1269 < 1300), so the bottleneck returns to **drive A itself**:
  `T = solo_A×104/64 ≈ 2064×104/64 ≈ 3354`, hit at -1.6%—confirming that "when the weight design is right, the model is
  predicted by the fastest constrained resource"; it also directly validates the purpose of the weight derivation in §3.3.3.
  (Note: B+C+D is only ~2.4% short of the DMI limit and A is not at full solo (~98%), so both constraints are near
  saturation; the intent of DMI-aware is "not letting non-A traffic exceed the DMI limit," not claiming DMI has large
  headroom, see the note in §6.1.3. S4 must be measured with borrow off: borrow-on redirects D's share to A, aggravates A's
  bottleneck, and drops the write to ~2517, see §6.5 B4—not a production choice.)

This set of data proves that (§3.2) is not only an upper bound: **it is reachable when the weights match, and accurately
predicts the bottleneck when they do not.**

![Figure F10 Bottleneck model vs. measured (figs/F10_model_en.svg)](figs/F10_model_en.svg)

> **Figure F10.** Paired bars of model vs. measured for each weight set in the main tables. All weight-matching scenarios
> S1–S4 hit within ±5%, with S4 in the drain state at **-1.6% deviation**. The model includes the DMI-aware budget
> (§3.3.3): S3's model value is `solo_A + DMI ≈ 3364`; S4's model value is `solo_A×104/64 ≈ 3354` (A is the bottleneck,
> B+C+D held within the DMI budget).

### 6.3.2 Auto Weight (auto_weight)

Using `scripts/auto_weight.sh` to enumerate (base 2..40, floor/ceil ±1 per weight, cap 128, based on 8 G average solo) to
derive the weights, measured in the cold state (P2). **This batch of data is from the morning of 8/14 on the B@x1
topology**: solo (8 G average) A=2056.5, B=413.1, C=518.0, D=220.3 (Σsolo=3208)—a **different topology** from the §6.3.1
main tables (afternoon of 8/14, final B@x4 topology), hence a different weight system (10:2/20:4:5/56:11:14:6 vs
37:27/64:30:10/64:27:9:4). The two tables must not be read together.

**Table 6.7.** auto_weight Results (morning of 8/14, B@x1)

| Volume | auto-weight | Measured write(MB/s) | Model | Deviation | Model/Σsolo |
|----|-------------|---------------|------|------|------------|
| S2 | 10:2 | 2410 | 2468 | -2.4% | 99.9% |
| S3 | 20:4:5 | 2896 | 2982 | -2.9% | 99.8% |
| S4 | 56:11:14:6 | **3006** | 3194 | -5.9% | 99.6% |

> Note: the "Model/Σsolo" column is the ratio of the **model bound** (the max-min value predicted by (§3.2)) to each
> volume's Σsolo, not a measured value; the **measured utilization** is 97.6%/96.9%/93.7% for S2/S3/S4
> (2410/2469, 2896/2988, 3006/3208), and S4's -5.9% deviation is exactly this gap (see below).

- The write staircase is **strictly monotonic 2078 < 2410 < 2896 < 3006**;
- S4's 3006 vs. the equal-weight 6:1:1:1's 1762 (measured morning of 8/14, see §6.3.3), a **70.6% improvement**—the value
  of matching weights;
- S2/S3 hit within ±3%; S4 deviates -5.9% (slightly over the ±5% threshold)—the auto_weight model estimates 3194 using "A
  and D in parallel," reaching 99.6% of Σsolo, but **the measurement reaches only 93.7%**; the discrete solutions of the
  enumeration landing near the drive speed ratios make the residual an artifact of enumeration granularity rather than a
  model failure, and the main table's DMI-aware manual weights (§6.3.1) are actually more precise (-1.6%).
- "Model bound/Σsolo ≥ 99.6%" means the upper bound predicted by (§3.2) is close to Σsolo; **the measured utilization
  (93.7%) is the truly reachable value**; the model still correctly points out the enumeration direction (make each drive's
  `soloᵢ×ΣW/wᵢ` as equal as possible, maximizing the weakest drive's utilization);
- **Chunk size (1 M vs 256 K) is throughput-neutral**: striping parallelism is 1 M's strength, but 256 K is no worse;
  configuration flexibility does not hurt performance.

### 6.3.3 The Cost of Weight Mismatch (Counter-Example)

Same session (night of 8/13), weight comparison: when a fixed weight ratio mismatches the drive speed ratios, the slowest
drive's weight "being 1 like the fast drives" makes it the bottleneck; after adjusting to the speed ratios it improves:

**Table 6.8.** Weight Mismatch Comparison (Equal Weight vs. Speed Ratio)

| Weight | Bottleneck drive | Bottleneck value | Measured(MB/s) |
|------|--------|--------|-----------|
| 6:1:1:1 (equal) | D | D×9 ≈ 2007 | 1966 |
| 10:2:2:1 (speed ratio) | A | A×15/10 ≈ 2673 | 2673 |

> Note: the model for the 10:2:2:1 row uses **solo ≈ 1782 with A's SLC partially full after 5.7 G already written** (not
> the cold solo_A≈2064), `1782×15/10 ≈ 2673`—consecutive same-session measurements partially fill A's SLC band;
> estimating with cold solo_A gives `2064×15/10 ≈ 3096`, which would overestimate, so the table takes the session's
> measured solo as authoritative (RESULTS, night of 8/13).

The difference is **36%**, and both distributions are **exact** (§6.2.1). This comparison clearly proves: **"correct
weights" (distribution correct) ≠ "good performance"; weights must match the actual speed ratios**. This is the necessity
evidence for auto_weight.

**Degradation re-measurement (morning of 8/14, sdb solo dropped further to 219.6)**: under the same 6:1:1:1, S4 drops
further to **1762** (model `D×9 ≈ 1976`, -10.8%), the staircase is **1983 < 2384 < 2531 but S4 falls back to 1762**;
auto_weight (9:2:2:1) pulls S4 back up to **2749** (+56%). With the same equal-weight configuration, the measurement slides
from 1966 (8/13) → 1762 (8/14) as sdb degrades, confirming that with "static weights and hardware degradation" the
bottleneck migrates from A to D—precisely the motivation for auto_weight (static weights become a mismatch). §6.6,
Limitation 5 also notes this as an unverified boundary for scale/dynamic scenarios.

**Historical lesson**: `set_policy adaptive` (a dynamic drive-selection policy that used three EMA factors to pick the
least-busy drive in real time; since removed) measured **-44%** with C/D imbalance—dynamic selection both breaks address
determinism and performs poorly, and was replaced by weight borrowing (§4.1). This data is included in the thesis as
experimental evidence for "why not dynamic drive selection."

### 6.3.4 The DMI Wall (Shared Upstream Bus)

Under B@x4, B and C (and D) all traverse the PCH DMI (~1300 MB/s) while A uses the CPU direct link and does not cross DMI:

**Table 6.9.** DMI Wall Weight Comparison

| Weight | Measured write(MB/s) | Analysis |
|------|----------------|------|
| Proportional weight [64:47:16] | 2561 | B+C contend for DMI; neither reaches its solo |
| **DMI-aware [64:30:10]** | **3370 (+32%)** | Combined B+C traffic ≈ DMI limit; A is the bottleneck |

![Figure F11 PCH DMI wall illustration (figs/F11_dmi_en.svg)](figs/F11_dmi_en.svg)

**Mathematical proof** (§3.3.3): `S3_max = solo_A + DMI ≈ 2064 + 1300 = 3364`,
`S2_max = solo_A + solo_B ≈ 3590`. Hence on the B85, **"a+b+c three-drive write" will not exceed "a+b two drives"**—C adds
capacity only, not write throughput. This is the hardware (DMI upstream bandwidth) ceiling, **not a driver defect**; the
weight [64:30:10] already pins the throughput to the ceiling (measured 3370 ≈ model 3364, +0.2%).
(Note: DMI ~1300 is the shared saturation value when multiple drives **simultaneously** use the PCH, not a per-drive hard
limit—B's solo 1522 is above 1300, and B's share in S2 ≈1497 (= 3547×27/64) likewise, so S2 3547 does not violate the DMI
wall; the wall's effect is that the B+C(+D) **combined** traffic is capped at ~1300, e.g., S3's B+C ≈1296 already touches
the ceiling.)

**S4 validates the DMI-aware design intent**: under four drives [64:27:9:4], the DMI budget (~1300) is allocated to the
combined B+C+D share (40/104), and the drain-state measured B+C+D write traffic is ≈**1269** (=3300×40/104) < 1300, with
the bottleneck returning to drive A (§6.3.1's -1.6% hit). The two data sets are complementary: the three-drive version
proves "when the weight is not corrected, DMI is the bottleneck"; the four-drive version proves "after the weight is
corrected, non-A traffic does not exceed the DMI limit"—two faces of the same hardware constraint. (Note: B+C+D is only
~2.4% short of DMI and A is not at full solo, so both constraints are near saturation, see §6.3.1 note.)

**Reads are not subject to the DMI write limit**: reads are **3112 < 3899 < 4323** (1→2→3 drives reading in parallel); the
three-drive parallel read 4323 is even higher than any write value; S4 read 4292 ≈ S3 read 4323—D is a "capacity
contributor" on the read path, not a read throughput bottleneck (reads use the CPU direct link and DMI downstream, which are
not limited by the write-direction DMI cap). The DMI wall applies only to the write direction.

### 6.3.5 PCIe Slot Effect

**Table 6.10.** PCIe Slot Effect (Drive B)

| Configuration | B solo write | a+b write |
|------|----------|----------|
| B on PCH **x1** | 415 MB/s | 2410 MB/s |
| B on PCH **x4** | 1522 MB/s (**+3.7x**) | 3547 MB/s (**+47%**) |

**Insight**: the same drive on the same motherboard differs 3.7× just by changing the slot. If solo is measured on x1 and
weights are assigned accordingly, both the weights and the model are distorted. **Performance engineering must be measured
against the "final slot topology"**; all solo numbers, weights, and models in this thesis were completed on the settled
topology (A@CPU-x4, B@PCH-x4, C/D@SATA) and are explicitly listed in §6.1.1.

## 6.4 Comparison with LVM (Including Random I/O and Mixed Workloads)

### 6.4.1 Sequential Large-Block Comparison

On the same platform, compare `dm-striped` (LVM striped [9], equal weight 1:1) against TieredVol weighted striping
(B@x4 + D return-to-pool topology, sequential 1M, 20 G, measured):

**Table 6.11.** Sequential Large-Block Comparison (vs. LVM)

| Scheme | Write(MB/s) | Read(MB/s) |
|------|-----------|-----------|
| LVM 4-drive 1M stripe 20G | 1616 | 1791 |
| TieredVol S4 (cold fresh) | 3091 | 3575 |
| TieredVol S4 (drain state, main-table P1, borrow off) | 3300 | 4292 |
| **Multiplier (cold)** | **~1.9x** | **2.0x** |

- **Reads**: TieredVol weighted striping is **2.0x (cold) to 2.4x (drain state 4292)** faster than LVM striped—the more
  fast drives, the more pronounced (LVM feeds a fixed fraction of data to the slow drives, making a slow drive the read
  bottleneck).
- **Writes**: ~1.9x (cold fresh 3091 vs 1616); drain state **~2.0x (3300 vs 1616)**. The direction is consistent with the
  earlier B@x1 topology (originally 1.96–3.5x); under B@x4 the multiplier drops slightly but the **direction is
  unchanged**.
- **4 K small writes (sequential, 8/13 old B@x1 topology)**: LVM is ~1.32x faster—4 K bios are smaller than the chunk, and
  after bypassing WC (§4.2.3), TieredVol's 4 K cost is mainly stripe splitting and placement distribution; this is a
  **known trade-off** (large blocks win in parallel, small blocks lose), and comparing both side by side is the fair
  approach. **Random 4 K has been re-measured on the B@x4 new topology (§6.4.2), where TieredVol is instead +16%**—the
  difference comes from test type (sequential vs. random) and topology (B@x1 vs B@x4); the two tables must not be read
  together.

> The comparison was re-measured on the B@x4 + D settled topology (A3, night of 8/14), and the conclusion "large-block
> TieredVol wins" holds on both slot topologies; the LVM **sequential** 4 K small-write comparison is still old-topology
> data (B@x1, LVM ~1.32x faster), while the **random** 4 K comparison is new topology (B@x4, TieredVol +16%, §6.4.2), as
> annotated in §6.6.

### 6.4.2 Random I/O and Mixed Workload Comparison

To present the complete picture of "large blocks win, small blocks lose," and to pre-answer "how does your system handle
random I/O?", the following comparison is added (B@x4 topology, second measurement batch on the night of 8/14). The protocol
is the same as §6.4.1: TieredVol is measured under **P1 drain state** (S4 `tv_s4.conf` [64:27:9:4], 20 G volume, borrow
off); LVM 4d stripe (`pvcreate` on 4 drives → `lvcreate --stripes 4 --stripesize 1M -L 20G`, then
`vgremove/pvremove` to restore the bare drives) and single drive (A, bare drive by-id direct link) are compared with the
same drain protocol (write ≥64 G first, then measure), ensuring all three sides are in TLC steady state with no SLC
transient interference.

**Table 6.12.** Random I/O and Mixed Workload Comparison (8 G, B@x4 topology)

| Test (8G) | TieredVol S4 (P1) | LVM 4d stripe | Single drive (A) | Analysis |
|------|-----------|-------------|-----------|------|
| 4 K random write | **663** | 570 | 812 | Small bios bypass WC; the cost is in stripe splitting; includes the aggregate performance of the slow B/C/D drives |
| 4 K random read | **680** | 496 | 533 | Reads are not re-written; 4-drive parallel aggregation beats a single drive |
| 1M 50:50 mixed | **R1149 / W1175** | R366 / W375 | R584 / W597 | Advantage of 4-drive aggregation under mixed load |

> Measurement command: `fio --rw=randwrite|randread|rw --bs=4K|1M --rwmixread=50
> --size=8G --direct=1 --ioengine=libaio --iodepth=32 --numjobs=1`;
> each cell takes the median of 3 runs (§6.1.1 repeatability rule). Mixed uses `--rw=randrw --rwmixread=50`, reporting one
> value for read and one for write.

**Results**: wins all three against LVM—4 K write **+16%**, 4 K read **+37%**, 1M mixed **~3.1x** (LVM 4-drive stripe
under 1M randrw seeks across the 1M strip with RMW contention, only 366/375). vs. single drive A: 4 K write 663 < 812
(**-18%**; on the small-block path, 4-drive aggregation is worse than a single fast drive; and the 1M chunk makes a 4K I/O
land on a single drive), 4 K read **+28%**, 1M mixed **~2x** (advantage of 4-drive aggregation under mixed load).

> **The 4 K conclusion depends on test type**: this is **random 4 K** (B@x4 new topology), where TieredVol is +16% vs. LVM
> (LVM's random small writes suffer RMW/cross-strip costs); §6.4.1's **sequential 4 K small writes** (B@x1 old topology)
> have LVM ~1.32x faster—"who wins small blocks" depends on sequential/random and topology, while large-block sequential
> and mixed win on both topologies. Overall this is consistent with the §6.4.1 trade-off: **4 K random I/O is not
> striping's strength over a single drive**, but **large-block sequential and mixed still win**—clearly delineating this
> thesis's applicability boundary (cf. §1.3 "focus on sequential throughput").

## 6.5 Targeted Tests

- **Weight borrowing**: when a slow drive is under high load, whole blocks are offloaded to a fast drive's borrow area; 4 G
  write verify err=0; after `remove`/reload the mapping is restored (`.borrow` persisted)—validating the four consistency
  invariants of §4.1. **The benefit is topology-dependent** (B4, two sessions on 8/13 and 8/14):
  - When the slow drive D is truly the bottleneck (6:1:1:1 equal weight): borrowing **+3%** (measured 8/13);
  - At the settled weight [64:27:9:4] (D's share only 3.85%, ≈127 MB/s ≪ solo 229): D is naturally not the bottleneck,
    **nothing to borrow, on≈off (within noise)**—the two are complementary, proving borrowing only has positive benefit in
    topologies where the slow drive is truly the bottleneck.
  - **B4 supplement (second batch, night of 8/14)**: the "neutral" above holds only with D saturated in the background.
    **When D is idle, borrow ON is instead a net loss of 16% (4 G) to 29% (8 G)**: m_s4b (borrow ON, area 2048 MB@A,
    watermark 256 KB) 1M write 4G=2769, 8G=2344 (at 8 G the 2G table fills plus unborrow write-back is slower), vs ~3300
    for borrow OFF at the same weight. Cause: D's share of writes is redirected to A's borrow area, aggravating A's
    bottleneck (A's load goes from 64/104 to ~68/104). **The main-table S4 drain-state 2517 is caused by the borrow-on
    config; the production tv_s4 taking borrow off is the correct choice** (§6.1.3 main-table 3300 is the borrow-off
    value).
  - **Design limitation**: borrow table size = 20G carve/128KB = 163840 entries × 16B ≈ 2.6 MB (header magic `TVBR`,
    version, n_blocks + entries array); the 100G carve (819200 entries ≈ 13 MB) exceeds the kmalloc limit → ctr ENOMEM.
    All active deployments use the 20G carve.
- **Mirror (MIR)**: write **457 MB/s** (A2, night of 8/14, main table), ~88% of the mirror drive C's own solo
  (≈517)—the bottleneck is the mirror drive (SATA), not the primary merge rate (in the 8/12 comparison session, primary
  aggregate 2390 vs. mirror volume 463, a ~81% loss, same origin); 4 K writes cost -52% due to COW; reads incur **0% extra
  cost** (reads are not re-written); 16 G read **3799 MB/s** with distribution A:B=4:3 exact and C=0 (§6.1.3). **Read
  retry fail injection (C5)**: a 1M error window on drive A → automatic mirror fallback → byte-exact read-back (§6.2.2).
- **WC**: after the 4 K write fix it reaches **612 MiB/s** (final build tv_s2; before the fix, 4 K was only 14→500 MiB/s);
  the large-write path is unaffected (measured against 1 M=2661 MiB/s)—WC's value is "coalescing 4 K-class small writes
  into large blocks"; the read-after-write semantics are validated by D7 (immediate read-back correct, fio 6 G verify 0
  mismatch).
- **Bad regions (badmap)**: C6 validates the complete error path of "write error → automatic marking + zero-fill + rewrite
  succeeds" (§6.2.2).
- **Concurrent multi-volume**: see §6.2.3.

## 6.6 Limitations

1. **WC power-loss consistency**: WC is a deferred-flush cache; on power loss, data not yet written from the buffer is
   lost; this implementation offers no crash guarantee. Applications requiring strict persistence should disable WC
   (`wc_enabled=N`) or rely on upper-layer barrier/fsync.
2. **Single platform and the DMI wall**: all measurements are on a single B85 platform; the DMI upstream ~1300 MB/s caps
   writes with three or more drives at `solo_A + DMI` (§6.3.4). This is a **hardware limitation**, not an algorithmic
   defect; moving to an all-PCIe3.0/4.0 x4 platform (e.g., B650M AM5) could validate multi-drive scaling of the model
   without the DMI wall. **The DMI-aware weights (§3.3.3) are precisely the solution under this constraint**: they push
   the combined non-A traffic into the DMI budget (B+C+D ≈1269 < 1300 under S4), returning S4's bottleneck to drive A
   (§6.3.1).
3. **SLC transient**: NVMe short writes land in the SLC band, causing measurement artifacts (the 8/12 table
   1981→2661→2787→3091 is exactly this kind, with same-session re-measurements jittering by 20%); therefore the P1 (drain
   state) and P3 (60 s idle) protocols ensure reproducibility, and each table is annotated with its protocol.
4. **Fairness**: the large-block vs. LVM comparison was re-measured on the B@x4 + D settled topology (§6.4.1, ~1.9x write,
   2.0–2.4x read); the **sequential** 4 K small-write comparison is still old-topology (B@x1) data (LVM ~1.32x faster,
   8/13), and the **random** 4 K comparison is new topology (B@x4, 8/14, TieredVol +16%, §6.4.2)—the 4 K winner depends on
   test type and topology, the ratios change with the slot, and the directional conclusion is anchored on large blocks.
5. **Scale**: experimental drive count ≤ 4; larger scales (multiple controllers, NVMe-oF, multi-queue/NUMA) are
   unverified.
6. **Methodology**: io_uring is not used (see §6.1.2); the numbers are libaio values of "real hardware limits"; switching
   to io_uring's inflated numbers would overestimate, so it is not adopted.

## Chapter Summary

Chapter 6 validates all claims on a real B85 platform:
- Correctness and determinism (§6.2): counters verify the distribution byte by byte (including the 64:27:9:4 drain-state
  zero error and D8 deterministic reproduction), `err=0`, crc32c 0 mismatch, mirror read-retry and badmap auto-marking fail
  injections all PASS, and full recovery after reload;
- Performance and models (§6.3): the main tables **hit the bottleneck model for all of S1–S4** (S4 drain-state 3300 with
  drive A as bottleneck at -1.6%), `T = D×9` hits exactly, the weight comparison confirms the failure of proportional
  weights, and three hardware insights of general significance to storage design are exposed (slot x1/x4 3.7× difference,
  the DMI wall, the SLC transient);
- The comparisons (§6.4), targeted tests (§6.5), and limitations (§6.6) delineate the applicability boundary—vs. LVM
  re-measured on the settled topology (~1.9x write, 2.0–2.4x read), borrowing's benefit is topology-dependent (+3% only
  when D is truly the bottleneck).

The correspondence between limitations and conclusions is wrapped up in Chapter 7.
