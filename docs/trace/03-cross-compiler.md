# SP-Forth/4 原始碼追蹤 — 交叉編譯器與目標系統框架深入解析

> 對應原始碼：`src/tc_spf.F`、`src/tc-dl.f`、`src/tc-dl-tc.f`、`src/tc-dl-imm.f`、`src/tc-configure-lines.f`、`src/noopt.f`、`src/xsave.f`
> 原始碼版權：Copyright [C] 1992-2000 A.Cherezov ac@forth.org

> 本章目標：理解 host/target 雙位址空間如何切換、`[T]/[I]` 夾擊模式怎麼確保目標映像的正確性。
> 
> 註：`tc_spf.F` 檔頭仍寫著「SP-Forth v3.7x」，這是該檔沿用的歷史性來源標頭；本文件追蹤的實際系統則是目前 repo 中的 SPF4 / kernel version 429。

---

## 1. 交叉編譯器概述與元編譯（Meta-Compilation）原理

### 1.1 什麼是元編譯？

Forth 的交叉編譯是一種**元編譯**（meta-compilation）技術：使用一個已經在執行的 Forth 系統（稱為**宿主系統**，host），来編譯產生另一個 Forth 系統的記憶體映像（稱為**目標系統**，target）。這種技術使得 Forth 能夠自舉（bootstrap）——用 Forth 來編譯 Forth。

SP-Forth 的元編譯器設計在以下幾個層次上運作：

| 層次 | 說明 | 對應原始碼 |
|------|------|-----------|
| 宿主系統 | 執行中的 spf4orig（預建構的 Forth 系統） | 外部二進位 |
| 元編譯器 | 載入於宿主系統之上，控制交叉編譯流程 | `tc_spf.F` |
| 目標映像 | 元編譯器產生的二進位映像 | 記憶體中的字典空間 |

### 1.2 核心概念術語對照

| 概念 | 英文 | 說明 |
|------|------|------|
| 宿主系統 | Host | 正在執行的 Forth 系統（spf4orig） |
| 目標系統 | Target | 被編譯產生的 Forth 系統映像 |
| `[T]` | To Target | 切換搜尋順序到目標詞彙表 |
| `[I]` | To Interpreter | 切換搜尋順序回宿主詞彙表 |
| `>VIRT` | To Virtual | 宿主位址 → 目標位址轉換 |
| `VIRT>` | From Virtual | 目標位址 → 宿主位址轉換 |
| `TC-` 前綴 | Target Compiler | 目標編譯器專用的字 |
| `IMAGE-START` | — | 目標映像基址；同時參與位址轉換，POSIX 版也會由 linker script 把 `.forth` 連到這個位址 |

### 1.3 為何需要交叉編譯？

傳統的 Forth 系統使用「 appending」（追加）方式建立新定義——新定義直接追加到執行中系統的字典。但 SP-Forth 的交叉編譯器需要：

1. **產生獨立的二進位映像**：目標系統必須能夠脫離宿主系統獨立執行
2. **確保位址一致性**：目標系統中的位址在儲存後不能改變
3. **處理字詞的雙重存在**：每個字詞同時存在於宿主系統（用於編譯）和目標系統（用於執行）

### 1.4 範例：`VARIABLE X` 如何同時碰到 host 與 target？

```forth
VARIABLE X
```

在交叉編譯器裡，這行不是單純把資料 append 到目前字典，而是同時經過兩個世界：

1. **宿主系統執行 `VARIABLE`**：這個 `VARIABLE` 是 `TC` 詞彙表裡的定義，用來控制交叉編譯流程。
2. **`[T] HEADER [I]`**：先切到 `TC-TRG` 建立目標字頭，再切回宿主繼續編譯。
3. **`CREATE-CODE COMPILE,`**：把目標系統執行時要用的 `CREATE` 語意編入 target 映像。
4. **`0 ,`**：在 target 映像中為 `X` 配置初值 0。

因此，**宿主負責「做編譯這件事」，目標負責「未來執行時怎麼表現」**。這正是 `[T]` / `[I]` 存在的原因。

---

## 2. 虛擬位址與映像基址（tc_spf.F）

### 2.1 編譯期常數與記憶體佈局

```forth
IMAGE-SIZE = 512 * 1024  (512 KiB 初始映像大小)
IMAGE-START = 0x8050000  (目標映像基址)
```

`IMAGE-START` 在 `src/spf.f` 中對 POSIX / Windows 兩條建構路徑都會先定義。它一方面提供 `virtual-address` 建立 target/host 位址轉換，另一方面在 POSIX 路徑上也會由 `forth.ld` 把 `.forth` 段連到 `0x8050000`。因此在 POSIX 路徑中，它不只是「名目值」，而是交叉編譯期位址轉換與最終 ELF 連結共同使用的 `.forth` 基址；Windows 路徑雖也先定義 `IMAGE-START` 供交叉編譯流程使用，但最終 PE 的 `IMAGE-BASE` 另由儲存路徑計算。

### 2.2 位址轉換函式

```forth
\ tc_spf.F:10-20
0 VALUE virt-offset

TARGET-POSIX [IF]
: >VIRT ( a -- va) virt-offset + ;    \ 宿主位址 → 目標位址
: VIRT> ( va -- a) virt-offset - ;     \ 目標位址 → 宿主位址
: >VIRT! ( a -- ) virt-offset SWAP +! ; \ 遞增修改目標位址
[ELSE]
: >VIRT ;    \ Windows 版：恆等操作
[THEN]

: virtual-address ( va -- ) HERE - TO virt-offset ;
: *DP@ ( -- va) DP @ >VIRT ;          \ 字典指標的目標位址
```

**POSIX vs Windows 的差異**：

在 POSIX 系統上，目標映像先在宿主系統記憶體中的 `HERE` 位置逐步生成；之後再用 `IMAGE-START virtual-address` 把「宿主生成位址」校正成「目標映像位址」，並由 `forth.ld` 把 `.forth` 段連到同一個 `IMAGE-START`。因此 `>VIRT` 的重點不是把決定權交給 ELF 載入器，而是協調 **宿主 `HERE` 與最終 link 位址** 之間的差值。

在 Windows 分支中 `>VIRT` 是恆等操作。但**不要**把這解釋成 PE 的 `IMAGE-BASE` 等於 `IMAGE-START`：`IMAGE-START`（`spf.f:138` = 0x8050000）只是交叉編譯期的虛擬位址基準；Windows 儲存路徑真正的 PE `IMAGE-BASE` 是由目前映像的 `ORG-ADDR − 0x2000` 推出（`src/win/spf_pe_save.f:14` `DUP 8 1024 * -`），不是 0x8050000。

### 2.3 ELF 偏移管理

```forth
\ tc_spf.F:32-35
0 VALUE elf-offset

: +elf-offset ( n -- ) elf-offset + TO elf-offset ;
: offset,size, ( n -- ) elf-offset , DUP , +elf-offset ;
```

`elf-offset` 用於追蹤 ELF 檔案中各段的偏移量。`offset,size,` 同時記錄偏移和大小，用於 ELF 段表（section table）的建構。

### 2.4 virtual-address 的設定時機

```forth
\ tc_spf.F:791
IMAGE-START virtual-address
```

這行位於 `tc_spf.F` 結尾（`src/tc_spf.F:791`），會在**交叉編譯器本身初始化完成後、`spf.f` 繼續產生 target image 之前**執行（`tc_spf.F` 由 `spf.f:149` 載入，而 target kernel/compiler/platform 從 `spf.f:160` 起才開始建立）。它將 `virt-offset` 設定為 `IMAGE-START - HERE`（更一般地說是 `va - HERE`），建立後續 target 編譯所用的「宿主 `HERE` → `IMAGE-START`」位址偏移。此後所有 `>VIRT` 轉換都基於這個偏移量。它並不是「所有目標代碼編譯完成後」才執行。

---

## 3. 目標編譯器詞彙架構

### 3.1 三重詞彙表系統

交叉編譯器使用三個專門的詞彙表（再加上宿主系統的 `FORTH` 詞彙表）：

