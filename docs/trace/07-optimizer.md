# SP-Forth/4 原始碼追蹤 — 巨集最佳化器

> 本章目標：理解最佳化器如何透過 OP 緩衝區追蹤已發出的機器碼，把 `CALL CONSTANT` 摺疊成 `MOV EAX, #值`。
> 
> 對應原始碼：`macroopt.f`、`noopt.f`、`macroopt-hide.f`（部分）

---

## 1. 概述

SP-Forth 的**巨集最佳化器**（Macro Optimizer），又稱**窺孔最佳化器**（Peephole Optimizer），是系統最大的單一原始碼檔案（5548 行），實作了編譯期機器碼層級的最佳化。

最佳化器在交叉編譯過程中運作，對已產生的 x86 機器碼進行後處理，識別並替換可最佳化的指令序列。它利用 SP-Forth 的 TOS-in-EAX 暫存器模型，追蹤 EAX 和 EBP 的偏移狀態，消除冗餘的暫存器移動和堆疊操作。

若你是第一次讀 SP-Forth 的追蹤文件，建議先讀完 [01-kernel.md](01-kernel.md)、[02-compiler.md](02-compiler.md) 與 [03-cross-compiler.md](03-cross-compiler.md) 再回來。這份文件預設你已經知道：

- TOS-in-EAX / EBP 資料堆疊模型
- `COMPILE,` / `MCOMPILE,` 在宿主編譯器中的角色
- target machine code 是如何由 `TC-CALL,` / `MCOMPILE,` 產生
- `[>T]`、`FORLIT,`、`_INLINE,` 這些編譯期輔助字在 target 生成流程中的角色

也因此，`07` 應視為**進階選讀**，而不是整套文件的入口。

### 1.1 架構模型

```forth
編譯期產生的機器碼
       │
       ├── OPT_INIT → 記錄最佳化起始點
       │
       ├── 編譯指令（COMPILE, LITERAL, 等）
       │     └── 每條指令後可能呼叫 DO_OPT
       │           └── OPT_ → OPT-RULES 迴圈
       │                 └── 識別最佳化機會 → 替換指令序列
       │
       ├── OPT_CLOSE → 更新偏移、對齊
       │
       └── ??BR-OPT → 條件跳躍最佳化
             └── 決定使用短跳（2 位元組）或長跳（6 位元組）
```

### 1.2 看一個具體例子：CONSTANT 如何被摺疊

假設原始碼中定義並使用一個常數：

```forth
314159 CONSTANT PI    \ 定義常數
PI DUP *              \ 使用 PI 兩次
```

未經最佳化時，`PI` 會被編譯為一條 `CALL PI_XT`（5 bytes），執行時跑到 `_CONSTANT-CODE` 讀取 PFA 中的數值。最佳化器介入後，`COMPILE,` 內部的 `CON>LIT` 會識別出這是一個 CONSTANT，直接將它替換為：

```asm
MOV EAX, #314159      ; 5 bytes：直接把常數值載入 TOS
```

**省去了** CALL → JMP → MOV EAX,[EAX] 的整段執行期路徑。

再進一步，後續的 `DUP *` 編譯後，最佳化器又會嘗試把連續的 `MOV EAX,#n` + 堆疊操作合併成更短的序列。這是最佳化器「常數傳播 + 指令合成」的典型流程：

| 階段 | 產生的機器碼 | 長度 |
|------|-------------|------|
| 無最佳化 | `CALL PI_XT` `CALL DUP_XT` `CALL MULT_XT` | 15+ bytes |
| CON>LIT 摺疊 PI | `MOV EAX,#314159` `CALL DUP_XT` `CALL MULT_XT` | 13 bytes |
| 進一步內聯 | `MOV EAX,#314159` `LEA EBP,-4[EBP]` `MOV[EBP],EAX` `MUL[EBP]` `LEA EBP,4[EBP]` | ~20 bytes（但無 CALL/RET 開銷）|

所有這些替換都在編譯期完成，對執行期完全透明。

### 1.3 啟用/停用

```forth
: SET-OPT TRUE TO OPT? ;     \ 啟用最佳化
: DIS-OPT FALSE TO OPT? ;    \ 停用最佳化
```

`OPT?` 是控制最佳化器是否運作的開關。在 `SMALLEST-SPF` 模式下，`BUILD-OPTIMIZER` 會被設成 `FALSE`，因此 `spf.f` 會改載入 `noopt.f`；這時**目標映像**裡的 `OPT?` 初值也是 `FALSE`，除非後續明確執行 `SET-OPT`。另一方面，宿主編譯器 `spf4orig` 仍可能以自己的最佳化器來參與建構流程，所以 `USE-OPTIMIZER = TRUE` 不等於目標映像中的最佳化器已經啟用。

### 1.4 輔助規則檔（macroopt-hide.f）

`macroopt-hide.f`（3919 位元組，182 行）**不是**最佳化規則檔。`OPT-RULES` 本體在 `macroopt.f`（`src/macroopt.f:2681-4575`）；`macroopt-hide.f` 是由 `macroopt.f:5` 載入的**支援檔**，負責把 macroopt 的內部字搬移到/隱藏在 `MACROOPT-WL` 詞彙表，並匯出必要的 public API。

**主要內容**（`src/macroopt-hide.f:97-170`）：
- `INIT-MACROOPT-HIDING`：建立並設定 `MACROOPT-WL`
- `EXPORT-NAME`：把指定字匯出到外部可見的詞彙表
- `HIDE-MACROOPT-WORDS`：把 macroopt 內部字隱藏起來，避免污染使用者命名空間

**與 macroopt.f 的關係**：
```forth
macroopt.f（最佳化器本體）
    ├── OPT-RULES（L2681-4575）、CON>LIT、_INLINE, 等實際最佳化邏輯
    └── 第 5 行 INCLUDED macroopt-hide.f
        └── 隱藏內部字 / 匯出 public API（不含最佳化規則）
```

