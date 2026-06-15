# SP-Forth/4 原始碼追蹤 — 驗證、效能量測與安全檢查

> 定位：補上「文件說明如何被驗證」與「修改後如何避免破壞語意」。
>
> 本章聚焦檢查清單與最小測試策略；實作細節請回到各 trace 主題文件。

---

## 1. 驗證分層

SP-Forth 的驗證不要只跑最後的可執行檔。較穩定的方式是分層確認：

| 層級 | 驗證目標 | 代表文件 |
|------|----------|----------|
| primitive | `EAX` / `EBP` / flags / memory side effect 正確 | [01-kernel.md](01-kernel.md) |
| compiler | parser、search-order、immediate word、backpatch 正確 | [02-compiler.md](02-compiler.md) |
| cross compiler | host/target 位址、target dictionary、image layout 正確 | [03-cross-compiler.md](03-cross-compiler.md) |
| platform | FFI、thread、signal/SEH、I/O 正確 | [04-posix-platform.md](04-posix-platform.md), [09-windows-platform.md](09-windows-platform.md) |
| image save | ELF/PE header、section/segment、relocation/import 正確 | [06-build-save.md](06-build-save.md) |
| optimizer | rewrite 前後 stack effect、flags、暫存器語意等價 | [07-optimizer.md](07-optimizer.md) |

任何測試失敗時，先把失敗歸到其中一層；不要直接修改多層邏輯。

---

## 2. Primitive 驗證

### 2.1 Stack effect 是第一規格

每個 primitive 至少要驗證：

1. 輸入 stack effect。
2. 輸出 stack effect。
3. `EAX` 是否保存新的 TOS。
4. `EBP` 是否指向新的次堆疊項。
5. 是否意外改變 `EDI`。
6. 若後續會依賴 flags，是否保留或明確重建 flags。

範例：`DUP ( x -- x x )` 驗證重點不是只看結果有兩個 `x`，還要看 `EAX` 與 `[EBP]` 的分工是否符合 TOS-in-EAX 模型。

### 2.2 建議測資

| 類型 | 測資 |
|------|------|
| 零值 | `0` |
| 正負邊界 | `1`, `-1`, `0x7fffffff`, `0x80000000` |
| 位元樣式 | `0x55555555`, `0xaaaaaaaa` |
| 位址樣式 | 對齊位址、非對齊位址、空指標語意值 |
| 浮點 | `0.0`, `-0.0`, `1.0`, 極大/極小值、NaN/Inf 若平台支援 |

比較 primitive 要特別測 Forth truth value：true 是 `-1`，不是 C 的 `1`。

### 2.3 既有測試資源與最小斷言

此 repo 內已有可參考的 ANS CORE 測試樣本：`samples/ans/tester.f`。它適合用來驗證標準 core word 的行為是否仍符合預期；但它不會覆蓋 SP-Forth 的所有 native-code、optimizer、ELF/PE save、FFI 與 callback 行為。

若只需要臨時建立小型檢查，可用最小斷言字包住預期值：

```forth
: ASSERT= ( actual expected -- )
  = 0= IF -2 THROW THEN ;

0 0= -1 ASSERT=   \ Forth true 應為 -1
1 0=  0 ASSERT=   \ false 應為 0
```

這類斷言的好處是能被 `CATCH` 捕捉，也能放進建構或 smoke test 腳本。缺點是它只告訴你「失敗」，不會自動定位是哪一層壞掉；定位仍要回到 [12-debugging.md](12-debugging.md)。

---

## 3. Compiler 與 wordlist 驗證

### 3.1 Parser / source input

最小檢查：

- 空白、tab、換行混合。
- 檔案輸入、stdin、`EVALUATE` 三種 `SOURCE-ID`。
- 字串 literal 橫跨 parser buffer 邊界。
- `SAVE-SOURCE` / `RESTORE-SOURCE` 後 `>IN` 是否恢復。

### 3.2 Search-order / wordlist

驗證項目：

1. 同名字在不同 wordlist 時，搜尋順序是否正確。
2. `CURRENT` 與 `CONTEXT` 分離是否正確。
3. 新定義在 `HIDE` 期間不可見，`;` 後恢復可見。
4. `MODULE:` / `EXPORT` 只暴露預期字。
5. case-sensitive 與 case-insensitive 版本行為差異符合預期。

### 3.3 Immediate words 與 backpatch

控制結構要測巢狀與邊界：

```forth
: t1 IF 1 ELSE 2 THEN ;        \ 用法：-1 t1 → 1；0 t1 → 2
: t2 BEGIN DUP 0= UNTIL ;       \ 用法：0 t2（見下方警告）
: t3 10 0 DO I LOOP ;
: t4 10 0 DO I 5 = IF LEAVE THEN LOOP ;
```