```forth
角色分層（不是任何時刻都同時在搜尋順序中）：
  TC-IMM    ← 立即字層（IF, THEN, LITERAL, POSTPONE 等）
  TC-TRG    ← 目標系統定義層（被編譯的字詞）
  TC        ← 目標編譯器工具層（:, CREATE, CONSTANT 等）
  FORTH     ← 宿主系統字詞層（基本操作）
```

**為何需要三層？**

- **TC-IMM**：包含在編譯期需要立即執行的字（如 `IF`、`THEN`），這些字在前一節的編譯器中也是立即字。在交叉編譯中，它們需要產生**目標機器碼**而非宿主機器碼。
- **TC-TRG**：包含目標系統中的所有定義。當使用 `'`（tick）時，應該搜尋目標系統而非宿主系統。
- **TC**：包含定義字（如 `:`、`CREATE`、`VARIABLE`），它們建立目標系統的字頭結構。

```forth
\ tc_spf.F:60-64
VOCABULARY TC-TRG
VARIABLE SAVED-CURRENT

: [T] GET-CURRENT SAVED-CURRENT ! ALSO TC-TRG DEFINITIONS ;
: [I] PREVIOUS SAVED-CURRENT @ SET-CURRENT ;
```

`[T]` 和 `[I]` 是詞彙表切換字：

- `[T]`：儲存目前 CURRENT 到 `SAVED-CURRENT`，切換搜尋順序到 TC-TRG，並設定 CURRENT 為 TC-TRG 的 wid
- `[I]`：恢復搜尋順序（`PREVIOUS` 移除 TC-TRG），恢復 CURRENT 為之前儲存的值

### 3.2 [T] 和 [I] 的使用模式

```forth
: VARIABLE ( "<spaces>name" -- ) \ 94
  [T] HEADER [I]        \ 在目標詞彙表中建立字頭
  CREATE-CODE COMPILE,   \ 編譯 CREATE 執行碼
  0 ,                    \ 初始值為 0
;
```

`[T]` 切換到目標詞彙表使得 `HEADER` 在目標字典中建立名稱，然後 `[I]` 切換回宿主詞彙表繼續編譯。這種 `[T]/[I]` 夾擊模式在所有定義字中反覆出現。

### 3.3 冒號定義的進入與離開

```forth
\ tc_spf.F:530
:  [T] : ALSO TC-IMM ;

\ tc_spf.F:584-589
: ; PREVIOUS
  ?SET SetOP  POSTPONE ; [I] OPT OPT_CLOSE
; IMMEDIATE
```

**`:` 的行為**：
1. `[T] :`：在目標詞彙表中執行宿主 `:`（建立字頭並進入編譯模式）
2. `ALSO TC-IMM`：將 TC-IMM 加入搜尋順序，使得立即字可以被找到

**`;` 的行為**：
1. `PREVIOUS`：移除搜尋順序頂端（TC-IMM）
2. `?SET SetOP`：確保最佳化點正確設定
3. `POSTPONE ;`：編譯宿主 `;`（實際結束定義）
4. `[I]`：切換回宿主詞彙表

**搜尋順序變化圖**：

```forth
基線狀態：       TC → FORTH
進入 : 定義後：  TC-IMM → TC-TRG → TC → FORTH
離開 ; 定義後：  TC → FORTH（恢復）
```

這也對應到 `tc_spf.F` 的兩個註解，但要分成兩個階段看：`TC` 與 `TC-IMM` 在**宣告詞彙表本身**之後都不會自動常駐於搜尋順序；直到檔案尾端的 `ONLY FORTH DEFINITIONS ALSO TC` 執行後，基線搜尋順序才固定為 `TC -> FORTH`。而 `TC-TRG` 是由 `:` 內部的 `[T]`（本質上是 `ALSO TC-TRG`）臨時加入，`TC-IMM` 則只在進入 `:` / `;` 這類編譯情境時加入，所以「基線狀態」與「冒號定義內」必須分開理解。

### 3.4 CODE 定義的進入與離開

```forth
\ tc_spf.F:327-341
: CODE ( "<spaces>name" -- )
  TRUE StartColonHelp
  [T] CODE-ORIG      \ 在目標詞彙表中建立組合語言定義的字頭
  POP-ORDER SET-ORDER-TOP \ 類似 NIP-ORDER
;

: _END-CODE2
  EndColonHelp
  [ ALSO ASSEMBLER  ACTION-OF END-CODE  COMPILE,  PREVIOUS ]
  [I] ALSO TC
;
```

CODE 定義切換到 ASSEMBLER 詞彙表以支援組合語言助憶符，結束時恢復。

---

## 4. 目標程式碼產生

### 4.1 TC-CALL,：函式呼叫

```forth
\ tc_spf.F:158-165
: TC-CALL, ( addr -- )
  ?SET
  SetOP
  0E8 C,              \ x86 CALL rel32 opcode
  DP @ CELL+ - ,      \ 計算相對偏移量
  DP @ TO LAST-HERE
;
```

產生一條 x86 `CALL` 指令（opcode 0xE8 + 4 bytes 相對位址）。`DP @ CELL+ -` 計算從 CALL 指令結尾到目標位址的偏移——這是 x86 相對呼叫的標準計算方式：

```forth
偏移量 = 目標位址 - (CALL指令位址 + 5)
       = 目標位址 - (DP + 4)
       = (目標位址由 addr 參數指定) - DP @ CELL+
```

這裡的 `addr` 應理解為**要寫進 target 映像的目標位址**。對同一 `.forth` 段內的呼叫來說，`TC-CALL,` 在編譯時就以 target 位址差算出 `rel32`；由於 `rel32` 是相對位移，對整段基址平移並不敏感，因此這類內部 `CALL` **通常不需要** `.rel.forth` 重定位。ELF 的 `.rel.forth`（`src/elf.f:155-187` 共 8 筆）是針對 `dl-first`、`.dlstrings`、`dlopen`、`dlsym`、`realloc`、`write`、`calloc`、`dlerror` 等動態連結表與外部符號，而**不是**每個內部 CALL site。

### 4.2 MCOMPILE,：巨集編譯分派

```forth
\ tc_spf.F:167-174
: MCOMPILE, ( CFA -- )
    CON>LIT
    IF INLINE?
      IF     INLINE,
      ELSE   TC-CALL,
      THEN
    THEN
;
```

`MCOMPILE,` 與宿主系統的 `COMPILE,` 邏輯完全相同，但使用 `TC-CALL,` 代替 `_COMPILE,`。這保證了交叉編譯產生的 CALL 指令在目標映像中。

**編譯決策樹**（與宿主 COMPILE, 相同邏輯）：

```forth
MCOMPILE, ( CFA )    \ tc_spf.F:167-174: CON>LIT IF INLINE? IF INLINE, ELSE TC-CALL, THEN THEN
  │
  ├─ CON>LIT 回傳 TRUE（= 未處理，需繼續一般編譯）？
  │    ├─ 是 → INLINE? 偵測到短定義？
  │    │    ├─ 是 → INLINE,（內聯展開，機器碼拷貝到目標映像）
  │    │    └─ 否 → TC-CALL,（產生 CALL 指令到目標映像）
  │    └─ 否（CON>LIT 回傳 FALSE）→ 已由 CON>LIT 完成常數/特殊內聯處理，不再走 INLINE?/TC-CALL,
  └─（流程結束）
```

> **注意 `CON>LIT` 的回傳語意**：`CON>LIT` 回傳 **FALSE 表示「已完成」**常數/特殊定義的內聯處理；回傳 **TRUE 才表示「未處理」**，由後續 `INLINE?` 決定內聯或 `TC-CALL,`。這與直覺相反，閱讀 `MCOMPILE,` 時要特別小心。

### 4.3 TC-LIT,：常值編譯

```forth
\ tc_spf.F:176-180
: TC-LIT, ( x -- )
  S" DUP" TC-FINDOUT INLINE,    \ 內聯 DUP 的機器碼
  OPT_INIT
  SetOP 0B8 C,  , OPT           \ MOV EAX, #imm32
  OPT_CLOSE
;
```

與宿主系統的 `LIT,` 完全對稱，但使用 `TC-FINDOUT` 找到目標系統中的 DUP。`TC-FINDOUT`（第 96~98 行）的實作：

```forth
: TC-FINDOUT
   SFIND 0= ABORT" Can't find - TC-FINDOUT"
;
```