換言之，分離出 `macroopt-hide.f` 的目的是**命名空間管理**（隱藏與匯出），不是把最佳化規則放在那裡。

---

## 2. noopt.f — 最小最佳化器

當 `BUILD-OPTIMIZER` 為 FALSE 時，載入 `noopt.f`（44 行），提供最佳化器的最小子集：

```forth
FALSE VALUE OPT?                   \ 最佳化器停用
084 VALUE J_COD                    \ 跳躍碼（短跳字首）
0 VALUE MM_SIZE                    \ 記憶體管理區塊大小 = 0
0 VALUE :-SET                      \ 最佳化邊界 = 0
0 VALUE J-SET                      \ 跳躍邊界 = 0
0 VALUE LAST-HERE                  \ 上次最佳化位址 = 0
0x4 CELLS DUP CONSTANT OpBuffSize  \ 操作緩衝區大小 = 16 位元組（最小）
CREATE OP0 HERE >T , 0 , ALLOT     \ 操作緩衝區（僅 1 個插槽）
: SetOP ; IMMEDIATE                \ 空操作
: ClearJpBuff ; IMMEDIATE          \ 空操作
: SetJP ; IMMEDIATE                \ 空操作
: ?SET ; IMMEDIATE                 \ 空操作
FALSE VALUE ?C-JMP                 \ 條件跳躍最佳化停用
0 CONSTANT INLINE?                 \ 內聯停用（回傳 0 = FALSE）
: OPT_CLOSE ; IMMEDIATE            \ 空操作
: OPT_INIT ; IMMEDIATE             \ 空操作
: OPT ; IMMEDIATE                  \ 空操作
TRUE CONSTANT CON>LIT               \ no-op stub：固定回傳「未處理」，不做常數傳播/摺疊
FALSE VALUE J_OPT?                  \ 跳躍最佳化停用
: RESOLVE_OPT DROP ;               \ 跳躍解析停用
: INIT-MACROOPT-LIGHT ;           \ 空操作
: MACRO, INLINE, ;                 \ 內聯直接複製機器碼
: SET-OPT TRUE TO OPT? ;
: DIS-OPT FALSE TO OPT? ;
```

noopt.f 只保留最基本的字詞介面，所有最佳化功能都為空操作。`MACRO,` 和 `INLINE,` 直接複製機器碼（透過 `INLINE,`），不做任何最佳化替換。

`INIT-MACROOPT-LIGHT` 在 noopt.f 中為空操作，在 macroopt.f 中設定 `J_COD` 和 `~BR-OPT`。

---

## 3. 操作緩衝區（OP Buffer）

### 3.1 定義

```forth
0x44 CELLS DUP CONSTANT OpBuffSize    \ 68 個 CELL（272 位元組）

USER-CREATE OP0 2 CELLS + [DEFINED] TC [IF] TC-USER-ALLOT [ELSE] USER-ALLOT [THEN]
0
CELL+ DUP : OP1 OP0 LITERAL + ;
CELL+ DUP : OP2 OP0 LITERAL + ;
CELL+ DUP : OP3 OP0 LITERAL + ;
CELL+ DUP : OP4 OP0 LITERAL + ;
CELL+ DUP : OP5 OP0 LITERAL + ;
CELL+ DUP : OP6 OP0 LITERAL + ;
CELL+ DUP : OP7 OP0 LITERAL + ;
CELL+ DUP : OP8 OP0 LITERAL + ;
          : OPLast OP0 OpBuffSize + CELL- ;
DROP
```

操作緩衝區（OP Buffer）是一個**以 cell 為單位的位址滑動陣列**，記錄最近編譯的機器碼指令的起點位址。`OP1`..`OP8` 從 `OP0` 每次 `CELL+`（`src/macroopt.f:48-57`），也就是每格一個 cell；`SetOP`（`src/macroopt.f:61-64`）用 `OP0 OP1 ... CMOVE>` 把整列往後滑一個 cell。**每格只是一個位址，不是「DP 位址 + 0」的兩-cell record。**

```forth
┌────────────┐
│ DP 位址     │  ← OP0：最新指令起點（一格 = 1 cell）
├────────────┤
│ DP 位址     │  ← OP1：前一條指令起點
├────────────┤
│ ...        │
├────────────┤
│ DP 位址     │  ← OP8
└────────────┘
```

每個 OP 格存的就是字典中該指令的起點位址；指令大小由**相鄰兩格的位址差**推得（不是固定 2 cell）。透過 `@`/`W@`/`C@` 可讀取該位址上不同寬度的指令位元組。

### 3.2 SetOP — 記錄最佳化起始點

```forth
: SetOP ( -- )
  DP @ OP0 @ = IF -8FD THROW THEN    \ 防止 OP0 與 OP1 重疊
  OP0 OP1 OpBuffSize CELL- CMOVE>      \ 將所有 OP 插槽往後移動一格
  DP @ OP0 !                            \ 當前 DP 存入 OP0
;
```

`SetOP` 通常在**輸出一條新機器碼之前**呼叫（例如 `tc_spf.F:160-163` 的 `TC-CALL,` 是 `SetOP` 後才 `0E8 C,`），用目前 `DP @` 標記「即將輸出的這條指令的起點」。所有舊的操作位址向後滑動一格（OP1→OP2, OP2→OP3, ...），OP0 記錄最新指令起點。

### 3.3 ?SET — 檢查並重設過時的 OP

