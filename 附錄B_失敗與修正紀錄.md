# 附錄 B 失敗與修正紀錄

> 本附錄記錄開發過程中「做出來卻不對、量測卻被騙」的關鍵事件。這些踩坑是
> 設計取捨（第四章 4.6）與量測協定（第六章 6.1）的成因，也是證明實作
> 真實性的素材。每項記「現象 → 根因 → 修正 → 現況」。

## B.1 動態選碟（adaptive policy）—44% 失衡

- **現象**：以 EMA 三因子（近期延遲/負載/錯誤）即時選「最閒碟」的動態選碟，
  實測寫入較權重條帶 **-44%**，且 C/D 兩碟嚴重失衡。
- **根因**：動態選碟的決策窗口與 I/O 完成時間不同步，快碟常被「剛忙完就選上」、
  慢碟卻被避開造成其他碟堆積；且位址不確定（同一邏輯位址在不同時間落不同碟）。
- **修正**：整個機制移除（`set_policy adaptive` 不再存在），改採
  「靜態佈局＋權重借調」（4.1）。
- **現況**：被 weight borrowing 取代；-44% 數據收入 6.3.3 作為「為何不採用
  動態選碟」的實驗佐證。

## B.2 冷態短寫的量測假象（SLC 暫態）

- **現象**：8/12 疊碟表寫入 1981→2661→2787→3091，看似「碟愈多愈快」的漂亮
  階梯，但**同場重測跳動達 20%**，且與後續排水態數據（1360→1667→1999）矛盾。
- **根因**：NVMe 內建 SLC 快取帶——短寫落在 SLC、速率先高後衰，數字反映
  「快取剩餘量」而非硬體穩態。
- **修正**：定義三種量測協定（P1 排水態 / P2 冷態 / P3 冷態＋60 s 空檔，
  6.1.2），主表以 P1/P3 產出可重現數據；8/12 表退休。
- **現況**：F12 SLC 曲線圖成為「為何要三協定」的直觀證據——8/14 晚第二批
  實測顯示 `[64:27:9:4]`（borrow off）下曲線**全程平坦**（20G 平均 3278、
  100G 平均 3137），因為 A-bound 使聚合寫入從頭頂在天花板、SLC 增額無從顯現；
  相對地 8/12 冷態疊碟（A 非瓶頸）才有 1981→2661→2787→3091 的跳動。兩者
  互補證明「排水協定消除 SLC 假象」的設計意圖（6.1.2、6.3.1）。

## B.3 rebuild_badmap 的 compound page bug

- **現象**：壞區重建時 `bi_size` 計算錯誤，重建計數異常（部分壞區未被重建）。
- **根因**：compound page（多 page 組成的物理連續頁）使 `bio` 的 `bi_size` 推算
  與實際 segment 長度不符。
- **修正**：改以正確的 segment 長度計算 `bi_size`。
- **現況**：修正後 `1 recovered, 0 failed`、無 hang（6.2.2）。

## B.4 WC 小寫入的繞過條件 bug

- **現象**：4 K 小寫入性能異常（遠低於預期）。
- **根因**：`tieredvol_wc.c` 的緩衝條件分支有誤，小 bio（< chunk）未正確走
  `-EAGAIN` 繞過路徑，落入成本高昂的拆分流。
- **修正**：修正緩衝條件分支，使 `bio < chunk_size` 明確繞過 WC 走直接路徑。
- **現況**：修復後 4 K 寫入達 1400 MiB/s（6.5）；4 K 性能特性自此由「條帶化
  拆分成本」主導（4.2.3、6.4）。

## B.5 平行寫路徑的 `del_timer_sync()` 死鎖

- **現象**：平行提交完成回呼於 hardirq 執行時偶發死鎖。
- **根因**：完成回呼企圖以 `del_timer_sync()` 停 timer——該函數會自旋等待
  timeout callback 執行完畢，在 hardirq 內形成自旋等待自身。
- **修正**：改用 `del_timer()`（hardirq-safe），搭配 `kref_get_unless_zero()`
  保活 block 後以 `cmpxchg` 完成。
- **現況**：此規則已寫入「承重牆」（5.2.2、`DESIGN.md`），後續改動必須遵守。

## B.6 `borrow_off` 後小寫入帶鎖 return（sparse 抓出的死鎖）

- **現象**：`msg_borrow_off`（借調關閉、entries 保留、`enabled=false`）後，對
  非借用區的小寫入（`need>0` 分支）在**持 spinlock（irqs off）**狀態下直接
  `return false`——鎖未釋放，下一個碰 `borrow.lock` 的 I/O 死鎖。
- **根因**：`driver/tieredvol_borrow.c` 的 `tv_borrow_redirect` 漏掉
  `spin_unlock_irqrestore`。可達路徑：`msg_borrow_off` → <1M 小寫入（WC 不緩衝）。
- **為何沒被 B4 抓到**：B4 全用 1M 寫（被 WC 緩衝），未走 WC-bypass 路徑。
- **修正**：該分支補 `spin_unlock_irqrestore(&ctx->borrow.lock, flags);`。
- **驗證**：`configs/test/m_fix.conf`（同 m_s4b 的 borrow 卷）→ `msg_borrow_off`
  → 512K 寫入 offset 0/4/8（WC bypass）→ 不再掛、讀回正確；`borrow_on` 正常。
- **工具**：本機 kernel 6.14.0-27-generic 未開 `CONFIG_PROVE_LOCKING` → runtime
  lockdep 不可用；改用 **sparse**（`make C=2 CHECK="sparse"`）的 lock-context
  檢查抓到。**此例證明「工具抓不到 ≠ 沒有 bug」，錯誤路徑需要刻意構造**。

## B.7 SIGKILL 深佇列 direct I/O wedged AHCI（平台陷阱，非 driver bug）

- **現象**：boot -2 於 `pkill -9 -f busyd`（SIGKILL 兩個對 /dev/sdb offset 110G
  的 1M/d32 libaio fio）後 2 秒內硬當；boot -1 殘留態 35s 再當。
- **根因**：無 panic/oops、SMART 全乾淨 → **AHCI/SATA 控制器被深佇列 direct I/O
  的 SIGKILL wedged**（B85 老晶片組）；當下 driver 閒置、與 tieredvol 無關。
- **修正**：量測規約——不 `pkill -9`，一律固定 `--runtime` 讓 fio 自然結束。
- **現況**：寫入 6.1 量測協定與附錄 A。

> 教訓總結：**(1) 任何「看起來漂亮」的數據都要先懷疑量測協議**（B.2）；
> **(2) 動態選碟破壞確定性的代價是系統性的，不是參數能救的**（B.1）；
> **(3) hardirq 路徑的同步原語選擇是另一層次的 correctness**（B.5）；
> **(4) 鎖的生命週期要寫進工具能驗證的形式，sparse/lockdep 是審查的延長**（B.6）；
> **(5) 平台（老 SATA 控制器）也會 wedged，量測環境本身要被當作變因**（B.7）。
