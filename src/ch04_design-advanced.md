# 第四章 系統設計（二）：進階機制與容錯

> **本章導讀**：4.1 權重借調（動態平衡）；4.2 寫入快取（小寫合併）；
> 4.3 鏡像與重建（容錯）；4.4 並發一致性；4.5 設定與管理；4.6 以設計決策
> 紀錄表總結本章（與第三章）所有關鍵取捨。附錄 B 記錄開發過程的失敗與修正。

第三章建立了架構、加權條帶映射與瓶頸模型的「靜態核心」。本章在其上疊加所有
動態與容錯機制：權重借調（4.1）、寫入快取（4.2）、鏡像與重建（4.3）、
並發與一致性（4.4）、設定與管理（4.5）。共同原則：**所有動態性都是「靜態
確定性佈局之上的暫時例外」，不破壞第三章的映射函數**。

## 4.1 權重借調（Weight Borrowing）

### 4.1.1 動機

靜態權重假設權重與性能長時匹配。但現實中慢碟會暫時變慢（SLC 耗盡、碟忙碌、
磨損衰退）。兩個極端方案都不可行：

- 若仍依權重把資料餵給慢碟 → 慢碟成為瓶頸，整體被拖慢；
- 若改為動態選碟（adaptive policy，依負載即時選最閒碟）→ 破壞位址確定性，
  且實測失衡（-44%，見 6.3.3）。

折衷：**保留靜態權重佈局，僅對少數「整塊」寫入做暫時 offload**——正常資料仍依
確定性映射；只有「慢碟高負載」這個異常條件觸發例外路徑。

### 4.1.2 機制設計

- **觸發條件**：某碟的 in-flight 位元組 ≥ `borrow_watermark_kb`，**且**待寫區塊
  為整塊對齊。block 粒度 = `chunk_size/8`（1 M chunk → 128 KB block）。
  兩個條件缺一不可：只在高負載才借（避免正常路徑查表開銷）；只借整塊
  （borrow 區以 block 為單位配置，原子性）。
- **目的地選碟**：最少負載碟（排除自身、DEGRADED、借用區無空間者），
  寫入其 over-provisioned 借用區。
- **記錄**：per-block 表記 `(dst_disk, dst_sector)`。讀取與重寫（`need==0`）
  一律經 lookup 解析到同一目的地——**借出去的 block 永遠讀得回來**。
- **關閉語義**：`borrow_off` 只停止**新的**借出；lookup 與重寫不受開關影響
  （不檢查 enabled），因此關閉不影響已借資料的一致性。
- **原子性**：借用區配置為 all-or-none（整塊），避免部分配置造成表不一致。
- **持久化**：remove 時把表存成 `<config>.borrow`（v2 表 16 B/entry、magic 標示
  版本），重建時載入，跨 reload 位址一致（實驗：4 G 寫 + verify 0 錯誤，
  reload 後映射恢復）。

### 4.1.3 一致性不變式

1. **借出解析閉包**：任何被借出 block 的讀/重寫，永遠解析至借用區（lookup 不依賴
   `borrow_off`、`watermark` 等執行期開關）；
2. **全或無**：借用區以 block 為最小單位配置與釋放；
3. **臨界區**：表操作與對應 I/O 提交在同一臨界區，避免「表中記錄了但 I/O 未發」
   或反之；
4. **與靜態映射的關係**：借調是靜態映射之上的**例外清單**。正常位址仍走 3.2 的
   O(1) 公式；只有被借出的 block 走查表。兩者以「block 對齊 + 慢碟高負載」切換，
   例外數量級遠小於正常映射，查表成本可忽略，確定性佈局不變。

![圖 F6 權重借調流程（figs/F6_borrow.svg）](figs/F6_borrow.svg)