```forth
: ?SET DP @
  DUP LAST-HERE <> IF DUP TO :-SET DUP TO J-SET THEN
  DUP    OP0 @ U< IF OP0 0! THEN     \ OP0 已過時
  DUP    OP1 @ U< IF OP1 0! THEN     \ OP1 已過時
  DUP    JP0 @ U< IF JP0 0! THEN     \ JP0 已過時
               JP1 @ U< IF JP1 0! THEN ;  \ JP1 已過時
```

`?SET` 在最佳化前呼叫，清除所有指向已覆蓋區域的 OP 和 JP 插槽。若目前 `DP @` 與 `LAST-HERE`（上次最佳化邊界）**不相等**（`src/macroopt.f:133-135` 的 `DUP LAST-HERE <> IF ...`，是「不等於」而非「超過」），重設 `:-SET` 和 `J-SET`。

### 3.4 OP_SIZE / OPexcise / OPresize / OPinsert

```forth
: OP_SIZE ( OP - n ) DUP IF THEN DUP CELL- @ SWAP @ - ;

: OPexcise ( OPX -- )
  DUP OP0 = IF @ DP ! OP1 ToOP0 EXIT THEN    \ 若是 OP0，直接刪除
  >R
  R@ CELL- @ R@ @ DP @ R@ CELL- @ - CMOVE      \ 移動程式碼覆蓋被刪除的指令
  R@ OP_SIZE NEGATE                             \ 計算刪除的大小
  R@ OP0 DO DUP I +! CELL +LOOP                 \ 調整所有 OP 插槽的偏移
  ALLOT                                          \ 回收空間
  R@ CELL+ R@ OpBuffSize CELL- R> - OP0 + CMOVE ;  \ 移動 OP 填充空隙
```

`OPexcise` 移除一條指令：從字典中壓縮掉該指令的機器碼，調整所有 OP 插槽的偏移，回收空間。

```forth
: OPresize ( OPX n -- )          \ 改變指令大小
  DUP >R
  OVER OP0 ?DO DUP I +! CELL +LOOP  \ 調整偏移
  ALLOT                              \ 分配/回收空間
  @ DUP R> + DUP DP @ - NEGATE MOVE ;  \ 移動後續指令
;

: OPinsert ( OPX n -- )           \ 插入空間
  DUP >R
  2DUP OPresize DROP                \ 擴展指令
  DUP CELL + OVER OP0 - OpBuffSize CELL- - NEGATE MOVE
  R> SWAP +!                       \ 調整偏移
;
```

---

## 4. EAX 偏移追蹤

### 4.1 核心概念

SP-Forth 使用 TOS-in-EAX 模型：資料堆疊頂部值（TOS）存放在 EAX 暫存器中，第二個值在 `[EBP]`（EBP 指向的記憶體位置）。最佳化器追蹤兩個偏移：

```forth
USER-VALUE OFF-EBP    \ EBP 相對於理想位置的偏移
USER-VALUE OFF-EAX    \ EAX 相對於理想值的偏移
```

**理想狀態**：
- `OFF-EBP = 0`：EBP 指向資料堆疊第二個元素的正確位置
- `OFF-EAX = 0`：EAX 包含正確的 TOS 值

**偏移狀態**：
- `OFF-EBP ≠ 0`：EBP 與理想位置有偏移（需要 `LEA EBP, OFF-EBP[EBP]` 修正）
- `OFF-EAX ≠ 0`：EAX 與正確的 TOS 值有偏移（需要 `LEA EAX, OFF-EAX[EAX]` 修正）

### 4.2 EVEN-EAX / EVEN-EBP

```forth
: EVEN-EAX OFF-EAX
   IF      SetOP OFF-EAX DUP SHORT?
       IF    0408D W, C,            \ LEA EAX, OFF-EAX[EAX]（短偏移，5 位元組）
       ELSE  0808D W, ,             \ LEA EAX, OFF-EAX[EAX]（長偏移，6 位元組）
       THEN
       0 TO OFF-EAX
   THEN
;

: EVEN-EBP OFF-EBP
   IF SetOP OFF-EBP  06D8D W, C,   \ LEA EBP, OFF-EBP[EBP]（3 位元組）
      0 TO OFF-EBP
   THEN
;
```

`EVEN-EAX` 和 `EVEN-EBP` 分別修正 EAX 和 EBP 的偏移狀態。`SHORT?` 判斷偏移是否在 -128 到 +127 範圍內，決定使用短偏移（5 位元組）還是長偏移（6 位元組）。

```forth
: SHORT? ( n -- -129 < n < 128 )
  0x80 + 0x100 U<
;
```

### 4.3 LEA 消除最佳化

最佳化器的核心策略之一是**LEA 消除**：當編譯指令序列對 EAX 或 EBP 產生淨偏移時，不立即產生 `LEA` 指令，而是追蹤偏移量，在需要時才統一修正。

例如，連續的 `ADD EAX, #5` 和 `ADD EAX, #3` 可以合併為 `ADD EAX, #8`（或直接調整 OFF-EAX），避免兩條指令。

---

## 5. 指令模式識別

### 5.1 DUP2B? / DUP3B? / DUP5B? / DUP6B? / DUP7B?

這些字詞判斷機器碼位元組模式是否匹配特定的 x86 指令：