它在搜尋順序中查找字詞，如果未找到則中止。由於搜尋順序包含 TC-TRG，所以會找到目標系統的定義。

### 4.4 'DUP 和 'DROP：目標常值的特殊處理

```forth
\ tc_spf.F:182-187
: 'DUP
  S" DUP" TC-FINDOUT TC-LIT, ; IMMEDIATE

: 'DROP
  S" DROP" TC-FINDOUT >VIRT TC-LIT, ; IMMEDIATE
```

`'DUP` 編譯目標系統中 DUP 的 XT 作為常值。`'DROP` 則將 DROP 的 XT 透過 `>VIRT` 轉換為目標位址後再編譯——注意 `>VIRT` 只用於 `'DROP`，因為 DROP 在最佳化器中需要目標位址來進行內聯展開判斷。

### 4.5 TC-?BRANCH, 與 TC-BRANCH,：跳躍編譯

```forth
\ tc_spf.F:195-209
: TC-?BRANCH, ( ADDR -> )
  ?SET
  084 TO J_COD
  ???BR-OPT
  SetJP  SetOP
  J_COD    \ JX prefix 或 0x84
  0x0F     \ 若為近跳躍則需要 0x0F prefix
  C, C,
  DUP IF DP @ CELL+ - THEN , DP @ TO LAST-HERE
;

: TC-BRANCH, ( ADDR -> )
  ?SET SetOP SetJP E9 C,
  DUP IF DP @ CELL+ - THEN , DP @ TO LAST-HERE
;
```

與宿主系統的 `?BRANCH,` 和 `BRANCH,` 完全對稱。`TC-?BRANCH,` 產生條件跳躍（JZ/JNZ near，6 bytes），`TC-BRANCH,` 產生無條件跳躍（JMP near，5 bytes）。

### 4.6 回填機制

```forth
\ tc_spf.F:211-226
: TC>RESOLVE1 ( A -> )
  DUP
    DP @ DUP TO :-SET
    OVER - 4 -
    SWAP !
  RESOLVE_OPT
;

: TC>RESOLVE ( A, N -- )
  DUP 1 = IF   DROP TC>RESOLVE1
          ELSE 2 <> IF -2007 THROW THEN
               TC>RESOLVE1
          THEN
;
```

`TC>RESOLVE` 是宿主 `>ORESOLVE` 的目標版本。它回填前向跳躍的目標位址。引數 `N` 標記跳躍類型：1 表示來自 IF，2 表示來自 ELSE——這與宿主系統的約定完全一致。

---

## 5. SHEADER — 目標名稱解析

### 5.1 SHEADER 的完整流程

```forth
\ tc_spf.F:292-303
: SHEADER ( addr u -- )
  HERE 0 , ( cfa )         \ 分配 CFA，初始為 0
  0 C,     ( flags )        \ 旗標位元組，初始為 0
  UNROT WARNING @
  IF 2DUP GET-CURRENT search-wordlist
     IF DROP 2DUP TYPE ."  isn't unique" CR THEN
  THEN
  GET-CURRENT +SWORD         \ 加入詞彙表鍊結
  ALIGN                      \ 對齊
  HERE SWAP ! ( 回填 CFA )   \ 將 HERE 寫入 CFA 欄位
;
```

與宿主系統的 `SHEADER1`（02-compiler.md 第 9.1 節）相比，目標版本少了兩個步驟：

1. **沒有 `ALIGN-BYTES` 填充邏輯**：宿主版本有 `ALIGN-BYTES @ DUP 4 > IF 5 - ALLOT ELSE 1 - ALLOT THEN`，目標版本只有簡單的 `ALIGN`
2. **沒有 `DUP LAST-CFA !`**：目標系統不需要追蹤 CFA

### 5.2 +SWORD 的目標版本

```forth
\ tc_spf.F:280-286
: +SWORD ( addr u wid -> )
  HERE LAST !
  HERE 2SWAP S", SWAP DUP @ , !
;
```

與宿主系統的 `+SWORD` 完全相同——名稱字串寫入字典、鍊結到詞彙表頭。

### 5.3 HEADER — 便捷入口

```forth
\ tc_spf.F:305-307
: HEADER
   PARSE-NAME SHEADER
;
```

---

## 6. 定義字（目標版本）深入解析

### 6.1 CREATE、VARIABLE、->VARIABLE

```forth
\ tc_spf.F:344-357
: CREATE ( "<spaces>name" -- ) \ 94
  [T] HEADER [I]
  CREATE-CODE COMPILE,
;

: VARIABLE ( "<spaces>name" -- ) \ 94
  [T] HEADER [I]
  CREATE-CODE COMPILE,
  0 ,
;

: ->VARIABLE ( x "<spaces>name" -- ) \ 94
  [T] HEADER [I]
  CREATE-CODE COMPILE,
  ,
;
```

所有定義字遵循相同的模式：`[T] HEADER [I]` 建立目標字典字頭，然後 COMPILE, 對應的執行碼。

`CREATE-CODE` 是一個 VALUE，在目標系統編譯 `_CREATE-CODE` 的 XT 後被設定：

```forth
\ tc_spf.F:67
0 VALUE CREATE-CODE
```

在核心原語編譯完成後，`CREATE-CODE` 會透過 `TO` 設定為目標系統中 `_CREATE-CODE` 的位址。

### 6.2 CONSTANT 與 VALUE

```forth
\ tc_spf.F:370-378
: CONSTANT ( x "<spaces>name" -- ) \ 94
  [T] HEADER [I]
  CONSTANT-CODE COMPILE, ,
;

: VALUE ( x "<spaces>name" -- ) \ 94 CORE EXT
  [T] HEADER [I]
  CONSTANT-CODE COMPILE, ,        \ 讀取用
  TOVALUE-CODE COMPILE,            \ TO 修改用
;
```

VALUE 比 CONSTANT 多編譯了一個 `_TOVALUE-CODE` 的 XT，使得 `TO` 能找到修改值的位置。這與宿主系統的 VALUE 完全對稱。

### 6.3 USER 變數

```forth
\ tc_spf.F:358-368
: USER ( "<spaces>name" -- )
  [T] HEADER [I]
  USER-CODE COMPILE,
  TC-USER-ALIGNED SWAP ,       \ 偏移量寫入 PFA
  CELL+ TC-USER-ALLOT           \ 遞增 USER 偏移
;

: USER-CREATE ( "<spaces>name" -- )
  [T] HEADER [I]
  USER-CODE COMPILE,
  TC-USER-ALIGNED SWAP ,
  TC-USER-ALLOT                 \ 不自動遞增偏移
;
```

`TC-USER-OFFS`（第 101~108 行）追蹤目標系統的 USER 偏移量：

```forth
VARIABLE TC-USER-OFFS 16 TC-USER-OFFS !

: TC-USER-ALLOT ( n -- )   TC-USER-OFFS +! ;
: TC-USER-HERE ( -- n )    TC-USER-OFFS @ ;
```

初始偏移 16 bytes 是 target USER 區的保留開頭（`src/tc_spf.F:101` 將 `TC-USER-OFFS` 初始化為 16）；本檔未列出這 16 bytes 具體對應哪些 USER 變數。

### 6.4 VECT 與 ->VECT

```forth
\ tc_spf.F:395-404
: VECT ( -> )
  [T] HEADER [I]
  VECT-CODE COMPILE, NOOP-CODE >VIRT ,
  TOVALUE-CODE COMPILE,
;

: ->VECT ( x -> )
  [T] HEADER [I]
  VECT-CODE COMPILE, ,
  TOVALUE-CODE COMPILE,
;
```

VECT 的字典結構：

```forth
  ┌──────────────────┐
  │ VECT-CODE CALL    │ ← CFL（5 bytes）
  ├──────────────────┤
  │ NOOP-CODE XT (或初始值) │ ← PFA：目前的執行向量
  ├──────────────────┤
  │ TOVALUE-CODE CALL │ ← TO 修改時的程式碼
  └──────────────────┘
```

注意 `NOOP-CODE >VIRT`——NOOP-CODE 的位址需要透過 `>VIRT` 轉換為目標位址，因為它在目標映像中。

### 6.5 WORDLIST