> **`t2` 是有條件的測試，不是無條件正路徑。** `BEGIN DUP 0= UNTIL` 只有當堆疊頂端為 `0` 時才會在第一圈離開（`0 0=` → `-1`(true) → `UNTIL` 離開）；若先推入非 0 值，`DUP 0=` 永遠為 `0`(false)，會變成**無窮迴圈**。要測它請先推入 `0`（`0 t2`）；若想當成正路徑壓力測試，改寫成 `: t2 5 BEGIN 1- DUP 0= UNTIL ;` 之類有遞減條件的版本。

這類測試的目的不是只看能否執行，而是確認 branch placeholder、offset、`HERE`、`DP` 在編譯期都被正確回填。

---

## 4. Optimizer 等價性檢查

### 4.1 每條 rewrite 都要保留四件事

optimizer 規則不能只保留結果值。每條 rewrite 前後都要確認：

| 必須保留 | 說明 |
|----------|------|
| stack effect | 輸入/輸出資料堆疊深度一致 |
| TOS location | 結束時 TOS 仍在 `EAX` |
| `EBP` offset | 資料堆疊指標位移一致 |
| flags 語意 | 若後續條件跳躍依賴 flags，不能被破壞 |

例如 `LEA` 常可取代 `ADD`，但 `LEA` 不改 flags；若後面需要 flags，兩者不等價。

### 4.2 macroopt / noopt A/B 測試

每個 optimizer 相關變更都應至少跑：

```text
同一輸入程式：
  A. 使用 macroopt（BUILD-OPTIMIZER=TRUE，USE-OPTIMIZER=TRUE）
  B. 使用 noopt（BUILD-OPTIMIZER=FALSE，USE-OPTIMIZER=FALSE）
比較：
  1. 執行結果
  2. stack depth
  3. 例外碼
  4. 產生 image 是否可啟動
```

> **A/B 是「兩份各自重新建構的 spf4」，不是在同一個 prompt 下動態切換。** 是否把 optimizer 編進系統由建構期選項 `BUILD-OPTIMIZER`（決定載入 `src/macroopt.f` 或 `src/noopt.f`，見 `src/spf.f:254–258`）與 `USE-OPTIMIZER` 控制；`OPT?` 只是執行期的 VALUE（`macroopt.f:24` 預設 TRUE、`noopt.f:10` 為 FALSE），無法靠 `TO OPT?` 把已建好的系統從「有 optimizer」變成「完全沒有」。實務上請以不同的 `compile.ini` 各建一份 spf4 來做 A/B。

若 A/B 結果不同，先縮小到單一 word 或單一 optimizer pattern。

### 4.3 最佳化測資類型

| 規則 | 測資 |
|------|------|
| constant folding | `0`, `1`, `-1`, 大常數、相鄰 literal |
| inline | 小 word、剛好超過大小限制的 word、含 return stack 操作的 word |
| jump shortening | 最短距離、剛好超過 short jump range、巢狀 branch |
| stack shuffle | `DUP DROP`, `SWAP SWAP`, `OVER DROP` 這類可消去序列 |

---

## 5. Image / ELF / PE 驗證

### 5.1 檔案格式檢查

產生 image 後，至少檢查：

| 項目 | ELF | PE |
|------|-----|----|
| magic | `7F 45 4C 46` | `MZ` + `PE\0\0` |
| machine | IA-32 | I386 |
| entry point | 指向初始化入口 | 指向 PE stub / runtime init |
| section / segment | `.forth`、`.space`、`.rel.forth`、`.dltable`、`.dlstrings` 存在且大小合理；`.space` 是 SHT_NOBITS（BSS-like），不佔檔案大小 | section table、import table 合理 |
| dynamic symbols | libc / libdl 符號完整 | Import Directory / IAT 完整 |

### 5.2 位址空間檢查

最容易混淆的三種值：

```text
target virtual address
file offset
host build-time address
```

驗證 relocation / import / dictionary pointer 時，必須先標記欄位需要哪一種位址。若某欄位在檔案中看似合理，但載入後 crash，常見原因是 file offset 與 virtual address 混用。

---

## 6. FFI 安全檢查

### 6.1 宣告外部函式前的檢查表

| 檢查項 | POSIX | Windows |
|--------|-------|---------|
| 呼叫約定 | cdecl，呼叫者清理 | WinAPI 多為 stdcall，被呼叫者清理 |
| 參數數量 | 必須與 C prototype 一致 | 必須與 Win32 API prototype 一致 |
| 回傳寬度 | 32-bit 或 64-bit 分流 | handle / BOOL / pointer 都是 32-bit IA-32 值 |
| 錯誤來源 | `errno`, `dlerror()` | `GetLastError()` |
| 字串生命週期 | C 端是否延後保存指標 | API 是否同步複製 buffer |

