# SP-Forth/4 原始碼追蹤 — `lib/` 使用索引與可跑範例

> 定位：本章是 [16-lib.md](file:///Users/wenij/work/forth/spf/docs/trace/16-lib.md) 的配套 cookbook。
> 主章負責說明 `lib/` 的角色、`spf4` / `spf4e` build flow 與載入策略；本章則回答「我想直接用 `lib/` 的某個 word / 某個檔案，怎麼載、怎麼用、有什麼前提」。

---

## 1. 使用前先確認的事

`lib/` 與 `ac-lib3/` / `devel/` 不同，它是 **`spf4e` 的核心補齊層**。也就是說：

| 檢查點 | 原因 |
|--------|------|
| 你是在 `spf4` 還是 `spf4e` | `spf4e` 已經內建大部分 `lib/include/ansi.f` 與 `lib/ext/spf4e.f` 的內容；在純 `spf4` 下則要手動 include |
| 是否已載入 `lib/include/ansi.f` | `CASE` / `DEFER` / `INCLUDE` / `BIN` / `FILE-STATUS` 等 convenience 主要由 `ansi.f` 串起來 |
| 平台是 POSIX 還是 Windows | `lib/posix/` 與 `lib/win/` 會走不同實作；名稱可能相同、行為不同 |
| 你要的是「基礎補齊」還是「大型工具箱」 | 如果需求是 registry / COM / ODBC / regex / MIME / template string，多半還是要回 [17-ac-lib3-cookbook.md](file:///Users/wenij/work/forth/spf/docs/trace/17-ac-lib3-cookbook.md) |

最保守的做法：

```forth
S" lib/ext/spf4e.f" INCLUDED
```

這樣可以在 `spf4` 上手動補齊出接近 `spf4e` 的行為。

---

## 2. `lib/include/` 可跑範例

### 2.1 `control-case.f` — `CASE` / `OF` / `ENDOF` / `ENDCASE`

Forth-2012 的 `CASE` 直接編譯期展開，沒有 run-time overhead：

```forth
REQUIRE CASE lib/include/control-case.f

: WEEKDAY-NAME ( n -- c-addr u )
  CASE
    1 OF S" Monday"    ENDOF
    2 OF S" Tuesday"   ENDOF
    3 OF S" Wednesday" ENDOF
    4 OF S" Thursday"  ENDOF
    5 OF S" Friday"    ENDOF
    6 OF S" Saturday"  ENDOF
    7 OF S" Sunday"    ENDOF
    ( default ) S" ???"  \ 都不 match 時的後備
  ENDCASE
;

3 WEEKDAY-NAME TYPE CR   \ 印出 Wednesday
0 WEEKDAY-NAME TYPE CR   \ 印出 ???
```

`?OF` 是 `OFT` 的同義詞，行為類似「else-if 條件」：

```forth
: CLASSIFY ( n -- )
  CASE
    DUP 0<       OF ." negative" ENDOF
    DUP 100 >    OF ." large"    ENDOF
    DUP 50  >=   OF ." medium"   ENDOF
    ." small"
  ENDCASE
;
```

### 2.2 `string.f` — `/STRING` / `BLANK`

`/STRING` 從字串前/後推進/縮短指標，常用於解析參數、讀檔 line 切割；`BLANK` 寫入空白字元：

```forth
REQUIRE /STRING lib/include/string.f

\ 把 "key=value" 切成 key / value
: SPLIT-EQ ( c-addr u -- key-addr key-u val-addr val-u )
  2DUP [CHAR] = SCAN  ( c-addr u c-addr2 u2 )
  DUP >R            \ 暫存 = 後面剩餘的長度
  2SWAP DROP        \ 丟掉 key 末尾之後到 = 的部分
  2 PICK R@ -       \ 計算 key 長度
  R>                \ 恢復 val 長度
;

S" name=Alice" SPLIT-EQ
\ Stack: ( name 4 Alice 5 )
```

`BLANK` 適合把 buffer 預先清成空白再填入：

```forth
CREATE LINE-BUF  80 CHARS ALLOT
LINE-BUF 80 BLANK
S" Hello" LINE-BUF SWAP CMOVE
LINE-BUF 80 TYPE CR
```

### 2.3 `core-ext.f` — `.R` / `MARKER` / `0>`

`.R` 是固定寬度右對齊輸出，常用於印表格：

```forth
: .TABLE-ROW ( n1 n2 n3 -- )
  10 .R ."  | " 12 .R ."  | "  8 .R CR
;

1 234 56789 .TABLE-ROW
\ 印出:          1  |          234  |    56789
```

`MARKER` 用來「記住目前 dictionary 範圍」，之後呼叫一次 marker 即可釋放中間定義過的 word：

```forth
: LOAD-EXPERIMENT ( -- )
  S" lib/include/quotations.f" INCLUDED
  MY-WORD1
  MY-WORD2
;
: UNLOAD-EXPERIMENT ( -- )
  EXPERIMENT-MARKER
;
EXPERIMENT-MARKER
\ 之後 LOAD-EXPERIMENT 定義的 MY-WORD1/MY-WORD2 都會消失
```

`0>` 是 `0 >` 的具名版本，常用於型別 guard：

```forth
: REQUIRE-POSITIVE ( n -- n )
  DUP 0> IF EXIT THEN
  S" expected positive" ABORT" "
;
```

### 2.4 `facil.f` — `TIME&DATE` / `ms@` / `MS`

`TIME&DATE` 回傳 6 個值（sec min hour day month year），`ms@` 是 millisecond 計數器，`MS` 是暫停 N 毫秒：

```forth
REQUIRE TIME&DATE lib/include/facil.f

: PRINT-NOW ( -- )
  TIME&DATE
  >R >R >R >R        \ 暫存 sec..month
  ." " . ." /" . ." /" .      \ 印出年/月/日
  R> R> R> R>         \ 取回 hour..sec
  ."  " . ." :" . ." :" . CR  \ 印出時:分:秒
;

: BENCHMARK ( xt -- ms )
  ms@ >R  EXECUTE  ms@ R> -
;

: WAIT-1SEC  1000 MS ;
```

### 2.5 `defer.f` — `DEFER` / `IS` / `ACTION-OF` / `DEFER@` / `DEFER!`

`DEFER` 建立可在執行期換掉行為的 word；`IS`（即 `TO`）用來設定，`ACTION-OF` 取出目前行為：

```forth
REQUIRE DEFER lib/include/defer.f

DEFER GREETING
: HELLO    ." Hello!" CR ;
: BONJOUR  ." Bonjour!" CR ;

: FRENCH-MODE  ['] BONJOUR IS GREETING ;
: ENGLISH-MODE ['] HELLO   IS GREETING ;

FRENCH-MODE  GREETING    \ Bonjour!
ENGLISH-MODE GREETING    \ Hello!

ACTION-OF GREETING . CR   \ 印出 HELLO 的 xt
```

`DEFER@` / `DEFER!` 是 explicit 版本，適合把 xt 存進變數或 table：

```forth
DEFER MY-CALLBACK
: SLOT1 ['] HELLO DEFER! MY-CALLBACK ;
SLOT1  MY-CALLBACK       \ Hello!
```

### 2.6 `tools.f` — `[IF] / AHEAD / .S`

`[IF] / [ELSE] / [THEN]` 是條件編譯。`tools.f` 的版本會跟著系統 case-sensitivity 走（`spf4e` 下用 `caseins.f` 的規則）：

```forth
REQUIRE [IF] lib/include/tools.f

[DEFINED] WINAPI: [IF]
: HOST-OS S" Windows" ;
[ELSE]
: HOST-OS S" POSIX" ;
[THEN]

HOST-OS TYPE CR
```

`AHEAD` 是「無條件向前跳」，等於 `ELSE` 的單邊版本：

```forth
: TEST-AHEAD ( flag -- )
  IF  AHEAD  ." no" THEN
  ." yes" CR
;
```

`.S` 直接把目前 stack 印出來（深度與值），比手寫 `DUP .` 方便：

```forth
1 2 3 .S      \ <3> 1 2 3
4 5 .S        \ <5> 1 2 3 4 5
DROP DROP DROP DROP DROP .S  \ <0>
```

### 2.7 `wordlist-tools.f` — `NAME>INTERPRET` / `NAME>COMPILE` / `TRAVERSE-WORDLIST`

這組用於在 runtime 走訪 / 取用 dictionary 內的 name token：

```forth
REQUIRE NAME>COMPILE lib/include/wordlist-tools.f

: PRINT-COMPILERS ( -- )
  S" compiler" TRAVERSE-WORDLIST
  [: ." : " NAME>STRING TYPE CR ;]
;

: GET-COMPILE-XT ( c-addr u -- xt | 0 )
  FIND NIP DUP IF NAME>COMPILE NIP THEN ;
```

### 2.8 `quotations.f` — `[: ... ;]`

`[: ... ;]` 是 Forth-2012 風格的 quotation（lambda），回傳可重複執行的 xt：

```forth
REQUIRE [: lib/include/quotations.f

: APPLY3 ( xt -- )
  DUP EXECUTE  DUP EXECUTE  EXECUTE ;

: SQUARE ( n -- n^2 ) DUP * ;
: CUBE   ( n -- n^2*n ) DUP SQUARE * ;

' SQUARE APPLY3   \ 三次執行 SQUARE（4 → 16 → 256 → 65536）
DROP
```

> 注意：`locals.f` 的 `{ ... }` local 變數目前不相容 quotation 內部（兩者底層是不同 frame 機制）；要兩者並用時可改用 stack。

### 2.9 `double.f` — `2CONSTANT` / `2VARIABLE` / `2VALUE` / `D.R`

`double.f` 處理的是 **double-cell integer**，不是浮點數。也就是說，一個 `d` / `ud` 會佔 **兩個 cell**，仍然走一般 data stack。

它最常出現於三種情境：

1. **超過單一 cell 範圍的整數**
2. **檔案大小 / offset**（例如 `FILE-SIZE`、`REPOSITION-FILE`）
3. **數值格式化**（`<# # #S #>` 與 `D.R` / `D.`）

`2CONSTANT` 與 `2VARIABLE` 對應 ANS Forth 的 double-cell 數值：

```forth
REQUIRE D0< lib/include/double.f

2CONSTANT PI-APPROX
\ PI ≈ 3.14159265358979323846
\ 取前 16 位有效數字：3 141592653589793 2CONSTANT PI

2VARIABLE COUNTER
0. COUNTER 2!

: BUMP-COUNTER ( -- )  COUNTER 2@ 1. D+ COUNTER 2! ;
: SHOW-COUNTER ( -- )  COUNTER 2@ D. CR ;

BUMP-COUNTER BUMP-COUNTER
SHOW-COUNTER
```

若你只是從 single-cell 整數升級成 double-cell，先用 `S>D`：

```forth
123456 S>D D. CR     \ 印出 123456
-1 S>D D0< . CR      \ -1 (true)
```

`2VALUE` 是 double-cell 版的可改值變數（要 `TO` 設定）：

```forth
1000. 2VALUE LIMIT-D
LIMIT-D D. CR

2000. TO LIMIT-D
LIMIT-D D. CR
```

`D.R` 與 `.R` 類似但處理 double-cell：

```forth
12345678901234. 20 D.R
\ 印出右對齊到 20 字元的 double-cell 數字
```

幾個常用的 double 運算：

```forth
10. 20. D+ D. CR      \ 30
10. 20. DMAX D. CR    \ 20
10. 20. DMIN D. CR    \ 10
100. 5 M+ D. CR       \ 105
```

> `S>D` 是把 single-cell 整數 sign-extend 成 double-cell；如果你處理的是 unsigned 值，常見做法是 `0 SWAP` 組成 `ud`，而不是直接 `S>D`。

### 2.10 `float2.f` — `FCONSTANT` / `F.` / `FS.`

`float2.f` 補齊 SP-Forth 的浮點延伸。和 `double.f` 最大的差異是：

- `double.f` = 兩個 cell 的 **整數**
- `float2.f` = 放在 **獨立 floating-point stack** 的實數

因此 stack comment 會寫成：

```text
( F: r1 -- r2 )
```

這表示它不是吃一般 data stack 的 `n` / `u` / `d`，而是吃 float stack 上的 `r`。

`spf4e` 透過 `FCONSTANT` 自動引入：

```forth
REQUIRE FCONSTANT lib/include/float2.f

FCONSTANT PI2  3.141592653589793e
FCONSTANT E    2.718281828459045e

: CIRCUMFERENCE ( r -- )  2e F* PI2 F* FS. CR ;
1.5e CIRCUMFERENCE        \ 9.4247...
```

若需要可修改的 float 值，用 `FVARIABLE` / `FVALUE`：

```forth
REQUIRE FCONSTANT lib/include/float2.f

FVARIABLE TEMPERATURE
36.5e TEMPERATURE F!
TEMPERATURE F@ F. CR

1.6180339887e FVALUE GOLDEN
GOLDEN F. CR

1.4142135623e TO GOLDEN
GOLDEN FS. CR
```

`float2.f` 裡還補了 rounding 類工具，很適合做量測值與 UI 輸出：

```forth
2.9e FLOOR  F. CR     \ 2.000000
2.1e FROUND F. CR     \ 2.000000
2.9e FROUND F. CR     \ 3.000000
```

幾個實戰上很常見的範例：

```forth
\ 平均值
: AVG2 ( F: r1 r2 -- r3 )  F+ 2e F/ ;
10e 14e AVG2 FS. CR        \ 12

\ 攝氏轉華氏
: C>F ( F: c -- f )  9e F* 5e F/ 32e F+ ;
25e C>F F. CR

\ 圓面積
: CIRCLE-AREA ( F: r -- area )  DUP F* PI2 F* ;
3e CIRCLE-AREA F. CR
```

從外部知識角度理解，這裡的 `double precision` 指的是 IEEE 754 類型的 64-bit 浮點表示：

- 1 bit sign
- 11 bits exponent
- 52 bits fraction（有效精度約 15~17 位十進位數）

所以：

- 金額、計數、檔案 offset 這類需要 **精確整數** 的資料，不要用 float，改用 `double.f`
- 幾何、比例、平均值、量測值這類接受誤差的資料，才用 `float2.f`

> `F.` / `FS.` 是 day 9.03.2005 加入的高階輸出；`F.` 預設 6 位、`FS.` 採整數表示法。`REPRESENT` 與底層 pad 由 `~yGREK` 重構。對應 Forth 標準語意上，`FCONSTANT` / `FVARIABLE` / `FVALUE` 都屬於 optional floating-point word set。 

### 2.11 對齊（alignment）與 float / double 的記憶體配置

SP-Forth 在 compiler 端提供一般 data 的 `ALIGN` / `ALIGNED`，而 `float2.f` 另外補了浮點專用的 `FALIGN` / `FALIGNED`。實務上你只要記住：

- 存 cell / double-cell 整數 → `ALIGN`
- 存 float → `FALIGN`
- 直接用 `2VARIABLE` / `FVARIABLE` 時，library 已幫你處理好

最小示範：

```forth
HERE . CR
1 C,              \ 故意放 1 byte，打亂對齊
HERE . CR
ALIGN
HERE . CR         \ 現在回到 cell 對齊
```

浮點對齊示範：

```forth
REQUIRE FCONSTANT lib/include/float2.f

HERE . CR
1 C,
HERE . CR
FALIGN
HERE . CR         \ 現在回到 float 對齊
```

若你只是需要一個可存取的浮點位置，直接用 `FVARIABLE` 最穩：

```forth
FVARIABLE SCALE
1.25e SCALE F!
SCALE F@ F. CR
```

### 2.12 `DEFER` / `[: ... ;]` / `locals` 的相容性陷阱

這三組機制常被初學者混在一起，但它們解的問題不同：

| 機制 | 真正用途 | 典型誤用 |
|------|----------|----------|
| `DEFER` / `IS` / `ACTION-OF` | 換掉行為入口 | 拿來當匿名函式 |
| `[: ... ;]` | 產生匿名 xt | 拿來當可變 callback slot |
| `lib/ext/locals.f` 的 `{ ... }` | 讓 stack 變可讀 | 嘗試放進 quotation 內 |

`DEFER` 正確用法：callback slot / strategy pattern

```forth
REQUIRE DEFER lib/include/defer.f

DEFER RENDER
: TEXT-MODE  ." text" CR ;
: JSON-MODE  ." json" CR ;

['] TEXT-MODE IS RENDER
RENDER
['] JSON-MODE IS RENDER
RENDER
```

quotation 正確用法：產生可傳遞的匿名 xt

```forth
REQUIRE [: lib/include/quotations.f

: APPLY ( xt -- ) EXECUTE ;
[:  2 3 + . ;] APPLY
```

**不要這樣做**：

```forth
\ 概念上錯誤：locals 與 quotation 混用
\ : BAD { x -- }
\   [: x . ;] EXECUTE
\ ;
```

原因不是語法漂亮不漂亮，而是 `locals` 與 `quotation` 都會建立自己的 frame；目前 `lib/ext/locals.f` 明說不相容這種疊法。

### 2.13 `ansi.f` 補齊的 convenience — `INCLUDE` / `BIN` / `FILE-STATUS`

`ansi.f` 除了把上述 include 串起來，還順便補上幾個常見的便利 word：

```forth
REQUIRE lib/include/ansi.f

\ INCLUDE：支援解析名稱的 INCLUDED
INCLUDE my-source.f    \ 等同 S" my-source.f" INCLUDED

\ BIN：fam flag 給 file access mode 加 binary 標記（POSIX 上是 identity）
S" data.bin" R/W BIN OPEN-FILE

\ FILE-STATUS：把 FILE-EXIST 轉成標準 ( x ior ) 形式
S" data.bin" FILE-STATUS  . .   \ 0 0 表示檔案存在、無錯誤
```

---

## 3. `ansi-file.f` 實戰用法

### 3.1 行為差異：kernel 版 vs ansi 版

載入 `ansi-file.f` 之前後，`OPEN-FILE` 的語意差異：

| 項目 | 載入前（kernel） | 載入後（ansi-file） |
|------|------------------|---------------------|
| 呼叫形式 | `S" file.z" 0 OPEN-FILE`（須有 `\0`）| `S" file" R/O OPEN-FILE`（標準 form）|
| 檔名長度 | 自動截到第一個 `0` 為止 | 用 length cell，不被 `0` 截斷 |
| 內部 buffer | 無 | 動態配置 `PFILENAME`，size 隨用過的最大檔名成長 |
| `READ-FILE` 與 `WRITE-FILE` | 同樣只看 ASCIIZ | 包裝為 `c-addr u` 形式 |

> 結論：在 `spf4e` 或已 `REQUIRE lib/include/ansi.f` 的環境下，**永遠用 `c-addr u` 形式**寫檔案 I/O；kernel 內部的 ASCIIZ 形式保留是為底層相容性。

### 3.2 完整讀檔範例：行讀直到 EOF

```forth
REQUIRE ANSI-FILE lib/include/ansi.f

CREATE LINE-BUF  1024 CHARS ALLOT

: PROCESS-LINE ( c-addr u -- )  TYPE CR ;

: READ-ALL-LINES ( c-addr u -- )
  R/O OPEN-FILE THROW  ( fileid )
  BEGIN
    LINE-BUF 1024  ( c-addr maxlen )
    2 PICK READ-LINE ( c-addr u flag ior fileid )
  WHILE
    ( -- c-addr u flag ior fileid )  \ 還沒到 EOF
    ROT DROP  2SWAP 2DROP              \ 丟 flag 與 ior，剩 ( c-addr u )
    PROCESS-LINE
  REPEAT
  ( c-addr u flag ior fileid )
  2DROP 2DROP  DROP                   \ 清乾淨
  CLOSE-FILE THROW
;

S" mydata.txt" READ-ALL-LINES
```

> 為什麼 `READ-LINE` 的 stack effect 這麼長？因為它要同時回傳「已讀長度」、「是否到 EOF」、「錯誤碼」與「fileid」給後續控制流。

### 3.3 完整寫檔範例：把整段 string 一次寫入

```forth
: WRITE-STRING-TO ( c-addr u filename-c-addr filename-u -- )
  W/O CREATE-FILE THROW  ( fileid c-addr u )
  2SWAP                  ( filename-c-addr filename-u fileid c-addr u )
  WRITE-FILE THROW        ( filename-c-addr filename-u fileid ior )
  2DROP  CLOSE-FILE THROW
;

S" Hello, world!" S" greeting.txt" WRITE-STRING-TO
```

### 3.4 二進位讀寫範例

加 `BIN` flag 確保在文字 / 二進位行為可能不同的平台（如 Windows）走二進位模式：

```forth
: WRITE-BINARY ( c-addr u filename-c-addr filename-u -- )
  W/O BIN CREATE-FILE THROW  >R
  2SWAP R> WRITE-FILE THROW
  CLOSE-FILE THROW
;

\ 把 buffer 寫成 raw bytes
HERE 100  S" data.bin" WRITE-BINARY
```

### 3.5 常見錯誤與對應

| 症狀 | 原因 | 修正 |
|------|------|------|
| `OPEN-FILE` 沒讀完整檔名 | 載入 ansi 之前用 ASCIIZ 寫法 | `REQUIRE lib/include/ansi.f` |
| 寫檔出現 garbage | 沒 flush / `WRITE-FILE` 只寫部分 | loop 到 `WRITE-FILE` 全部寫完才關 |
| 跨平台 line ending 不一致 | `READ-LINE` 在 Windows 可能吃 `\r\n` | 視需求手動 `S\" \r\n"` 過濾 |
| 大檔一次讀爆 buffer | `READ-FILE` 不切 chunk | 改用 `READ-LINE` 或 loop 讀固定 size |

### 3.6 `READ-LINE` / `WRITE-FILE` / `ior` 的 stack-effect 圖解

`READ-LINE` 最容易讓人搞混，因為它把三個資訊一起回傳：

- `u2`：實際讀到幾個字元
- `flag`：是否還有更多資料（到 EOF 會是 false）
- `ior`：是否發生 I/O error

最小心智模型：

```text
( c-addr u1 fileid -- u2 flag ior )
```

讀一行時，建議照這個順序判斷：

1. 先看 `ior`
2. 再看 `flag`
3. 最後才處理 `u2`

也就是：

```forth
: SAFE-READ-LINE ( c-addr u fileid -- u2 flag )
  READ-LINE THROW         \ THROW 會先處理 ior
;
```

對 `WRITE-FILE` 也是一樣：

```text
( c-addr u fileid -- ior )
```

所以最穩的用法通常是：

```forth
S" output.txt" W/O CREATE-FILE THROW >R
S" hello" R@ WRITE-FILE THROW
R> CLOSE-FILE THROW
```

這樣每一步都把 `ior` 轉成 exception，不會留下半成功半失敗的狀態。

### 3.7 `REQUIRE` / `INCLUDE` / `find-fullname` 最小實例

假設有這個結構：

```text
demo/
  main.f
  util.f
```

`main.f`：

```forth
INCLUDE ./util.f
RUN
```

`util.f`：

```forth
: RUN  ." ok" CR ;
```

在 `spf4e` 下，`./util.f` 會相對 `main.f` 的 `source-basepath` 解析；也就是說，你從 repo 根目錄、`demo/` 目錄，甚至別的工作目錄啟動，只要 `main.f` 被正確找到，裡面的 `./util.f` 都還是會相對 `main.f` 自己找。

相對地，`REQUIRE` 更適合寫 library：

```forth
REQUIRE RUN ./util.f
```

差異是：

- `INCLUDE` / `INCLUDED`：每次都執行
- `REQUIRE`：只有 `RUN` 尚未存在時才載入

如果你在寫的是 reusable library，選 `REQUIRE`；如果你在寫的是 top-level app loader，選 `INCLUDE` 通常更直覺。

---

## 4. `lib/ext/` 可跑範例

### 4.1 `caseins.f` — 大小寫不敏感搜尋的切換

```forth
S" lib/ext/caseins.f" INCLUDED

\ 預設 ON（已透過 CASE-INS ON）
: HELLO  ." hello" CR ;
: hello  ." hello (lower)" CR ;

HELLO        \ 因為大小寫不敏感，找到第一個定義，印 hello
CASE-INS OFF
HELLO        \ case-sensitive，印 hello (lower)
CASE-INS ON  \ 切回
```

> 切回 `spf4` 風格時整個 dictionary 搜尋變嚴格；建議除非有特殊需要，否則保持 ON。

### 4.2 `disasm.f` — `SEE` 反組譯

`spf4e.f` 會把 `SEE` 暴露成 disasm-voc 內的 word；底層走 `disasm.f` 的 Intel-style 反組譯器：

```forth
S" lib/ext/disasm.f" INCLUDED

: SQUARE  DUP * ;
SEE SQUARE   \ 印出 SQUARE 的組語碼（常數 inline、呼叫 frame）
```

對於 IMMEDIATE word：

```forth
SEE IF      \ 印出 IF 的 inline 邏輯
```

### 4.3 `struct.f` — `STRUCT:` 結構定義

`STRUCT:` 會建立一個 vocabulary，把欄位名包進去，並以 offset 形式提供：

```forth
S" lib/ext/struct.f" INCLUDED

STRUCT: POINT
  CELL -- .x
  CELL -- .y
;STRUCT

\ 建立 1 個 POINT 實例
HERE  POINT /SIZE ALLOT   CONSTANT MY-POINT

\ 設定欄位
10 MY-POINT .x !
20 MY-POINT .y !

\ 取欄位
MY-POINT .x @  MY-POINT .y @  . .  \ 印 20 10

\ 也可放在 CREATE 後面
CREATE P2  POINT /SIZE ALLOT
P2 .x !
```

> 結構欄位名是 deferred 的 offset accessor，呼叫 `.x` 會編譯成「`addr + offset`」的直接碼，沒有額外 lookup overhead。

### 4.4 `vocs.f` — `VOCS` 與 `NextNFA`

`VOCS` 把目前 dictionary chain 內的 wordlist 全列出，並標示每個 wordlist 是否在某個 word 內被定義：

```forth
S" lib/ext/vocs.f" INCLUDED
VOCS   \ 印出所有 wordlist 名稱與其「is the main vocabulary / defined in ...」標記
```

`NextNFA` 是反向走訪 dictionary 的低階工具，常用於 disassembler / debugger / cross-reference：

```forth
: PRINT-DICTIONARY ( -- )
  0 NextNFA              ( nfa2 | 0 )
  BEGIN ?DUP WHILE
    DUP NAME>STRING TYPE CR
    NextNFA
  REPEAT DROP
;
```

### 4.5 `locals.f` — `{ ... -- ... }` 與 `LOCAL`

```forth
S" lib/ext/locals.f" INCLUDED

: HYPOT { a b -- c }
  a a *  b b *  F+  FSQRT  -> c
  c
;

3e 4e HYPOT FS.       \ 5.0
```

未初始化的 local 寫成 `\ name`：

```forth
: ACCUMULATE { n \ acc -- sum }
  0 -> acc
  n 0 ?DO  I  -> acc +  LOOP
  acc
;
```

> 與 `[: ... ;]` quotation **不相容**（兩者底層 frame 模型不同），混用時會編譯失敗或行為未定義。實際工作上通常選一種風格貫穿整個專案。

### 4.6 `patch.f` — `REPLACE-WORD` 直接改 hot path

`REPLACE-WORD` 在目標 word 的入口寫入 `JMP`，把呼叫 redirect 到新 word：

```forth
S" lib/ext/patch.f" INCLUDED

: ORIGINAL ( -- ) ." original" CR ;
: REPLACED ( -- ) ." replaced" CR ;

['] REPLACED ['] ORIGINAL REPLACE-WORD
ORIGINAL          \ 印 replaced

\ 還原：把 ORIGINAL 重新定義
: ORIGINAL ( -- ) ." original again" CR ;
ORIGINAL          \ 印 original again
```

> 用在 hot path instrumentation、tracing、AOP 風格的「攔截+還原」。**不要**在 production 程式碼亂用，這會破壞 dictionary 的一致性。

### 4.7 `onoff.f` — `ON` / `OFF` flag helper

```forth
S" lib/ext/onoff.f" INCLUDED

VARIABLE DEBUG?
: SET-DEBUG  TRUE DEBUG? ON ;
: CLR-DEBUG  FALSE DEBUG? OFF ;
```

> 單獨的 `lib/ext/onoff.f` 沒什麼負擔，可以當作「小工具 include」直接 INCLUDE 到自己的小專案。

### 4.8 `rnd.f` — `RANDOM` / `CHOOSE` / `RANDOMIZE`

```forth
S" lib/ext/rnd.f" INCLUDED

12345 SEED                  \ 固定 seed → 可重現的序列
10 CHOOSE                   \ 0..9 的隨機數
RANDOMIZE                   \ 用 ms@ 重新 seed

\ 模擬擲骰子
: D6  6 CHOOSE 1+ ;
: ROLL-3D6  D6 D6 D6  . . . ;
```

> 這是 LCG，不是密碼學等級的隨機。crypto / Monte Carlo 嚴肅應用請改用 `devel/~ygrek/lib/neilbawd/mersenne.f`（Mersenne Twister）。

### 4.9 `uppercase.f` — `UPPERCASE` / `CEQUAL-U` / `CHAR-UPPERCASE`

```forth
S" lib/ext/uppercase.f" INCLUDED

CREATE BUF  16 CHARS ALLOT
S" Hello, World" BUF SWAP CMOVE
BUF 12 UPPERCASE   \ 原地轉大寫
BUF 12 TYPE CR      \ HELLO, WORLD

\ 忽略大小寫比對
S" search-wordlist" S" SEARCH-WORDLIST" CEQUAL-U .  \ -1 (true)
```

`CHAR-UPPERCASE` 對超過 `0x7F` 的 byte 是 implementation-defined；純 ASCII 範圍才安全。

### 4.10 `help.f` — `***` 區塊的線上說明

`help.f` 提供 `***` / `***g:` 等 word 來收集行內 help block，並在 `HELP` 觸發時印出：

```forth
S" lib/ext/help.f" INCLUDED

: GREETING
  *** 印出 hello 並換行
  ." Hello!" CR
;
```

> 純 SP-Forth 歷史工具，新文件建議用獨立 `*.md` 加 grep，不要依賴這個機制。

### 4.11 `util.f` — `TryOpenFile` 模組 / library 路徑搜尋

`util.f` 提供「先在 cwd 找，再去 module path 找，最後去 library path 找」的 helper：

```forth
S" lib/ext/util.f" INCLUDED

S" lib/ext/caseins.f" R/O TryOpenFile
\ Stack: ( handle 0 ) 或 ( 0 ior )
\ 在 spf4 / spf4e 啟動時通常直接命中 cwd
```

這個機制解釋了為什麼在 SP-Forth 裡直接 `S" some.f" R/O OPEN-FILE` 也能成功，即使目前工作目錄不是 source 所在目錄。

### 4.12 `const.f` — 動態常數 vocabulary 機制

`lib/ext/const.f` 本身定義 `WINCONST` vocabulary 與 `SEARCH-CONST`，但**更常被引用**是因為它把常數表 `.const` 載入成可搜尋 wordlist：

```forth
\ 在 spf4e 下載入常數（lib/win/const.f 或 lib/posix/const.f 會自動執行）
S" O_RDONLY" FIND NIP 0= [IF] S" lib/posix/const/linux.const" INCLUDED [THEN]
O_RDONLY .     \ 印出 POSIX O_RDONLY 的數值
```

> 大多數使用者**不需要**直接 include `lib/ext/const.f`；`lib/win/const.f` 與 `lib/posix/const.f` 會在載入 `ansi.f` 後自動選邊帶入。

如果你想直接看它怎麼工作，可以拆成三步：

#### 4.12.1 直接查詢常數名

```forth
S" lib/ext/const.f" INCLUDED
S" lib/posix/const/linux.const" ADD-CONST-VOC

S" O_RDONLY" SEARCH-CONST . . CR
```

`SEARCH-CONST` 的回傳是：

- `u -1`：找到常數值 `u`
- `0`：找不到

也就是說，這一層還只是「字串查表」。

#### 4.12.2 真正好用的地方：掛進 `NOTFOUND`

`lib/ext/const.f` 真正厲害的地方不是 `SEARCH-CONST`，而是它改寫了 `NOTFOUND`：

1. 一般 dictionary 找不到某個名字
2. `NOTFOUND` 被觸發
3. `NOTFOUND` 再去 `ChainOfConst` 內的常數表找
4. 找到的話，就把值編譯成 literal

所以載入 `lib/win/const.f` 後你可以直接這樣寫：

```forth
S" lib/win/const.f" INCLUDED

: ACCESS-MASK ( -- u )
  GENERIC_READ GENERIC_WRITE OR
;

ACCESS-MASK . CR
```

這裡的 `GENERIC_READ` / `GENERIC_WRITE` 並不是一般 colon word，而是透過常數表 + `NOTFOUND` hook 變成可用的 literal。

#### 4.12.3 平台差異：POSIX vs Windows

POSIX：

```forth
S" lib/posix/const.f" INCLUDED
O_RDONLY . CR
O_CREAT  . CR
```

Windows：

```forth
S" lib/win/const.f" INCLUDED
GENERIC_READ    . CR
FILE_SHARE_READ . CR
```

不要混用：

- POSIX 下找 `GENERIC_READ` 不會有意義
- Windows 下找 `O_RDONLY` 也不是你想要的 API 常數語意

#### 4.12.4 何時用 `REMOVE-ALL-CONSTANTS`

`REMOVE-ALL-CONSTANTS` 會把 `ChainOfConst` 掛上的常數表全部 free 掉：

```forth
REMOVE-ALL-CONSTANTS
```

這通常只在兩種情況有用：

1. 你在同一個 session 內想重新載入另一份 `.const` 檔
2. 你在做常數表相關的測試，不想讓前一次載入結果污染下一次

---

## 5. `lib/posix/` 可跑範例

### 5.1 自動載入：`RENAME-FILE` 走 POSIX 路徑

在 `spf4e` 或 `spf4 + lib/include/ansi.f` 環境下，呼叫 `RENAME-FILE` 會走 `lib/posix/file.f`：

```forth
S" old-name.txt" S" new-name.txt" RENAME-FILE THROW
```

> 注意：`lib/posix/file.f` 的 `RENAME-FILE` 內部仍用 `( )) rename` 把 stack 直接餵給 libc `rename(2)`，所以 stack effect 與 file.f 宣告一致，但實作上會丟掉 filename length 依賴 ASCIIZ（file.f 開頭有 `.( FIXME: do not require ascii-zeroed strings!) CR` 的警告）。實務上搭配 `lib/include/ansi-file.f` 使用即可。

### 5.2 `lib/posix/key.f` 完整載入

`lib/posix/key.f` 不會被 `ansi.f` 自動載入。需要在互動模式需要即時按鍵時手動 include：

```forth
S" lib/posix/key.f" INCLUDED

\ 之後 KEY 不再阻塞等 Enter，而是立刻回傳一個字元
KEY EMIT
```

> 注意：`KEY-TERMIOS` 會把 terminal 切到 raw 模式。batch / pipe 模式（stdin 不是 tty）下會失敗或行為不確定；可用 `ISATTY?` 之類的工具先檢查。

### 5.3 POSIX 常數表

`lib/posix/const.f` 透過 `ADD-CONST-VOC` 把 `lib/posix/const/linux.const` 載入成可搜尋的 wordlist：

```forth
S" lib/posix/const.f" INCLUDED

\ 之後可直接用常數名搜尋
O_RDONLY  .        \ 印出 O_RDONLY 的數值
O_WRONLY  .        \ 印出 O_WRONLY 的數值
O_CREAT   .        \ 印出 O_CREAT 的數值
```

> 如果常數查不到，通常代表 `linux.const` 還沒重新生成（內容依賴 `/usr/include` 與核心 header）。重新生成流程參考 `lib/posix/const/` 目錄下的腳本。

### 5.4 POSIX 平台常見小工具

| 需求 | 入口 |
|------|------|
| termios 單鍵輸入 | `lib/posix/key.f` |
| 重新編譯 / 重新產生常數表 | `lib/posix/const/` |
| `O_*` / `S_*` / `PROT_*` 等旗標 | `lib/posix/const.f` 載入 `linux.const` |
| 改寫 `RENAME-FILE` 用 ASCIIZ 以外的字串 | 已內建在 `lib/posix/file.f` |

---

## 6. `lib/win/` 可跑範例

### 6.1 `lib/win/file.f` — 額外的檔案工具

`lib/win/file.f` 提供 `RENAME-FILE` / `TOEND-FILE` / `COPY-FILE` / `COPY-FILE-OVER` / `DELETE-FOLDER` 等高階檔案工具，底層呼叫 `MoveFileA` / `CopyFileA` / `RemoveDirectoryA`：

```forth
S" lib/win/file.f" INCLUDED

\ 複製（若目標存在則失敗）
S" source.txt" S" dest.txt" COPY-FILE THROW

\ 強制覆蓋（FALSE flag = bFailIfExists = FALSE）
S" source.txt" S" dest.txt" COPY-FILE-OVER THROW

\ 移到檔案末尾
S" log.txt" R/O OPEN-FILE THROW >R
R@ TOEND-FILE THROW
R> CLOSE-FILE THROW

\ 刪除空資料夾
S" empty-dir" DELETE-FOLDER THROW
```

> 若要取得絕對路徑，要用 `lib/posix/file.f` 提供的 `ExtFilePathName`（POSIX 平台限定）；Windows 版本可改呼叫 `GetFullPathNameA`（在 `ac-lib3/win/file/` 或直接 `WINAPI:` 宣告）。

### 6.2 `lib/win/mutex.f` — 跨 process 互斥

```forth
S" lib/win/mutex.f" INCLUDED

: GRAB-LOCK ( -- handle ior )
  S" my-app-lock" FALSE CREATE-MUTEX
;

: WAIT-LOCK ( handle -- ior )
  5000 SWAP WAIT         \ 5 秒逾時
;

: RELEASE-LOCK ( handle -- ior )
  RELEASE-MUTEX
;
```

典型用法：

```forth
GRAB-LOCK THROW >R
R@ WAIT-LOCK THROW
\ ... critical section ...
R> RELEASE-LOCK THROW
CLOSE-MUTEX THROW
```

> 真正應用上會把 handle 存在全域變數或物件裡；`lib/win/mutex.f` 的 API 與 Win32 的 `CreateMutexA` / `WaitForSingleObject` / `ReleaseMutex` 一一對應，呼叫順序與逾時常數請參考 MS 文件。

### 6.3 `lib/win/osver.f` — OS 版本偵測

```forth
S" lib/win/osver.f" INCLUDED

OSVER CASE
  OS_WIN95 OF ." Windows 95"     ENDOF
  OS_WIN98 OF ." Windows 98"     ENDOF
  OS_WINNT OF ." Windows NT 系"  ENDOF
  ." 未知"
ENDCASE
```

> 對現代 Windows 10/11，平台會被歸到 `OS_WINNT`；major / minor / build 仍可用 `OSVERSIONINFO` 結構 + `GetVersionExA` 進一步查，但建議改用更精確的 `RtlGetVersion` 或 WMI 查詢。

### 6.4 `lib/win/winerr.f` — `DECODE-ERROR` 與 `WTHROW`

`lib/win/winerr.f` 把 `GetLastError` 的代碼轉成可讀訊息，並把 `WIN_ERROR` 範圍的代碼塞進 `DECODE-ERROR`：

```forth
S" lib/win/winerr.f" INCLUDED

: OPEN-OR-COMPLAIN ( c-addr u -- fileid ior )
  R/W OPEN-FILE
  DUP IF  DROP  GetLastError WIN_ERROR DECODE-ERROR TYPE  THEN
;
```

> 想要 trace-level 自動 throw，可以用 `WTHROW`：它會把目前的 Windows error 拋成 Forth exception，可以被 `CATCH` 接住。

### 6.5 `lib/win/const.f` — Windows 常數表

`lib/win/const.f` 透過 `ADD-CONST-VOC` 載入 `lib/win/winconst/windows.const`，把 `ERROR_*`、`FILE_SHARE_*`、`GENERIC_*` 之類的常數變成可搜尋 word：

```forth
S" lib/win/const.f" INCLUDED

\ 載入後可這樣用
GENERIC_READ  GENERIC_WRITE  OR  .  \ 印出組合後的 access mask
```

> `windows.const` 內容來自頭文件掃描；若 Windows SDK 升級，請用 `lib/win/winconst/` 目錄下的腳本重新生成。

### 6.6 `lib/win/api-call/` — 替代 API 呼叫模型

| 檔案 | 角色 |
|------|------|
| `capi.f` | C-style API call 實驗 |
| `capi2.f` | 簡化版 C-style API call |
| `altwinapi.f` | 替代 `WINAPI:` 與 `API-CALL` 的封裝 |

除非要在 `spf4`（無 `WINAPI:`）下做 Win32 開發，否則主線仍走 [09-windows-platform.md](file:///Users/wenij/work/forth/spf/docs/trace/09-windows-platform.md) 的 `WINAPI:` / `API-CALL`。

### 6.7 最小 `WINAPI:` + 常數實例

如果你的需求只是「宣告一個 Win32 API，搭配幾個常數呼叫」，那其實 `lib/win/const.f` + 既有 `WINAPI:` 就夠了：

```forth
S" lib/win/const.f" INCLUDED

WINAPI: GetStdHandle KERNEL32.DLL

STD_OUTPUT_HANDLE GetStdHandle DROP . CR
```

另一個常見場景是把 access / share flags 組起來：

```forth
GENERIC_READ GENERIC_WRITE OR . CR
FILE_SHARE_READ FILE_SHARE_WRITE OR . CR
```

也就是說，`lib/win/const.f` 的角色不是取代 `WINAPI:`，而是讓 `WINAPI:` 宣告後面真正可用。

### 6.8 `lib/win/spfgui/` — SP-Forth GUI 支援

`spfgui` 是 SP-Forth 的傳統 GUI 工具箱雛形，包含 button、edit、list 等控制項包裝。現代 GUI 開發建議參考 `ac-lib3/win/window/`（[17-ac-lib3.md](file:///Users/wenij/work/forth/spf/docs/trace/17-ac-lib3.md)）。

---

## 7. `spf4e` 最常見載入組合

| 場景 | 推薦載入 |
|------|----------|
| 在 `spf4` 上補齊成 `spf4e` 常用能力 | `S" lib/ext/spf4e.f" INCLUDED` |
| 只要 ANS word set | `S" lib/include/ansi.f" INCLUDED` |
| 只要 quotation | `REQUIRE [: lib/include/quotations.f` |
| 只要 locals | `S" lib/ext/locals.f" INCLUDED` |
| 只要大小寫不敏感搜尋 | `S" lib/ext/caseins.f" INCLUDED` |
| 只要 Windows mutex | `S" lib/win/mutex.f" INCLUDED` |
| 只要 POSIX 即時按鍵 | `S" lib/posix/key.f" INCLUDED` |

---

## 8. `lib/` vs `ac-lib3/` 的最小依賴選擇

| 需求 | 優先選 `lib/` | 什麼時候要升級到 `ac-lib3/` |
|------|--------------|------------------------------|
| CASE / DEFER / quotation / locals | ✅ | 幾乎不用 |
| 檔案 I/O / `RENAME-FILE` / `COPY-FILE` | ✅ | 需要 Windows registry / INI 時 |
| 大小寫不敏感搜尋 / `SEE` | ✅ | 不用 |
| 字串模板 / regex / MIME |  | ✅ |
| Windows registry / COM / ODBC / Winsock |  | ✅ |
| trace / instrumentation / hot patch |  | ✅ |
| 大型作者實驗 / framework / 範例 |  | 回 [18-devel-cookbook.md](file:///Users/wenij/work/forth/spf/docs/trace/18-devel-cookbook.md) |

更完整的三方對照見 [18-devel-cookbook.md §6](file:///Users/wenij/work/forth/spf/docs/trace/18-devel-cookbook.md#6-延伸函式庫使用對照lib-vs-ac-lib3-vs-devel) 與 [17-ac-lib3-cookbook.md §7](file:///Users/wenij/work/forth/spf/docs/trace/17-ac-lib3-cookbook.md#7-與-lib-devel-的對照)。

---

## 9. 讀完後回到哪裡？

- 想理解 `lib/` 的角色、`spf4` / `spf4e` build flow 與載入策略，回 [16-lib.md](file:///Users/wenij/work/forth/spf/docs/trace/16-lib.md)。
- 想找 Windows registry / COM / Winsock / ODBC 等進階整合，回 [17-ac-lib3-cookbook.md](file:///Users/wenij/work/forth/spf/docs/trace/17-ac-lib3-cookbook.md)。
- 想找作者子樹的 prototype / framework / 大型範例，回 [18-devel-cookbook.md](file:///Users/wenij/work/forth/spf/docs/trace/18-devel-cookbook.md)。
- 想理解 `spf4` / `spf4e` 的 build 與 image save，回 [06-build-save.md](file:///Users/wenij/work/forth/spf/docs/trace/06-build-save.md) 與 [15-standalone-cookbook.md](file:///Users/wenij/work/forth/spf/docs/trace/15-standalone-cookbook.md)。