```forth
\ tc_spf.F:406-414
: WORDLIST
  ALIGN
  HERE VOC-LIST @ , VOC-LIST !
  HERE 0 , \ wid +0 : HEAD
       0 , \ wid +4 : CSTRING
       0 , \ wid +8 : PAR
       0 , \ wid +12: CLASS
       0 , \ wid +16: WID-EXTRA / 保留
;
```

和宿主版一樣，這裡也有一個**隱藏的前置 `VOC-LIST` link cell**；對外回傳的 `wid` 指向的是公開欄位起點，而不是配置區塊最前端。差別在於目標版沒有像宿主版那樣用 `GET-CURRENT` 預先初始化 `PAR`，而是全部先填 0，留待後續 target 側修補。

---

## 7. 立即字編譯（TC-IMM 詞彙表）深入解析

### 7.1 流程控制字

```forth
\ tc_spf.F:626-628
: IF ( C: -- orig )
  ?COMP 0 TC-?BRANCH, >MARK 1
; IMMEDIATE

\ tc_spf.F:647-651
: ELSE ( C: orig1 -- orig2 )
  ?COMP 0 TC-BRANCH,
  TC>RESOLVE
  >MARK 2
; IMMEDIATE

\ tc_spf.F:653
: THEN ( C: orig -- )
  ?COMP TC>RESOLVE ; IMMEDIATE
```

與宿主系統的 IF/ELSE/THEN 完全對稱，但使用 `TC-?BRANCH,`、`TC-BRANCH,`、`TC>RESOLVE` 目標版本。

### 7.2 BEGIN/UNTIL/WHILE/REPEAT

```forth
\ tc_spf.F:630-664
: UNTIL ( C: dest -- )
  ?COMP 3 <> IF -2004 THROW THEN
  TC-?BRANCH,
  0xFFFFFF80 DP @ 4 - @ U<
  IF DP @ 5 - W@ 0x3F0 + DP @ 6 - W! -4 ALLOT THEN
  DP @ TO :-SET
; IMMEDIATE

: WHILE ( C: dest -- orig dest )
  ?COMP 0 TC-?BRANCH, >MARK 1
  2SWAP
; IMMEDIATE

: REPEAT ( C: orig dest -- )
  ?COMP
  3 <> IF -2005 THROW THEN
  DUP DP @ 2+ - DUP SHORT?
  IF SetJP 0xEB C, C, DROP            \ JMP short
  ELSE DROP TC-BRANCH, THEN            \ JMP near
  >RESOLVE
; IMMEDIATE
```

`UNTIL` 中的短跳躍最佳化（第 633~635 行）：

```forth
0xFFFFFF80 DP @ 4 - @ U<
IF DP @ 5 - W@ 0x3F0 + DP @ 6 - W! -4 ALLOT THEN
```

如果跳躍距離在 -128 以內，將 6 bytes 的 `0F 84 rel32`（JZ near）改為 2 bytes 的 `7x rel8`（JZ short），節省 4 bytes。具體操作：修改跳躍位址前方的 opcode 位元組。

### 7.3 DO/LOOP 目標版本

```forth
\ tc_spf.F:673-681
: DO ( C: -- do-sys )
  ?COMP
  S" C-DO" TC-FINDOUT INLINE,        \ 內聯 C-DO
  SetOP 0x68 C, DP @ 4 ALLOT          \ PUSH imm32（LEAVE 目標位址）
  SetOP 0x52 C,                        \ PUSH EDX
  SetOP 0x53 C,                        \ PUSH EBX
  4 ALIGN-NOP                          \ 依目標交叉編譯器這裡指定的 4-byte 邊界對齊
  DP @ DUP TO :-SET
; IMMEDIATE
```

與宿主版本完全對稱，但使用 `TC-FINDOUT` 找到目標系統的 `C-DO`。`INLINE,` 將目標系統 C-DO 的機器碼直接拷貝到目標映像中。

```forth
\ tc_spf.F:692-704
: LOOP ( C: do-sys -- )
  ?COMP
  24 04FF W, C,            \ inc dword [esp]
  042444FF ,               \ inc dword 4[esp]
  HERE 2+ - DUP SHORT? SetOP SetJP
  IF 71 C, C,              \ jno short
  ELSE 4 - 0F C, 81 C, ,  \ jno near
  THEN    SetOP
  0C24648D ,               \ lea esp, 0c [esp]
  *DP@ SWAP !              \ 回填 LEAVE 目標位址
; IMMEDIATE
```

注意第 703 行的 `*DP@`：LOOP 回填 LEAVE 目標位址時使用 `*DP@`（DP @ >VIRT）而非 DP @——因為 DO 的 PUSH imm32 需要儲存的是**目標位址**（虛擬位址），而非宿主位址。

這是 POSIX 和 Windows 版本的關鍵差異之一。在 Windows 版本中，`>VIRT` 是恆等操作，所以 `*DP@` 等同於 `DP @`。

### 7.4 +LOOP 的差異

```forth
\ tc_spf.F:706-718
: +LOOP ( C: do-sys -- )
  ?COMP
  1 C, 4 C, 24 C, SetOP   \ ADD [ESP], EAX（手動編碼）
  04244401 ,               \ ADD 4[ESP], EAX
  'DROP INLINE,             \ 內聯 DROP
  HERE 2+ - DUP SHORT? SetOP SetJP
  IF 71 C, C,
  ELSE 4 - 0F C, 81 C, ,
  THEN    SetOP
  0C24648D ,               \ lea esp, 0xC [esp]
  *DP@ SWAP !
; IMMEDIATE
```

+LOOP 的 ADD 指令使用了手動編碼（`1 C, 4 C, 24 C,`）而非 `S" ADD[ESP],EAX" TC-FINDOUT INLINE,`，這可能是因為 ADD 指令的變體需要精確的 opcode 控制。

### 7.5 I、UNLOOP、LEAVE、>R、R>、RDROP

這些迴圈輔助字的目標版本完全使用 `TC-FINDOUT INLINE,` 模式：

```forth
\ tc_spf.F:721-746
: I    ?COMP S" C-I" TC-FINDOUT INLINE, ; IMMEDIATE
: >R   ?COMP S" C->R" TC-FINDOUT INLINE, ; IMMEDIATE
: R>   ?COMP S" C-R>" TC-FINDOUT INLINE, ; IMMEDIATE
: RDROP ?COMP S" C-RDROP" TC-FINDOUT INLINE, ; IMMEDIATE
```

UNLOOP 和 LEAVE 使用手動編碼：

```forth
\ tc_spf.F:725-734
: UNLOOP
  ?COMP SetOP 0C24648D ,    \ lea esp, 0c [esp]
; IMMEDIATE

: LEAVE
  ?COMP
  SetOP 0824648D ,            \ lea esp, 08 [esp]
  SetOP C3 C,                \ ret
; IMMEDIATE
```

### 7.6 ?DUP 的狀態檢查

```forth
\ tc_spf.F:754-759
: ?DUP ( x -- 0 | x x )
  STATE @
  IF   HERE TO :-SET
       S" C-?DUP" TC-FINDOUT INLINE,
       HERE TO :-SET
  ELSE ?DUP
  THEN ; IMMEDIATE
```

`?DUP` 根據 `STATE` 選擇不同行為：編譯模式下內聯 `C-?DUP`，直譯模式下執行宿主 `?DUP`。`HERE TO :-SET` 的雙重呼叫是為了最佳化器：第一次標記最佳化點起點，第二次標記終點——允許 `?DUP` 之後的代碼與之前的代碼進行最佳化組合。

### 7.7 THROW 的最佳化路徑

```forth
\ tc_spf.F:761-774
: THROW
     STATE @ IF
     OPT_INIT OP0 @ C@ 0xB8 = 0 AND        \ 檢查最佳化緩衝區是否為 MOV EAX, #imm
     IF  0xE9 C,                             \ 產生 JMP（無條件跳躍）
         THROW-CODE DP @ CELL+ - ,           \ 跳到 THROW-CODE
         EXIT
     THEN
     OPT_CLOSE
     0x850FC00B ,                             \ OR EAX, EAX; JNZ near
     THROW-CODE DP @ CELL+ - ,
     'DROP INLINE,
     ELSE THROW
     THEN ; IMMEDIATE
```