```forth
: DUP2B? ( W -- W FLAG )     \ 2 位元組模式
   CASE
   DUP 0E4C5 AND 0C001 <> IF  \ ADD|OR|ADC|SBB|AND|SUB|XOR|CMP E_X, E_X
   DUP           01001 <> IF  \ ADD [EAX], EDX
   DUP            0003 <> IF  \ ADD EAX, [EAX]
   DUP           F633 <> IF  \ XOR ESI, ESI
   ...
   DUP 0C0FF AND  C085 <> IF \ TEST E__, E__
   DUP          C78B <> IF  \ MOV EAX, EDI
   DUP          C68B <> IF  \ MOV EAX, ESI
   DUP          F88B <> IF  \ MOV EDI, EAX
   DUP          F08B <> IF  \ MOV ESI, EAX
   DUP 0E4FC AND 0E0D0 <> IF \ SHL|SHR|SAR E_X, CL|1
   ...
   DUP  F0FF AND  F0D9 <> IF \ F2XM1 FYL2X ... FSIN FCOS
   DUP  E8FF AND  20DB <> IF \ FLD EXTENDED [E_X]
   DUP  E8FF AND  00DD <> IF \ FLD DOUBLE [E_X]
   DUP 30FF AND  C0DE <> IF \ FADDP FMULP ... FDIVP
   DUP           00FF <> IF  \ INC [EAX]
   DUP 0F0FF AND 0D0F7 <> IF \ NOT|NEG E_X
   DUP           0E9F7 <> IF  \ IMUL ECX
   DUP           0F1F7 <> IF  \ DIV ECX
   DUP           0F9F7 <> IF  \ IDIV ECX
              FALSE EXIT
   DUPENDCASE TRUE ;
```

每個 `DUPnB?` 字識別特定長度的 x86 指令模式，用於 `INLINE?` 判斷一個 CODE 定義是否可以內聯。

### 5.2 INLINE? — 內聯判斷

```forth
: INLINE? ( CFA -- CFA FLAG )
  DUP BEGIN
    2DUP MM_SIZE - U> 0= IF DROP FALSE EXIT THEN   \ 超過大小限制
    DUP C@
    DUP 0C3 = IF 2DROP TRUE EXIT THEN               \ RET → 結束
    DUP5B?         M_WL DROP 5 + REPEAT              \ ADD EAX, # X
    DUP E0 AND 40 = M_WL 1+, REPEAT                \ INC|DEC|PUSH|POP E_X
    DUP 099 = M_WL 1+, REPEAT                       \ CDQ
    ...
    DUP3B?[EBP]   M_WL 3+, REPEAT                   \ 3 位元組 [EBP] 模式
    DUP3B?         M_WL 3+, REPEAT                   \ 3 位元組模式
    DUP 06D8D = M_WL 3+, REPEAT                      \ LEA EBP, OFF-EBP[EBP]
    DUP2B?         M_WL 2+, REPEAT                   \ 2 位元組模式
    DUP6B?         M_WL 6+, REPEAT                   \ 6 位元組模式
    ...
    DUP7B? WHILE 7+, REPEAT                          \ 7 位元組模式
  2DROP FALSE ;
```

`INLINE?` 從 CFA（Code Field Address）開始掃描機器碼，判斷是否可以內聯展開。條件：
1. 不超過 `MM_SIZE`（0x20 = 32 位元組）的大小限制
2. 遇到 `RET`（0xC3）指令時結束並回傳 TRUE
3. 遇到無法識別的指令模式時回傳 FALSE

`M_WL`（MacroOPT WordList）用於跳過已知指令，繼續掃描。

---

## 6. 最佳化規則

### 6.1 OPT-RULES — 主要最佳化迴圈

```forth
: OPT-RULES ( ADDR -- ADDR' FLAG )
  BEGIN
    OP0 @ :-SET U< IF TRUE EXIT THEN    \ 無可最佳化指令，離開

    OP0 @ W@ 408D =                     \ LEA EAX, X[EAX]
    WHILE
        OP0 @ 2+ C@ C>S OFF-EAX + TO OFF-EAX   \ 累積偏移
        OP1 ToOP0                                \ 移除 LEA 指令
        -3 ALLOT                                 \ 回收 3 位元組
  REPEAT

    OP0 @ C@ 05 = ~BR-OPT AND            \ ADD EAX, # X
    IF
        OP0 @ 1+ @ OFF-EAX + TO OFF-EAX  \ 累積偏移
        OP1 ToOP0                          \ 移除 ADD 指令
        FALSE -5 ALLOT                     \ 回收 5 位元組
        EXIT
    THEN

    OP0 @ W@ 808D =                      \ LEA EAX, X[EAX]（長偏移）
    IF
        OP0 @ 2+ @ OFF-EAX + TO OFF-EAX   \ 累積偏移
        OP1 ToOP0
        -6 ALLOT FALSE
        EXIT
    THEN

    OFF-EAX
    OP0 @ W@ C033 = AND                   \ XOR EAX, EAX
    IF
        B8 OP0 @ C!                        \ 改為 MOV EAX, #0
        OFF-EAX OP0 @ 1+ !                 \ 設定立即值
        0 TO OFF-EAX                        \ 偏移歸零
        3 ALLOT FALSE EXIT                  \ 擴展為 5 位元組
    THEN
    ...（數百條規則）
;
```

OPT-RULES 是最佳化器的核心，包含數百條模式匹配規則。每條規則：
1. 檢查 OP0（最新指令）是否匹配特定模式
2. 如果匹配，替換為更優的指令序列
3. 回傳 FALSE 表示繼續最佳化，TRUE 表示結束

### 6.2 常見最佳化規則分類

#### 6.2.1 常數傳播（CON>LIT）