> **圖 F6 說明**：觸發條件（整塊對齊＋慢碟高負載）把 I/O 分成兩條路——多數走
> 正常 O(1) 確定性映射，少數整塊寫入走借用區例外路徑。下方兩條帶收束
> 4.1.3 的借出閉包與持久化不變式。

### 4.1.4 與第六章的對應

借調的驗證重點不在吞吐（它是「故障/退化時的救生筏」），而在**正確性與一致性**：
分布精確、4 G verify 0 錯誤、reload 後映射恢復、關閉後已借資料仍可讀（6.5）。

## 4.2 寫入快取（Write Coalescing, WC）

### 4.2.1 動機

條帶化的平行寫以「大塊」最有效；但上層可能以 4 K 小寫入塞入。若每個 4 K 都拆成
per-disk sub-bio，bio 管理（clone/advance/submit/endio）成本遠高於資料本身。
WC 把小寫入**按條帶分組緩衝**，累積成整條帶再 flush——以「延遲落碟」換「合併效率」。

### 4.2.2 緩衝與 Flush

- **緩衝條件**：`wc_enabled`、方向為 WRITE、segment 有效、且 `disk_count > 1`
  （單碟 segment 不緩衝，直接提交）。
- **分組鍵**：`(segment, stripe_no)`。跨條帶邊界的 bio 由 DM 先切半（3.2.5），
  WC 只緩衝切割後的 bio，保證每筆 entry 在同一條帶內。
- **Flush 時機**：

**表 4.1 WC Flush 觸發時機**

| 條件 | 行為 |
|------|------|
| 累積 ≥ stripe_size | 同步 flush |
| 換 stripe（新 stripe_no） | 先 flush 舊 stripe 再緩衝新的 |
| 1 jiffy 逾時 | 非同步 flush（`system_wq`） |
| 收到 READ bio | **先 flush**（讀序保證） |
| device destroy | 強制 flush |

- **Flush 內容**：把 entries splice 成 batch，每筆走原本的平行/單碟提交路徑，
  並於提交前補 mirror（4.3）。

![圖 F7 寫入快取（WC）路徑（figs/F7_wc.svg）](figs/F7_wc.svg)

> **圖 F7 說明**：READ 先 flush（讀序承重牆）；WRITE 依緩衝條件分流——符合條件
> 進 (segment, stripe_no) 分組緩衝，由五種 flush 時機觸發；不符合（含 4 K 小寫）
> 回 -EAGAIN 走直接路徑。flush 重跑與直接提交共用同一平行/單碟邏輯。

### 4.2.3 一致性語義

- **讀序保證（承重牆）**：任何 READ 到來必先 `tv_wc_flush()`，因此 WC **不改變
  讀寫序**——這是不變式「讀到最新資料」的唯一保障，改動此處 = 讀序錯誤。
- **繞過路徑（-EAGAIN）**：不符合緩衝條件的 bio 回 `-EAGAIN`，走直接路徑、不進
  WC。這解釋了 4 K 小寫入的性能行為：**4 K bio < chunk_size，不滿足整塊條件而
  繞過 WC**（`tieredvol_wc.c` 的條件分支），4 K 性能主要由條帶化拆分成本與放置
  分布決定（6.4）。
- **flush 重跑**：flush 時對每筆 entry 重算並行/單碟路徑，與直接提交共用同一邏輯，
  避免兩條路徑行為分歧。

### 4.2.4 限制（誠實聲明）

WC 是**延遲刷盤**快取：flush 前的資料僅在記憶體。**斷電時緩衝區未落碟的資料會
遺失**。本論文實作不提供斷電一致性的 crash guarantee；需嚴格持久性者應關閉 WC
（`wc_enabled=N`）或由上層（檔案系統 barrier/fsync）把關。此為 6.6 列出的限制之一
（WC 斷電一致性的成本效益取捨）。

## 4.3 鏡像與重建

### 4.3.1 每段鏡像（per-segment mirror）