THROW 的編譯在 source 裡看似有兩條路徑，但其中一條目前是**被關閉的草稿**：

1. **被停用的常值最佳化草稿**（`OP0 @ C@ 0xB8 = 0 AND`）：原意是「若前一條指令是 `MOV EAX, #imm32`（常值），直接用 `JMP` 跳到 THROW 處理程式碼」。但 source（`src/tc_spf.F:761-768`）在條件後加了 `0 AND`，把整個條件強制為 false，**因此這條路徑實際上永遠不會被走到**。

   ```asm
   ; 這段在 source 中存在，但被 `0 AND` 關閉，不會執行：
   MOV EAX, #error_code
   JMP THROW_HANDLER
   ```

2. **實際走的一般路徑**（`src/tc_spf.F:769-772`）：產生 `OR EAX, EAX`（測試 TOS）+ `JNZ near THROW_HANDLER`（條件跳轉），TOS 為零時內聯 `DROP` 丟棄它。

   ```asm
   ; 一般路徑：
   OR EAX, EAX                ; 0x0B 0xC0 0x0F 0x85
   JNZ THROW_HANDLER          ; rel32
   DROP                       ; 內聯 DROP
   ```

### 7.8 [']：目標 XT 常值

```forth
\ tc_spf.F:592
: ['] ALSO TC-TRG ' >VIRT TC-LIT, PREVIOUS ; IMMEDIATE
```

`[']` 在目標編譯器中的行為：
1. `ALSO TC-TRG`：將目標詞彙表加入搜尋順序
2. `'`：查找字詞的 XT（在目標詞彙表中）
3. `>VIRT`：將宿主位址轉換為目標位址
4. `TC-LIT,`：編譯為目標常值
5. `PREVIOUS`：移除目標詞彙表

關鍵：在交叉編譯中，`'` 找到的 XT 是**宿主系統的位址**，必須透過 `>VIRT` 轉換為目標位址才能在目標映像中使用。

### 7.9 POSTPONE 與 [COMPILE] 的目標版

```forth
\ tc_spf.F:596-609
: POSTPONE ( "<spaces>name" -- )
  ALSO TC-TRG
  ?COMP
  PARSE-NAME SFIND DUP
  0= IF -321 THROW THEN
  1 = IF COMPILE,
      ELSE LIT, S" COMPILE," TC-FINDOUT COMPILE, THEN
  PREVIOUS
; IMMEDIATE

: [COMPILE] ( "<spaces>name" -- )
  ALSO TC-TRG ' PREVIOUS
  COMPILE,
; IMMEDIATE
```

兩個字都在搜尋目標詞彙表（`ALSO TC-TRG`），確保找到的是目標系統的定義。POSTPONE 的邏輯與宿主版本相同：
- 立即字（旗標 1）：`COMPILE,` 直接編譯 XT
- 非立即字（旗標 -1）：`LIT,` 編譯 XT + `COMPILE,` 編譯編譯行為

### 7.10 TO 的目標版

```forth
\ tc_spf.F:594
: TO ALSO TC-TRG [COMPILE] TO PREVIOUS ; IMMEDIATE
```

透過 `[COMPILE] TO` 來強制編譯目標系統的 `TO`（即使 `TO` 是立即字）。

### 7.11 (TO)：內部 TO 實作

```forth
\ tc_spf.F:492-497
: (TO)
  ALSO TC-TRG '
  9 + STATE @
  IF COMPILE, ELSE  EXECUTE  THEN
  PREVIOUS
; IMMEDIATE
```

`(TO)` 是 `TO` 的底層實作，與宿主系統的 `TO` 完全對稱（跳過 CFL + CELL = 9 bytes 到達 TOVALUE-CODE）。

### 7.12 TC-VECT! 與 TC-ADDR!

```forth
\ tc_spf.F:499-507
: TC-VECT! ( xt xt-vect -- )
  >R >VIRT R>
  9 +
  EXECUTE
;

: TC-ADDR! ( addr xt-variable -- )
  >R >VIRT R>
  EXECUTE  !
;
```

`TC-VECT!` 用於設定目標系統中向量的執行碼。流程：
1. `>VIRT`：將 XT 轉換為目標位址
2. `9 +`：跳到 CFL + CELL 處（TOVALUE-CODE 的位置）
3. `EXECUTE`：執行 TOVALUE-CODE（通常會修改向量值）

`TC-ADDR!` 用於設定目標系統中的變數值。流程：
1. `>VIRT`：將位址轉換為目標位址
2. `EXECUTE !`：執行變數位址然後儲存值

---

## 8. 結構欄位定義（`--` 字）

### 8.1 -- 的實作

```forth
\ tc_spf.F:418-425
: -- ( u.field-offset u.field-size "field-name" -- u.next-field-offset )
  OVER >R +
  [T] HEADER [I]
  OPT_INIT
  SetOP  05 C, R> , OPT    \ ADD EAX, #xxx
  OPT_CLOSE
  RET,
;
```

`--` 用於定義結構體的欄位存取字，每個存取字只是一條 `ADD EAX, #offset; RET` 指令。

堆疊追蹤：

```forth
假設 EXEC-STRUCT 0 初始偏移，CELL 大小欄位：

0 CELL -- EXEC-PC    ← 編譯 ADD EAX, #0; RET
CELL CELL -- EXEC-SP ← 編譯 ADD EAX, #4; RET
CEL... CELL -- EXEC-RP← 編譯 ADD EAX, #8; RET
```

每個欄位存取字執行時只需 2 條指令（ADD + RET），這是 Forth 結構體存取的典型最佳化。

---

## 9. 動態連結表（tc-dl.f, tc-dl-tc.f, tc-dl-imm.f）深入解析

### 9.1 符號表結構

```forth
\ tc-dl.f:30
2 CELLS CONSTANT dl-rec#
```

每個符號記錄佔 2 個儲存格（8 bytes）：

```forth
  ┌────────────────────────┐
  │ +0 cell: 名稱偏移      │ ← strtab 中的偏移（負值表示程式庫名稱）
  │ +4 cell: 函數位址      │ ← 0 = 尚未解析
  └────────────────────────┘
```

名稱偏移使用正/負值區分符號類型：
- **正值**：普通符號名稱（函數名）
- **負值**：程式庫名稱（用於 `dlopen`）

### 9.2 兩級符號表

```forth
\ tc-dl.f:32-37
0 VALUE dl-first          \ 預載入符號表（啟動時填充）
0 VALUE dl-first#         \ 預載入符號數量
0 VALUE dl-first-strtab   \ 預載入字串表
0 VALUE dl-second         \ 執行期符號表（動態新增）
0 VALUE dl-second#        \ 執行期符號數量
0 VALUE dl-second-strtab  \ 執行期字串表
```

預載入表（dl-first）記錄系統啟動時就需要的符號（如 C 標準庫函數），執行期表（dl-second）記錄執行過程中動態載入的符號。

### 9.3 name-lookup 與 symbol-lookup

```forth
\ tc-dl.f:65-79
: name-lookup ( a # library? -- sym# )
  UNROT
  2DUP
  dl-second-strtab dl-second dl-second# table-lookup IF
    dl-first# + NIP NIP NIP EXIT
  THEN
  table-enter
;

: symbol-lookup ( a # -- sym# )
  FALSE name-lookup
;
```

`name-lookup` 的流程：
1. 先在 `dl-second` 表中搜尋（透過 `table-lookup`）
2. 若找到，加上 `dl-first#` 偏移量（因為符號編號是全域的）
3. 若未找到，透過 `table-enter` 新增到 `dl-second` 表

`symbol-lookup` 是 `name-lookup` 的簡便介面，`library?` 參數設為 `FALSE`（表示非程式庫名稱）。

### 9.4 table-lookup 與 table-enter

```forth
\ tc-dl.f:43-63
: table-lookup ( a # strtab symtab symtab# -- sym# T / F)
  0 ?DO
    2OVER 2OVER
    I dl-rec# * + @ + szcompare IF
      2DROP 2DROP I TRUE UNLOOP EXIT
    THEN
  LOOP
  2DROP 2DROP FALSE
;

: table-enter ( library? a # -- sym# )
  dl-second-strtab enter-into-strtab SWAP IF NEGATE THEN
  dl-second dl-second# dl-rec# * + DUP 2 CELLS ERASE !
  dl-second# DUP 1+ TO dl-second# dl-first# +
;
```