```forth
: CON>LIT ( CFA -- CFA TRUE | FALSE )
  OPT? 0= IF TRUE EXIT THEN ?SET
  MM_SIZE 0= IF TRUE EXIT THEN
  DUP C@ 0E8 <> IF TRUE EXIT THEN    \ 必須是 CALL 指令

  DUP 1+ REL@ CELL+
  DUP CREATE-CODE =                    \ CREATE 常數
  IF DROP OPT_INIT 5+ [>T] FORLIT, FALSE OPT_CLOSE EXIT THEN

  DUP USER-CODE =                     \ USER 變數
  IF DROP OPT_INIT 'DUP _INLINE,
    SetOP 878D W, 5+ @ , OPT FALSE OPT_CLOSE EXIT THEN

  DUP USER-VALUE-CODE =               \ USER-VALUE
  IF DROP OPT_INIT 'DUP _INLINE,
    SetOP 878B W, 5+ @ , OPT FALSE OPT_CLOSE EXIT THEN

  DUP CONSTANT-CODE =                  \ CONSTANT
  IF DROP OPT_INIT 5+ DUP 5+ REL@
      TOVALUE-CODE CELL- =
      IF 'DUP _INLINE, SetOP 0A1 C, [>T] , OPT
      ELSE @ FORLIT,
      THEN FALSE OPT_CLOSE EXIT THEN

  DUP 1+ REL@ CELL+ DOES-CODE =      \ DOES>
  IF 5+ SWAP 5+ OPT_INIT FORLIT, TRUE OPT_CLOSE EXIT THEN

  DUP TOUSER-VALUE-CODE =              \ TO USER-VALUE
  IF DROP OPT_INIT
      SetOP 8789 W, CELL- @ , OPT
      'DROP _INLINE, FALSE OPT_CLOSE EXIT THEN

  DUP TOVALUE-CODE =                   \ TO VALUE
  IF DROP OPT_INIT
      SetOP A3 C, CELL- [>T] , OPT
      'DROP _INLINE, FALSE OPT_CLOSE EXIT THEN

  VECT-INLINE? IF
    DUP VECT-CODE =                    \ VECT 向量
    IF DROP SetOP 0x15FF W, 5+ [>T] , OPT FALSE OPT_CLOSE EXIT THEN
  THEN
  DROP TRUE ;
```

常數傳播將執行期查找替換為編譯期常數：

| 原始碼 | 編譯結果（未最佳化） | 最佳化後 |
|--------|---------------------|---------|
| `CONSTANT X ... X` | `CALL X_doCREATE ... CALL X` | `MOV EAX, #值` |
| `USER VAR ... VAR` | `CALL X_doUSER ... CALL VAR` | `LEA EAX, [EDI+offset]` |
| `USER-VALUE V ... V` | （`USER-VALUE-CODE` 分支） | `MOV EAX, [EDI+offset]`（`macroopt.f:5420-5425`） |
| `VALUE V ... V` | （`CONSTANT-CODE` + `TOVALUE-CODE`） | 讀取最佳化成 `MOV EAX, [addr]`（`macroopt.f:5428-5435`） |
| `V !` | `CALL X_TO-USER-VALUE` | `MOV [EDI+offset], EAX` |
| `DOES> 字 ... 字` | `CALL 字 ... CALL X_doDOES>` | `MOV EAX, #值 CALL 主體` |

#### 6.2.2 指令合成

常見的指令合成最佳化：

| 原始序列 | 最佳化後 | 說明 |
|---------|---------|------|
| `XOR EAX, EAX` + `ADD EAX, #X` | `MOV EAX, #X` | 清零+賦值→直接賦值 |
| `XOR EAX, EAX` + `ADD EAX, F8[EBP]` | `MOV EAX, F8[EBP]` | 清零+載入→載入 |
| `MOV EAX, [EDX]` + `MOV ECX, #X` + `CMP EAX, ECX` | `CMP [EDX], #X` + `DROP` | 比較消除 |
| `LEA EAX, FF[EAX]` + `CMP EAX, #0` | `DEC EAX` | 遞增+零比較→遞減 |
| `MOV FC[EBP], EAX` + `XOR EAX, EAX` + `CMP EAX, FC[EBP]` | `CMP #0, FC[EBP]` | 儲存+清零+比較→直接比較 |
| `NEG EAX` + `ADD EAX, EDX` | `SUB EDX, EAX` | 否定+加法→減法 |
| `MOV ECX, EDX` + `OR ECX, ECX` | `OR EDX, EDX` + `MOV ECX, EDX` 消除 | 減少暫存器使用 |
| `PUSH EAX` + `MOV EAX, [ESP]` | （消除，POP EAX 或直接使用） | 堆疊往返消除 |
| `CALL X` + `RET` | `JMP X` | 尾呼叫最佳化 |

#### 6.2.3 MOV EAX 消除（EAX>EBX/EAX>ECX）

當最佳化器偵測到 `MOV EDX, X[EBP]` 後，追蹤 EDX 的使用，將後續的 `MOV X[EBP], EDX` 替換為直接操作：

```forth
: ?EDXEAX ( -- FLAG )
  OP0 @ W@ 558B <> IF FALSE EXIT THEN    \ 必須是 MOV EDX, X[EBP]
  OP1
  BEGIN ?EDX_[EBP] 0=                   \ 追蹤 EDX 的後續使用
  WHILE CELL+
       ?OPlast IF DROP FALSE EXIT THEN
       DUP @ W@ FFFD AND 4589 =         \ MOV X[EBP], EAX
       IF DUP @ 2+ C@ OP0 @ 2+ C@ =    \ 相同的 EBP 偏移
          IF CELL- 2 OPinsert
             D08B SWAP CELL+ @ W!       \ MOV EDX, EAX
             TRUE EXIT
          THEN
       THEN
  REPEAT DROP FALSE
;
```

這個規則將：
```forth
MOV  EDX, FC[EBP]    ; 載入堆疊值到 EDX
...               ; EDX 不被修改
MOV  X[EBP], EAX     ; 儲存 EAX 到堆疊
```
替換為：
```forth
MOV  EDX, EAX        ; 重新安排：EDX = EAX
```

並在原始 `MOV X[EBP], EAX` 的位置插入新的儲存指令。

#### 6.2.4 條件跳躍最佳化（?BR-OPT）

