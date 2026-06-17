# SP-Forth/4 原始碼追蹤 — 附錄 B：Forth 編譯模式深入理解

> 本章目標：看懂 `STATE`、`IMMEDIATE`、`POSTPONE`、`COMPILE,`、`DOES>` 如何在 SP-Forth 原始碼中運作。
>
> 閱讀定位：若你對 Forth 的**編譯與直譯雙模式**還不熟悉，建議先讀完本章再進入 [02-compiler.md](02-compiler.md) 與 [03-cross-compiler.md](03-cross-compiler.md)。

---

## 1. 為什麼需要這一章？

Forth 與多數語言最不同的地方在於：**編譯器不是獨立工具，而是執行期的一部分**。撰寫 Forth 時，你不只是在寫「執行期跑的程式」，也常是在寫「編譯期跑、用來產生程式碼的程式」。

這套 trace 文件大量使用以下術語，但 Forth 初學者很容易混淆：

| 術語 | 初學者的典型困惑 |
|------|-----------------|
| `STATE` | 為什麼一個變數可以決定「執行」和「編譯」兩種行為？ |
| `:` / `;` | 到底什麼時候進入編譯？編譯期間做了什麼？ |
| `IMMEDIATE` | 同一個字為什麼有時執行有時編譯？ |
| `POSTPONE` | 跟 `'` + `COMPILE,` 差在哪？ |
| `COMPILE,` | 為什麼叫「執行期編譯原語」？ |
| `DOES>` | `CREATE ... DOES>` 到底是定義時跑還是執行時跑？ |

本章逐一解釋，並以最小範例對照原始碼中的真實用法。

---

## 2. STATE 與編譯/直譯雙模式

### 2.1 直譯模式（Interpret State）

在直譯模式下（`STATE` = 0），Forth 逐字讀取輸入：

1. 若找到的字詞有 **interpret 語意** → 立即執行
2. 若找到的是數字 → 推到資料堆疊

```forth
STATE = 0   →   1 2 + .
                 ^ ^ ^ ^
                 │ │ │ │
                 │ │ │ └ . (print TOS, 輸出 3)
                 │ │ └── + (add: 1+2=3, TOS=3)
                 │ └──── 2 (push 2, TOS=2)
                 └────── 1 (push 1, TOS=1)
```

### 2.2 編譯模式（Compile State）

在編譯模式下（`STATE` ≠ 0），Forth 換了另一套規則：

1. 若找到的字詞有 **compile 語意** → 編譯到字典中（通常產生一條 `CALL`）
2. 若找到的是數字 → 編譯成常值載入
3. 若字詞是 `IMMEDIATE` → **無視 STATE，立即執行其 interpret 語意**

```forth
STATE ≠ 0  →  1 2 + .
                 ^ ^ ^ ^
                 │ │ │ │
                 │ │ │ └ . 不是 IMMEDIATE → 編譯成 CALL .
                 │ │ └── + 不是 IMMEDIATE → 編譯成 CALL +
                 │ └──── 2 → 編譯成 push 2
                 └────── 1 → 編譯成 push 1
```

### 2.3 `[` 和 `]` — 手動切換

`[` 是 IMMEDIATE 字，執行時將 `STATE` 設為 0；`]` 設為非 0：

```forth
: test
  [ 1 2 + . ]   \ 直譯執行：當場印出 3
  CR ." back to compile"  \ 又回到編譯模式（; 最後會設 STATE=0）
;
```

在 SP-Forth 原始碼中，`[` 常用於**在編譯期插入計算**，例如交叉編譯器中的常量表達式：

```forth
\ tc_spf.F 片段：在編譯期計算 target offset
[ HERE VIRTUAL-ADDRESS @ - ] LITERAL
```

### 2.4 SP-Forth 中 STATE 的實際角色

SP-Forth 的 `STATE` 不是全域變數，而是一個 `USER` 變數（每執行緒獨立）：

```forth
USER STATE     \ spf_translate.f:10
```

這代表不同執行緒可以有各自的編譯狀態——多執行緒編譯時，不會相互干擾。

---

## 3. `:` 與 `;` — 字詞定義