`table-lookup` 使用線性搜尋逐一比較符號名稱。`szcompare` 比較計數字串與 ASCIIZ 字串。若找到則回傳符號編號和 `TRUE`，否則回傳 `FALSE`。

`table-enter` 將新符號加入 `dl-second` 表的末尾，並在字串表中分配空間。若 `library?` 為 `TRUE`，名稱偏移取反值以標記為程式庫名稱。

### 9.5 enter-into-strtab：字串表管理

```forth
\ tc-dl.f:11-21
: enter-into-strtab ( a n strtab -- n )
  >R
  R@ @ 1000 MOD 0= IF
    ABORT" 超過 1000 字串上限或錯誤"
  THEN
  R@ @ 2DUP + 1+ R@ !
  DUP R> + SWAP >R CZMOVE
  R>
;
```

字串表使用連續記憶體，每次新增字串時遞增偏移。`CZMOVE`（第 7 行定義）拷貝字串並在末尾添加零位元組（ASCIIZ 格式）。

### 9.6 tc-dl-tc.f：USE 命令

```forth
\ tc-dl-tc.f:1-3
: USE ( "name" -- )
  PARSE-NAME TRUE name-lookup DROP
;
```

`USE` 在交叉編譯時將外部模組名稱加入符號表，但不實際載入模組。`library? = TRUE` 表示這是程式庫名稱（偏移取反值）。

**設計說明：為何需要 tc-dl-tc.f？**

`tc-dl-tc.f`（僅 73 位元組）是 `tc-dl.f` 與 `tc-dl-imm.f` 之間的**橋接層**（bridge layer）。由於 `USE` 命令在交叉編譯期（target compile time）與執行期的語法相同但實作不同，這裡存在一個載入順序的雞生蛋問題：

1. **載入階段問題**：當 `tc_spf.F` 正在載入時，它會設定交叉編譯環境，此時 `tc-dl.f` 中的 `name-lookup` 已經可用，但 `tc-dl-imm.f` 的立即字語法尚未完全設定。

2. **簡化依賴**：`tc-dl-tc.f` 提供了一個最小化的 stub，讓 `tc_spf.F` 在載入過程中不會因未定義 `USE` 而失敗。實際的 `USE` 語法解析（`"library" USE`）由宿主系統（`spf4orig`）提供，而交叉編譯期的目標符號表記錄則由這個簡化版完成。

3. **與執行期的對稱**：這個設計讓 `src/spf.f` 的載入流程可以統一使用 `USE` 語法，無論是在宿主環境還是交叉編譯環境，實際行為由當時載入的上下文決定。

```forth
載入流程中的 USE 實作：
├── 宿主系統（spf4orig）：執行期動態連結
├── tc-dl-tc.f（交叉編譯期）：僅記錄程式庫名稱到符號表
└── tc-dl-imm.f（目標立即字）：編譯目標碼時的外部呼叫
```

### 9.7 tc-dl-imm.f：)) 和 (()) 立即字

```forth
\ tc-dl-imm.f:1-15
: )) ( "name" -- )
  PARSE-NAME symbol-lookup
  STATE @ IF
   ()))-adr COMPILE,
   TC-LIT,
   (__ret2) @ IF
     symbol-call2-adr COMPILE,
   ELSE
     symbol-call-adr COMPILE,
   THEN
   (__ret2) 0!
  THEN ; IMMEDIATE

: (()) ( "name" -- )
  PARSE-NAME symbol-lookup
  STATE @ IF
   0 TC-LIT, TC-LIT,
   (__ret2) @ IF
      symbol-call2-adr COMPILE,
    ELSE
      symbol-call-adr COMPILE,
    THEN
    (__ret2) 0!
  THEN ; IMMEDIATE

: __ret2 ( -- ) TRUE (__ret2) ! ; IMMEDIATE
```

`))` 是立即字；它在編譯期執行，用來解析符號並**產生 target 執行期的外部函式呼叫序列**（不是在編譯期直接呼叫該 C 函式）。編譯結果為：

```asm
CALL ())_handler    ; (__ret2)-adr: 設定呼叫引數數量
MOV EAX, #n         ; TC-LIT, : 符號編號
CALL symbol-call     ; 或 symbol-call2: 執行呼叫
```

`(())` 用於編譯無引數的外部 C 函式呼叫（0 引數，字名是 `(())`，見 `src/tc-dl-imm.f:17`），編譯結果為：

```asm
MOV EAX, #0          ; 第1個引數：0（無引數）
MOV EAX, #n          ; 第2個引數：符號編號
CALL symbol-call     ; 執行呼叫
```

`__ret2` 旗標控制是否使用 64 位元回傳值的呼叫慣例（`symbol-call2-adr`）。

---

## 10. WINAPI 介面（Windows 版）

### 10.1 WINAPI: 命令

```forth
\ tc_spf.F:435-448
: WINAPI: ( "DLL-name" "function-name" -- )  \ Windows 版
  >IN @ [T] HEADER [I]  >IN !
  WINAPI-CODE COMPILE,
  HERE >R
  0 , \ address of winproc
  0 , \ address of library name
  0 , \ address of function name
  -1 , \ # of parameters
  HERE TC-WINAPLINK @ , TC-WINAPLINK ! ( 鍊結)
  HERE DUP R@ CELL+ CELL+ !
  PARSE-NAME HERE SWAP DUP ALLOT MOVE 0 C, \ 函數名稱
  HERE DUP R> CELL+ !
  PARSE-NAME HERE SWAP DUP ALLOT MOVE 0 C, \ DLL名稱
  LoadLibraryA DUP 0= ABORT" Library not found"
  GetProcAddress 0= ABORT" Procedure not found"
;
```

WINAPI: 的 Win32 動態連結介面僅在 Windows 版本中編譯（`TARGET-POSIX [IF]` ... `[ELSE]` 區塊中）。它建立一個目標系統定義，其字典結構包含：

```forth
  ┌──────────────────┐ ← xt
  │ WINAPI-CODE CALL │ ← CFL（5 bytes）
  ├──────────────────┤
  │ winproc 位址     │ ← PFA+0：執行期由 GetProcAddress 填入
  │ DLL名稱位址      │ ← PFA+4（library name，tc_spf.F:444-447 寫到 R> CELL+）
  │ 函數名稱位址     │ ← PFA+8（function name，寫到 R@ CELL+ CELL+）
  │ 參數數量 (-1)    │ ← PFA+12：-1 表示 stdcall
  ├──────────────────┤ ← 鍊結
  │ 下一個 WINAPI    │ ← 鍊結指標
  ├──────────────────┤
  │ 函數名稱 ASCIIZ │ ← 函數名稱字串
  │ DLL名稱 ASCIIZ  │ ← DLL名稱字串
  └──────────────────┘
```

### 10.2 PROCESSPROC: 與 TC-CALLBACK:

```forth
\ tc_spf.F:462-488
TARGET-POSIX [IF]
: PROCESSPROC: ( xt "name" -- )
  HERE
  2 CELLS LIT,                     \ POSIX: 2 cells 參數
  TC-FORTH-INSTANCE> COMPILE,
  SWAP COMPILE,
  RET,
  [T] HEADER [I]
  WNDPROC-CODE COMPILE,
  >VIRT ,
;
[ELSE]
: PROCESSPROC: ( xt "name" -- )
  HERE
  0 CELLS LIT,                     \ Windows: 0 cells 參數
  TC-FORTH-INSTANCE> COMPILE,
  SWAP COMPILE,
  RET,
  [T] HEADER [I]
  WNDPROC-CODE COMPILE,
  >VIRT ,
;
[THEN]
```

PROCESSPROC: 建立一個可作為程序入口點的包裝函式。POSIX 版本有 2 個 cell 的參數空間（用於 argc/argv），Windows 版本有 0 個 cell。

`TC-CALLBACK:`（第 478~488 行）建立 Windows 回呼函式包裝，包含 `TC-FORTH-INSTANCE>` 和 `TC-<FORTH-INSTANCE` 的配對呼叫，用於切換執行緒環境。

---

## 11. 編譯器修補與最終設定