```forth
: ?BR-OPT
  BEGIN BEGIN ?BR-OPT-RULES UNTIL
        ['] NOOP OPT-RULES NIP
  UNTIL BR-EVEN-EAX
  OP0 @ :-SET U<
  IF    SetOP 0xC00B W,                 \ OR EAX, EAX（5 位元組長跳前綴）
        EXIT
  THEN
  OP0 @ C@
  ...（判斷是否可以用短指令替代 OR EAX, EAX）
  IF    SetOP 0xC00B W,                 \ OR EAX, EAX
  THEN
;
```

條件跳躍最佳化決定使用哪種跳躍格式：

- 短跳（2 位元組）：`Jcc rel8`，適用於 ±127 位元組範圍
- 近跳（6 位元組）：`0F Jcc rel32`，適用於任意範圍

`??BR-OPT` 先產生長跳格式，若 `RESOLVE_OPT` 判定目標在短跳範圍內，則縮減為短跳。

```forth
: ??BR-OPT
  OPT? IF OPT_INIT
    ?BR-OPT
    OPT_CLOSE
  THEN ;
```

`???BR-OPT` 是另一個入口點，用於需要先插入 `OR EAX, EAX` 再最佳化的情況。

#### 6.2.5 跳躍最佳化（RESOLVE_OPT）

```forth
TRUE VALUE J_OPT?

: RESOLVE_OPT ( ADR -- )
    OPT? 0= IF DROP EXIT THEN
    J_OPT? 0= IF DROP EXIT THEN
    
    DUP CELL- JP0 JpBuffSize + CELL- @ U<
    IF DUP CELL- REL@ CELL+ J-SET UMAX TO J-SET THEN

    DP @ OVER - 7E > IF DROP EXIT THEN     \ 距離 > 126 位元組，無法短跳
    DP @ LAST-HERE <> IF ?SET DROP EXIT THEN
    OPT? 0= IF DROP EXIT THEN
    CELL+ OP0
    BEGIN J?_STEP
    UNTIL
    IF DUP @
       DUP C@ E9 =                        \ 長跳 JMP
       IF EB SWAP C! 3                     \ 改為短跳 JMP，節省 3 位元組
       ELSE
             DUP 1+ W@ 10 -               \ 調整近跳偏移
            SWAP W!  4                     \ 節省 2 位元組
       THEN
       J_MOVE DP @ TO LAST-HERE EXIT
    THEN DROP
;
```

`RESOLVE_OPT` 在解析跳躍目標時呼叫，嘗試將長跳轉換為短跳，節省空間。

### 6.3 最佳化流程示例

以 `DUP +` 為概念例子，先看 kernel primitive 的基線序列：

```forth
DUP:
  LEA EBP, -4 [EBP]
  MOV [EBP], EAX

+:
  ADD EAX, [EBP]
  LEA EBP, 4 [EBP]
```

這表示 `DUP` 先把原本的 TOS 寫回資料堆疊，再由 `+` 立刻從 `[EBP]` 讀回同一值。最佳化器能利用這種「剛寫入又立刻讀回」的短命堆疊流量做 peephole rewrite，但實際能否縮成更短序列，仍取決於前後文與當前追蹤到的 EAX / EBP 狀態。這個例子的重點是消去冗餘的 stack traffic，而不是固定改寫成某一條單獨的 `MOV` / `ADD` 模式。

---

## 7. 內聯展開

### 7.1 _INLINE, — 內聯複製

```forth
: _INLINE, ( CFA -- )
  BEGIN DO_OPT                  \ 執行最佳化
    DUP @                         \ 讀取指令
    DUP 8BE08B5B = DUP            \ 檢測 RP! 特殊序列
    IF DROP OVER 3 + 2@ E3FF046D 8D00458B D=  \ 確認是 RP!
    THEN M_WL DROP SetOP
                   8B C, E0 C,                  \ MOV ESP, EAX
                   DROP 'DROP                    \ 內聯 DROP（恢復 TOS）
                REPEAT
  FF AND                        \ 取指令的第一個位元組

  DUP 0C3 = IF 2DROP EXIT THEN  \ RET → 結束內聯
  DUP5B? M_WL 5_,_STEP REPEAT   \ 5 位元組指令
  ...
  DUP7B? WHILE 7+, REPEAT        \ 7 位元組指令
  HEX U. ." @COD, ERROR" ABORT  \ 無法識別的指令
;
```

`_INLINE,` 將一個 CODE 定義的機器碼逐條複製到目標字典中，每條指令後執行 `DO_OPT` 進行最佳化。

特殊處理：
- **RP! 偵測**：`8BE08B5B` 序列（`POP EBX; MOV EAX, [EBP]; LEA EBP, 4[EBP]; JMP EBX`）是 `>R` 的內聯展開，其中 `8D00458B` 是 `LEA EAX, [EBP+4]` 的反轉模式
- **RET 結束**：遇到 `0xC3`（RET）時停止內聯

### 7.2 FORLIT, — 常數展開

```forth
: FORLIT, ( N -- )
  'DUP _INLINE, SetOP 0B8 C, , OPT ;
```

將常數展開為 `MOV EAX, #N`，然後執行最佳化。`0B8` 是 `MOV EAX, immediate32` 的 x86 操作碼。

### 7.3 MACRO, — 巨集內聯

```forth
: MACRO, INLINE, ;
```

`MACRO,` 是 `INLINE,` 的別名，用於巨集展開。

---

## 8. 最佳化器詞彙表

### 8.1 MACROOPT-WL

最佳化器使用獨立的詞彙表 `MACROOPT-WL` 來定義其內部字詞，避免與核心詞彙衝突：

```forth
WORDLIST VALUE MACROOPT-WL
' MACROOPT-WL EXECUTE ( wid )
LATEST-NAME NAME>CSTRING SWAP VOC-NAME!
' MACROOPT-WL EXECUTE PUSH-ORDER DEFINITIONS
TC-TRG ALSO TC-IMM
```