### 3.1 `: name ... ;` 的完整流程

在 SP-Forth 中，`:` 是一個一般（非 IMMEDIATE）的定義字；當外層直譯器在直譯狀態下遇到它，就會執行它去開新定義。當你輸入：

```forth
: DOUBLE DUP + ;
```

`:` 做了這些事：

```forth
步驟 1: 在字典中建立 "DOUBLE" 的標頭（HEADER）
        → 寫入 NFA（名稱）、LFA（鏈結）、CFA（預留）
步驟 2: STATE 設為非 0（進入編譯模式）
步驟 3: 回到主迴圈，開始讀取後續的 "DUP" "+" ";"
步驟 4: DUP → 不是 IMMEDIATE → 編譯成 CALL DUP
步驟 5: +   → 不是 IMMEDIATE → 編譯成 CALL +  
步驟 6: ;   → IMMEDIATE → 立即執行
        → ; 寫入 RET opcode
        → STATE 設為 0（回到直譯模式）
```

編譯後的 `DOUBLE` 在記憶體中長這樣：

```asm
DOUBLE:
  CALL DUP     ; call DUP
  CALL +       ; call +
  RET          ; return
```

### 3.2 SP-Forth 的編譯器如何處理 `:` 與 `;`？

`:` 定義在 `src/compiler/spf_defwords.f:281–298`：

```forth
\ src/compiler/spf_defwords.f:281
: : ( C: "<spaces>name" -- colon-sys ) \ 94
  HEADER      \ 解析名稱，建立字典標頭
  ]           \ STATE ← TRUE，進入編譯模式
  HIDE        \ 暫時隱藏（透過 C-SMUDGE 覆寫名稱長度位元組）
;
```

> **注意**：SP-Forth 的 `:` 是一般定義字，**不是** IMMEDIATE — 定義以單純的 `;` 結尾，沒有 `; IMMEDIATE`。這也符合 Forth 的典型用法：`:` 預期在直譯狀態下被外層直譯器執行，用來建立新的 colon definition 並切入編譯狀態（`:` 本來就不是需要 immediate 的控制字）。

`;` 定義在 `src/compiler/spf_immed_transl.f:82–86`，**是** IMMEDIATE：

```forth
\ src/compiler/spf_immed_transl.f:82
: ; ( -- )
  RET,             \ 編譯 RET 指令
  [COMPILE] [      \ STATE ← FALSE，回到直譯模式
  SMUDGE           \ 解除新字的隱藏狀態
  ClearJpBuff      \ 清理 peephole optimizer 的 jump buffer
  0 TO LAST-NON
; IMMEDIATE
```

重點是：`;` 不只是「結束文字」，它會編譯 RET、回到直譯模式、解除隱藏，並把 optimizer 的內部狀態 reset。

### 3.3 初學者常見問題

**Q: 為什麼 `:` 不需要是 IMMEDIATE？**

A: `:` 不需要是 IMMEDIATE，因為它通常只在直譯狀態下被外層直譯器執行，用來開啟新定義並切換到編譯狀態 —— 這正是 Forth 的典型用法，`:` 本來就不屬於「會在編譯狀態下改寫編譯流程」的那類控制字。若要在編譯期建立匿名定義，請改用 `:NONAME`（`spf_defwords.f:261–278`）。

---

## 4. IMMEDIATE — 立即執行

### 4.1 什麼是 IMMEDIATE？

一個字詞被標記為 `IMMEDIATE` 後，**無論 STATE 為何，都執行其 interpret 語意**。

```forth
直譯模式:   IMMEDIATE 字 = 執行
非 IMMEDIATE 字 = 執行

編譯模式:   IMMEDIATE 字 = 執行
非 IMMEDIATE 字 = 編譯
```

### 4.2 誰需要是 IMMEDIATE？

控制結構與部分編譯控制字（例如 `IF`/`THEN`/`DO`/`LOOP`、`POSTPONE`、`[COMPILE]`、`;`）通常必須是 IMMEDIATE，因為它們要在編譯狀態下改寫編譯流程。一般的 defining words（例如 `:`、`CREATE`、`CONSTANT`）則通常在直譯狀態下執行，**不需要**標成 IMMEDIATE：