### 11.1 編譯器替換

```forth
\ tc_spf.F:794-798
ONLY FORTH DEFINITIONS ALSO TC

' TC-?SLITERAL TO ?SLITERAL
0xE9 ' COMPILE, C!
'MCOMPILE, ' COMPILE, 1+ CELL+ - ' COMPILE, 1+ !
```

這三行是交叉編譯器最關鍵的修補操作：

1. **`' TC-?SLITERAL TO ?SLITERAL`**：將直譯器的數字解析替換為目標版本。此後 INTERPRET 迴圈中的 `?SLITERAL` 會呼叫 `TC-?SLITERAL`，使得所有數字都被編譯到目標映像中。

2. **`0xE9 ' COMPILE, C!`**：將 `COMPILE,` 的第一個位元組改為 `0xE9`（JMP 指令的 opcode）。這使得對 `COMPILE,` 的呼叫直接跳到新的實作。

3. **`' MCOMPILE, ' COMPILE, 1+ CELL+ - ' COMPILE, 1+ !`**：在 `COMPILE,` 的跳轉目標寫入 `MCOMPILE,` 的相對偏移量，使得 JMP 指令跳到 `MCOMPILE,`。

**為何需要修補？**

在交叉編譯完成後，宿主系統的 INTERPRET 迴圈仍然使用 `COMPILE,` 和 `?SLITERAL`。但這些字現在需要產生目標系統的代碼，而非宿主系統的代碼。修補操作使得這些字指向目標版本。

### 11.2 IMAGE-START 設定

```forth
\ tc_spf.F:791
IMAGE-START virtual-address
```

`virtual-address`（第 20 行）會把 `virt-offset` 設成 `va - HERE`；套到這裡就是 `IMAGE-START - HERE`。POSIX 版稍後也會由 `forth.ld` 把 `.forth` 段連到同一個 `0x8050000`，所以這裡的基址設定會一路延續到最終 ELF 佈局。

### 11.3 記憶體對齊

```forth
\ tc_spf.F:788
HERE 10000 + 10000 / 10000 * 2000 + DP !
```

這行將字典指標向上對齊到下一個 10000 的倍數，再加上 2000 bytes 的安全邊際。這確保目標映像有足夠的空閒字典空間供執行期使用。

### 11.4 TC-LATEST->：更新最新字詞指標

```forth
\ tc_spf.F:509-511
: TC-LATEST-> ( "<spaces>name.constant.wordlist" -- )
  ALSO TC-TRG ORDER-TOP ( wid.tail )  '  PREVIOUS  EXECUTE  CHAIN-WORDLIST
;
```

`TC-LATEST->` 用於將一個詞彙表的最新定義鍊結到另一個詞彙表。這在模組系統（MODULE: / EXPORT / ;MODULE）中用於匯出定義。

### 11.5 SYNONYM 的目標版本

```forth
\ tc_spf.F:513-520
: SYNONYM ( "<spaces>name.new" "<spaces>name.old" -- )
  [T]
  PARSE-NAME 2>R
  PARSE-NAME SFIND DUP 0= -13 AND THROW  1 =  ( xt flag.imm )
  2R> SHEADER  IF IMMEDIATE THEN
  LATEST-NAME NAME>C !
  [I]
;
```

與宿主版本對比，目標版本的 SYNONYM 使用 `[T]/[I]` 切換詞彙表，並確保新名稱建立在目標字典中。

---

## 12. noopt.f：最小最佳化器

