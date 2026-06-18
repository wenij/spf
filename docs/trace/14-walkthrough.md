# SP-Forth/4 原始碼追蹤 — 從一個字到可執行映像的端到端走讀

> 定位：把前面各章拆開的機制串成一條可追蹤路徑。
>
> 本章用一個很小的 Forth 定義作為例子，追蹤它如何被讀入、解析、編譯、最佳化、寫入目標 image，最後在啟動後執行。

---

## 1. 範例程式

用最小但能碰到多個子系統的例子：

```forth
: SQUARE ( n -- n*n ) DUP * ;
: MAIN   7 SQUARE . CR ;
MAIN BYE
```

它會經過：

1. parser 讀取 token。
2. `:` 建立新字頭並進入編譯狀態。
3. `DUP`、`*` 被查找並編譯。
4. `;` 結束定義並解除隱藏狀態。
5. `MAIN` 執行時呼叫 `SQUARE`，最後輸出結果。

若這段程式被納入建構流程，還會進一步經過 target dictionary、optimizer、ELF/PE image save 與 runtime startup。

---

## 2. 第一段：來源輸入與 token 解析

入口是 `SOURCE` / `REFILL` / `>IN` 這組輸入狀態。不同來源會設定不同 `SOURCE-ID`：

| 來源 | `SOURCE-ID` 語意 | 常見入口 |
|------|------------------|----------|
| 互動輸入 | `0` | `QUIT` 迴圈 |
| `EVALUATE` 字串 | `-1` | 測試片段、動態載入 |
| 檔案 | `> 0` | `INCLUDED` |

`NextWord` / `PARSE` 依照 `>IN` 從目前 source buffer 取出 token。對範例而言，token 序列是：

```text
:  SQUARE  DUP  *  ;  :  MAIN  7  SQUARE  .  CR  ;  MAIN  BYE
```

若這一層出錯，通常會看到：

- token 被截斷。
- 字串 literal 讀錯。
- `INCLUDED` 後檔案路徑或行號錯。
- `SAVE-SOURCE` / `RESTORE-SOURCE` 後 `>IN` 不對。

對應文件：