```forth
\ 控制結構：編譯期決定跳轉目標
: IF
  ?COMPILING
  HERE 0 ,        \ 預留條件跳轉位置
; IMMEDIATE

: THEN
  ?COMPILING
  DUP HERE SWAP - \ 計算偏移
  SWAP !          \ 回填 IF 預留的位置
; IMMEDIATE
```

當你寫 `: foo IF 1 THEN ;` 時，`IF` 是 IMMEDIATE，所以在編譯模式下它立即執行，預留一個待回填的跳轉位址。如果 `IF` 不是 IMMEDIATE，它會被編譯成 `CALL IF`，完全失去控制結構的意義。

### 4.3 SP-Forth 中的 IMMEDIATE 實作

SP-Forth 的 `IMMEDIATE` 修改字詞標頭旗標位元組中的旗標位元（定義在 `src/compiler/spf_wordlist.f:240–251`）：

```forth
\ src/compiler/spf_wordlist.f
1 CONSTANT &IMMEDIATE   \ 旗標位元遮罩：bit 0（值 1）

: IMMEDIATE ( -- ) \ 94
\ WARNING 檢查省略
  LATEST-NAME NAME>F DUP C@ &IMMEDIATE OR SWAP C!
;
```

注意關鍵點：

- `&IMMEDIATE` 是常數 **1**（bit 0），**不是** 0x80（bit 7）。
- `LATEST-NAME NAME>F` 取得最近定義字詞的「旗標位元組」位址（不是 NFA 本身）；同一個位元組也存 `&VOC = 2`（bit 1）等其它旗標。
- 隱藏（HIDE/SMUDGE）使用的不是這個旗標位元組，而是名稱長度位元組本身（見 `src/compiler/spf_defwords.f:247–257` 與 `IS-NAME-HIDDEN` 在 `spf_wordlist.f:180–182`：用 `12` 覆蓋名稱長度位元組）。

後續查詢由 `IS-NAME-IMMEDIATE` 處理（`spf_wordlist.f:183–185`）：

```forth
: IS-NAME-IMMEDIATE ( nt -- flag )
  NAME>F C@ &IMMEDIATE AND 0<>
;
```

並且 `SFIND`（`src/compiler/spf_find.f:175`）會把這個旗標折成回傳值 `1`（立即字）或 `-1`（一般字），編譯器以 `STATE @ =` 來分流（見 [02-compiler.md §10](02-compiler.md)）。

### 4.4 初學者最常卡住的地方

**典型迷思**：以為 `IMMEDIATE` 是「立刻執行完再繼續」。

**正確理解**：`IMMEDIATE` 只決定「在編譯模式中，這個字是執行還是編譯」。它不是在搶 CPU 時間片，也不是中斷向量。

---

## 5. POSTPONE — 編譯語意的推遲

### 5.1 問題場景

你想寫一個「總是編譯 IF 結構」的包裝字：

```forth
: MY-IF
  IF      \ 這樣寫對嗎？
;
```

問題：當你定義 `MY-IF` 時，`IF` 在編譯模式下被看到。如果 `IF` 不是 IMMEDIATE，它會被編譯。但 `IF` 是 IMMEDIATE——所以它會立即執行！在 `MY-IF` 的定義體內立即執行 `IF` 會在這裡建立一個條件跳轉，但這不是我們要的。

我們要的是：「當 `MY-IF` 被執行時，才編譯 IF」。

### 5.2 POSTPONE 的解法

```forth
: MY-IF
  POSTPONE IF     \ 「推遲」IF 的編譯語意
; IMMEDIATE
```

`POSTPONE IF` 的意思是：

> 在目前編譯點（`MY-IF` 的定義體內）寫入一段程式碼，這段程式碼**當 MY-IF 被執行時**會編譯 `IF`。

換句話說，`POSTPONE` 把 `IF` 的**編譯語意**（不是執行語意！）包裝起來，等執行期才觸發。

### 5.3 POSTPONE 的底層原理

