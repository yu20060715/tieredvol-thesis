# Appendix B Failure and Fix Log

> This appendix records the key events during development where "it was built but wrong, measured but fooled." These pitfalls are the causes of the design choices (Chapter 4 §4.6) and the measurement protocols (Chapter 6 §6.1), and are material proving the authenticity of the implementation. Each entry records "symptom → root cause → fix → current status."

## B.1 Adaptive Disk Selection (adaptive policy) — 44% Imbalance

- **Symptom**: adaptive disk selection, which used the EMA three factors (recent latency/load/error) to pick the "most idle disk" in real time, measured **-44%** write throughput versus weighted striping, and the C/D disks were severely imbalanced.
- **Root cause**: the decision window of adaptive disk selection was out of sync with I/O completion time — a fast disk was often "picked right after it finished busy," while the slow disk was avoided, causing accumulation on the other disks; the address was also nondeterministic (the same logical address landed on different disks at different times).
- **Fix**: the entire mechanism was removed (`set_policy adaptive` no longer exists), replaced with "static layout + weight borrowing" (§4.1).
- **Current status**: superseded by weight borrowing; the -44% data is included in §6.3.3 as experimental evidence of "why adaptive disk selection was not adopted."

## B.2 Cold-State Short-Write Measurement Artifact (SLC Transient)

- **Symptom**: on 8/12 the stacked-disk table writes went 1981→2661→2787→3091, looking like a beautiful "more disks = faster" ladder, but **re-measuring in the same session varied by up to 20%**, contradicting the later drain-state data (1360→1667→1999).
- **Root cause**: the NVMe built-in SLC cache band — short writes land in the SLC and the rate starts high then decays; the numbers reflect "remaining cache" rather than the hardware steady state.
- **Fix**: defined the three measurement protocols (P1 drain state / P2 cold state / P3 cold state + 60 s idle, §6.1.2); the main tables use P1/P3 to produce reproducible data; the 8/12 table was retired.
- **Current status**: the F12 SLC curve chart became direct evidence of "why three protocols" — in the second batch of real measurements on the night of 8/14 (**60 s-recharge protocol**), the curve under `[64:27:9:4]` (borrow off) was **flat throughout** (average 3278 over 20 G, average 3137 over 100 G), because being A-bound pinned aggregate writes against the ceiling from the start, leaving no room for the SLC surplus to show; by contrast, the 8/12 cold stacked-disk writes (A not the bottleneck) showed the 1981→2661→2787→3091 variation. Together the two prove the design intent that "the drain protocol eliminates the SLC artifact" (§6.1.2, §6.3.1).

## B.3 rebuild_badmap Compound Page Bug

- **Symptom**: during bad-region rebuild the `bi_size` calculation was wrong, and the rebuild counters were abnormal (some bad regions were not rebuilt).
- **Root cause**: a compound page (a physically contiguous page composed of multiple pages) made the `bi_size` inferred from the `bio` inconsistent with the actual segment length.
- **Fix**: switched to computing `bi_size` from the correct segment length.
- **Current status**: after the fix, `1 recovered, 0 failed`, no hang (§6.2.2).

## B.4 WC Small-Write Bypass Condition Bug

- **Symptom**: 4 K small-write performance was abnormal (far below expectation).
- **Root cause**: the buffering condition branch in `tieredvol_wc.c` was wrong; small bios (< chunk) did not correctly take the `-EAGAIN` bypass path and fell into the costly split flow.
- **Fix**: corrected the buffering condition branch so that `bio < chunk_size` explicitly bypasses WC and takes the direct path.
- **Current status**: after the fix, 4 K write went 14→500 MiB/s (the final build tv_s2 is 612, §6.5); 4 K performance characteristics have since been dominated by "striping split cost" (§4.2.3, §6.4).

## B.5 `del_timer_sync()` Deadlock in the Parallel Write Path

- **Symptom**: occasional deadlock when the parallel submission completion callback ran in hardirq.
- **Root cause**: the completion callback attempted to stop the timer with `del_timer_sync()` — that function spins waiting for the timeout callback to finish, forming a spin-wait on itself inside hardirq.
- **Fix**: switched to `del_timer()` (hardirq-safe), paired with `kref_get_unless_zero()` to keep the block alive, then completing via `cmpxchg`.
- **Current status**: this rule is now written into the "load-bearing wall" (§5.2.2, `DESIGN.md`), and subsequent changes must comply.

## B.6 Small-Write Locked Return After `borrow_off` (Deadlock Caught by sparse)

- **Symptom**: after `msg_borrow_off` (borrow disabled, entries retained, `enabled=false`), a small write to a non-borrowed region (the `need>0` branch) directly `return false` while **holding the spinlock (irqs off)** — the lock was never released, so the next I/O touching `borrow.lock` deadlocked.
- **Root cause**: `tv_borrow_redirect` in `driver/tieredvol_borrow.c` was missing `spin_unlock_irqrestore`. Reachable path: `msg_borrow_off` → <1M small write (WC does not buffer).
- **Why B4 did not catch it**: B4 used only 1M writes (buffered by WC) and never took the WC-bypass path.
- **Fix**: added `spin_unlock_irqrestore(&ctx->borrow.lock, flags);` to that branch.
- **Verification**: `configs/test/m_fix.conf` (same borrow volume as m_s4b) → `msg_borrow_off` → 512K writes at offsets 0/4/8 (WC bypass) → no more hang, reads back correct; `borrow_on` normal.
- **Tooling**: the local kernel 6.14.0-27-generic does not enable `CONFIG_PROVE_LOCKING` → runtime lockdep is unavailable; instead it was caught by the lock-context checks in **sparse** (`make C=2 CHECK="sparse"`). **This case proves that "the tool cannot catch it ≠ there is no bug"; erroneous paths need to be deliberately constructed.**

## B.7 SIGKILL Deep-Queue Direct I/O Wedged AHCI (Platform Pitfall, Not a Driver Bug)

- **Symptom**: boot -2 hard-crashed within 2 seconds of `pkill -9 -f busyd` (SIGKILL on two 1M/d32 libaio fio jobs at offset 110G on /dev/sdb); boot -1 hung 35 s later in the residual state.
- **Root cause**: no panic/oops, SMART fully clean → **the AHCI/SATA controller was wedged by the SIGKILL of deep-queue direct I/O** (B85 old chipset); the driver was idle at the time, unrelated to tieredvol.
- **Fix**: measurement convention — never `pkill -9`; always fix a `--runtime` so that fio ends naturally.
- **Current status**: written into the §6.1 measurement protocols and Appendix A.

> Lessons summary: **(1) any "good-looking" data must first be suspected of the measurement protocol** (B.2); **(2) the cost of adaptive disk selection breaking determinism is systemic, not something parameters can save** (B.1); **(3) choosing synchronization primitives for the hardirq path is another level of correctness** (B.5); **(4) the lifetime of locks must be written in a form tools can verify; sparse/lockdep are an extension of review** (B.6); **(5) the platform (old SATA controller) can also be wedged; the measurement environment itself must be treated as a variable** (B.7).
