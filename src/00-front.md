# 前頁：摘要、符號表與縮寫表

## 中文摘要

異質儲存裝置並存（NVMe 與 SATA、快碟與慢碟混插）已是現代電腦系統的常態，但既有
條帶化技術（硬體 RAID 0、Linux `dm-striped`、LVM striped）皆假設各碟等速，在異質
碟上會使最慢碟成為瓶頸、拖累整體吞吐。本論文提出 **TieredVol**——一個以**加權
條帶化**為核心的 Linux 核心（Device Mapper）異質磁碟儲存系統：管理者為每顆碟指定
與性能成正比的權重，TieredVol 依權重把 I/O 均分到全部碟，並以**確定性無表 O(1)
數學映射**保證分布逐 byte 精確、可重現、熱路徑無鎖。

本論文建立瓶頸性能模型 `T(W) = minᵢ(soloᵢ × ΣW/wᵢ)` 並證明權重與速比成正比時總
吞吐等於各碟之和；據此實作 `auto_weight` 工具由量測自動求近最優權重，並處理共享
匯流排（PCH DMI）下的權重修正（DMI-aware）。在此之上整合權重借調（weight
borrowing，慢碟暫時退化時的確定性例外路徑）、寫入快取、同步鏡像、壞區重建與
並發一致性於單一 target。

在真實 B85 異質平台（CPU 直連 NVMe＋PCH NVMe＋兩顆 SATA SSD）的 1–4 碟組態下，
以三種量測協定（排水態/冷態/冷態＋空檔）驗證：權重匹配的排水態場景下模型命中率
±5% 內；auto_weight 的**模型上界**達各碟之和的 99.6%（實測達 93.7%、S4 偏差
-5.9%），較等權重提升 70.6%；並揭露三個對儲存系統設計有普遍意義
的硬體洞見——PCIe 插槽（x1/x4）使同一 NVMe solo 相差 3.7 倍、PCH DMI 上行頻寬牆
使三碟併寫封頂於「solo_A + DMI」、NVMe SLC 快取暫態造成量測假象。全程
`err=0`、8 G crc32c 驗證零錯誤。

**關鍵字**：Device Mapper、異質儲存、加權條帶化、瓶頸模型、確定性映射、儲存快取

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

## 符號表（Notation）

**表 T10 符號表**

| 符號 | 意義 |
|------|------|
| n | 碟數 |
| W = (w₁,…,wₙ) | 權重向量；wᵢ 為碟 i 的權重（正整數） |
| ΣW | 總權重 = Σᵢ wᵢ |
| c | chunk 大小（本論文固定 1 MB） |
| soloᵢ | 碟 i 獨占介面時的順序寫入速率（量測基準） |
| T(W) | 權重 W 下條帶化寫入的總吞吐 |
| stripe_size | 一次權重分配循環的長度 = Σᵢ wᵢ × c |
| boundary[i] | 條帶內碟區累積邊界 = Σ_{j<i} w_j × c |
| 𝒟 | 走共享匯流排（DMI）的碟集合 |
| DMI_Budget | DMI 上行實測可用頻寬（~1300 MB/s） |
| block_size | 借調粒度 = chunk_size/8（1 M chunk → 128 KB） |
| P1/P2/P3 | 量測協定：排水態 / 冷態 / 冷態＋60 s 空檔 |

## 縮寫表（Abbreviations）

**表 T11 縮寫表**

| 縮寫 | 全稱 |
|------|------|
| dm / DM | Device Mapper |
| DMI | Direct Media Interface（南橋上行匯流排） |
| PCH | Platform Controller Hub（南橋） |
| NVMe | Non-Volatile Memory Express |
| SATA | Serial ATA |
| SLC / TLC | Single / Triple-Level Cell |
| WC | Write Coalescing（寫入快取） |
| MIR | Mirror（鏡像卷） |
| RAID | Redundant Array of Independent Disks |
| LVM | Logical Volume Manager |
| bio | block I/O（核心區塊 I/O 結構） |
| kref | kernel reference counter |
| CRC32C | Castagnoli CRC-32 校驗 |
| libaio | Linux Asynchronous I/O 函式庫 |
| io_uring | Linux 高效能非同步 I/O 框架 |
| O(1) | 常數時間複雜度 |