`POSTPONE` 不是單一固定的展開式——它先用 `SFIND` 判斷目標字是否 immediate，再分兩條路：

- **目標是 immediate**（例如 `IF`）：`POSTPONE IF` 直接在目前定義中編譯 `IF` 的 xt（`COMPILE,`），使包裝字日後執行時就執行 `IF` 的編譯期行為。
- **目標是 non-immediate**（例如 `DUP`）：才需要編出「日後再編譯此 xt」的序列——`LIT, xt` 後接 `COMPILE,`。

所以對 immediate 目標，`POSTPONE IF` 就近似於 `' IF COMPILE,`；但對 non-immediate 目標則不是，必須多包一層延遲。注意 SP-Forth 的 `COMPILE,` 並不是「`CALL (COMPILE)` + XT」這種固定 pair，它會經過 `CON>LIT`/`INLINE?`/`_COMPILE,` 產生 CALL、inline 或特化序列（見 [02-compiler.md §8](02-compiler.md)）。

### 5.4 POSTPONE 在 SP-Forth 中的實作

```forth
\ spf_immed_transl.f
: POSTPONE
  ?COMP
  PARSE-NAME SFIND DUP
  0= IF -321 THROW THEN
  1 = IF COMPILE,                       \ immediate：直接編譯其編譯語意
      ELSE LIT, ['] COMPILE, COMPILE,   \ 非 immediate：延後到執行期再 COMPILE,
      THEN
; IMMEDIATE
```

`POSTPONE` 自己也是 IMMEDIATE——這很合理，因為你必須在**定義期**處理推遲邏輯。注意 `SFIND` 的回傳值：`1` 表示 immediate，`-1` 表示 non-immediate，`0` 表示找不到。因此這段程式的分支不能只用「旗標真/假」直覺閱讀。

### 5.4a POSTPONE 遇到 immediate 與 non-immediate 的差異

| 後續字詞類型 | `SFIND` 回傳 | `POSTPONE` 的動作 | 效果 |
|--------------|--------------|-------------------|------|
| immediate | `1` | `COMPILE,` | 直接保留該字的編譯語意，例如 `IF` 的 backpatch 行為 |
| non-immediate | `-1` | `LIT, ['] COMPILE, COMPILE,` | 編出「日後執行時再編譯此 XT」的程式碼 |
| 找不到 | `0` | `THROW -321` | 報錯 |

這正是 `POSTPONE` 比 `[COMPILE]` 更安全的原因：它依字詞是否 immediate 選擇不同策略，而不是一律強制編譯。

### 5.5 POSTPONE 與 `[COMPILE]` 的差別

| 特性 | `POSTPONE name` | `[COMPILE] name` |
|------|-----------------|-------------------|
| 標準 | ANS Forth 94 | 舊標準（已淘汰） |
| 處理 IMMEDIATE | 依 immediate / non-immediate 自動選擇策略 | 在編譯期強制編譯指定字 |
| 使用場景 | 定義傳遞編譯語意的包裝字 | 臨時在定義體內編譯 IMMEDIATE 字 |
| 範例 | `: MY-IF POSTPONE IF ;` | `[COMPILE] IF`（不常用） |

SP-Forth 原始碼中幾乎只用 `POSTPONE`，因為它是 ANS 標準且更一致。

---

## 6. COMPILE, — 執行期編譯原語

### 6.1 什麼是 COMPILE,？

`COMPILE,` 接收一個 XT，在**當前字典位置**編譯對應的執行語意：

```forth
' DUP COMPILE,   \ 在 HERE 處寫入 CALL DUP
```

注意這是**編譯期**使用的（寫在 `:` 定義體內）。如果是執行期，也是同樣的效果。

### 6.2 執行期 COMPILE,（最讓人困惑的部分）

`COMPILE,` 的命名很容易誤導。關鍵是：
- 通常在**編譯期**被呼叫（撰寫定義字時）
- 但本身也可以在**執行期**被呼叫

看看這個例子：