> noopt.f 在最佳化器架構中的角色（與 macroopt.f 的對照），另見 [07-optimizer.md §2](07-optimizer.md#2-nooptf--最小最佳化器)；本章聚焦於其在交叉編譯流程中的使用脈絡。

### 12.1 什麼是 noopt.f？

`noopt.f` 是巨集最佳化器（macroopt.f）的最小替代實作。當系統不使用最佳化器時（`BUILD-OPTIMIZER [IF]` 為 false），載入 noopt.f 提供最佳化器介面的空操作實作。

### 12.2 關鍵定義

```forth
\ noopt.f:10-36
FALSE VALUE OPT?                \ 最佳化器永遠不啟用
084 VALUE J_COD                 \ JZ 條件碼（預設值）
0 VALUE MM_SIZE                 \ 巨集匹配大小 = 0
0 VALUE :-SET                   \ 最佳化點起始位址
0 VALUE J-SET                   \ 跳躍點位址
0 VALUE LAST-HERE               \ 上次編譯位址
0x4 CELLS DUP CONSTANT OpBuffSize  \ 最佳化緩衝區大小 = 16 bytes
CREATE OP0 HERE >T  , 0 ,  ALLOT  \ 最佳化緩衝區

: SetOP ; IMMEDIATE              \ 空操作
: ClearJpBuff ; IMMEDIATE       \ 空操作
: SetJP ; IMMEDIATE              \ 空操作
: ?SET ; IMMEDIATE               \ 空操作
FALSE VALUE ?C-JMP               \ 條件跳躍最佳化 = false
0 CONSTANT INLINE?               \ 永遠回傳 0（不可內聯）
: OPT_CLOSE ; IMMEDIATE          \ 空操作
: OPT_INIT ; IMMEDIATE           \ 空操作
TRUE CONSTANT CON>LIT            \ 固定回傳 TRUE = 「未處理」，不做常數摺疊

: INLINE, ( cfa -- )
  BEGIN COUNT DUP C3 <>
  WHILE C,
  REPEAT 2DROP ;
```

**關鍵設計決策**：

- `OPT?` = FALSE：最佳化器永不啟用
- `INLINE?` = 0：所有字都不可內聯
- `CON>LIT` = TRUE：依 `MCOMPILE,` 的語意，固定回傳 TRUE 代表「`CON>LIT` 未處理、繼續走一般編譯」——也就是 **不做** 常數摺疊。這是介面 stub，不是最佳化功能
- `INLINE,`：唯一的非空操作——它拷貝機器碼直到遇到 RET（0xC3）

### 12.3 ???BR-OPT：最佳化前的條件碼設定

```forth
\ noopt.f:30-32
: ???BR-OPT
  C00B W,          \ OR EAX, EAX
  'DROP INLINE,
;
```

`???BR-OPT` 在條件跳躍前插入 `OR EAX, EAX`（測試 TOS 是否為零）和 `DROP`（丟棄 TOS）。這是 `?BRANCH,` 的前導代碼——無論最佳化器是否啟用，條件跳躍都需要先測試 TOS。

### 12.4 與 macroopt.f 的對比

macroopt.f（5548 行）提供完整最佳化，包括：
- 常數摺疊（CON>LIT）
- 指令合成（如 `OVER +` → `ADD [EBP], EAX; MOV EAX, [EBP+4]`）
- 內聯展開決策（INLINE? 判斷字是否短到值得內聯）
- 條件分支最佳化（短跳躍/近跳躍選擇）
- 跳躍最佳化（J_COD 可變條件碼）

noopt.f 保留相同的字詞介面與基本的 `INLINE,` 複製機制，但 `CON>LIT` 是固定回傳 TRUE 的占位實作（不做常數摺疊）、`INLINE?` 固定為 0（不做內聯判斷），確保編譯器在無最佳化模式下仍能正常工作。

---

## 13. ELF 儲存（xsave.f）

> 關於 XSAVE 的 ELF 段表填寫與 gcc 連結命令細節，另見 [06-build-save.md §8](06-build-save.md#8-xsave--交叉編譯-elf-儲存xsavef)；本章聚焦於交叉編譯流程中的重定位與儲存步驟。

### 13.1 XSAVE 流程

```forth
\ xsave.f:84-105
: XSAVE ( c-addr u -- )
  R/W CREATE-FILE THROW TO h
  elf-header header-size >elf

  reloc-sections-offsets

  reloc-wordlists-all     \ 重新定位所有詞彙表
  reloc-voclist           \ 重新定位詞彙表鍊結

  sections total-sections-size >elf
  segments total-segments-size >elf
  .shstrtab .shstrtab# >elf
  .strtab .strtab# >elf
  .symtab .symtab# >elf
  .rel.forth .rel.forth# >elf
  .forth .forth# >elf
  dl-second .dltable# >elf
  dl-second-strtab .dlstrings# >elf
  h CLOSE-FILE THROW
  BYE
;
```

XSAVE 的輸出結構：

| 段 | 說明 |
|----|------|
| ELF header | 檔案格式標頭（52 bytes） |
| Sections | 段表（描述各段屬性） |
| Segments | 段表（描述載入屬性） |
| `.shstrtab` | 段名稱字串表 |
| `.strtab` | 符號名稱字串表 |
| `.symtab` | 符號表 |
| `.rel.forth` | Forth 段的重定位資訊 |
| `.forth` | Forth 字典與程式碼段 |
| `.dltable` | 動態連結符號表 |
| `.dlstrings` | 動態連結字串表 |

### 13.2 重定位處理

```forth
\ xsave.f:49-69
: reloc-wordlist-chain ( wl-last -- )
  BEGIN ?DUP WHILE
    DUP NAME>C >VIRT!
    DUP NAME>NEXT-NAME SWAP
    NAME>L ?VIRT!
  REPEAT
;

: reloc-wordlist ( wid -- )
  DUP @ reloc-wordlist-chain
  DUP       ?VIRT! \ words chain
  DUP CELL+ ?VIRT! \ wordlist's name
  DUP 2 CELLS + ?VIRT! \ parent
  DUP 3 CELLS + ?VIRT! \ class
  DROP
;

: reloc-wordlists-all ( -- )
  ['] reloc-wordlist ENUM-VOCS
;

: reloc-voclist ( -- )
  VOC-LIST @
  BEGIN DUP WHILE
    DUP @ SWAP ?VIRT!
  REPEAT DROP
;
```

重定位（relocation）是 POSIX 版本儲存的關鍵步驟。由於目標映像在宿主系統記憶體中的位址與最終執行位址不同（透過 `virt-offset` 校正），所有指標都需要透過 `>VIRT!` 轉換為虛擬位址：

- **詞彙表鍊結**：每個詞彙表的雜湊鍊頭、名稱指標、父詞彙表、類別指標
- **字頭結構**：CFA（程式碼欄位位址）、LFA（鍊結欄位位址）
- **VOC-LIST**：詞彙表清單的鍊結指標

`?VIRT!`（第 38~40 行）的定義：

```forth
: ?VIRT! ( addr -- )
  DUP @ 0= IF DROP EXIT THEN >VIRT!
;
```

它只轉換非零值——零表示「尚未設定」或「空指標」，不需要轉換。

---

## 14. tc-configure-lines.f：行尾設定

```forth
\ tc-configure-lines.f:1-5
SOURCE + 1 CHARS - C@ 0xA = CHAR | AND PARSE | UNIX-LINES
2DROP
```

這個小檔案的作用是檢查原始碼的最後一個字元是否為 LF（0xA），如果是則執行 `UNIX-LINES` 設定行尾格式。這確保了交叉編譯器在不同行尾格式的原始碼中正確運作。

---

## 15. 特殊字：... 和 ..:

```forth
\ tc_spf.F:778-780
: ... 0 TC-BRANCH, >MARK DUP >VIRT , 1 >RESOLVE ; IMMEDIATE
: ..: '  >BODY DUP @  1 >RESOLVE ] ;
: ;..  DUP CELL+ TC-BRANCH, >MARK SWAP ! [COMPILE] [ ; IMMEDIATE
```

這三個字實作了一種類似 C 語言的 switch/case 結構：

- `...`：定義一個跳轉表項（無條件跳轉到 ..: 指定的位置）
- `..:`：定義一個 case 處理程式
- `;..`：結束 case 處理程式

堆疊追蹤：

```forth
: DISPATCH ...        
         ↓ 產生 JMP to ???, 並將位址留在堆疊上
  ..: CASE1 ;..
  ..: CASE2 ;..
         ↓ 每個 ..: 回填前一個 JMP 並建立新的 JMP
```

---

## 16. 編譯器整體流程圖

### 16.1 交叉編譯的初始化流程

```forth
載入 tc_spf.F
  │
  ├─ 宣告 virt-offset / >VIRT / VIRT>（尚未套用 IMAGE-START）
  ├─ 載入 tc-dl.f（POSIX 版動態連結）
  ├─ 設定 TC-TRG, TC, TC-IMM 詞彙表
  ├─ 載入 macroopt.f 或 noopt.f（最佳化器選擇）
  ├─ 定義 TC-CALL,, TC-LIT,, TC-?BRANCH,, ...
  ├─ 定義所有定義字（: CREATE VARIABLE CONSTANT ...）
  ├─ 定義所有立即字（IF THEN ELSE DO LOOP ...）
  ├─ 載入 tc-dl-imm.f（POSIX 版動態連結立即字）
  ├─ 對齊字典指標
  ├─ 設定 IMAGE-START virtual-address
  ├─ 修補 COMPILE, → MCOMPILE,
  ├─ 修補 ?SLITERAL → TC-?SLITERAL
  └─ 記錄 TC-IMAGE-BASE
```

### 16.2 定義字的三層夾擊模式

```forth
所有定義字遵循 [T] ... [I] 夾擊模式：
  ┌──────────────────────────────┐
  │  [T] 切換到目標詞彙表     │
  │  建立字頭（HEADER 等）     │
  │  [I] 切換回宿主詞彙表     │
  │  編譯執行碼（COMPILE, 等） │
  │  編譯參數（, 等）          │
  └──────────────────────────────┘
```

### 16.3 編譯完成後的修補

```forth
COMPILE, 字頭 → JMP MCOMPILE,
                       │
                       ├─ CON>LIT → 常數摺疊
                       ├─ INLINE? → 內聯展開
                       └─ TC-CALL, → 產生 CALL 指令

?SLITERAL → TC-?SLITERAL → 目標數字解析
```

### 16.4 目標映像的儲存流程

```forth
目標映像（記憶體中）
  │
  ├─ reloc-wordlists-all（重定位詞彙表）
  ├─ reloc-voclist（重定位詞彙表鍊結）
  │
  ├─ POSIX: XSAVE → ELF .o 檔案 → gcc 連結
  └─ Windows: PE 格式儲存
```

---

## 17. 技術總結

### 17.1 SP-Forth 交叉編譯器的核心設計特點

1. **雙位址空間管理**：`>VIRT`/`VIRT>` 在 POSIX 版本中處理宿主/目標位址轉換，在 Windows 版本中為恆等操作。這種抽象化使得同一套編譯邏輯可以在兩種平台上運作。

2. **三重詞彙表架構**：TC-IMM（立即字）、TC-TRG（目標定義）、TC（定義字）三層詞彙表確保了編譯期的名稱解析正確性。搜尋順序保證立即字優先於目標定義，目標定義優先於定義工具，定義工具優先於宿主系統。

3. **[T]/[I] 夾擊模式**：所有定義字都使用 `[T] ... [I]` 模式在目標和宿主詞彙表之間切換，確保字頭建立在目標字典而執行碼使用宿主系統的功能。

4. **COMPILE, 修補**：交叉編譯完成後，宿主系統的 `COMPILE,` 被 `JMP MCOMPILE,` 覆蓋，使得 INTERPRET 迴圈從此產生目標代碼。這是 Forth 自舉的最巧妙的一步。

5. **TC-FINDOUT + INLINE, 模式**：目標系統的原語透過 `S" name" TC-FINDOUT INLINE,` 內聯到目標映像中。這確保了目標系統的機器碼與宿主系統的原語一致。

6. ***DP@ 的虛擬位址感知**：迴圈結構（DO/LOOP/LEAVE）中回填 LEAVE 目標位址時使用 `*DP@`（= `DP @ >VIRT`），確保 POSIX 版本的位址在儲存時就是虛擬位址。

7. **THROW 的雙路徑最佳化**：在交叉編譯器中，THROW 偵測 TOS 是否為常值（`OP0 @ C@ 0xB8 =`），若是則產生無條件跳躍（JMP），否則產生條件跳躍（OR + JNZ）。這是最佳化器與編譯器緊密合作的一個典型案例。

8. **ELF 重定位**：POSIX 版本透過 `reloc-wordlists-all` 和 `reloc-voclist` 將所有內部指標轉換為虛擬位址，產生 ELF 可重定位物件檔案，最終由 gcc 連結為可執行檔。