- [02-compiler.md §2](02-compiler.md#2-語法剖析器spf_parserf深入解析)
- [02-compiler.md §3](02-compiler.md#3-原始碼讀取spf_read_sourcef深入解析)
- [05-io-error-init.md §11.1](05-io-error-init.md#111-source-id-與來源追蹤)

---

## 3. 第二段：`:` 建立字頭並切入編譯狀態

遇到 `:` 時，SP-Forth 不是立即產生完整 native code，而是先建立 dictionary entry：

```text
name token / header
        ↓
link field
        ↓
code field
        ↓
parameter / compiled body
```

對 `: SQUARE ... ;` 而言：

1. `:` 讀取下一個 token `SQUARE`。
2. `SHEADER` / `HEADER` 建立名稱欄位與 link。
3. 新定義暫時 `HIDE`，避免編譯未完成時被搜尋到。
4. `STATE` 切到編譯狀態。
5. 後續 token 依照編譯語意處理。

這裡要注意 `CURRENT` 與 `CONTEXT` 的差異：

- `CURRENT` 決定新定義寫入哪個 wordlist。
- `CONTEXT` 決定查找 token 時搜尋哪些 wordlist。

如果 `SQUARE` 定義後找不到，先查 `CURRENT` 是否是預期 wordlist，再查 `HIDE` / `SMUDGE` 是否在 `;` 後恢復。

對應文件：

- [02-compiler.md §7](02-compiler.md#7-詞彙表管理spf_wordlistf深入解析)
- [02-compiler.md §9](02-compiler.md#9-定義字spf_defwordsf深入解析)
- [11-forth-compilation.md](11-forth-compilation.md)

---

## 4. 第三段：編譯 `DUP *`

在編譯狀態下，`INTERPRET` 對每個 token 做三件事：

1. 用搜尋順序找 token。
2. 判斷找到的是 immediate 還是一般字。
3. immediate 字立即執行；一般字被編譯進目前定義。

在 SP-Forth 內部，`INTERPRET` 是可被重新導向的 vectored word；本節描述的是一般執行環境中的預設行為。交叉編譯器可改變某些分派點，讓同樣的 token 被解讀為 target dictionary 的定義或 host 端的編譯控制。

`DUP` 與 `*` 是一般字，因此會被編進 `SQUARE` 的 body。概念上可視為：

```text
SQUARE body:
  call DUP
  call *
  exit
```

實際機器碼可能因 optimizer 而不是單純 call 序列。

### 4.1 `DUP` 的執行模型

SP-Forth 的核心慣例是 TOS-in-EAX：

```text
EAX = TOS
EBP = 指向次堆疊項
```

所以 `DUP ( x -- x x )` 的核心動作是：

```asm
LEA EBP, -4 [EBP]   ; 資料堆疊往下長，空出一格
MOV [EBP], EAX      ; 舊 TOS 成為次堆疊項
```

`EAX` 仍保留 TOS，因此結果是兩個 `x`。

### 4.2 `*` 的執行模型

`* ( n1 n2 -- n3 )` 會使用 `EAX` 與 `[EBP]`，結果仍放回 `EAX`，並調整 `EBP` 讓堆疊少一項。

因此 `SQUARE` 的 runtime stack flow 是：

```text
輸入：        EAX = n
DUP 後：      EAX = n, [EBP] = n
* 後：        EAX = n*n
```

對應文件：

- [01-kernel.md §1](01-kernel.md#1-forth-虛擬機器架構)
- [01-kernel.md §3](01-kernel.md#3-forth-程序核心spf_forthprocf深入解析)
- [08-append-a.md](08-append-a.md)

---

## 5. 第四段：`;` 結束定義

`;` 是 immediate word。它不會被當成普通 call 編入 `SQUARE`，而是在編譯期執行：

1. 編入結束控制，例如 `EXIT` 或等價終止序列。
2. 解除 `HIDE` / `SMUDGE`，讓 `SQUARE` 可被搜尋。
3. `STATE` 回到直譯狀態。

若 `SQUARE` 在 `;` 後仍找不到，優先查 `SMUDGE` 是否恢復名稱可見性。

對應文件：

- [02-compiler.md §12](02-compiler.md#12-立即字-直譯分支spf_immed_translf深入解析)
- [11-forth-compilation.md §2](11-forth-compilation.md#2-state-與編譯直譯雙模式)

---

## 6. 第五段：`MAIN` 如何呼叫 `SQUARE`

定義 `MAIN` 時，`7` 是 literal，`SQUARE`、`.`、`CR` 是一般字：

```forth
: MAIN 7 SQUARE . CR ;
```

編譯時大致產生：

```text
push literal 7
call SQUARE
call .
call CR
exit
```

這裡會碰到兩個重要機制：

| token | 機制 |
|-------|------|
| `7` | 數字解析，編成 literal |
| `SQUARE` | 查找剛才解除隱藏的新定義 |

若 `7` 被當成未定義字，問題在數字解析 / literal branch。若 `SQUARE` 找不到，問題在 wordlist / `SMUDGE` / search order。

對應文件：

- [02-compiler.md §10](02-compiler.md#10-直譯器spf_translatef深入解析)
- [02-compiler.md §13](02-compiler.md#13-立即字-常值分支spf_immed_litf-spf_literalf深入解析)

---

## 7. 第六段：optimizer 可能如何改寫

若 macro optimizer 啟用，編譯結果不一定是單純的 call 序列。可能發生：

- literal 被編成直接載入。
- 小型 primitive 被 inline。
- `DUP *` 附近的 stack 操作被合併或簡化。
- jump / branch 被縮短。

但是 optimizer 必須保持：

1. stack effect 相同。
2. `EAX` 結束時仍是 TOS。
3. `EBP` 位移相同。
4. 若後續依賴 flags，flags 語意不能被破壞。

排查 optimizer 時，最可靠的第一步是 macroopt / noopt A/B：同一段程式在 noopt 正常、macroopt 異常，才優先懷疑 optimizer。

對應文件：

- [07-optimizer.md](07-optimizer.md)
- [13-verification.md §4](13-verification.md#4-optimizer-等價性檢查)

---

## 8. 第七段：交叉編譯與 target dictionary

在自舉或建構 image 時，情況比互動定義多一層：host Forth 正在建構 target Forth。

因此每個位址都要問：

| 問題 | 例子 |
|------|------|
| 這是 host XT 嗎？ | 建構時可直接在 host 執行的 word |
| 這是 target CFA/PFA 嗎？ | 要寫入目標 dictionary 的位址 |
| 這是檔案 offset 嗎？ | ELF/PE 內的檔案位置 |
| 這是載入後 virtual address 嗎？ | runtime EIP 會跳去的位置 |

`[T]` / `[I]` 的作用是控制「現在 token 的語意應該作用在 target 還是 host」。`>VIRT` / `VIRT>` 則用來處理 target virtual address 與建構期位址的轉換。

對應文件：

- [03-cross-compiler.md §1](03-cross-compiler.md#1-交叉編譯器概述與元編譯meta-compilation原理)
- [03-cross-compiler.md §2](03-cross-compiler.md#2-虛擬位址與映像基址tc_spff)
- [03-cross-compiler.md §3](03-cross-compiler.md#3-目標編譯器詞彙架構)

---

## 9. 第八段：儲存成 ELF / PE image

target dictionary 與 native code 形成後，`SAVE` / `XSAVE` 類機制會把記憶體內容轉成平台格式：

| 平台 | 主要格式 | 檢查重點 |
|------|----------|----------|
| POSIX | ELF | section / segment、relocation、dynamic symbol |
| Windows | PE | DOS stub、PE header、section table、import table |

以 `SQUARE` / `MAIN` 這類定義而言，最終要確認：

1. compiled body 被放進正確可執行區域。
2. entry point 會先完成 runtime init。
3. dictionary pointer / USER 區 / heap 在啟動時正確設定。
4. 若呼叫外部 API，dynamic symbol 或 import table 完整。

對應文件：

- [06-build-save.md](06-build-save.md)
- [09-windows-platform.md §7](09-windows-platform.md#7-pe-映像儲存spf_pe_savef深入解析)
- [13-verification.md §5](13-verification.md#5-image-elf-pe-驗證)

---

## 10. 第九段：runtime startup 後執行

執行 image 時，系統不是直接跳進 `MAIN`。通常會先完成：

1. platform 初始化。
2. USER 區 / TLS 設定。
3. heap / memory pool 初始化。
4. console / file I/O 初始化。
5. signal / SEH handler 安裝。
6. module path 設定。
7. 進入 `QUIT` 或執行指定命令。

若 image 可以產生但啟動即 crash，優先查初始化序列；若啟動正常但執行 `MAIN` crash，才回頭查 compiled body、optimizer、FFI 或 primitive。

對應文件：

- [05-io-error-init.md §10](05-io-error-init.md#10-系統初始化spf_initf)
- [04-posix-platform.md §12](04-posix-platform.md#12-信號處理posixinitf深入解析)
- [09-windows-platform.md §5](09-windows-platform.md#5-例外處理與-sehspf_win_initf深入解析)

---

## 11. 一張端到端追蹤圖

```text
source file / stdin / EVALUATE
        │
        ▼
SOURCE / REFILL / >IN
        │
        ▼
NextWord / PARSE
        │
        ▼
INTERPRET
        │
        ├─ 找到 immediate word ──► 編譯期執行
        │
        ├─ 找到一般 word ───────► COMPILE, / optimizer / inline
        │
        └─ 找不到 ──────────────► number parser / NOTFOUND / THROW
        │
        ▼
dictionary entry / compiled body
        │
        ▼
target dictionary（交叉編譯時）
        │
        ▼
ELF / PE image save
        │
        ▼
runtime init（TLS / USER / heap / I/O / signal 或 SEH）
        │
        ▼
執行 word body（EAX=TOS, EBP=data stack, EDI=USER base）
```

---

## 12. 逐步狀態表：`: SQUARE DUP * ;`

把第一節的範例拆成更細的狀態變化：

| 步驟 | token | `STATE` | immediate? | 動作 | 主要副作用 |
|------|-------|---------|------------|------|------------|
| 1 | `:` | 0 | 是 / defining word | 執行 `:` | 讀取下一 token 作為名稱，建立 header，切到 compile state |
| 2 | `SQUARE` | 由 `:` 消耗 | 不適用 | 作為新字名 | 寫入名稱欄位，接到 `CURRENT` wordlist |
| 3 | `DUP` | 非 0 | 否 | 編譯 `DUP` | 寫入 call 或 inline 片段 |
| 4 | `*` | 非 0 | 否 | 編譯 `*` | 寫入 call 或 inline 片段 |
| 5 | `;` | 非 0 | 是 | 執行 `;` | 編入 exit，解除 hidden/smudge，回到 interpret state |

這張表有兩個用途：

1. 讓你看到 Forth 沒有獨立 compiler pass；每個 token 被讀到時就決定動作。
2. 排查時可定位錯在哪一步：若 `SQUARE` 定義後找不到，是第 2/5 步；若執行結果錯，是第 3/4 步或 optimizer。

### 12.1 概念化的 dictionary entry

`SQUARE` 編譯後可用下圖理解：

```text
wordlist HEAD ──► name: SQUARE
                   │
                   ├─ link: previous word
                   ├─ code field: colon/native entry
                   └─ body:
                        [ compiled DUP ]
                        [ compiled *   ]
                        [ compiled EXIT]
```

在 noopt 情況下，body 可能接近「call DUP、call *、exit」；在 macroopt 啟用時，小 primitive 可能被 inline，因此你在機器碼裡未必看得到明確的 `CALL DUP`。

### 12.2 Optimizer 前後的追蹤差異

對 `: MAIN 7 SQUARE . CR ;`，概念上有兩種觀察方式：

| 模式 | 你可能看到 | 排查重點 |
|------|------------|----------|
| noopt | literal 7、call SQUARE、call `.`, call `CR` | 容易對照 source token |
| macroopt | literal 直接載入、`SQUARE` 可能 inline、stack shuffle 被消去 | 要看 stack effect 是否等價，不要執著於 call 是否存在 |

因此調試時若你「找不到 `SQUARE` 的 call」，不一定代表它沒被編譯；它可能被 inline 或重寫。這時用 [13-verification.md §9.3](13-verification.md#93-optimizer-ab-測試樣式) 的 macroopt/noopt A/B 方法判斷。

### 12.3 Host / target 位址錯用的具體例子

交叉編譯時最危險的錯誤是把 host address 寫入 target image：

```text
錯誤概念：
  把 host DP @ 得到的位址值直接當成 target virtual address 寫入 image

後果：
  saved image 內含 host process 的暫時位址
  目標 executable 啟動後該位址無效
  EIP / dictionary link 可能跳到不存在位置
```

正確概念是：凡是要留在 target image 裡的指標，都要確認它是 target virtual address 或可 relocation 的值。這也是 [03-cross-compiler.md](03-cross-compiler.md) 反覆強調 `>VIRT` / `VIRT>` 的原因；[15-standalone-executable.md](15-standalone-executable.md) 則從 ELF/PE 輸出角度說明這些 relocation 最後如何落到可執行映像。

---

## 13. 從 source token 到可執行 image 的資料形態轉換

同一段程式在每一層的形態都不同：

| 階段 | 形態 | 例子 |
|------|------|------|
| source | 字元序列 | `: SQUARE DUP * ;` |
| parser | token | `:`, `SQUARE`, `DUP`, `*`, `;` |
| search | XT / nt | 找到 `DUP` 的 execution token |
| compiler | dictionary bytes | call/inline/literal/exit |
| optimizer | 改寫後 bytes | inline primitive、short jump、constant folding |
| image save | ELF/PE sections | `.forth`, `.space`, `.text`, `.idata` |
| runtime | CPU 狀態 | `EAX=TOS`, `EBP=data stack`, `EDI=USER base` |

讀 trace 文件時要一直問：**我現在看到的是哪一種形態？** 若把 token、XT、file offset、runtime address 混在一起，就很容易誤判。

---

## 14. 如何用這條路徑排查

| 如果壞在 | 先看 |
|----------|------|
| token 讀錯 | `SOURCE-ID`, `>IN`, parser |
| 字找不到 | `CONTEXT`, `CURRENT`, wordlist, `HIDE` |
| 編譯控制結構錯 | immediate word, branch backpatch, `HERE` |
| noopt 正常 macroopt 壞 | optimizer rewrite 等價性 |
| image 產生但不能跑 | entry point, relocation, import table, USER init |
| FFI 後壞 | cdecl/stdcall、參數數、pointer lifetime、callback bridge |
| signal/SEH 後壞 | `EDI` / USER 區恢復、exception context |

這也是閱讀 `docs/trace/*` 的實用順序：先從症狀定位層級，再回到該層文件，而不是從第一章一路線性重讀。