```forth
: COMPILE-DUP
  ['] DUP COMPILE,   \ 編譯 DUP 到字典中
;                     \ 注意：COMPILE-DUP 不是 IMMEDIATE

\ 執行的時候：
COMPILE-DUP           \ 執行 COMPILE-DUP
                      \ → 它會在 CURRENT 字典的 HERE 處寫入 CALL DUP
```

`COMPILE-DUP` 執行時會建立機器碼！這就是 Forth 的「程式即資料」本質。

### 6.3 SP-Forth 中 COMPILE, 的真實使用

在交叉編譯器中，`COMPILE,` 被用來編譯目標程式碼：

```forth
\ tc_spf.F：在 target 映像中編譯一個 CALL
: TC-CALL, ( addr -- )
  ?SET
  SetOP
  0E8 C,              \ 寫出 CALL opcode
  DP @ CELL+ - ,      \ 寫出 rel32 = target - (here + 4)
  DP @ TO LAST-HERE   \ 記錄機器碼邊界
;
```

這裡的 `C,` 和 `,` 是更低階的「寫 bytes 到字典」：`C,` 寫 1 byte，`,` 寫 1 cell（4 bytes）。

### 6.4 COMPILE, 與 POSTPONE 的關係

`POSTPONE name` 等於在編譯期寫入「執行期呼叫 COMPILE, 來編譯 name」的程式碼。即：

```forth
POSTPONE IF
\ 等同於
' IF COMPILE,    \ 在編譯期編譯 COMPILE, 的呼叫
```

概念上的對照（SP-Forth 不使用通用的 `(LIT)`/`(COMPILE)` pair；下表只表達語意，不是逐字機器碼）：

| 寫法 | 語意 | 備註 |
|------|------|------|
| `' EXECUTE` | 取得 `EXECUTE` 的 xt 放上堆疊 | `'` 是 parse-time 取 xt |
| `EXECUTE COMPILE,` | 把 `EXECUTE` 的 xt 編入目前定義 | `COMPILE,` 經 `CON>LIT`/`INLINE?`/`_COMPILE,` 產生 CALL/inline/特化序列 |
| `POSTPONE EXECUTE` | `EXECUTE` 是 non-immediate → 編出「日後再 `COMPILE,` 此 xt」的延遲序列（`LIT, xt` + `COMPILE,`） | 對 immediate 目標則改為直接 `COMPILE,` |

> 注意 SP-Forth 的 `LIT,` 不是 `CALL (LIT)` 模型，而是內聯 `DUP` 後產生 `MOV EAX, imm32` 的 TOS-in-EAX 載入序列（見 [02-compiler.md §8](02-compiler.md)）。

---

## 7. CREATE 與 DOES> — 自訂定義字

### 7.1 什麼是定義字？

`VARIABLE`、`CONSTANT`、`USER`、`VALUE` 都是**定義字**——它們不是簡單的關鍵字，而是「用來定義其他字詞」的字詞。Forth 提供 `CREATE ... DOES>` 作為建構自訂定義字的框架。

### 7.2 基本用法

```forth
CREATE COUNTER 0 ,
```

這在字典中建立 `COUNTER`，並在其 PFA 中寫入一個 `0`。當 `COUNTER` 被執行時，它會回傳其 PFA 位址（像 `VARIABLE` 的行為）。

```forth
CREATE COUNTER 0 ,
COUNTER .    \ 印出位址（PFA）
```

但如果要自訂執行行為，就需要 `DOES>`：

```forth
: CONSTANT ( n -- )
  CREATE ,    \ 建立字典項，儲存常數值
  DOES>       \ 定義執行期行為
    @         \ 讀取 PFA 的值
;
```

當 `CONSTANT` 被執行時：
- **定義期**（`CONSTANT` 的 `:` 體內）：`CREATE` 建立字典項，`,` 儲存值
- **使用期**（`42 CONSTANT answer` 時）：同上，`answer` 被建立
- **執行期**（使用 `answer` 時）：`DOES>` 後的 `@` 被執行，從 PFA 讀取 `42` 並推入 TOS

### 7.3 完整的生命週期圖