每個 segment 可指定一顆 mirror 碟（`seg0_mirror=idx`）；mirror 碟不能是該 segment
的任一 primary 碟，每 segment 最多一個 mirror。

**寫入**：原始 WRITE 仍走加權條帶路徑；同時以 `bio_alloc_clone()` fire-and-forget
複製一份寫到 mirror 碟（`mirror_sec = logical − seg_begin`）：

- clone 用 mempool（pool size 128）確保不 OOM，**不阻塞原始 bio**；
- 完成時 `mirror_write_ops++` / `mirror_errors++`（統計可查）；
- mirror 寫不進 WC 緩衝（直接提交），與 primary 平行。

**讀取與重試**：primary 讀失敗時，若該位置有 mirror 寫入 pending，等待（每 1 ms、
最多 32 次退讓）排空後從 mirror 重試（流程見 4.4 的 pending 記錄）。超過退讓
次數即 give-up，避免無限等待。

### 4.3.2 重建與壞區（Rebuild & Badmap）

- **Rebuild**：kthread 依靜態映射逐 chunk「讀 primary → 寫 mirror」；同步 I/O +
  `wait_for_completion`；失敗 backoff（10 ms 開始、加倍至 1 s）；每 10 MB 回報進度。
- **Badmap**：per-disk chunk bitmap（`n_chunks = disk_sectors/chunk`）。壞塊**讀**
  以 zero-fill 完成（讀作零）；壞塊**寫**直接跳過（`bio_endio`）。WRITE 錯誤在完成
  回呼自動標壞 chunk；以 range 字串（`badmap_<disk>=a-b,c`）持久化進 config，
  kernel save 時壓縮寫回。
- **rebuild_badmap**：重建時對壞區的處理已修正一個實作 bug（compound page 造成
  `bi_size` 計算錯誤），修正後 `1 recovered, 0 failed`、無 hang。

### 4.3.3 鏡像成本分析

鏡像寫與 primary 平行提交，瓶頸即 mirror 碟自身的寫入速率：總寫入時間
≈ max(primary 路徑時間, mirror 碟時間)。實驗中 M 卷寫入 ≈457 MB/s，達 mirror
碟 C 自身 solo（≈517）的 ~88%——瓶頸是 mirror 碟（SATA）而非 primary 合併
（8/12 對照場 primary 聚合 2390 vs mirror 卷 463、減損 ~81%，同源於此）；
4 K 寫因 COW 成本降幅較大（-52%）；讀取幾乎 0% 額外成本（讀不複寫）。

## 4.4 並發與一致性

### 4.4.1 資料結構

- **pending-write ring**（`tv_pw_lock` spinlock 保護）：記錄進行中的寫入
  （含 mirror 寫），供讀取錯誤重試時判斷「該位置是否仍可能有未完成寫入」。
- **pending-read ring**（`tv_pending_lock` spinlock 保護）：per-CPU lockless，
  記錄正在讀的 range，供錯誤處理追溯。

### 4.4.2 語義（三種結果）

**表 4.2 併發一致性三種結果語義**

| 情況 | 行為 |
|------|------|
| **MISS** | 錯誤讀的位置沒有對應 pending 記錄 → 直接回報錯誤或走 mirror retry |
| **give-up** | 等 mirror 寫排空超過 32 次退讓 → 放棄、回報錯誤（避免無限等待） |
| **full** | ring 滿時由實作定義的拒絕/覆寫策略，防止結構溢位破壞一致性 |

計數器以 `err` 反映這些事件；實驗全程 `err=0`（6.2）。

### 4.4.3 無共享鎖的熱路徑

映射本身無鎖（3.2）；鏡像熱路徑使用 per-CPU ring + atomic；唯一共享 spinlock
在完成/錯誤處理的冷路徑。多卷併發實驗（6.2.3）顯示「driver 自身不共享」的兩卷
併發性能孤立（±2%），證實熱路徑無鎖爭搶。

## 4.5 設定與管理

