# SP-Forth/4 原始碼追蹤 — 附錄 B：Forth 編譯模式深入理解

> 本章目標：看懂 `STATE`、`IMMEDIATE`、`POSTPONE`、`COMPILE,`、`DOES>` 如何在 SP-Forth 原始碼中運作。
>
> 閱讀定位：若你對 Forth 的**編譯與直譯雙模式**還不熟悉，建議先讀完本章再進入 [02-compiler.md](02-compiler.md) 與 [03-cross-compiler.md](03-cross-compiler.md)。

---

## 1. 為什麼需要這一章？

Forth 與多數語言最不同的地方在於：**編譯器不是獨立工具，而是執行期的一部分**。撰寫 Forth 時，你不只是在寫「執行期跑的程式」，也常是在寫「編譯期跑、用來產生程式碼的程式」。

這套 trace 文件大量使用以下術語，但 Fɔrth 初學者很容易混淆：

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

```
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

```
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
USER STATE     \ spf_forthproc.f
```

這代表不同執行緒可以有各自的編譯狀態——多執行緒編譯時，不會相互干擾。

---

## 3. `:` 與 `;` — 字詞定義

### 3.1 `: name ... ;` 的完整流程

`:` 是一個 IMMEDIATE 字。當你輸入：

```forth
: DOUBLE DUP + ;
```

`:` 做了這些事：

```
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

### 3.2 SP-Forth 的編譯器如何處理 `:`？

在 `spf_compile.f` 中，編譯 `:` 時會呼叫 `]` 進入編譯模式：

```forth
: :
  HEADER      \ 建立字典標頭
  ]           \ STATE ON → 進入編譯模式
; IMMEDIATE
```

`;` 則編譯一個 `RET` 並切回直譯模式：

```forth
: ;
  ?COMPILING       \ 確保在編譯模式中
  COMPILE EXIT     \ 編譯 RET（SP-Forth 的 EXIT = RET）
  REVEAL           \ 釋出字詞（讓後續定義可找到）
  [COMPILE] [      \ STATE OFF → 回到直譯模式
; IMMEDIATE
```

注意 SP-Forth 使用 `EXIT` 而非 `;` 的 `;S`，因為 x86 直接執行緒碼中，`;` 的最後一步就是 `RET`。

### 3.3 初學者常見問題

**Q: 為什麼 `:` 要設為 IMMEDIATE？**

A: 因為當 `:` 處於編譯模式被呼叫時，它必須「在編譯期執行」來建立新字典項並切換 STATE。如果不是 IMMEDIATE，那在另一個 `:` 定義中寫 `:` 就會被編譯成 CALL，無法開啓新定義。

---

## 4. IMMEDIATE — 立即執行

### 4.1 什麼是 IMMEDIATE？

一個字詞被標記為 `IMMEDIATE` 後，**無論 STATE 為何，都執行其 interpret 語意**。

```
直譯模式:   IMMEDIATE 字 = 執行
非 IMMEDIATE 字 = 執行

編譯模式:   IMMEDIATE 字 = 執行
非 IMMEDIATE 字 = 編譯
```

### 4.2 誰需要是 IMMEDIATE？

控制結構、定義字與編譯控制字必須是 IMMEDIATE：

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

SP-Forth 的 `IMMEDIATE` 修改字詞標頭的旗標位元：

```forth
\ spf_defkern.f
: IMMEDIATE
  >NAME                    \ 取得最近定義的 NFA
  DUP C@ 80 OR SWAP C!    \ 設定 bit 7（IMMEDIATE flag）
;
```

`80` 是 `#x80`（bit 7），後續編譯器的 `?COMPILING` 查詢此旗標來決定行為：

```forth
: ?COMPILING ( -- )
  COMPILING? 0= ABORT" compile state required"
;
```

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

`POSTPONE` 本質上等同於：

```forth
' IF COMPILE,    \ 取得 IF 的 XT，在編譯期寫入「編譯 IF」的指令
```

等一下——`' IF COMPILE,` 到底做了什麼？

讓我們一步步追：

1. `' IF` → 取得 `IF` 的 XT
2. `COMPILE,` → 在當前字典位置寫入 `CALL (COMPILE)` 加上 `IF` 的 XT

所以 `POSTPONE IF` 產生的程式碼，在執行期會：