```text
撰寫期： : CONSTANT ( n -- ) CREATE , DOES> @ ;
         ↑                ↑        ↑
         │                │        └ DOES> 儲存「執行期行為」的位址
         │                └────────── CREATE 建立字典項
         └─────────────────────────── : 進入編譯模式

定義期： 42 CONSTANT answer
                 ↑
                 └────── CONSTANT 執行時：
                        1. CREATE 建立 answer 的字典項
                        2. , 將 42 寫入 answer 的 PFA
                        3. DOES> 設置 answer 的 CFA
                           指向內部的 (DOES2) 處理器

執行期： answer .
         ↑
         └────── answer 的 CFA 指向 (DOES2)
                (DOES2) 切換回 Forth 堆疊後跑 @
                → 從 PFA 讀出 42
                → 印出 42
```

### 7.4 SP-Forth 的 (DOES1) 與 (DOES2)

SP-Forth 不使用一般的 DOES> 實作，而是用兩個特殊字：

- `(DOES1)` — 在含 `DOES>` 的 defining word 執行、剛建立新字之後被呼叫，patch 該新字的執行入口
- `(DOES2)` — 被建立的新字日後執行時的入口，把 PFA 推上資料堆疊並跳到 `DOES>` 後的程式碼

實際原始碼（`src/compiler/spf_defwords.f:83-95`）：

```forth
\ src/compiler/spf_defwords.f:83
: (DOES1)
  R> DOES>A @ CFL + -
  DOES>A @ 1+ !
;

CODE (DOES2)
  LEA  EBP, -4 [EBP]
  MOV  [EBP], EAX
  MOV  EAX, 4 [ESP]   \ PFA
  MOV  EBX, [ESP]     \ DOES> 後的程式碼位址
  LEA  ESP, 8 [ESP]
  JMP  EBX
END-CODE
```

`DOES>` 本身是 IMMEDIATE（`spf_defwords.f:99-123`），它的工作只是依序編譯 `(DOES1)` 與 `(DOES2)`：

```forth
\ src/compiler/spf_defwords.f:99（節錄）
: DOES>  \ 94
  ['] (DOES1) COMPILE,
  ['] (DOES2) COMPILE,
; IMMEDIATE
```

因此你不需要自己寫 `['] (DOES1) COMPILE,`——只要寫 `CREATE ... DOES> ...` 即可，`DOES>` 會自動編譯這兩段。定義出的 defining word 是否為 IMMEDIATE 是另一回事：一般像 `CONSTANT` 這類 defining word 通常**不是** IMMEDIATE。

### 7.5 進階範例：自訂計數器

```forth
: COUNTER: ( n -- )
  CREATE ,              \ 儲存初始值
  DOES>
    DUP @               \ 讀取目前值
    SWAP 1+ SWAP !      \ 遞增
;
```

用法：

```forth
5 COUNTER: MY-COUNT
MY-COUNT .    \ 印出 5
MY-COUNT .    \ 印出 6
MY-COUNT .    \ 印出 7
```

### 7.6 初學者最常卡住的地方

**Q: DOES> 後面的程式碼什麼時候被執行？**

A: 不是定義時，是**使用時**。`DOES>` 定義的執行期行為，在每次 `name` 被呼叫時才執行。

**Q: 如果 CREATE 後面沒有 DOES> 呢？**

A: 該字的行為就像 `VARIABLE`——執行時回傳 PFA 位址。

**Q: DOES> 可以訪問 CREATE 時存的資料嗎？**

A: 可以。`DOES>` 執行時，PFA 的起始位址在堆疊頂端，所以你可以在 `DOES>` 後用 `@`、`!`、`+!` 等操作 PFA 中的資料。

---

## 8. 六個概念的關係圖