在最佳化器完成後，這些字詞會被隱藏：

```forth
[DEFINED] HIDE-MACROOPT-WORDS [IF] HIDE-MACROOPT-WORDS [THEN]
```

### 8.2 NON-OPT-WL

`noopt.f` 建立的 `NON-OPT-WL` 詞彙表包含不被最佳化器處理的基礎字詞：

```forth
CODE1 RDROP    \ POP EBX; LEA ESP, 4[ESP]; JMP EBX
CODE1 >R       \ POP EBX; PUSH EAX; MOV EAX, [EBP]; LEA EBP, 4[EBP]; JMP EBX
CODE1 R>       \ LEA EBP, -4[EBP]; MOV [EBP], EAX; POP EBX; POP EAX; JMP EBX
CODE1 ?DUP     \ OR EAX, EAX; JNZ ' DUP; RET
CODE1 EXECUTE  \ MOV EBX, EAX; MOV EAX, [EBP]; LEA EBP, 4[EBP]; JMP EBX
```

這些 CODE 定義直接使用機器碼，不經過最佳化器。

---

## 9. 跳躍緩衝區（JP Buffer）

```forth
0x11 CELLS DUP CONSTANT JpBuffSize    \ 17 個 CELL

USER-CREATE JP0 1 CELLS + [DEFINED] TC [IF] TC-USER-ALLOT [ELSE] USER-ALLOT [THEN]
0
CELL+ DUP : JP1 JP0 LITERAL + ;
CELL+ DUP : JP2 JP0 LITERAL + ;
CELL+ DUP : JP3 JP0 LITERAL + ;
CELL+ DUP : JP4 JP0 LITERAL + ;
DROP
```

跳躍緩衝區記錄最近解析的跳躍指令位址，用於 `RESOLVE_OPT` 將長跳轉換為短跳。

```forth
: SetJP ( -- )
  JP0 JpBuffSize + CELL- @ DUP
  IF J_@
  THEN
  J-SET UMAX TO J-SET
  JP0 JP1 JpBuffSize CELL- CMOVE>
  DP @ JP0 ! ;
```

### 9.1 J_@ — 跳躍目標解析

```forth
: J_@ ( addr -- addr' )
        DUP C@ F0
           AND 70 = IF   SJ@ ELSE    \ 短條件跳（2 位元組）
        DUP C@ EB = IF   SJ@ ELSE    \ 短無條件跳（2 位元組）
        DUP C@ E9 = IF    J@ ELSE    \ 近無條件跳（5 位元組）
        DUP W@ F0FF
         AND 800F = IF 1+ J@ ELSE    \ 近條件跳（6 位元組）
        HEX U. 1 ." J_@ ERR" ABORT  \ 無法識別的跳躍
        THEN  THEN THEN THEN ;
```

`J_@` 解析跳躍指令的目標位址，支援四種 x86 跳躍格式：

| 格式 | 操作碼 | 大小 | 說明 |
|------|--------|------|------|
| 短條件跳 | `7x` | 2 位元組 | `Jcc rel8` |
| 短無條件跳 | `EB` | 2 位元組 | `JMP rel8` |
| 近無條件跳 | `E9` | 5 位元組 | `JMP rel32` |
| 近條件跳 | `0F8x` | 6 位元組 | `Jcc rel32` |

### 9.2 J_MOVE — 跳躍重定位

```forth
: J_MOVE ( OPX n -- )
  OVER OP0 <>
  IF
      OVER CELL- @
      2DUP - NEGATE
      OVER DP @ - NEGATE ( U. U. U. ABORT ) CMOVE
      OVER OP0 ?DO DUP NEGATE I +! CELL +LOOP
  THEN
      OVER @
      JP0 JpBuffSize + JP0
      ?DO I @
           IF   DUP  I @ U<
                IF    OVER NEGATE I @ J_+!
                     DUP I @ J_@ U>
                     IF OVER I @ J_+! THEN
                ELSE
                     DUP  I @ <>
                    IF    DUP  I @ J_@ U<
                          IF OVER NEGATE  I @ J_+! THEN
                    THEN
                THEN
           THEN CELL +LOOP DROP
  NIP NEGATE DUP ALLOT :-SET + TO :-SET EXIT ;
```

`J_MOVE` 在最佳化器修改指令時，調整所有跳躍目標和 OP 緩衝區的偏移。

---

## 10. 最佳化器入口點

### 10.1 OPT_INIT / OPT_CLOSE

```forth
: OPT_INIT ?SET -EVEN-EBP ;
: OPT_CLOSE EVEN-EBP DP @ TO LAST-HERE ;
```

- `OPT_INIT`：呼叫 `?SET` 清除過時的 OP/JP 插槽，然後呼叫 `-EVEN-EBP` 修正 EBP 偏移
- `OPT_CLOSE`：呼叫 `EVEN-EBP` 修正 EBP 偏移，然後記錄 `LAST-HERE` 作為下次最佳化的邊界

### 10.2 DO_OPT

```forth
: DO_OPT ( ADDR -- ADDR' )
  OPT? IF OPT_ THEN ;
```

`DO_OPT` 是最佳化器的主要入口點。若 `OPT?` 為 TRUE，執行 `OPT_`；否則不做任何事。

```forth
: OPT_ ( -- )
  BEGIN
    OPT-RULES UNTIL
    EVEN-EAX ;
```

`OPT_` 持續執行 `OPT-RULES` 直到無法再最佳化，然後修正 EAX 偏移。

### 10.3 INLINE, — 完整的內聯入口

```forth
: INLINE, ( CFA -- ) OPT_INIT _INLINE, OPT_CLOSE ;
: MACRO, INLINE, ;
```