1. 呼叫 `(COMPILE)`（Forth 的「編譯一個 XT」原語）
2. `(COMPILE)` 讀取 `IF` 的 XT 並編譯之

### 5.4 POSTPONE 在 SP-Forth 中的實作

```forth
\ spf_immed_transl.f
: POSTPONE
  '                      \ 取得後續字詞的 XT
  ?DUP IF
    DUP @ 80 AND         \ 檢查是否 IMMEDIATE
    IF
      COMPILE,           \ 非 immediate：直接編譯 CALL
    ELSE
      [COMPILE] COMPILE, \ immediate：特殊處理
    THEN
  THEN
; IMMEDIATE
```

`POSTPONE` 自己也是 IMMEDIATE——這很合理，因為你必須在**定義期**處理推遲邏輯。

### 5.5 POSTPONE 與 `[COMPILE]` 的差別

| 特性 | `POSTPONE name` | `[COMPILE] name` |
|------|-----------------|-------------------|
| 標準 | ANS Forth 94 | 舊標準（已淘汰） |
| 處理 IMMEDIATE | 推遲其編譯語意 | 在編譯期強制編譯 |
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

完整的等價關係：

| 寫法 | 編譯期產生的程式碼 | 執行期效果 |
|------|-------------------|-----------|
| `' EXECUTE` | `CALL (LIT)` + EXE XT | 執行 EXECUTE |
| `COMPILE, EXECUTE` | `CALL (COMPILE)` + EXE XT | 編譯 EXECUTE |
| `POSTPONE EXECUTE` | `CALL (COMPILE)` + EXE XT | 同上 |

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

- `(DOES1)` — 在 `CREATE` 定義時被呼叫，修改 CFA
- `(DOES2)` — 執行期的入口，負責轉到 `DOES>` 定義的程式碼

```forth
\ spf_defwords.f
: (DOES1) ( -- )
  R>            \ 取得返回位址（也就是 DOES> 後的程式碼位址）
  LATEST NAME>  \ 取得最新定義的字典項
  DUP >NAME     \ NFA
  DUP CFALFA    \ 目前的 CFA
  !             \ 把 DOES> 後的程式碼位址寫入 CFA
;

: (DOES2) ( -- )
  >R            \ 把 PFA 推到回返堆疊
  R>            \ 取出執行
  EXECUTE       \ 執行 DOES> 定義的行為
;
```

所以 `DOES>` 當編譯時：

```forth
: CONSTANT
  CREATE ,
  ['] (DOES1) COMPILE,   \ 編譯 (DOES1) 呼叫
  DOES>                   \ DOES> 本身是 IMMEDIATE
  @                       \ 這之後的程式碼被 (DOES1) 記錄下來
; IMMEDIATE
```

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

```
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

## 9. 總結對照

| 概念 | 一句話 | SP-Forth 原始碼位置 |
|------|--------|-------------------|
| `STATE` | 決定目前是直譯還是編譯 | `spf_forthproc.f`（USER 變數） |
| `[`/`]` | 手動切換 STATE | `spf_translate.f` |
| `:`/`;` | 定義字詞的標準方式 | `spf_defwords.f` / `spf_compile.f` |
| `IMMEDIATE` | 編譯模式下仍立即執行的記號 | `spf_defkern.f`（設定 flag） |
| `POSTPONE` | 推遲字的編譯語意到執行期 | `spf_immed_transl.f` |
| `COMPILE,` | 在當前字典位置編譯一個 XT | `spf_compile.f` |
| `CREATE` | 建立字典項 | `spf_defwords.f` |
| `DOES>` | 自訂執行期行為的機制 | `spf_defwords.f`（`(DOES1)`/`(DOES2)`） |

---

## 10. 下一步

讀完本章後，你應該能看懂 Forth 原始碼中哪些是編譯期邏輯、哪些是執行期邏輯。接下來可進入：

- [02-compiler.md](02-compiler.md) — 完整的編譯器子系統 trace，大量使用上述概念
- [03-cross-compiler.md](03-cross-compiler.md) — 交叉編譯器，是上述技巧的進階應用
- [10-quick-ref.md §8](10-quick-ref.md#8-forth-基礎概念速查給初學者) — Forth 基礎速查（簡短版）