```forth
              STATE = 0
        ┌─── interpret ────────────┐
        │   逐字：執行或推數字      │
        └──────────────────────────┘

              STATE ≠ 0
        ┌─── compile ──────────────┐
        │   逐字：編譯或推常值      │
        │   IMMEDIATE 字除外       │
        │   → IMMEDIATE 無視 STATE │
        └──────────────────────────┘

        ┌─── : name ... ; ─────────┐
        │   進入編譯 → 定義字詞    │
        │   ; → 寫 RET + 回直譯   │
        └──────────────────────────┘

        ┌─── POSTPONE name ────────┐
        │   編譯期：把 name 的      │
        │   編譯語意打包            │
        │   → 執行期才真正編譯 name│
        └──────────────────────────┘

        ┌─── COMPILE, xt ──────────┐
        │   執行期（或編譯期）：    │
        │   在 HERE 寫入 CALL xt   │
        │   = 最底層的編譯原語     │
        └──────────────────────────┘

        ┌─── CREATE ... DOES> ─────┐
        │   CREATE: 建立字典項      │
        │   DOES>: 自訂執行行為    │
        └──────────────────────────┘
```

---

## 9. 從 `INTERPRET` 角度看整個分派

前面各節分別介紹 `STATE`、`IMMEDIATE`、`POSTPONE`、`COMPILE,`。真正讀原始碼時，最好把它們合成一個問題：**`INTERPRET` 每讀到一個 token，到底要執行、編譯，還是當成數字？**

可以用這張決策表記住：

| 條件 | 直譯模式 `STATE = 0` | 編譯模式 `STATE ≠ 0` |
|------|----------------------|------------------------|
| 找到一般字 | `EXECUTE` | `COMPILE,` |
| 找到 `IMMEDIATE` 字 | `EXECUTE` | `EXECUTE` |
| 找不到但可解析成數字 | push literal value | 編譯 literal |
| 找不到且不是數字 | `NOTFOUND` / `THROW` | `NOTFOUND` / `THROW` |

對 `: DOUBLE DUP + ;` 逐 token 追蹤：

| token | 讀取時 `STATE` | token 類型 | 動作 | 字典變化 |
|-------|----------------|-----------|------|----------|
| `:` | 0 | defining word / immediate | 執行 `:` | 建立新 header，`STATE` 開啟 |
| `DOUBLE` | 由 `:` 消耗 | 名稱 token | 作為新字名 | 寫入 NFA/LFA/CFA 起點 |
| `DUP` | 非 0 | 一般字 | `COMPILE, DUP` | 寫入 call/inline 片段 |
| `+` | 非 0 | 一般字 | `COMPILE, +` | 寫入 call/inline 片段 |
| `;` | 非 0 | immediate | 執行 `;` | 編入 `EXIT`，解除隱藏，`STATE` 關閉 |

這就是 Forth「編譯器是直譯器的一部分」的具體含義：沒有另一個獨立 compiler pass；同一個 `INTERPRET` 迴圈根據 `STATE` 和 immediate flag 改變行為。

### 9.1 `COMPILE`、`COMPILE,`、`POSTPONE` 的差別

這三個名字相近但層級不同：

| 名稱 | 接收什麼 | 何時用 | 直覺理解 |
|------|----------|--------|----------|
| `COMPILE,` | XT | 編譯期或執行期都可 | 「把這個 XT 的執行語意寫到 HERE」 |
| `COMPILE` | 通常跟在字後使用 | 舊式定義字/編譯控制 | 「把下一個字的編譯動作塞進目前定義」 |
| `POSTPONE` | 後面跟一個 word name | 定義 immediate wrapper | 「推遲後面那個字的編譯語意」 |

現代 ANS Forth 寫法通常偏好 `POSTPONE`，因為它能正確處理 immediate 與 non-immediate 字的差異。讀 SP-Forth 舊碼時若看到 `COMPILE` 或 `[COMPILE]`，要先問：它是在強制編譯一個 immediate word，還是在建立一個會於未來編譯的 wrapper？

### 9.2 `HIDE` / `SMUDGE`：為什麼未完成定義暫時找不到？

定義新字時，SP-Forth 會讓正在編譯的字暫時不可被搜尋到。原因是避免這種未完成定義被錯誤呼叫：

```forth
: broken  broken ;  \ 若未隱藏，可能在定義尚未完成時找到自己
```

這裡的重點不是「禁止遞迴」；真正遞迴通常要用 `RECURSE` 或明確機制。`HIDE` / `SMUDGE` 的目的是防止半成品 header 被 search engine 當成完整 word。讀 [02-compiler.md](02-compiler.md) 的 search-order 與 `SHEADER` 時，若某個字「明明剛建立卻找不到」，要先檢查是否仍處於 hidden/smudged 狀態。

