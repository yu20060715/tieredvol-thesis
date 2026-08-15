# Chapter 7 Conclusion and Contributions

> **Chapter guide:** §7.1 reviews the core claims and cautionary conclusions; §7.2 summarizes the contributions.

## 7.1 Conclusion

This thesis designed, implemented, and evaluated **TieredVol**: a Linux in-kernel heterogeneous
disk storage system (Device Mapper target) centered on weighted striping. For the realistic
scenario of "multiple disks with vastly different performance coexisting," TieredVol replaces equal-weight striping with **weighted allocation**,
guarantees correctness with a **deterministic O(1) mapping**,
guides weight selection with the **bottleneck model and auto_weight**, and completes dynamic balancing and fault tolerance within a single target
via **weight borrowing, mirroring, rebuild, bad regions, and write coalescing (WC)**.

The core claims confirmed by experiment (evidence for each item appears in Chapter 6):

1. **Weighted striping is correct and deterministic**: the distribution is byte-exact (all multi-weight counter groups correct, §6.2.1),
   the mapping is O(1) pure arithmetic with no tables and no locks, `err=0` throughout, and an 8 G crc32c verify with 0 mismatches (§6.2.2).
2. **The bottleneck model holds**: `min(soloᵢ × ΣW/wᵢ)` hit within ±5% under 1–4 disks, multiple weight groups, and both the steady-state drain and cold (SLC-fresh) states
   (weight-matched scenarios, §6.3.1); the purest demonstrations are the drain-state disk stack (6:1:1:1) with
   `D×9 ≈ 1760` and the B@x4 four-disk [64:27:9:4] with `solo_A×104/64 ≈ 3354`
   (measured 3300, −1.6%) — two hits; auto_weight's S4 deviation of −5.9% and the regression re-test of
   −10.8% are exceptions attributable to enumeration granularity and hardware degradation (§6.3.2, §6.3.3).
3. **Automatic weights reach near-optimality**: `auto_weight` exhaustive weights make the write staircase strictly monotonic
   (2078 < 2410 < 2896 < 3006), the model upper bound reaches 99.6% of Σsolo (measured 93.7%), and
   S4 improves 70.6% over equal weights (§6.3.2).
4. **Shared upstream bus requires DMI-aware weights**: with proportional weights, three disks sharing the PCH DMI dropped to 2561 MB/s,
   and DMI-aware weights recovered to 3370 MB/s (+32%); the "three-disk writes cannot exceed two-disk" hardware ceiling is explained mathematically
   by `solo_A + DMI`; under four-disk [64:27:9:4], the DMI budget returns the bottleneck
   to drive A, measured at 3300 with a −1.6% deviation hit (§6.3.1, §6.3.4).
5. **Reliability mechanisms integrated**: mirroring, rebuild, bad regions, weight borrowing (including persistence and reload recovery), and
   small-write coalescing operate within a single target without introducing additional errors (§6.2, §6.5).

**Cautionary conclusion**: the crux of heterogeneous-disk striping is not "correct weights" (that is a determinism problem — any weight
can yield a correct distribution), but **the match between the weights and the actual speed ratio** (that is a performance problem). A weight mismatch loses
more than 36% of throughput even with an exact distribution (§6.3.3); and the "speed ratio" itself is affected by PCIe slots (3.7×,
§6.3.5) and the shared DMI bus (capped at `solo_A + DMI`, §6.3.4) — **performance engineering must be measured on the real topology;
otherwise both the model and the data will be distorted**.

## 7.2 Summary of Contributions

1. **Weighted striping + deterministic table-free O(1) arithmetic mapping**: pure four-arithmetic-operation, byte-exact, reproducible,
   lock-free hot path (Chapter 3, §3.2).
2. **Bottleneck performance model and DMI-aware weight allocation**: proof of `min(solo×ΣW/w)` and cross-scenario verification;
   weight-correction formula under a shared upstream bus (§3.3).
3. **auto_weight exhaustive automatic weight tool**: automatically derives near-optimal weights from measurements (near-optimal, +70.6%).
4. **Dynamic weight borrowing**: an exception mechanism on a static layout, with persistence/reload recovery (Chapter 4, §4.1);
   the claim is primarily mechanism correctness, with the performance benefit conditional (§6.5).
5. **Multiple mechanisms integrated in a single target**: mirroring, rebuild, bad regions, concurrency consistency, write coalescing (§4.2–4.5).
6. **Four-layer test architecture and real-platform profiling**: unit → in-kernel simulation → dmsetup → fio; revealing the
   three hardware insights of slots, DMI, and SLC (Chapter 5, §5.8; Chapter 6, §6.3).