`INLINE,` 是完整的內聯入口：先呼叫 `OPT_INIT` 記錄最佳化起點，然後呼叫 `_INLINE,` 複製機器碼（每條指令後執行 `DO_OPT`），最後呼叫 `OPT_CLOSE` 修正偏移。

---

## 11. 最佳化策略總覽

| 策略 | 說明 | 實作字 |
|------|------|--------|
| 常數傳播 | `CON>LIT`：將執行期查找替換為編譯期常數 | `CON>LIT` |
| LEA 消除 | 追蹤 OFF-EAX/OFF-EBP，延遲 LEA 修正 | `EVEN-EAX`、`EVEN-EBP` |
| 指令合成 | 將指令序列合成為更短的單指令 | `OPT-RULES` |
| 短跳最佳化 | `RESOLVE_OPT`：長跳→短跳 | `SetJP`、`RESOLVE_OPT` |
| 內聯展開 | `_INLINE,`：將短小的 CODE 定義直接嵌入呼叫點 | `INLINE,`、`INLINE?` |
| NOP 填充 | 對齊填補（未實作） | — |
| EAX 消除 | 將 `MOV EAX, X[EBP]` + 後續使用替換為直接操作 | `?EAX=RULES`、`?EDXEAX` |
| 堆疊往返消除 | 將 `PUSH EAX` + `MOV EAX, [ESP]` 替換為直接使用 | `OP-RULES` |
| 尾呼叫最佳化 | `CALL X` + `RET` → `JMP X` | `OPT-RULES` |

### 11.1 最佳化器狀態變數

| 變數 | 類型 | 說明 |
|------|------|------|
| `OPT?` | VALUE | 最佳化器開關（TRUE/FALSE） |
| `~BR-OPT` | USER-VALUE | 條件跳躍最佳化開關 |
| `J_COD` | USER-VALUE | 跳躍碼（短跳字首，預設 0x84） |
| `MM_SIZE` | VALUE | 記憶體管理區塊大小（0=停用，0x20=啟用） |
| `OFF-EBP` | USER-VALUE | EBP 相對偏移 |
| `OFF-EAX` | USER-VALUE | EAX 相對偏移 |
| `:-SET` | USER-VALUE | 最佳化邊界（不跨越此點） |
| `J-SET` | USER-VALUE | 跳躍邊界 |
| `LAST-HERE` | USER-VALUE | 上次最佳化的 DP 位址 |
| `?C-JMP` | VALUE | 條件跳躍最佳化旗標 |
| `J_OPT?` | VALUE | 跳躍最佳化開關 |

### 11.2 初始化

```forth
: INIT-MACROOPT-LIGHT ( -- )
  084 TO J_COD           \ 0x84 = near JZ/JE（0F 84）的第二 opcode byte（JNZ/JNE 則是 0x85）
  TRUE TO ~BR-OPT        \ 啟用條件跳躍最佳化
;
```

在 `POOL-INIT` 中呼叫，設定最佳化器的初始狀態。

---

## 12. 偵錯支援

最佳化器包含大量的偵錯輸出（`M\` 註解和 `DTST` 追蹤點），這些在正常編譯時被忽略：

```forth
M\ VECT DTST
M\ 1000 DTST     \ EVEN-EAX 觸發
M\ 1001 DTST     \ EVEN-EAX 完成
M\ -1 DTST       \ OPT-RULES 迴圈開始
M\ 2 DTST        \ LEA EAX, X[EAX] 消除
M\ 3 DTST        \ LEA 消除完成
M\ 4 DTST        \ ADD EAX, #X 消除
M\ ...
```

`M\` 是一個註解字（`M\` = macro debug），在生產編譯中不起作用。每個追蹤點有唯一的數字標識，可用於偵錯特定最佳化規則的觸發。

---

## 13. CON>LIT 與向量內聯

### 13.1 向量內聯

```forth
VECT-INLINE? IF
  DUP VECT-CODE =
  IF DROP SetOP 0x15FF W, 5+ [>T] , OPT FALSE OPT_CLOSE EXIT THEN
THEN
```

當 `VECT-INLINE?` 為 TRUE 時，`CON>LIT` 也嘗試內聯 VECT 向量呼叫。向量呼叫內聯後變成 `CALL dword ptr [vector-cell-address]`（`src/macroopt.f:5442-5444` 的 `0x15FF W,`，即 `FF 15 [addr]`）。注意這**仍是經由向量 cell 的間接呼叫**，只是省去了進入 Forth `VECT-CODE` 那一層執行碼，並非變成直接呼叫目標函式。

### 13.2 CONSTANT 內聯路徑

```forth
DUP CONSTANT-CODE =
IF DROP OPT_INIT 5+ DUP 5+ REL@
    TOVALUE-CODE CELL- =
    IF 'DUP _INLINE, SetOP 0A1 C, [>T] , OPT   \ MOV EAX, [addr]
    ELSE @ FORLIT,                                  \ MOV EAX, #value
    THEN FALSE OPT_CLOSE EXIT THEN
```

對於 CONSTANT，根據其實作方式選擇不同的內聯路徑：
- 若 CONSTANT 值是 TO-VALUE（可修改值），使用 `MOV EAX, [addr]`（5 位元組）
- 若 CONSTANT 值是唯讀值，使用 `MOV EAX, #value`（5 位元組）

### 13.3 DOES> 內聯

```forth
DUP 1+ REL@ CELL+ DOES-CODE =
IF 5+ SWAP 5+ OPT_INIT FORLIT, TRUE OPT_CLOSE EXIT THEN
```

對於 DOES> 定義的字詞，`CON>LIT` 將常數部分展開為 `FORLIT,`（MOV EAX, #value），然後保留 DOES> 體的呼叫（回傳 TRUE 表示需要後續呼叫）。