### 9.3 `:NONAME`：沒有名字的 colon definition

`: name ... ;` 會建立有名字的字典項；`:NONAME ... ;` 則建立匿名定義，通常回傳 XT。概念上：

```forth
:NONAME 1 2 + ;  \ -- xt
```

適合用在：

- callback / event handler table。
- `VECT` / deferred behavior 的初始化。
- 測試中臨時建立一段可 `EXECUTE` 的程式。

它能幫助理解一件事：Forth 的核心單位不是「名字」，而是 **execution token（XT）**。名字只是讓 search-order 找到 XT 的一種索引。

### 9.4 `CREATE ... DOES>` 的記憶體視角

`CREATE ... DOES>` 最容易混淆，因為它同時牽涉「定義字本身」與「被定義出來的新字」。可以用兩層字典項看：

```text
定義字 CONSTANT 的字典項
┌──── name: CONSTANT ────┐
│ CFA: colon body        │
│ body: CREATE , DOES> @ │
└────────────────────────┘

被 CONSTANT 建出的 answer
┌──── name: answer ──────┐
│ CFA: (DOES2) / does-code│  ← 執行 answer 時會跑 DOES> 後的行為
│ PFA: 42                │  ← CREATE / , 存入的資料
└────────────────────────┘
```

因此 `DOES>` 後的程式碼不是在 `CONSTANT` 被定義時執行，也不是在 `42 CONSTANT answer` 的每一步都執行；它是 **answer 日後被呼叫時的執行期行為**。

---

## 10. 常見誤讀與排查

| 現象 | 常見誤讀 | 正確排查 |
|------|----------|----------|
| immediate word 在 `:` 裡「沒有被編進去」 | 以為 compiler 漏編 | immediate 本來就會在編譯期執行 |
| `POSTPONE IF` 不等於 `['] IF COMPILE,` 的直覺結果 | 把 interpret 語意和 compile 語意混在一起 | 看它推遲的是「編譯語意」 |
| 新定義中途找不到自己 | 以為 search-order 壞掉 | 檢查 `HIDE` / `SMUDGE` |
| `COMPILE,` 在執行期改變字典 | 以為只有 compiler 能寫 code | Forth 允許執行期生成/修改定義 |
| `DOES>` 後的程式碼執行時機混亂 | 以為在 `CREATE` 時立即執行 | 實際是在被建立的字日後被呼叫時執行 |

---

## 11. 總結對照

| 概念 | 一句話 | SP-Forth 原始碼位置 |
|------|--------|-------------------|
| `STATE` | 決定目前是直譯還是編譯 | `spf_translate.f:10`（USER 變數） |
| `[`/`]` | 手動切換 STATE | `spf_translate.f` |
| `:`/`;` | 定義字詞的標準方式 | `spf_defwords.f`（`:`）/ `spf_immed_transl.f`（`;`） |
| `IMMEDIATE` | 編譯模式下仍立即執行的記號 | `spf_wordlist.f:240`（用 `&IMMEDIATE` = bit 0 設旗標） |
| `POSTPONE` | 推遲字的編譯語意到執行期 | `spf_immed_transl.f` |
| `COMPILE,` | 在當前字典位置編譯一個 XT | `spf_compile.f` |
| `CREATE` | 建立字典項 | `spf_defwords.f` |
| `DOES>` | 自訂執行期行為的機制 | `spf_defwords.f`（`(DOES1)`/`(DOES2)`） |

---

## 12. 下一步

讀完本章後，你應該能看懂 Forth 原始碼中哪些是編譯期邏輯、哪些是執行期邏輯。接下來可進入：

- [02-compiler.md](02-compiler.md) — 完整的編譯器子系統 trace，大量使用上述概念
- [03-cross-compiler.md](03-cross-compiler.md) — 交叉編譯器，是上述技巧的進階應用
- [10-quick-ref.md §9](10-quick-ref.md#9-forth-基礎概念速查給初學者) — Forth 基礎速查（簡短版）