- **Config**：`/etc/tieredvol/<name>.conf` 為單一真相來源；dm table 極簡
  （`0 <sectors> tieredvol <config_path>`），佈局全在 config。kernel 載入驗
  CRC32C；kernel save 先寫 `.bak`。**不變式**：改 config 格式 = kernel parser
  與 CRC 演算法**兩處同步**，否則載入失敗或靜默損壞。
- **參數驗證（fail-closed）**：ctr() 拒絕非法參數——被移除的 adaptive policy 值、
  越界權重、重複碟、mirror 碟與 primary 重疊、segment 順序錯誤等。
- **sysfs / dmsetup message**：管理介面輸出權重與各碟統計；`show_mirror`、
  rebuild 觸發、policy 切換等 message 命令。
- **統計計數器**：每碟 `wr=/rd= ops/bytes`、`err`、borrow 計數、mirror 計數
  （`mirror_wr/rd ops`、`mirror_err`），為第六章正確性驗證的依據。

## 4.6 設計決策紀錄（Decision Log）

以下彙整第三章與本章出現的所有關鍵設計取捨，供答辯與審查快速索引
（詳細理由見對應章節）：

**表 4.3 設計決策紀錄（D1–D10）**

| # | 決策 | 放棄的方案 | 選擇的理由（證據） |
|---|------|-----------|--------------------|
| D1 | 條帶化（權重並行） | 兩層快取/分層置放 | 每筆資料並行分布全部碟，非依命中率搬熱資料（2.3） |
| D2 | segment 分段 | 全域依容量調權重 | 「性能權重」與「容量分段」正交，可獨立調配（3.2.2） |
| D3 | O(1) 無表數學映射 | mapping table / 動態索引 | 熱路徑無鎖、可重現；n≤4 時公式比查表便宜（3.2.3） |
| D4 | 窮舉 auto_weight | 閉式解 | 權重需整數、max-min 問題、n 小，窮舉可納 cap 等約束（3.3.2） |
| D5 | DMI-aware 權重 | 純 solo 比例權重 | 共享匯流排預算 (3.3)；比例權重實測掉到 2561（6.3.4） |
| D6 | 靜態佈局＋借調 | 動態選碟（adaptive） | 確定性不被破壞；adaptive 實測 -44% 且 C/D 失衡（6.3.3） |
| D7 | 借調粒度 = chunk/8 | 整 chunk 借調 | 細粒度填慢碟空檔，原子性以 block 為單位保證（4.1.2） |
| D8 | WC 延遲刷盤 | 直寫 | 小寫合併效率；接受斷電風險（可關閉，4.2.4） |
| D9 | mirror 內建於 target | 另開 dm-mirror | 單 target 一致性、per-segment 彈性、減少堆疊層（4.3） |
| D10 | libaio 深度 32 | io_uring 深佇列 [10] | 反映真實硬體上限，避免把數字「灌高」（6.1.2） |

> 決策原則：**所有動態性都是確定性佈局之上的暫時例外**（D6）。任何可能讓
> 「同一邏輯位址在不同時間落不同碟」的機制一律排除。
> 各決策的「踩坑」與修正歷程見附錄 B。

## 本章小結

第四章回答了 P3（權重借調）與 P4（容錯/管理）的**設計**：
- 權重借調 (4.1)：以細粒度 block 在慢碟高負載時暫時 offload，配合持久化表
  reload 恢復，不破壞確定性佈局；
- 寫入快取 (4.2)：小 bio 延遲刷盤、bio<chunk 的 -EAGAIN 繞過，兼顧小寫效能與
  一致性聲明；
- 鏡像/重建/壞區 (4.3) 與並發一致性 (4.4)：整合於單一 target，全程 err=0；
- 設定與管理 (4.5) 與決策紀錄 (4.6)：把第三章、第四章所有取捨收束成可答辯的
  決策表。

第五章以實作對應本節與第三章的每項設計。