### 6.2 Buffer 與 pointer lifetime

FFI 測試要特別確認：

1. Forth buffer 在 C 函式返回前是否仍有效。
2. C 端是否保存 pointer 到 callback 或全域狀態。
3. buffer 長度是否包含 NUL 結尾。
4. API 是否回寫超過預留長度。
5. callback 是否可能在另一個 OS thread 執行。

若 C 端會延後使用 pointer，就不能傳入暫時 parser buffer 或即將被覆寫的 `SYSTEM-PAD`。

### 6.3 Callback 驗證

callback 最小測試順序：

1. C 端同步呼叫 callback 一次。
2. C 端多次呼叫 callback。
3. callback 內讀寫 USER 變數。
4. callback 內觸發 `THROW` 或回傳錯誤碼。
5. 若平台支援，再測跨 thread callback。

每一步都要檢查 `EDI` / USER 區是否仍正確。callback 能返回不代表 thread-local runtime 狀態一定正確。

---

## 7. 效能量測原則

### 7.1 不要只數指令

[01-kernel.md](01-kernel.md) 與 [07-optimizer.md](07-optimizer.md) 已經提供很多指令級分析，但實測時還要考慮：

- branch prediction。
- cache locality。
- memory dependency。
- flags dependency。
- call/ret prediction。
- alignment。

例如 branchless rewrite 在舊 CPU 上可能明顯有利，但在不同 pipeline / predictor 下不一定永遠勝出。文件可以說明設計意圖，但效能結論應以目標平台測量為準。

### 7.2 建議 benchmark 方式

1. 固定 CPU governor / 電源模式。
2. 預熱執行一次，避免 cold cache 影響。
3. 同一 image 內多次重複測量。
4. macroopt / noopt 同時測。
5. 測試結果同時記錄編譯選項、CPU、OS、toolchain。

### 7.3 該量什麼

| 對象 | 指標 |
|------|------|
| primitive | 每次操作時間、stack depth 穩定性 |
| compiler | 每千行 source 編譯時間、word lookup 熱點 |
| optimizer | image size、編譯時間、runtime speedup |
| FFI | 每次 call overhead、callback overhead |
| image startup | 啟動時間、初始化各階段耗時 |

---

## 8. 文件與原始碼一致性檢查

trace 文件更新時，至少檢查：

1. 文件提到的原始檔仍存在。
2. section 標題中的檔名與 quick-ref 對照一致。
3. 若引用 source line，確認 line number 沒因原始碼變動而失真。
4. 程式片段不是「概念化到改變語意」。
5. POSIX / Windows 對照表沒有把 cdecl/stdcall、signal/SEH 混用。

若無法保證 line number 長期穩定，優先引用函式名與檔名，再在文字中說明目前版本觀察到的位置。

---

## 9. 可直接套用的驗證 recipe

本章前面是原則；本節提供更接近實作時可照抄的檢查流程。

### 9.1 Stack effect 測試樣式

Forth 測試最小單位通常不是「回傳值」，而是「執行前後 stack 長相」。可以用這種形式記錄：

```forth
\ 測 DUP: ( x -- x x )
123 DUP  \ expect: 123 123

\ 測 DROP: ( x -- )
123 DROP \ expect: stack depth 回到原狀
```

文件中建議把測試寫成三欄：

| 測試 | stack effect | 預期 |
|------|--------------|------|
| `123 DUP` | `( x -- x x )` | 多一個 cell，兩者相等 |
| `1 2 SWAP` | `( a b -- b a )` | 頂端為 1，次項為 2 |
| `0 0=` | `( 0 -- flag )` | flag = `-1` |
| `1 0=` | `( 1 -- flag )` | flag = `0` |

注意 Forth true 是 `-1`，不是 C 的 `1`。這會影響所有 bitwise 邏輯與 branchless comparison 測試。

### 9.2 Control structure 測試樣式

控制結構的 bug 常不是「語法不能編」，而是 backpatch offset 差幾個 byte。最小測試要同時覆蓋 true branch、false branch、巢狀與 loop exit：

```forth
: if-true   -1 IF 11 ELSE 22 THEN ;  \ expect 11
: if-false   0 IF 11 ELSE 22 THEN ;  \ expect 22

: nested-if ( n -- x )
  DUP 0= IF DROP 0 ELSE
    DUP 1 = IF DROP 10 ELSE DROP 20 THEN
  THEN ;

: loop-sum ( -- n )
  0  5 0 DO I + LOOP ;  \ expect 0+1+2+3+4 = 10
```

如果只有巢狀版本錯，優先查 control-flow stack；如果 simple `IF` 都錯，優先查 branch compile word 或 literal compile。

### 9.3 Optimizer A/B 測試樣式

optimizer 驗證要保持同一輸入、同一環境，只改 optimizer 狀態：

```text
Case A: macroopt enabled
  run input → record stack result, output, exception, image startup

Case B: noopt / OPT? disabled
  run same input → record same fields

Compare:
  - stack depth
  - TOS value
  - visible output
  - THROW/signal
```

如果 A/B 不同，縮小到單一 pattern：

| 差異 | 優先懷疑 |
|------|----------|
| 結果值錯，stack depth 正確 | arithmetic rewrite / constant folding |
| stack depth 錯 | stack shuffle rewrite |
| branch 錯 | flags preservation / jump shortening |
| 只有 image 啟動後錯 | relocation / inline address / save path |

### 9.4 Image 驗證樣式

產物層驗證至少包含：

```text
1. 檔案 magic：ELF = 7F 45 4C 46，PE = MZ + PE\0\0
2. 入口：ELF main 或 PE EntryPoint 指向 runtime init
3. 區段：.forth/.space 或 .text/.idata 存在且大小合理
4. dynamic linking：dlopen/dlsym 或 LoadLibraryA/GetProcAddress 可解析
5. 實際執行：跑最小 app，確認能正常 BYE
```

`.space` / reserve space 不應只看檔案大小；在 ELF 中它可能是 NOBITS/BSS-like 區域，表示載入後配置，不一定佔據同等檔案大小。

---

## 10. 失敗後的縮小策略

測試失敗後，照這個順序縮小：

1. **固定輸入**：把互動輸入改成單一 `.f` 檔。
2. **固定環境**：記錄 spf4/spf4e、optimizer、platform、toolchain。
3. **去掉 FFI**：若去掉外部函式後正常，優先查 ABI / pointer lifetime。
4. **關掉 optimizer**：noopt 正常才進入 optimizer 排查。
5. **移除 image save**：在互動 runtime 正常但 saved image 失敗，才查 ELF/PE。
6. **縮到單一 word**：用最小 `: test ... ;` 重現。

不要同時改 optimizer、platform 與 source input，否則無法判斷是哪一層修好了或弄壞了。

---

## 11. 修改後最小驗證清單

### 11.1 修改 kernel primitive 後

- 跑 stack effect 測試。
- 測 `0`, `-1`, 邊界整數。
- 測後續依賴 flags 的序列。
- 測 signal/exception path 是否仍能印出錯誤。

### 11.2 修改 compiler / immediate words 後

- 測 `: ... ;` 基本定義。
- 測巢狀 `IF/ELSE/THEN`。
- 測 `BEGIN/UNTIL/WHILE/REPEAT`。
- 測 `DO/LOOP/+LOOP/LEAVE`。
- 測 `POSTPONE`, `[']`, `LITERAL`, `SLITERAL`。

### 11.3 修改 optimizer 後

- macroopt / noopt A/B。
- 測 rewrite 前後 flags。
- 測 inline size 邊界。
- 測 jump offset 邊界。

### 11.4 修改 platform / FFI 後

- 測無參數 C call。
- 測多參數 C call。
- 測 64-bit return。
- 測錯誤碼取得。
- 測 callback。
- 測 thread 內 USER 變數。

### 11.5 修改 image save 後

- 檢查 ELF/PE magic 與 header。
- 檢查 entry point。
- 檢查 relocation/import。
- 執行產物並跑最小 Forth 程式。

### 11.6 修改範圍與最小測試矩陣

| 你修改了 | 至少測試 | 建議額外測試 |
|----------|----------|--------------|
| kernel primitive | stack effect、邊界值、truth value | optimizer A/B，因 primitive 常被 inline |
| parser / source input | 空白、字串、檔案、`EVALUATE`、`SAVE-SOURCE` | include 巢狀與錯誤行號 |
| search-order / wordlist | 同名不同 wordlist、`CURRENT` / `CONTEXT`、hidden/smudge | module export / temporary wordlist |
| immediate / control words | `IF/ELSE/THEN`、loop、`POSTPONE`、literal | image save 後再跑一次 |
| optimizer | macroopt/noopt A/B、flags、inline size 邊界 | branch-heavy 程式與 saved executable startup |
| FFI / platform | 無參數、多參數、64-bit return、錯誤碼、callback | thread/TLS 與 signal/SEH 路徑 |
| image save | magic、entry、relocation/import、實際執行 | `SAVE-WITH-RESERVE` 字典成長 |

---

## 12. 建議新增到每章末尾的「驗證提示」

為了讓 trace 文件更可維護，每章可在總結前加入一小段：

```markdown
### 驗證提示

- 修改此章相關原始碼後，至少測：...
- 若出錯，優先檢查：...
- 與其他章的交互影響：...
```

這能把目前分散的實作解析，連回實際維護流程。
