# SP-Forth/4 原始碼追蹤 — 編譯器子系統深入解析

> 本章目標：看懂 token 如何被剖析、字詞如何被搜尋、編譯器如何決定要 CALL、內聯還是摺疊常數。
> 
> 對應原始碼：`src/compiler/` 目錄下所有檔案
> 原始碼版權：Copyright [C] 1992-1999 A.Cherezov ac@forth.org

---

## 1. 編譯器架構概覽

### 1.1 Forth 編譯器的獨特本質

Forth 的編譯器與傳統編譯器有根本性的不同。在 C 或 Java 等語言中，編譯器是一個獨立的前端工具，先將原始碼轉成中介表示，再經過最佳化與代码產生階段。但 Forth 的編譯器是**直譯器的一部分**——它是在直譯循環（interpret loop）中被條件性地啟動的功能模組。

SP-Forth 的編譯流程遵循以下核心概念：

- **狀態驅動**：`STATE` 變數決定目前處於直譯模式（`STATE = 0`）或編譯模式（`STATE = -1`，在 Forth 中任何非零值皆代表「真」）
- **立即字**（IMMEDIATE）：即使在編譯模式下也會被立即執行的字，用於在編譯期間產生控制結構代碼（如 `IF`、`THEN`、`DO`、`LOOP` 等）
- **執行緒式碼**（Threaded Code）：SP-Forth 使用 x86 直接執行緒式碼（direct-threaded code），每個編譯的呼叫點就是一條 `CALL` 指令

### 1.2 編譯器模組載入順序與職責

```
spf_parser.f        ← 語法剖析（NextWord, PARSE, SkipDelimiters 等）
spf_read_source.f   ← 原始碼讀取（REFILL, SOURCE, INCLUDED 等）
spf_nonopt.f        ← 非最佳化字集（RDROP, >R, R>, EXECUTE 等）
spf_compile0.f      ← 基本編譯控制（DP, ALLOT, ,, C, 等）
→ [macroopt.f 或 noopt.f]  ← 巨集最佳化器
spf_compile.f       ← 主要編譯器（COMPILE,, HERE, BRANCH,；透過 CON>LIT/INLINE? hook 接上最佳化器）
spf_wordlist.f      ← 詞彙表管理（WORDLIST, SEARCH-WORDLIST, +SWORD, 名稱存取等）
spf_find.f          ← 搜尋引擎（SFIND, FIND1, CDR-BY-NAME, 搜尋順序等）
spf_find_cdr.f      ← CDR-BY-NAME 組合語言最佳化版本（由 spf_find.f 內部 `INCLUDED`）
spf_words.f         ← 定義輔助（NLIST, WORDS 列舉）
spf_error.f         ← 錯誤處理（SAVE-ERR, PRINT-LAST-WORD, ERR-DATA 結構）
spf_translate.f     ← 直譯器核心（INTERPRET, QUIT, EVALUATE, INCLUDED, REQUIRE）
spf_defwords.f      ← 定義字定義（SHEADER, HEADER, CREATE, VARIABLE, CONSTANT, VALUE, DOES> 等）
spf_immed_transl.f  ← 立即字 — 直譯分支（TO, POSTPONE, ;, EXIT, [COMPILE] 等）
spf_immed_lit.f     ← 立即字 — 常值分支（LITERAL, 2LITERAL, SLITERAL, S", .", ABORT" 等）
spf_literal.f       ← 常值編譯（?SLITERAL1, ?LITERAL1, HEX-SLITERAL, ?SLITERAL2）
spf_immed_control.f ← 控制結構立即字（IF/THEN/ELSE/WHILE/REPEAT/BEGIN/UNTIL/AGAIN）
spf_immed_loop.f    ← 迴圈立即字（DO/LOOP/+LOOP/I/J/UNLOOP/LEAVE/?DO）
spf_modules.f       ← 模組載入（MODULE:, EXPORT, ;MODULE, {{, }}）
spf_inline.f         ← 內聯展開（>R, R>, RDROP, ?DUP, EXECUTE 的內聯版本）
```

模組之間的依賴關係可以概括為：**語法剖析器 → 搜尋引擎 → 直譯器 → 編譯器/常值編譯 → 控制結構/迴圈**。這是一種自舉（bootstrapping）的過程——早期的模組以最簡形式定義，後來的模組利用之前建立的基礎設施來構建更複雜的功能。

### 1.3 範例：`: SQUARE DUP * ;` 會經過哪些模組？

若你只想先抓住編譯器的主線，可以先看這個最小例子：

```forth
: SQUARE DUP * ;
```

它在 SP-Forth 中大致會經過以下路徑：

1. `spf_parser.f`：將 `:`, `SQUARE`, `DUP`, `*`, `;` 逐一切成 token。
2. `spf_defwords.f`：`:` 透過 `HEADER` / `HIDE` 建立新定義並切入編譯狀態。
3. `spf_find.f`：`DUP` 與 `*` 經 `SFIND` 在搜尋順序中解析成既有字詞。
4. `spf_compile.f`：`COMPILE,` / `_COMPILE,` 決定要產生一般 `CALL`，還是交給最佳化器做常值摺疊或內聯。
5. `spf_immed_transl.f`：`;` 結束定義、補上收尾碼並解除隱藏。

後續若你想看「這些 CALL 在 target 映像中長什麼樣」，再接到 [03-cross-compiler.md](03-cross-compiler.md)；若你想看 `MCOMPILE,` / `CON>LIT` / `INLINE?` 怎麼進一步改寫這條路徑，則接著讀 [07-optimizer.md](07-optimizer.md)。

若你想先看完整決策樹再深入細節，可先跳到 [§17](#17-編譯器整體流程圖) 看 INTERPRET 迴圈流程圖。

---

## 2. 語法剖析器（spf_parser.f）深入解析

### 2.1 輸入流管理模型

Forth 的輸入模型是基於**輸入緩衝區**（Terminal Input Buffer, TIB）的概念。SP-Forth 的輸入流管理設計體現在三個核心 USER 變數的互動：

```forth
\ spf_parser.f:9-26
USER #TIB    \ 輸入緩衝區字元數（行長度）
USER >IN     \ 輸入流偏移量（目前解析位置）
USER-VALUE TIB  \ 輸入緩衝區起始位址
```

**關鍵設計特點**：

1. `TIB` 是 `USER-VALUE` 而非 `USER`——這表示 `TIB` 是一個可重定向的值（可透過 `TO` 修改），而非固定位址。這讓 EVALUATE 和檔案載入可以切換不同的輸入來源，而無需拷貝資料。

2. `ATIB` 是一個 2048 位元組（`C/L + 2 = 1026` 的兩倍，向上取整）的 `USER-CREATE` 緩衝區，作為 TIB 的預設儲存空間。當從終端機讀取時，資料存放在 ATIB 中。

3. `C/L`（Chars per Line）設為 1024，但實際上 REFILL-STDIN 只讀取 `C/L` 個字元，多餘的空間用於安全裕度。

### 2.2 SOURCE 與 SOURCE! 的協作

```forth
\ spf_parser.f:27-34
: SOURCE ( -- c-addr u )   TIB #TIB @  ;
: SOURCE! ( c-addr u -- )  #TIB ! TO TIB >IN 0!  ;
```

`SOURCE` 回傳目前的輸入緩衝區起始位址與長度。`SOURCE!` 則設定新的輸入來源，同時重設 `>IN` 為零——這是一個重要的細節：**切換輸入來源時，解析位置永遠重頭開始**。

### 2.3 解析核心：SkipDelimiters → ParseWord → NextWord

整個剖析流程可以分解為三個階段：

```
NextWord = SkipDelimiters + ParseWord + 邊界校正
         ┌──────────┐     ┌──────────┐     ┌───────────┐
輸入流 → │ 跳過空白 │ ──→ │ 解析字詞 │ ──→ │ 校正 >IN  │
         └──────────┘     └──────────┘     └───────────┘
```

**SkipDelimiters**（第 64~69 行）：

```forth
: SkipDelimiters ( -- )
  BEGIN OnDelimiter WHILE >IN 1+! REPEAT ;
```

迴圈地跳過所有 `IsDelimiter` 為真的字元。`IsDelimiter` 的預設實作 `IsDelimiter1` 定義為 `BL 1+ <`，即所有 ASCII 碼小於或等於空白（值 32）的字元都是分隔字元——這包含了空白、Tab、換行、歸位等控制字元。

**ParseWord**（第 91~95 行）：

```forth
: ParseWord ( -- c-addr u )
  CharAddr >IN @ SkipWord >IN @ - NEGATE ;
```

邏輯分解：
1. `CharAddr` = `TIB + >IN @`（目前字元位址）
2. 記錄目前 `>IN` 值
3. `SkipWord` 遞增 `>IN` 直到遇到分隔字元
4. 差值的負數 = 字詞長度

技巧說明：`NEGATE` 是因為結束位置 - 開始位置 = 長度，但由於 `SkipWord` 會遞增 `>IN`，所以 `>IN @（後） - >IN @（前）` 就是長度。但 Forth 的 `NEGATE` 是直接計算負數差值，這是一個巧妙的堆疊操作簡化。

**NextWord**（第 97~105 行）：

```forth
: NextWord ( -- c-addr u )
  SkipDelimiters ParseWord
  >IN @ 1+ #TIB @ MIN >IN !   \ 邊界校正
;
```

最後一行 `>IN @ 1+ #TIB @ MIN >IN !` 是關鍵的邊界校正。當字詞正好在輸入流的末尾時，`ParseWord` 會停在字詞尾端而非下一個分隔字元。這行確保 `>IN` 不會超過 `#TIB`，使得後續的 `EndOfChunk` 正確回傳 true。

### 2.4 PARSE：以終止字元解析

```forth
\ spf_parser.f:110-119
: PARSE ( char "ccc<char>" -- c-addr u )
  CharAddr >IN @
  ROT SkipUpTo
  >IN @ - NEGATE
  >IN 1+! ;
```

`PARSE` 是 Forth 94 CORE EXT 標準字，以指定字元作為終止字元來解析字串。它使用 `SkipUpTo`（第 83~89 行），後者逐字元遞增 `>IN` 直到遇到目標字元。

### 2.5 技術附註：分隔字元的定義範圍

`IsDelimiter` 判定 `char <= BL`（ASCII ≤ 32）為分隔字元。這意味著：
- 空白（0x20）、Tab（0x09）、換行（0x0A）、歸位（0x0D）都是合法的分隔字元
- 但逗號、分號、括號等標點符號**不是**分隔字元——它們是字詞的一部分
- 這符合 Forth 的設計哲學：字詞是完全由空白分隔的 token

值得注意的是 `IsDelimiter` 被宣告為 `VECT`（第 51 行），這代表它的行為可以被重新導向——允許自訂的剖析規則。

---

## 3. 原始碼讀取（spf_read_source.f）深入解析

### 3.1 輸入來源識別：SOURCE-ID 體系

SP-Forth 使用 `SOURCE-ID` 來區分三種輸入來源：

| SOURCE-ID 值 | 輸入來源 | 說明 |
|:---:|:---|:---|
| 0 | 終端機（stdin） | 互動式命令列輸入 |
| -1 | EVALUATE 字串 | 來自程式記憶體的字串求值 |
| >0（檔案 handle） | 檔案 | 載入的原始碼檔案 |

`SOURCE-ID-XT` 是一個延伸：當 SOURCE-ID 指向檔案時，SOURCE-ID-XT 可以指定一個自訂的讀取向量（xt），用於從非標準來源（如壓縮檔內的檔案）讀取。

### 3.2 REFILL 鏈的三層架構

REFILL 的實作採用了**向量置換**（vector replacement）策略，在系統初始化過程中逐步演化：

```forth
\ 初始狀態：REFILL → REFILL-STDIN（第 97 行）
' REFILL-STDIN ' REFILL TC-VECT!
\ 檔案支援載入後：REFILL → REFILL-FILE（第 123 行）
' REFILL-FILE ' REFILL TC-VECT!
\ 完整支援：REFILL → REFILL-SOURCE（第 139 行）
' REFILL-SOURCE ' REFILL TC-VECT!
```

演化過程反映了 Forth 的**自舉特性**：

1. **REFILL-STDIN**（第 89~96 行）：最基礎的版本，從終端機讀取一行。使用 `['] ACCEPT CATCH` 來安全地呼叫 ACCEPT，處理 pipe 中斷（錯誤碼 -1002）的邊界情況。呼叫 `TAKEN-TIB` 來完成 TIB 的設定。

2. **REFILL-FILE**（第 118~122 行）：先檢查 SOURCE-ID 是否為檔案（> 0），若是則使用 `FREFILL` 從檔案 handle 讀取一行；否則回退到 `REFILL-STDIN`。

3. **REFILL-SOURCE**（第 131~138 行）：最完整的版本，優先嘗試透過 `SOURCE-ID-XT` 執行自訂讀取邏輯；若無或非檔案來源，則回退到 `REFILL-FILE`。

### 3.3 TAKEN-TIB：輸入行安頓函式

```forth
\ spf_read_source.f:86-88
: TAKEN-TIB ( u flag -- flag )
  IF CURSTR 1+!  TIB SWAP SOURCE!  <PRE> -1  ELSE DROP 0  THEN
;
```

當 REFILL 成功讀取一行後，`TAKEN-TIB` 負責：
1. 遞增行號計數器 `CURSTR`
2. 將讀取的內容設定為新的輸入來源（透過 `SOURCE!`）
3. 呼叫 `<PRE>` 向量（預設為 `NOOP`，可用於預處理）
4. 回傳 `-1`（true，表示成功）

### 3.4 SOURCE-PATH 與 SOURCE-BASEPATH

原始碼追蹤功能提供了精確的來源定位：

- `SOURCE-FILE-PATH`（第 18~24 行）：回傳目前或最近祖先的檔案路徑（ASCIIZ 字串）
- `SOURCE-FILE-LN`（第 25~28 行）：回傳行號
- `SOURCE-PATH`（第 30~37 行）：根據 SOURCE-ID 回傳 URI 風格的路徑（`about:input-stdin` 或 `about:input-string`）
- `SOURCE-BASEPATH`（第 44~61 行）：回傳基準路徑，優先使用 `(BASEPATH)`，其次 SOURCE-FILE-PATH，用於解析相對路徑的 INCLUDE

---

## 4. 非最佳化字集（spf_nonopt.f）深入解析

### 4.1 NON-OPT-WL 的角色

spf_nonopt.f 建立了一個獨立的詞彙表 `NON-OPT-WL`，包含系統最基本的原語。這些原語**不參與巨集最佳化**——它們用 `CODE1` 定義（第 15~61 行），在目標系統中生成不可最佳化的機器碼。

```forth
\ spf_nonopt.f:6-13
WORDLIST VALUE NON-OPT-WL
' NON-OPT-WL EXECUTE LATEST-NAME NAME>CSTRING SWAP VOC-NAME!
' NON-OPT-WL EXECUTE PUSH-ORDER DEFINITIONS
TC-TRG ALSO TC-IMM
```

這段程式碼做了幾件事：
1. 建立 `NON-OPT-WL` 詞彙表並設為 CURRENT
2. 將搜尋順序設為 `NON-OPT-WL` + `TC-TRG` + `TC-IMM`
3. `TC-TRG` 和 `TC-IMM` 是交叉編譯器的詞彙表，確保定義的字可在目標系統中找到

### 4.2 CODE1 原語的 TOS 模型分析

下面逐行分析每個原語的機器碼和堆疊效果：

**RDROP**（第 15~19 行）：丟棄回返堆疊頂端

```asm
POP EBX           ; 從回返堆疊取出返回位址到 EBX
LEA ESP, 4[ESP]   ; ESP += 4，跳過回返堆疊頂端（即丟棄它）
JMP EBX           ; 跳回返回位址
```

堆疊效果：`( -- ) ( R: x -- )`。注意這不是 `R>` ——RDROP 只丟棄不出來，常在 `DO...LOOP` 結束和異常處理中使用。

**>R**（第 21~30 行）：將資料堆疊頂端推入回返堆疊

```asm
POP EBX           ; 返回位址 → EBX
PUSH EAX          ; TOS → 回返堆疊
MOV EAX, [EBP]    ; 次堆疊項 → EAX（新 TOS）
LEA EBP, 4[EBP]   ; EBP += 4，彈出次項
JMP EBX           ; 返回
```

標準堆疊效果仍然是 `（ x -- ） （ R: -- x ）`。若用 TOS-in-EAX 模型來看，則可描述為：執行前 `EAX = n2`（TOS）、`[EBP] = n1`（次項）；執行後 `n2` 被推入回返堆疊，而 `n1` 成為新的 TOS。

**R>**（第 32~41 行）：從回返堆疊取出到資料堆疊

```asm
LEA EBP, -4[EBP]   ; EBP -= 4，為新項騰出空間
MOV [EBP], EAX     ; 舊 TOS → 新次項
POP EBX            ; 返回位址 → EBX
POP EAX            ; 回返堆疊頂端 → EAX（新 TOS）
JMP EBX            ; 返回
```

堆疊效果：`( -- x ) ( R: x -- )`。舊 TOS 被推入堆疊成為次項，回返堆疊的值成為新 TOS。

**?DUP**（第 44~49 行）：條件複製

```asm
OR EAX, EAX      ; 測試 TOS 是否為零（設定旗標）
JNZ ' DUP       ; 非零則跳到 DUP（複製 TOS）
RET              ; 零則直接返回（不複製）
```

這裡 `JNZ ' DUP` 是 SP-Forth 的特殊語法：`' DUP` 取得 DUP 的 XT（程式碼欄位位址），因為 DUP 是 `CODE` 定義的原語，所以 XT 就是機器碼的起始位址，形成一個**直接跳躍**的尾呼叫最佳化。

**EXECUTE**（第 54~61 行）：間接跳躍執行

```asm
MOV EBX, EAX     ; XT → EBX
MOV EAX, [EBP]   ; 次項 → EAX（新 TOS）
LEA EBP, 4[EBP]  ; EBP += 4，彈出次項
JMP EBX          ; 跳到 XT 執行
```

堆疊效果：`( i*x xt -- j*x )`。注意 EXECUTE 彈出了堆疊頂端的 XT，同時也消耗了次項——但這是因為 TOS-in-EAX 模型：XT 在 TOS（EAX），而真正的堆疊頂端是 `[EBP]`（次項）。所以 EXECUTE 將 XT 從 TOS 取出，然後將次項提升為新 TOS。

### 4.3 設計意圖：為何分離非最佳化字集？

`NON-OPT-WL` 的存在是為了**確保核心原語的穩定性**。巨集最佳化器（macroopt）在最佳化過程中會修改某些字編譯時的行為（如將 `>R` 替換為內聯版本），但系統啟動時需要一組不依賴最佳化器的基礎字集。`CODE1` 定義的保證是：**這些字的機器碼永遠是固定的、不會被最佳化器改變**。

---

## 5. 基本編譯控制（spf_compile0.f）深入解析

### 5.1 字典指標管理：DP 的雙重機制

```forth
\ spf_compile0.f:10-13
USER CURRENT      \ 目前編譯詞彙表的 wid
VARIABLE (DP)     \ 字典指標變數
5 CONSTANT CFL    \ CREATE 欄位長度（5 bytes: CALL rel32）
USER DOES>A       \ DOES> 行為指標
```

`DP`（第 34~37 行）是最核心的字典管理字：

```forth
: DP ( -- addr )
  IS-TEMP-WL
  IF GET-CURRENT 7 CELLS + ELSE (DP) THEN
;
```

**模組暫時詞彙表的字典指標**：當目前編譯詞彙表是暫時詞彙表（`IS-TEMP-WORDLIST` 為真時），字典指標存放在該詞彙表結構的偏移 `7 CELLS`（28 bytes）處；否則使用全域變數 `(DP)`。

`IS-TEMP-WORDLIST`（第 26~29 行）的判定方式：

```forth
: IS-TEMP-WORDLIST ( wid -- flag )
  CELL- @ -1 =
;
```

它檢查 wid 前一個儲存格是否為 -1。在 `WORDLIST` 結構中，暫時詞彙表（`TEMP-WORDLIST`，spf_wordlist.f 第 99~108 行）的第一個儲存格被設為 -1 作為標記。

### 5.2 HERE 與 ALLOT 的設計

```forth
\ spf_compile0.f:39-49
: ALLOT ( n -- )   DP +!  ;
: , ( x -- )       DP @ 4 ALLOT !  ;
: C, ( char -- )   DP @ 1 CHARS ALLOT C!  ;
: W, ( word -- )   DP @ 2 ALLOT W!  ;
```

這三個字是字典建構的基石：

- `,`（comma）：分配一個儲存格（4 bytes），寫入 32 位元值
- `C,`：分配一個字元（1 byte），寫入 8 位元值
- `W,`：分配一個字組（2 bytes），寫入 16 位元值

注意 `,` 的實作：先 `DP @` 取得目前位址，再 `4 ALLOT` 推進指標，最後 `!` 寫入值。由於 TOS-in-EAX 模型，堆疊效果為 `( x -- )`，x 被寫入 DP 所指的位址。

### 5.3 CFL 常數與 CREATE 欄位

`CFL = 5` 定義了 CREATE 類型字的**程式碼欄位長度**。在 SP-Forth 的 IA-32 實作中，這 5 bytes 對應一條 `CALL rel32` 指令（1 byte opcode + 4 bytes 相對位址）。這是 Forth 字頭（header）設計的關鍵常數：

```
Forth 字在記憶體中的佈局：

  ┌─────────────────┐  ← NFA（名稱欄位位址，Name Field Address）
  │ 長度位元組       │  1 byte：名稱長度
  │ 名稱字元...      │  可變長度
  ├─────────────────┤
  │ LFA              │  4 bytes：鍊結欄位（前一個字的 NFA）
  ├─────────────────┤  ← CFA（程式碼欄位位址，Code Field Address）
  │ flags (1 byte)   │  旗標位元組（IMMEDIATE, VOC 等）
  │ CALL xxxxx       │  5 bytes：CFL = CALL rel32
  ├─────────────────┤
  │ PFA              │  參數欄位（Parameter Field Area）
  │ 參數資料...      │  由 CREATE/VARIABLE/CONSTANT 等配置
  └─────────────────┘
```

### 5.4 SET-CURRENT / GET-CURRENT

```forth
: SET-CURRENT ( wid -- )   CURRENT !  ;
: GET-CURRENT ( -- wid )   CURRENT @  ;
```

`CURRENT` 是 `USER` 變數，每個執行緒有獨立的 CURRENT。這使得 SP-Forth 支援多執行緒編譯。`SET-CURRENT` 和 `GET-CURRENT` 是 ANSI Forth 94 SEARCH 詞集的標準字。

---

## 6. 搜尋引擎（spf_find.f, spf_find_cdr.f）深入解析

### 6.1 雜湊搜尋與 CDR-BY-NAME 演算法

SP-Forth 詞彙表使用**雜湊鍊表**結構。每個詞彙表的 wid 指向一個雜湊桶（hash bucket），名稱透過雜湊函式映射到桶，桶內以鍊表串接所有同名或同桶的字。

搜尋的核心是 `CDR-BY-NAME`（`spf_find_cdr.f`，由 `spf_find.f` 在檔內 `INCLUDED`），它根據名稱長度選擇不同的最佳化路徑：

**長度 0（空字串）**——`CDR-BY-NAME0`（第 13~26 行）：

```asm
MOV EBX, [EBP]   \ counter = 0（名稱長度）
MOV EDX, # 0
JMP SHORT @@1
@@2: MOV EAX, 1[EDX][EAX]   \ 鍊結到下一個 NFA
@@1: OR EAX, EAX
JZ SHORT @@9                \ 鍊結結束，未找到
MOV DL, BYTE [EAX]         \ 取名稱長度位元組
CMP EDX, EBX                \ 比較長度
JNZ SHORT @@2               \ 長度不匹配，繼續搜尋
@@9: RET
```

這個版本只比對長度位元組——因為名稱長度為 0，只要長度匹配就是匹配（實際上空名稱在 Forth 中不應出現）。

**長度 1**——`CDR-BY-NAME1`（第 29~44 行）：只比對長度 + 第一個字元

**長度 2**——`CDR-BY-NAME2`（第 47~66 行）：比對長度 + 前兩個字元（以 16 位元整數形式）

**長度 3**——`CDR-BY-NAME3`（第 69~87 行）：比對長度 + 前三個字元（以 24 位元整數形式）

**長度 > 3**——`CDR-BY-NAME`（第 90~134 行）：先比對前 3 個字元（呼叫 CDR-BY-NAME3），然後對剩餘字元進行 `REPZ CMPS` 逐字元比對。

```asm
; u > 3 时的完整比對流程：
CALL ' CDR-BY-NAME3   ; 先快速篩選前 3 字元
OR EAX, EAX
JZ SHORT @@9          ; 不匹配
; 完整字串比對
PUSH EDI
MOV ESI, ECX          ; 來源位址 + 3
ADD ESI, # 3
MOV ECX, # 0
MOV CL, BL            ; 剩餘長度 = 總長度 - 3
SUB CL, # 3
PUSH ESI
REPZ CMPS BYTE        ; 逐字元比對
POP ESI
JNZ SHORT @@2          ; 不匹配，繼續搜尋
POP EDI
RET
@@9: RET
```

**設計原理**：這種根據名稱長度分派不同比對策略的設計是典型的**微最佳化**手法。短名稱（1~3 字元）是 Forth 最常見的情況（如 `+`、`>R`、`DUP`），使用快速路徑可以避免 `REPZ CMPS` 的設定開銷。長名稱則需要完整比對。

### 6.2 SFIND：逐詞彙表搜尋

```forth
\ spf_find.f:175-192
: SFIND ( addr u -- addr u 0 | xt 1 | xt -1 )
  CONTEXT
  BEGIN
    DUP S-O U> WHILE >R 2DUP R@ @ SEARCH-WORDLIST DUP 0= WHILE DROP R> CELL-
  REPEAT
    R> VOC-FOUND !
    2SWAP 2DROP EXIT
  THEN
  DROP VOC-FOUND 0! 0
;
```

SFIND 的搜尋策略：
1. 從 `CONTEXT`（搜尋順序頂端）開始，逐個詞彙表搜尋
2. 對每個詞彙表呼叫 `SEARCH-WORDLIST`
3. 第一個匹配的字詞就被採用（**最早定義優先，但搜尋順序優先於定義順序**）
4. 回傳值：0（未找到）、1（立即字）、-1（非立即字）
5. 找到時同時設定 `VOC-FOUND` 記錄在哪個詞彙表中找到

**搜尋順序管理**：SP-Forth 使用 `S-O`（搜尋順序陣列起點）和 `CONTEXT`（指向搜尋順序頂端）組成一個堆疊結構：

```
S-O   → wid_1（最後搜尋）
S-O+4 → wid_2
S-O+8 → wid_3
...
CONTEXT → wid_n（最先搜尋）
```

`PUSH-ORDER`（第 156~158 行）壓入新的 wid，`DROP-ORDER`（第 148~151 行）彈出頂端。搜尋時從 `CONTEXT`（最先搜尋）向 `S-O`（最後搜尋）遍歷。

### 6.3 FIND-NAME 與 FIND-NAME-IN

ANS Forth 2018 標準新增的 `FIND-NAME`（第 165~173 行）提供更簡潔的搜尋介面：

```forth
: FIND-NAME ( sd.name -- nt|0 )
  CONTEXT >R
  BEGIN R@ S-O U> WHILE ( sd.name )
    2DUP R@ @ ( wid ) FIND-NAME-IN
    DUP 0= WHILE  DROP R> CELL- >R
  REPEAT ( sd.name nt ) NIP NIP RDROP EXIT  THEN
  ( sd.name )
  RDROP 2DROP 0
;
```

與 SFIND 的區別：FIND-NAME 回傳 **nt**（name token），而 SFIND 回傳 **xt** + 旗標。nt 是 NFA（Name Field Address），可以直接用來取得名稱、旗標等資訊，比 xt 更基礎。

### 6.4 搜尋順序操作

Forth 搜尋順序的管理遵循 ANSI 94 SEARCH 詞集標準：

- `FORTH`（第 254~258 行）：替換搜尋順序頂端為 FORTH-WORDLIST
- `ONLY`（第 260~265 行）：清空搜尋順序，只保留 FORTH-WORDLIST
- `ALSO`（第 241~246 行）：複製搜尋順序頂端
- `PREVIOUS`（第 247~252 行）：移除搜尋順序頂端
- `DEFINITIONS`（第 207~212 行）：將 CURRENT 設為搜尋順序頂端的詞彙表

---

## 7. 詞彙表管理（spf_wordlist.f）深入解析

### 7.1 WORDLIST 結構詳解

`WORDLIST` 建立的是一個**帶有隱藏前置 link cell 的結構**。實際對外回傳的 `wid` 指向的是「公開欄位區」的起點；在它前面還有 1 個 cell 用來串接 `VOC-LIST`。之後 `AT-WORDLIST-CREATING` 與 `TEMP-WORDLIST` 還會在尾端附加延伸欄位。

```forth
\ spf_wordlist.f:76-92
: WORDLIST ( -- wid )
  ALIGN
  HERE VOC-LIST @ , VOC-LIST !    \ 隱藏前置欄位：VOC-LIST 鏈結
  HERE 0 ,                        \ wid +0 : HEAD（最新字頭）
       0 ,                        \ wid +4 : CSTRING（詞彙表名稱）
  GET-CURRENT ,                   \ wid +8 : PAR（初值為建立當下的 CURRENT）
       0 ,                        \ wid +12: CLASS
       0 ,                        \ wid +16: WID-EXTRA 起點
;
```

| 相對於 `wid` 的偏移 | 欄位 | 說明 |
|------|------|------|
| -4 | VOC-LIST link | 只供 `VOC-LIST` / `ENUM-VOCS` 串接所有詞彙表，不屬於公開 accessor 區 |
| +0 | HEAD | 由 `WID>HEAD` 讀取，指向該詞彙表最新定義的 nt |
| +4 | CSTRING | 由 `WID>CSTRING` 讀取，指向詞彙表名稱 |
| +8 | PAR | 由 `PAR@` 讀取，表示父詞彙表 |
| +12 | CLASS | 由 `CLASS@` 讀取，初值為 `0`（宿主版的 `GET-CURRENT` 寫在 `PAR` 欄位） |
| +16 起 | WID-EXTRA | 額外 metadata 區域，供延伸欄位使用 |

注意：`wid` 指向的是**公開欄位起點**，不是配置區塊的最前端；最前面的 `VOC-LIST` link 需要透過 `CELL-` 才能回到。舊版描述把 `GET-CURRENT ,` 誤寫成「wid 自身」，也忽略了這個隱藏前置欄位，容易讓 `ENUM-VOCS` / `TEMP-WORDLIST` 的實作看起來對不上。

**VOC-LIST**：全域詞彙表清單，所有新建的詞彙表透過鍊結串接，用於 `ENUM-VOCS` 遍歷所有詞彙表。

### 7.2 +SWORD：將字詞加入詞彙表

```forth
\ spf_wordlist.f:47-53
: +SWORD ( addr u wid -- )
  HERE LAST !
  HERE 2SWAP S", SWAP DUP @ , !
;
```

執行流程：
1. `HERE LAST !`：記錄目前字典位址到 LAST（用於 `IMMEDIATE` 等操作）
2. `HERE 2SWAP S", `：在字典中寫入計數字串（長度位元組 + 字元 + 對齊）
3. `SWAP DUP @ , !`：將新 NFA 鍊結到詞彙表的鍊頭

### 7.3 名稱欄位存取字

SP-Forth 提供了一組組合語言實作的名稱欄位存取字，極度效率導向：

```forth
\ spf_wordlist.f:135-155
CODE NAME> ( nt -- xt )        \ nt 轉 xt：讀取 nt 前方 5 bytes 處的 CFA
  MOV EAX, -5 [EAX]           \ 1 條指令！
  RET
END-CODE

CODE NAME>C ( nt -- a-addr )  \ nt 轉 CFA 位址
  LEA EAX, -5 [EAX]           \ 2 條指令
  RET
END-CODE

CODE NAME>F ( nt -- a-addr )  \ nt 轉旗標位址
  LEA EAX, -1 [EAX]
  RET
END-CODE

CODE NAME>L ( nt -- a-addr )  \ nt 轉鍊結位址
  MOVZX EBX, BYTE [EAX]       \ 讀取長度位元組
  LEA EAX, [EBX] [EAX]
  LEA EAX, 1 [EAX]            \ nt + len + 1
  RET
END-CODE
```

**設計分析**：`NAME>` 只需要一條 `MOV` 指令就完成 nt → xt 轉換。這得益於 Forth 字頭結構的巧妙設計：CFA 恰好在 NFA 前方 5 個 bytes 處（1 byte 旗標 + 4 bytes CFA/指向程式碼的指標）。

名稱欄位在記憶體中的佈局：

```
         ←── 低位址                          高位址 ──→
    ┌─────┬─────────┬────────┬──────┬─────────┬───────────┐
    │ CFA │ flags(1) │ 長度(1) │ 名稱 │  LFA(4) │ ... PFA    │
    └─────┴─────────┴────────┴──────┴─────────┴───────────┘
         ↑           ↑        ↑      ↑         ↑
      NAME>C     NAME>F    NFA    NAME>L   前一個字的NFA
                              ↑
                          NAME> 讀取此處前方5 bytes
```

### 7.4 TEMP-WORDLIST 與 FREE-WORDLIST

```forth
\ spf_wordlist.f:99-111
: TEMP-WORDLIST ( -- wid )
  WL_SIZE ALLOCATE-RWX THROW DUP >R WL_SIZE ERASE
  -1      R@ !                  \ 標記為暫時詞彙表
  R@      R@ 6 CELLS + !       \ Cell 3: wid = 自身起始+CELL
  VERSION R@ 7 CELLS + !       \ 版本資訊
  R@ 9 CELLS + DUP CELL- !     \ 初始化額外空間
  R> CELL+                     \ 跳過標記儲存格
;
: FREE-WORDLIST ( wid -- )
  CELL- FREE-RWX THROW          \ 釋放分配的記憶體
;
```

暫時詞彙表的記憶體來自 `ALLOCATE-RWX`（可執行記憶體分配），第一個儲存格設為 -1 作為標記（讓 `IS-TEMP-WORDLIST` 識別）。暫時詞彙表有自己獨立的字典指標（透過 `DP` 字的 `IS-TEMP-WL` 分支），用於模組系統中獨立編譯。

### 7.5 CHAIN-WORDLIST：詞彙表繼承

```forth
\ spf_wordlist.f:261-269
: CHAIN-WORDLIST ( wid.tail wid-empty -- )
  DUP WID>HEAD 0= IF >R LATEST-NAME-IN R> FIX-WID-HEAD EXIT THEN
  -12 THROW  \ "argument type mismatch"
;
```

`CHAIN-WORDLIST` 將一個詞彙表的最新字繼承到另一個空詞彙表中。這是模組系統 `EXPORT` 功能的基礎：模組內部定義的字透過鍊結「匯出」到外部詞彙表。

### 7.6 WORDS 與 NLIST

```forth
\ spf_words.f:13-37
: NLIST ( wid -- )
  LATEST-NAME-IN ( nt|0 )
  >OUT 0! CR W-CNT 0!
  BEGIN
    DUP KEY? 0= AND
  WHILE ( nt )
    W-CNT 1+!
    DUP NAME>STRING NIP DUP >R >OUT @ + 74 >
    IF CR >OUT 0! THEN
    DUP ID.
    R> >OUT +!
    15 >OUT @ 15 MOD - DUP >OUT +! SPACES
    NAME>NEXT-NAME
  REPEAT DROP KEY? IF KEY DROP THEN
  CR CR ." Words: " BASE @ DECIMAL W-CNT @ U. BASE ! CR
;
```

`NLIST` 以格式化方式列出詞彙表中的所有字，每 74 個字元換行，並在按鍵中斷時停止。最後顯示字的總數。

---

## 8. 主要編譯器（spf_compile.f）深入解析

### 8.1 HERE：編譯位址追蹤器

```forth
\ spf_compile.f:12-17
: HERE ( -- addr )
  DP @
  DUP TO :-SET
  DUP TO J-SET
;
```

`HERE` 不僅回傳字典指標，還同步更新兩個最佳化相關的變數：
- `:-SET`：最近一個最佳化點（optimization point），用於 `CON>LIT` 常數摺疊
- `J-SET`：最近一個跳躍點（jump point），用於跳躍最佳化

### 8.2 _COMPILE, 與 COMPILE,：編譯分派機制

```forth
\ spf_compile.f:19-42
: _COMPILE, ( xt -- )
  ?SET             \ 確保最佳化器狀態一致性
  SetOP            \ 設定最佳化點
  0E8 C,           \ 序數 0xE8 = CALL rel32
  DP @ CELL+ - ,   \ 計算相對位址
  DP @ TO LAST-HERE
;

: COMPILE, ( xt -- )
  CON>LIT          \ 嘗試常數摺疊
  IF INLINE?       \ 檢查是否可內聯
    IF INLINE,     \ 內行展開
    ELSE _COMPILE, \ 產生 CALL 指令
    THEN
  THEN
;
```

**編譯決策樹**：

```
COMPILE, ( xt )
  │
  ├─ CON>LIT 回傳 FALSE？
  │    └─ 是 → CON>LIT 已完成常數/USER/CREATE 等特殊編譯，COMPILE, 不再產生代碼
  │
  └─ CON>LIT 回傳 TRUE（仍需一般編譯）
       ├─ INLINE? 回傳 TRUE → INLINE,（內聯展開）
       └─ INLINE? 回傳 FALSE → _COMPILE,（產生 CALL）
```

注意：`CON>LIT` 的布林語意容易誤讀。它回傳 **FALSE** 時，代表自己已經處理完成（例如把 `CONSTANT`、`USER`、`CREATE` 類定義轉成 literal 或特殊內聯序列），因此外層 `COMPILE,` 不再產生一般 `CALL`。它回傳 **TRUE** 時，才表示需要繼續走 `INLINE?` / `_COMPILE,` 的一般路徑。

### 8.3 LIT,：常值編譯

```forth
\ spf_compile.f:53-58
: LIT, ( W -- )
  ['] DUP  INLINE,
  OPT_INIT
  SetOP 0B8 C,  , OPT    \ MOV EAX, #imm32
  OPT_CLOSE
;
```

編譯一個 32 位元立即常值的機器碼序列：
1. `['] DUP INLINE,`：內聯 DUP 的代碼（`MOV EAX, [EBP]; LEA EBP, 4[EBP]`）
2. `0B8 C, , `：產生 `MOV EAX, imm32`（0xB8 是 MOV EAX 的 opcode）
3. `OPT_INIT` / `OPT_CLOSE`：標記最佳化區段

**組合語言對照**：

```
; LIT, 編譯結果（以 42 LITERAL 為例）：
MOV EAX, [EBP]      ; 內聯 DUP —— 先將次項提升為新 TOS
LEA EBP, 4[EBP]     ; 資料堆疊指標上移
MOV EAX, 0x0000002A ; 將 42 載入 EAX（新 TOS）
```

這正是 TOS-in-EAX 模型的精髓：先儲存舊的次項到堆疊（DUP），再將常值載入 EAX。

### 8.4 BRANCH, 與 ?BRANCH,：跳躍編譯

```forth
\ spf_compile.f:44-47
: BRANCH, ( ADDR -- )
  ?SET SetOP SetJP E9 C,
  DUP IF DP @ CELL+ - THEN ,    DP @ TO LAST-HERE
;

\ spf_compile.f:73-82
: ?BRANCH, ( ADDR -- )
  ?SET
  084 TO J_COD
  ???BR-OPT
  SetJP  SetOP
  J_COD 0x0F C, C,
  DUP IF DP @ CELL+ - THEN , DP @ TO LAST-HERE
;
```

`BRANCH,` 產生 `E9`（JMP near，5 bytes）無條件跳躍。
`?BRANCH,` 產生條件跳躍：
- `J_COD` 初始為 `0x84`（`JZ near` 的 opcode 部分）
- `???BR-OPT` 可以將條件跳躍最佳化為其他條件（如 JNZ）
- 最終產生 `0x0F 8x` 的近條件跳躍（6 bytes）

### 8.5 對齊與 ALIGN

```forth
\ spf_compile.f:157-184
USER ALIGN-BYTES

: ALIGN-TO ( addr u -- addr1 )
  DUP 16 =
  IF 1- + 0xFFFFFFF0 AND     \ 16 位元組對齊的快速路徑
  ELSE 2DUP MOD DUP IF - + ELSE 2DROP THEN
  THEN
;

: ALIGNED ( addr -- a-addr )   ALIGN-BYTES @ ALIGN-TO  ;
: ALIGN ( -- )                  DP @ ALIGNED DP @ - ALLOT  ;
: ALIGN-NOP ( n -- )           HERE DUP ROT ALIGN-TO OVER - DUP ALLOT 0x90 FILL  ;
```

`ALIGN-NOP` 是一種特別的對齊技術：用 NOP（0x90）填充而不是零。這確保了 CPU 的對齊要求被滿足，同時不會在執行時產生意外。迴圈起始點的 16 位元組對齊（見 `DO` 中的 `ALIGN-BYTES @ ALIGN-NOP`）可以改善 CPU 快取行效率。

---

## 9. 定義字（spf_defwords.f）深入解析

### 9.1 SHEADER：名稱解析的核心

```forth
\ spf_defwords.f:15-36
: SHEADER1 ( addr u -- )
  HERE 0 , ( cfa )         \ 分配 CFA，初始為 0
  DUP LAST-CFA !            \ 記錄最後定義的 CFA
  0 C,     ( flags )        \ 旗標位元組，初始為 0
  UNROT WARNING @
  IF 2DUP GET-CURRENT SEARCH-WORDLIST
     IF DROP 2DUP TYPE ."  isn't unique (" SOURCE-PATH TYPE ." )" CR THEN
  THEN
  GET-CURRENT +SWORD         \ 加入詞彙表鍊結

  ALIGN                      \ 對齊 CFA 寫入位址
  ALIGN-BYTES @ DUP 4 >
  IF 5 - ALLOT               \ 大對齊要求時用 5 bytes 填充
  ELSE 1 - ALLOT             \ 小對齊要求時用 1 byte 填充
  THEN

  HERE SWAP ! ( 回填 CFA )   \ 將 HERE 寫入先前 CFA 欄位的位置
;
```

**SHEADER 的完整流程圖**：

```
SHEADER ( addr u -- )
  │
  ├─ 1. HERE 0 ,          分配 CFA 欄位（初始為 0）
  ├─ 2. DUP LAST-CFA !    記錄 CFA
  ├─ 3. 0 C,              寫入旗標位元組
  ├─ 4. WARNING 檢查       若啟用重複警告，搜尋同名字詞
  ├─ 5. GET-CURRENT +SWORD 將名稱加入詞彙表
  ├─ 6. ALIGN + 對齊填充   確保 CFA 位址對齊
  └─ 7. HERE SWAP !       回填 CFA 為 HERE（此時的 HERE 就是 PFA 的起始）
```

第 5 步的 `+SWORD` 在這裡的行為是：先寫入名稱字串（長度 + 字元），再鍊結到詞彙表的鍊頭。

第 6~7 步的對齊和回填是精妙的：CFA 欄位最初寫入 0，等到名稱和對齊完成後，才將 HERE（此時指向 PFA 起始）回填到 CFA 欄位。這是因為**名稱的長度不固定，無法預先計算 PFA 的位置**。

### 9.2 變數定義字

**VARIABLE**（第 148~158 行）：

```forth
: VARIABLE ( "<spaces>name" -- )
  CREATE 0 ,           \ CREATE 建立 PFA，0 , 初始值為 0
;
```

** ->VARIABLE**（第 191~195 行）：

```forth
: ->VARIABLE ( x "<spaces>name" -- )
  HEADER ['] _CREATE-CODE COMPILE, ,   \ 帶初始值的變數
;
```

**CONSTANT**（第 159~168 行）：

```forth
: CONSTANT ( x "<spaces>name" -- )
  HEADER
  ['] _CONSTANT-CODE COMPILE, ,   \ 執行時推入常數值
;
```

**VALUE**（第 169~181 行）：

```forth
: VALUE ( x "<spaces>name" -- )
  HEADER
  ['] _CONSTANT-CODE COMPILE, ,        \ 讀取用：推入值
  ['] _TOVALUE-CODE COMPILE,            \ TO 用：修改值
;
```

VALUE 的字典結構比 CONSTANT 多一個 `_TOVALUE-CODE` 的 XT。當執行 `TO name` 時，系統會跳到 PFA + CFL 位置找到修改程式碼。

### 9.3 DOES> 的實作機制

```forth
\ spf_defwords.f:83-86
: (DOES1) \ 執行時，當 CREATE 定義的字被呼叫時
  R> DOES>A @ CFL + -     \ 計算 DOES> 行為的位址
  DOES>A @ 1+ !            \ 修改 CFA 指向新的行為
;

\ spf_defwords.f:88-95
CODE (DOES2)    \ 執行時，當帶有 DOES> 的字被呼叫時
  LEA  EBP, -4 [EBP]   \ 壓入資料堆疊
  MOV  [EBP], EAX      \ 舊 TOS 成為次項
  MOV  EAX, 4 [ESP]    \ 從回返堆疊取得 PFA
  MOV  EBX, [ESP]      \ 取得 DOES> 代碼位址
  LEA  ESP, 8 [ESP]    \ 清理回返堆疊
  JMP  EBX              \ 跳到 DOES> 代碼
END-CODE
```

DOES> 的運作原理是 Forth 最精巧的設計之一：

1. **編譯期**：`DOES>` 編譯 `(DOES1)` 和 `(DOES2)` 兩個 XT
2. **CREATE 定義的字被呼叫時**：`(DOES1)` 執行，它修改自己的 CFA 使其指向 `(DOES2)`
3. **之後每次呼叫**：`(DOES2)` 執行，它將 PFA 位址推入資料堆疊，然後跳到 DOES> 之後的代碼

**記憶體佈局變化**：

```
CREATE 定義後：
  ┌──────────────────┐
  │ _CREATE-CODE 的  │ ← CFA（呼叫時跳到此處）
  │ CALL 指令        │
  ├──────────────────┤
  │ PFA 資料         │
  └──────────────────┘

第一次呼叫時 (DOES1) 修改 CFA 後：
  ┌──────────────────┐
  │ (DOES2) 的        │ ← CFA（被改為指向 DOES2）
  │ CALL 指令         │
  ├──────────────────┤
  │ PFA 資料          │
  ├──────────────────┤
  │ DOES> 後的代碼    │ ← DOES> & CFL 之前的偏移指向此處
  └──────────────────┘
```

### 9.4 USER 變數的實作

```forth
\ spf_defwords.f:197-208
: USER-ALIGNED ( -- a-addr n )
  USER-HERE 3 + 2 RSHIFT ( 4 / ) 4 * DUP USER-HERE -  ;

: USER-CREATE ( "<spaces>name" -- )
  HEADER
  HERE DOES>A ! ( 留給 DOES )
  ['] _USER-CODE COMPILE,
  USER-ALIGNED SWAP ,    \ 偏移儲存在 PFA
  USER-ALLOT              \ 分配 USER 空間
;
```

USER 變數透過 EDI 暫存器存取（參見 01-kernel.md 的暫存器分配），實作方式是：
1. 在 PFA 中存儲偏移量
2. `_USER-CODE` 的機器碼為 `MOV EAX, [EDI+EAX]`（或類似），透過 EDI（TLS 基底）+ 偏移量存取
3. `USER-ALIGNED` 確保偏移量對齊到 4 位元組邊界

### 9.5 :（冒號定義）與 HIDE/SMUDGE

```forth
\ spf_defwords.f:281-298
: : ( "<spaces>name" -- colon-sys )
  HEADER        \ 建立字頭
  ]             \ 進入編譯模式
  HIDE          \ 隱藏新定義（防止遞迴參照未完成定義）
;

\ spf_defwords.f:246-253
: SMUDGE ( -- )
  LATEST
  IF C-SMUDGE C@
     LATEST NAME>CSTRING CHAR+ C@ C-SMUDGE C!
     LATEST NAME>CSTRING CHAR+ C!
  THEN
;

: HIDE   12 C-SMUDGE C! SMUDGE  ;
```

**HIDE/SMUDGE 機制**：Forth 的冒號定義在編譯期間是「隱藏」的——它的名稱長度位元組的第二個位元組被設為 12（特殊標記），使得 `SEARCH-WORDLIST` 找不到它。編譯結束時 `;`（semicolon）呼叫 `SMUDGE` 恢復可見性。

`C-SMUDGE`（USER 變數）暫存原始的長度位元組，用於恢復。`HIDE` 設定 `C-SMUDGE = 12`，`SMUDGE` 將名稱長度位元組的第二個位元組異或 C-SMUDGE 的值。

但 `IS-NAME-HIDDEN`（spf_wordlist.f 第 180~182 行）的判定方式是：

```forth
: IS-NAME-HIDDEN ( nt -- flag )
  NAME>CSTRING CHAR+ C@ 12 =   \ 第二個位元組 == 12 表示隱藏
;
```

這解釋了為什麼 Forth 定義在編譯期間不可見——搜尋引擎會跳過 `IS-NAME-HIDDEN` 為真的字詞。

### 9.6 VOCABULARY 與詞彙表執行

```forth
\ spf_defwords.f:125-138
: VOCABULARY ( "<spaces>name" -- )
  WORDLIST DUP
  CREATE ,                          \ PFA 存放 wid
  LATEST-NAME NAME>CSTRING OVER VOC-NAME!  \ 設定詞彙表名稱
  GET-CURRENT SWAP PAR!             \ 設定父詞彙表
  VOC                               \ 設定 VOC 旗標
  (DOES1) (DOES2)                   \ 手動內聯 DOES> 行為
  @ SET-ORDER-TOP                   \ 執行時：將 wid 壓入搜尋順序
;
```

VOCABULARY 建立的字在執行時會將對應的詞彙表壓入搜尋順序頂端。這是透過 `(DOES1) (DOES2)` 組合實現的——手動內聯了 DOES> 的行為，因為 VOCABULARY 的 DOES> 部分需要特殊的處理。

### 9.7 VECT 與 BEHAVIOR

```forth
\ spf_defwords.f:182-188
: VECT ( -> )
  HEADER
  ['] _VECT-CODE COMPILE, ['] NOOP ,  \ 執行碼 + 預設 XT（NOOP）
  ['] _TOVALUE-CODE COMPILE,           \ TO 修改碼
;

: BEHAVIOR ( vect-xt -- assigned-xt )   CFL + @  ;
: BEHAVIOR! ( xt1 xt2 -- )             CFL + !  ;
```

VECT 類似 VALUE 但用於執行向量（execution vector）。其 PFA 結構：

```
  ┌──────────────────┐  ← xt（DOES> 指向 _VECT-CODE）
  │ _VECT-CODE CALL  │  ← CFL=5 bytes
  ├──────────────────┤
  │ NOOP XT          │  ← PFA：目前的執行向量（可透過 TO 修改）
  ├──────────────────┤
  │ _TOVALUE-CODE    │  ← TO 修改時的目標碼
  └──────────────────┘
```

`BEHAVIOR` 透過 `CFL + @` 取得 PFA 中的 XT，`BEHAVIOR!` 透過 `CFL + !` 設定它。TC-VECT! 在初始化期間用於設定向量指向。

### 9.8 :NONAME 與 RECURSE

```forth
\ spf_defwords.f:261-278
: :NONAME ( C: -- colon-sys ) ( S: -- xt )
  LATEST ?DUP IF 1+ C@ C-SMUDGE C! SMUDGE THEN
  HERE DUP TO LAST-NON [COMPILE] ]
;
```

`:NONAME` 建立一個**無名定義**，回傳其 XT。它：
1. 暫存目前 LATEST 的 smudge 狀態
2. 將 HERE 作為定義起始（不建立名稱）
3. 設定 LAST-NON 供 RECURSE 使用
4. 進入編譯模式

**RECURSE**（spf_immed_control.f 第 122~129 行）：

```forth
: RECURSE ( -- )
  ?COMP
  LAST-NON DUP 0=
  IF DROP LATEST NAME> THEN _COMPILE,
; IMMEDIATE
```

RECURSE 嘗試使用 `LAST-NON`（:NONAME 定義的 XT），若無則使用 `LATEST NAME>`（最近命名定義的 XT）。這是在冒號定義內遞迴呼叫自身的標準方式。

---

## 10. 直譯器（spf_translate.f）深入解析

### 10.1 INTERPRET 迴圈

```forth
\ spf_translate.f:114-129
: INTERPRET_ ( -> )
  BEGIN
    PARSE-NAME DUP
  WHILE
    SFIND ?DUP
    IF
         STATE @ =
         IF COMPILE, ELSE EXECUTE THEN
    ELSE
         S" NOTFOUND" SFIND
         IF EXECUTE
         ELSE 2DROP ?SLITERAL THEN
    THEN
    ?STACK
  REPEAT 2DROP
;
```

INTERPRET 的核心邏輯：

```
INTERPRET_
  │
  ├─ PARSE-NAME → 取得下一個字詞（addr u）
  │    └─ 若為空（輸入流耗盡）→ 結束迴圈
  │
  ├─ SFIND → 搜尋字詞
  │    ├─ 找到且 STATE 匹配 → COMPILE,（編譯模式）或 EXECUTE（直譯模式）
  │    └─ 未找到
  │         ├─ 嘗試 NOTFOUND 向量（處理 vocname::wordname 語法）
  │         └─ 嘗試 ?SLITERAL（數字解析）
  │
  └─ ?STACK → 檢查堆疊溢位
```

**STATE 匹配規則**：

`STATE @ =` 的比較是 SP-Forth 中一個精巧的設計。`SFIND` 回傳值：`1`（立即字）、`-1`（非立即字）、`0`（未找到）。`STATE @` 在編譯模式下為 `-1`（TRUE），直譯模式下為 `0`（FALSE）。

```
               │ SFIND = 1 (立即) │ SFIND = -1 (非立即)
───────────────┼──────────────────┼─────────────────────
STATE = -1(編譯)│ -1 = 1 → false  │ -1 = -1 → true
               │ → EXECUTE ✓     │ → COMPILE, ✓
───────────────┼──────────────────┼─────────────────────
STATE = 0(直譯) │ 0 = 1 → false   │ 0 = -1 → false
               │ → EXECUTE ✓     │ → EXECUTE ✓
```

- **編譯模式 + 非立即字**：`-1 = -1` → true → `COMPILE,`（編譯非立即字，正確）
- **編譯模式 + 立即字**：`-1 = 1` → false → `EXECUTE`（立即執行，不編譯，正確）
- **直譯模式 + 任何字**：`0 = 1` 或 `0 = -1` 都為 false → `EXECUTE`（直譯模式總是執行，正確）

### 10.2 NOTFOUND：詞彙表限定的名稱解析

```forth
\ spf_translate.f:86-112
: NOTFOUND ( a u -- )
  2DUP 2>R ['] ?SLITERAL CATCH ?DUP IF NIP NIP 2R>
  2DUP S" ::" SEARCH 0= IF 2DROP 2DROP THROW THEN
  2DROP ROT DROP
  GET-ORDER  N>R
  BEGIN ( a u )
    2DUP S" ::" SEARCH WHILE ( a1 u1 a3 u3 )
    2 -2 D+  2>R
    R@ - 2 - SFIND IF
    SP@ >R ALSO EXECUTE SP@ R> - 0=
    IF SET-ORDER-TOP THEN
    ELSE
    RDROP RDROP
    NR>  SET-ORDER
    -2011 THROW
    THEN
    2R> REPEAT
  NIP 0= IF 2DROP PARSE-NAME THEN
  ['] EVAL-WORD CATCH
  NR> SET-ORDER THROW
  ELSE RDROP RDROP THEN
;
```

`NOTFOUND` 實作了 `vocname::wordname` 的語法，允許直接指定搜尋特定詞彙表中的字詞。例如 `FORTH::DUP` 表示在 FORTH 詞彙表中搜尋 `DUP`。

解析流程：
1. 先嘗試 `?SLITERAL`（數字解析）
2. 若失敗，搜尋 `::` 分隔字串
3. 將 `::` 前的部分作為詞彙表名，透過 `SFIND` 找到詞彙表
4. 將該詞彙表壓入搜尋順序（`ALSO EXECUTE`）
5. 繼續解析後續的 `::` 分隔部分
6. 最後解析字詞名並執行或編譯

### 10.3 EVALUATE 與 RECEIVE-WITH

```forth
\ spf_translate.f:235-243
: EVALUATE ( i*x c-addr u -- j*x )
  ['] INTERPRET EVALUATE-WITH
;

\ spf_translate.f:226-233
: EVALUATE-WITH ( i*x c-addr u xt -- j*x )
  SAVE-SOURCE N>R
  >R SOURCE! -1 TO SOURCE-ID
  R> ( xt ) CATCH
  NR> RESTORE-SOURCE
  THROW
;
```

`EVALUATE` 的實作非常精巧：
1. `SAVE-SOURCE`：儲存目前所有的輸入來源狀態（SOURCE-ID, SOURCE-ID-XT, >IN, SOURCE, CURSTR）
2. `N>R`：將狀態推入回返堆疊
3. 設定新的輸入來源（`SOURCE!`），並將 `SOURCE-ID` 設為 `-1`（表示 EVALUATE）
4. 執行給定的 xt（預設為 INTERPRET）
5. `NR> RESTORE-SOURCE`：恢復原始輸入來源

這種 SAVE/RESTORE 模式確保了巢狀 EVALUATE 呼叫的正確性。

### 10.4 QUIT：互動式迴圈

```forth
\ spf_translate.f:189-215
: QUIT ( -- ) ( R: i*x )
  BEGIN
    CONSOLE-HANDLES
    0 TO SOURCE-ID
    0 TO SOURCE-ID-XT
    ATIB 0 SOURCE!
    [COMPILE] [
    ['] MAIN1 CATCH         DUP SOURCE NIP 2>R
    ['] ERROR CATCH DROP    2R> 0= IF HALT THEN DROP
    S0 @ SP!
  AGAIN
;
```

`QUIT` 是 SP-Forth 的主迴圈：
1. 設定終端機 I/O（`CONSOLE-HANDLES`）
2. 重設輸入來源為 stdin（`0 TO SOURCE-ID`）
3. 進入直譯模式（`[COMPILE] [`）
4. 執行 `MAIN1`（讀取並直譯一行）
5. 錯誤處理：先捕捉 `MAIN1` 的錯誤，再捕捉 `ERROR` 的錯誤
6. 重設資料堆疊（`S0 @ SP!`）
7. 無限循環（`AGAIN`）

### 10.5 INCLUDED 與模組載入

```forth
\ spf_translate.f:359-372
: INCLUDED_STD ( i*x c-addr u -- j*x )
  CURFILE @ >R
  2DUP HEAP-COPY CURFILE !
  INCLUDE-DEPTH 1+!
  INCLUDE-DEPTH @ 64 > IF -27 THROW THEN
  ['] (INCLUDED) CATCH
  INCLUDE-DEPTH @ 1- 0 MAX INCLUDE-DEPTH !
  CURFILE @ FREE THROW
  R> CURFILE !
  THROW
;
```

INCLUDED 的實作包含：
- **巢狀深度限制**：最大 64 層（防止無限遞迴）
- **CURFILE 追蹤**：記錄目前載入的檔案路徑
- **HEAP-COPY**：將檔案路徑複製到堆積，避免緩衝區覆蓋
- **INCLUDE-DEPTH**：追蹤嵌套深度

### 10.6 SAVE-SOURCE / RESTORE-SOURCE

```forth
\ spf_translate.f:217-224
: SAVE-SOURCE ( -- i*x i )
  SOURCE-ID-XT  SOURCE-ID   >IN @   SOURCE   CURSTR @   6
;
: RESTORE-SOURCE ( i*x i -- )
  6 <> IF ABORT THEN
  CURSTR !    SOURCE!  >IN !  TO SOURCE-ID   TO SOURCE-ID-XT
;
```

這對字用於保存和恢復輸入來源的完整狀態，包含 6 個值：
1. SOURCE-ID-XT
2. SOURCE-ID
3. >IN @
4. SOURCE（c-addr u，佔 2 個值）
5. CURSTR @
6. 計數器（6）

---

## 11. 錯誤處理（spf_error.f）深入解析

### 11.1 ERR-DATA 結構

```forth
\ spf_error.f:22-35
128 CHARS CONSTANT /errstr_
0
1 CELLS     -- err.number
1 CELLS     -- err.line#
1 CELLS     -- err.in#
1 CHARS     -- err.notseen
CELL+       -- err.line    （長度前綴字串，/errstr_ bytes）
CELL+       -- err.file   （長度前綴字串，/errstr_ bytes）
CONSTANT /err-data

USER-CREATE ERR-DATA [T] /err-data [I] TC-USER-ALLOT
```

每個執行緒都有獨立的錯誤資料結構，包含：
- `err.number`：錯誤代碼
- `err.line#`：原始碼行號
- `err.in#`：行內偏移（>IN 值）
- `err.notseen`：布林標記，表示錯誤是否已被「看過」
- `err.line`：原始碼行內容（計數字串，最長 128 字元）
- `err.file`：檔案路徑（計數字串，最長 128 字元）

### 11.2 SAVE-ERR 與 PRINT-LAST-WORD

```forth
\ spf_error.f:111-130
: SAVE-ERR ( err-num -- )
  ERR-DATA err.number !
  SOURCE-FILE-LN DUP 0= IF DROP SOURCE-LN THEN ERR-DATA err.line# !
  >IN @      ERR-DATA err.in#   !
  SOURCE /errstr_ >CHARS UMIN  DUP
             ERR-DATA err.line C!
             ERR-DATA err.line CHAR+ SWAP  CMOVE
         0  ERR-DATA err.line COUNT CHARS + C!
  SOURCE-FILE-PATH DUP 0= IF 2DROP SOURCE-PATH THEN
  /errstr_ >CHARS UMIN  DUP
             ERR-DATA err.file C!
             ERR-DATA err.file CHAR+ SWAP CHARS MOVE
         0  ERR-DATA err.file COUNT CHARS + C!
  NOTSEEN-ERR
;
```

`SAVE-ERR` 在錯誤發生時儲存完整的環境資訊：錯誤碼、行號、偏移、原始碼行內容、檔案路徑。然後設定 `NOTSEEN-ERR` 標記，表示這個錯誤尚未被處理。

`PRINT-LAST-WORD`（第 89~101 行）則負責格式化輸出錯誤資訊：

```forth
: PRINT-LAST-WORD ( -- )
  SEEN-ERR?
  IF
    SOURCE OVER >IN @ SCREEN-LENGTH
  ELSE
    SEEN-ERR
    ERR-STRING
    ERR-LINE DROP ERR-IN# SCREEN-LENGTH
  THEN
  UNROT TYPE0 CR
  2- 0 MAX SPACES [CHAR] ^ EMIT SPACE
;
```

它會在錯誤位置下方顯示一個 `^` 符號，直觀地標示出錯位置。

### 11.3 THROW-ERRMSG 與 (ABORT")

```forth
: THROW-ERRMSG ( sd -- )
  ER-U ! ER-A ! -2 THROW
;

: (ABORT1") ( flag c-addr -- )
  SWAP IF COUNT THROW-ERRMSG ELSE DROP THEN
;
```

`THROW-ERRMSG` 將字串儲存到 `ER-A`/`ER-U`，然後擲回 -2 錯誤碼。`ABORT"` 使用 `_CLITERAL-CODE` 在編譯期嵌入字串，執行期使用 `(ABORT")` 檢查旗標並可能丟出錯誤。

---

## 12. 立即字 — 直譯分支（spf_immed_transl.f）深入解析

### 12.1 TO：VALUE 修改

```forth
\ spf_immed_transl.f:10-26
: TO ( x "<spaces>name" -- )
  '
  9 + STATE @
  IF COMPILE, ELSE EXECUTE THEN
; IMMEDIATE
```

`TO` 的實作極度精巧：
1. `'` 取得字詞的 XT
2. `9 +` 跳過 XT 往前 9 個位元組，到達 `_TOVALUE-CODE` 的 CXF（Call eXecution Field）

這依賴於 VALUE 的字典結構：

```
  ┌──────────────────┐ ← xt（VALUE 的起始）
  │ _CONSTANT-CODE   │ ← 0 bytes offset（CFL=5）
  ├──────────────────┤ ← xt + CFL (= xt + 5)
  │ 常數值           │ ← PFA + 0
  ├──────────────────┤ ← xt + CFL + CELL (= xt + 9)
  │ _TOVALUE-CODE    │ ← 修改程式碼的 CXF
  └──────────────────┘
```

所以 `9 +` = `CFL(5) + CELL(4) = 9`，精確跳到 `_TOVALUE-CODE` 的程式碼欄位。在編譯模式下，`COMPILE,` 會將 `TO` 的目標碼編譯進去；在直譯模式下，`EXECUTE` 直接執行修改。

### 12.2 POSTPONE：延遲編譯

```forth
\ spf_immed_transl.f:28-38
: POSTPONE ( "<spaces>name" -- )
  ?COMP
  PARSE-NAME SFIND DUP
  0= IF -321 THROW THEN
  1 = IF COMPILE,
      ELSE LIT, ['] COMPILE, COMPILE, THEN
; IMMEDIATE
```

POSTPONE 是 Forth 最核心的元程式設計（metaprogramming）工具。它的行為取決於目標字的立即性：

- **立即字**（SFIND 回傳 1）：`COMPILE,` 將該字的 XT 直接編譯進去，執行時會直接執行該立即字
- **非立即字**（SFIND 回傳 -1）：`LIT, ['] COMPILE, COMPILE,` 先編譯 XT 作為常值，再編譯 COMPILE,，執行時會將該 XT 編譯進字典

範例：`POSTPONE IF`（IF 是立即字）→ 編譯 IF 的 XT，執行時直接執行 IF（即時產生條件跳躍代碼）。
範例：`POSTPONE DUP`（DUP 不是立即字）→ 編譯 `LIT, DUP_XT` 後接 `COMPILE,`，執行時將 DUP_XT 編譯進字典。

### 12.3 [COMPILE]：無條件編譯

```forth
\ spf_immed_transl.f:70-80
: [COMPILE] ( "<spaces>name" -- )
  ?COMP
  ' COMPILE,
; IMMEDIATE
```

與 POSTPONE 不同，`[COMPILE]` 無條件地將字的 XT 編譯進去，不管目標字是否為立即字。這在某些需要覆蓋立即字正常行為的場合很有用。

### 12.4 ;（分號）：結束編譯

```forth
\ spf_immed_transl.f:82-86
: ; ( -- )
  RET, [COMPILE] [ SMUDGE ClearJpBuff
  0 TO LAST-NON
; IMMEDIATE
```

分號執行四個動作：
1. `RET,`：編譯返回指令（0xC3）
2. `[COMPILE] [`：回到直譯模式（`[` 是立即字，正常情況下會立即執行；`[COMPILE]` 強制將其編譯進去，使得分號執行後回到直譯模式）
3. `SMUDGE`：恢復字詞可見性（取消 HIDE 的效果）
4. `ClearJpBuff`：清除跳躍最佳化緩衝區

### 12.5 EXIT：提前離開

```forth
\ spf_immed_transl.f:88-90
: EXIT
  RET,
; IMMEDIATE
```

`EXIT` 編譯一條 `RET` 指令，實現從冒號定義中途返回。在 Forth 中，EXIT 等價於 `return` 語句。

---

## 13. 立即字 — 常值分支（spf_immed_lit.f, spf_literal.f）深入解析

### 13.1 LITERAL 與 2LITERAL

```forth
\ spf_immed_lit.f:11-18
: LITERAL ( x -- )
  STATE @ IF LIT, THEN
; IMMEDIATE

: 2LITERAL ( x1 x2 -- )
  STATE @ IF 2LIT, THEN
; IMMEDIATE
```

`LITERAL` 檢查 `STATE`：若在編譯模式下，呼叫 `LIT,` 編譯常值；若在直譯模式下，什麼都不做（值留在堆疊上）。`2LITERAL` 類似但處理雙儲存格常值。

### 13.2 SLITERAL：字串常值

```forth
\ spf_immed_lit.f:29-41
: SLITERAL ( c-addr1 u -- )
  STATE @ IF SLIT, EXIT THEN
  OVER SOURCE OVER + WITHIN 0= IF EXIT THEN
  ALLOCATE-STRING THROW ( c-addr2 u )
; IMMEDIATE
```

SLITERAL 有三種行為：
1. **編譯模式**：呼叫 `SLIT,` 編譯字串常值
2. **直譯模式 + 字串在輸入緩衝區內**：直接使用原始指標（無需拷貝）
3. **直譯模式 + 字串不在輸入緩衝區**：透過 `ALLOCATE-STRING` 在堆積上分配拷貝（因為輸入緩衝區可能被覆蓋）

`SLIT,`（spf_compile.f 第 99~102 行）的編譯結果：

```
  CALL _SLITERAL-CODE    ; 執行期代碼
  <長度>  <字元...>  0   ; 計數字串 + 終止零
```

執行時，`_SLITERAL-CODE` 會回推到計數字串，將（位址, 長度）推入堆疊。

### 13.3 S" 與 C"：字串建構

```forth
\ S" 於 spf_immed_lit.f:47-60；C" 於 spf_immed_lit.f:62-78
: S" ( "ccc<quote>" -- c-addr u )
  [CHAR] " PARSE [COMPILE] SLITERAL
; IMMEDIATE

: C" ( "ccc<quote>" -- c-addr )
  [CHAR] " PeekChar OVER = IF
    DROP >IN 1+!
    SYSTEM-PAD DUP 0!
  ELSE WORD THEN
  [COMPILE] CLITERAL
; IMMEDIATE
```

`S"` 使用 `PARSE` 解析到引號，然後透過 `[COMPILE] SLITERAL` 編譯或直譯字串。

`C"` 的特殊處理：如果引號後緊跟著引號（空字串），直接建立空計數字串；否則使用 `WORD` 解析。這是因為 `WORD` 不支援零長度的字詞。

### 13.4 [']：編譯期取 XT

```forth
\ spf_immed_lit.f:130-143
: ['] ( "<spaces>name" -- )
  ' ( xt )
  STATE @ IF LIT, THEN
; IMMEDIATE
```

`[']` 在編譯期取得字的 XT 並作為常值編譯。在直譯模式下，XT 留在堆疊上（等同於 `'`）。

### 13.5 ABORT"：條件錯誤

```forth
\ spf_immed_lit.f:105-128
: ABORT" ( "ccc<quote>" -- )
  [CHAR] " PARSE
  STATE @ 0= IF ROT IF THROW-ERRMSG ( never ) THEN 2DROP EXIT THEN
  ['] _CLITERAL-CODE COMPILE,
  DUP C, CHARS HERE SWAP DUP ALLOT MOVE 0 C,
  ['] (ABORT") COMPILE,
; IMMEDIATE
```

ABORT" 的編譯期行為：
1. 解析引號內的字串
2. 編譯 `_CLITERAL-CODE` + 計數字串 + 終止零
3. 編譯 `(ABORT")` 的 XT

直譯期行為：檢查堆疊頂端，若為真則呼叫 `THROW-ERRMSG`（擲回 -2 例外帶錯誤訊息），否則丟棄字串。

注意第 123 行的 `( never )` 註解：在直譯模式下，`ROT IF THROW-ERRMSG THEN 2DROP` 實際上永遠不會執行到 `THROW-ERRMSG`，因為 `IF` 只在堆疊頂端為真時執行，而前面沒有推入任何值——但實際上 `ROT` 會將解析的字串位址放到堆疊底部，旗標留在堆疊頂端。不過這段程式碼的設計有點不透明，需要仔細追蹤堆疊才能理解。

### 13.6 數字解析：?SLITERAL1 與 ?SLITERAL2

```forth
\ spf_literal.f:10-26
: ?SLITERAL1 ( c-addr u -> ... )
  0 0 2SWAP
  OVER C@ [CHAR] - = DUP >R IF 1 - SWAP CHAR+ SWAP THEN
  DUP 1 > IF
    2DUP CHARS + CHAR- C@ [CHAR] . = DUP >R IF 1- THEN
  ELSE 0 >R THEN
  DUP 0= IF -2001 THROW THEN
  >NUMBER NIP IF -2001 THROW THEN
  R> IF
       R> IF DNEGATE THEN
       [COMPILE] 2LITERAL
  ELSE D>S
       R> IF NEGATE THEN
       [COMPILE] LITERAL
  THEN
;
```

`?SLITERAL1` 的數字解析流程：
1. 檢查前導負號
2. 檢查小數點（若有則為雙精確度數值）
3. 使用 `>NUMBER` 解析
4. 根據是否有小數點，決定編譯為 `LITERAL`（單精度）或 `2LITERAL`（雙精度）
5. 若有負號，執行 `NEGATE` 或 `DNEGATE`

```forth
\ spf_literal.f:40-64
: ?SLITERAL2 ( c-addr u -- ... )
  DUP 1 > IF OVER W@ 0x7830 ( 0x) =
    IF 2DUP 2>R HEX-SLITERAL IF RDROP RDROP EXIT ELSE 2R> THEN THEN
  THEN
  2DUP 2>R ['] ?SLITERAL1 CATCH
  0= IF RDROP RDROP EXIT THEN
  2DROP 2R>
  DUP 0 U> IF
       OVER C@ [CHAR] " = OVER 2 > AND
       IF 2 - SWAP 1+ SWAP THEN
       DUP 0 U>
  IF
       2DUP + 0 SWAP C!
       ['] INCLUDED CATCH
       DUP 2 <> OVER 3 <> AND OVER 161 <> AND
       IF THROW EXIT THEN
  THEN THEN
  -2003 THROW
;
```

`?SLITERAL2` 是 `?SLITERAL1` 的增強版，增加了：
- **十六進位字首** `0x`：嘗試 `HEX-SLITERAL` 解析
- **檔案包含回退**：如果數字解析失敗，嘗試將字詞作為檔案名稱（`INCLUDED`），這是 SP-Forth 的特色功能——數字和檔案名稱共用同一個回退路徑

---

## 14. 控制結構（spf_immed_control.f, spf_immed_loop.f）深入解析

### 14.1 IF/ELSE/THEN：條件分支

```forth
\ spf_immed_control.f:11-21
: IF ( C: -- orig )
  ?COMP 0 ?BRANCH, >MARK 1
; IMMEDIATE

\ spf_immed_control.f:23-36
: ELSE ( C: orig1 -- orig2 )
  ?COMP 0 BRANCH,
  >ORESOLVE
  >MARK 2
; IMMEDIATE

\ spf_immed_control.f:38-47
: THEN ( C: orig -- )
  ?COMP >ORESOLVE
; IMMEDIATE
```

**堆疊追蹤**：

```
: TEST  42 IF ." forty-two" ELSE ." not" THEN ;
編譯期堆疊變化：

IF:     ?BRANCH, 編譯前向跳躍 → >MARK 1    （orig = 跳躍目標位址的位址）
                           堆疊：( 1 )      ← 1 表示「來自 IF 的前向參考」

ELSE:   BRANCH, 編譯無條件跳躍
        >ORESOLVE 回填 IF 的跳躍目標
        >MARK 2                           （新的前向參考）
                           堆疊：( 2 )      ← 2 表示「來自 ELSE 的前向參考」

THEN:   >ORESOLVE 回填 ELSE 的跳躍目標
                           堆疊：( )
```

**組合語言對照**：

```asm
; IF ... ELSE ... THEN 編譯結果：
        ?BRANCH,  else_addr      ; 若 TOS 為零，跳到 ELSE 部分
        ...=true body...         ; IF 為真時執行
        JMP      then_addr       ; 跳過 ELSE 部分
else_addr:                       ; ELSE 起始
        ...false body...         ; IF 為假時執行
then_addr:                       ; THEN 起始
```

### 14.2 BEGIN/UNTIL/WHILE/REPEAT：迴圈結構

```forth
\ spf_immed_control.f:49-60
: BEGIN ( C: -- dest )
  ?COMP
  ALIGN-BYTES @ ALIGN-NOP
  <MARK 3
; IMMEDIATE

\ spf_immed_control.f:62-74
: UNTIL ( C: dest -- )
  ?COMP 3 <> IF -2004 THROW THEN
  ?BRANCH,
  0xFFFFFF80 DP @ 4 - @ U<
  IF DP @ 5 - W@ 0x3F0 + DP @ 6 - W! -4 ALLOT THEN
  DP @ TO :-SET
; IMMEDIATE
```

`BEGIN` 在編譯期堆疊上留下 `3`（標記類型為「後向參考」），`UNTIL` 驗證堆疊頂端確實是 3，然後編譯條件跳躍。

`UNTIL` 中有一段**短跳躍最佳化**（第 71~73 行）：

```forth
0xFFFFFF80 DP @ 4 - @ U<
IF DP @ 5 - W@ 0x3F0 + DP @ 6 - W! -4 ALLOT THEN
```

如果跳躍距離在 -128 bytes 以內（0xFFFFFF80 是 -128 的無號表示），可以將 `0F 84`（6 bytes 的 JZ near）最佳化為 `7x`（2 bytes 的 JZ short）。這個最佳化修改了已編譯的機器碼，將 `0F 84 xx xx xx xx` 改為 `74 xx`，並回收 4 bytes。

### 14.3 REPEAT 與 AGAIN

```forth
\ spf_immed_control.f:90-105
: REPEAT ( C: orig dest -- )
  ?COMP
  3 <> IF -2005 THROW THEN
  DUP DP @ 2+ - DUP SHORT?
  IF SetJP 0xEB C, C, DROP         \ JMP short（2 bytes）
  ELSE DROP BRANCH, THEN             \ JMP near（5 bytes）
  >ORESOLVE
; IMMEDIATE
```

`REPEAT` 和 `AGAIN` 都有短跳躍最佳化：如果後向跳躍距離在 -127 bytes 以內，使用 2 bytes 的短跳躍（`0xEB` opcode）而非 5 bytes 的近跳躍。

### 14.4 DO/LOOP：計數迴圈

```forth
\ spf_immed_loop.f:15-36
: DO ( C: -- do-sys )
  ?COMP
  ['] C-DO INLINE,                   \ 內聯 C-DO 的機器碼
  SetOP 0x68 C, DP @ 4 ALLOT          \ PUSH imm32（留空間給界限值）
  SetOP 0x52 C,                       \ PUSH EDX
  SetOP 0x53 C,                       \ PUSH EBX
  ALIGN-BYTES @ ALIGN-NOP             \ 對齊迴圈體
  DP @ DUP TO :-SET
; IMMEDIATE
```

DO 的編譯結果：

```asm
; DO 編譯結果：
        <C-DO 的內聯代碼>     ; 內聯 C-DO
        PUSH imm32             ; 下限值（LEAVE 目標跳躍位址）
        PUSH EDX               ; 保存暫存器
        PUSH EBX               ; 保存暫存器
        NOP 對齊填充           ; 16-byte 對齊
        ...迴圈體...           ; 迴圈起始（HERE 點）
```

注意要區分兩種視角，避免混淆：

**(1) DO prologue 三個 PUSH 剛執行完的瞬間佈局** — 依 `PUSH imm32 → PUSH EDX → PUSH EBX` 的順序，PUSH 會讓 ESP 遞減，因此最後 push 的 EBX 在最上面：

```
ESP+0  → [EBX 保存值]      ← 最後 push，位於頂端
ESP+4  → [EDX 保存值]
ESP+8  → [LEAVE 目標位址]  ← imm32，最先 push
```

**(2) 進入迴圈體後的概念佈局** — 此時 `C-DO` 已把界限與索引轉成迴圈計數器放在 `EDX`／`EAX` 等暫存器中（`I` 由暫存器計算，不是直接讀 ESP 頂端）；回返堆疊上保留的是上面那三項（EBX、EDX、LEAVE 目標）。`LOOP`／`+LOOP` 收尾時用 `LEA ESP, 0C [ESP]` 一次清掉這 3 個 4-byte 項（共 12 = 0x0C 位元組），再回填 LEAVE 目標。

> 換言之，「迴圈索引／界限」並不是固定躺在 `ESP+0`／`ESP+4`；那是計數器在暫存器中的邏輯狀態。堆疊上真正存的是 EBX／EDX 的保存值與 LEAVE 目標位址。

### 14.5 LOOP 與 +LOOP

```forth
\ spf_immed_loop.f:60-81
: LOOP ( C: do-sys -- )
  ?COMP
  24 04FF W, C,       \ inc dword [esp]         — 遞增索引
  042444FF ,          \ inc dword 4[esp]         — 遞增界限
  HERE 2+ - DUP SHORT? SetOP SetJP
  IF 71 C, C,          \ jno short                — 索引溢出時跳出
  ELSE 4 - 0F C, 81 C, , \ jno near              — 近跳躍版本
  THEN    SetOP
  0C24648D ,           \ lea esp, 0c [esp]       — 清理回返堆疊
  DP @ SWAP !          ; 回填 LEAVE 目標位址
```

**LOOP 的組合語言對照**：

```asm
; LOOP 編譯結果：
    inc dword [esp]          ; 索引++
    inc dword 4[esp]         ; 界限++（用於 +LOOP 的步進檢測）
    jno short/near loop_top  ; 若無溢出，跳回迴圈起始
    lea esp, 0c [esp]        ; 清理迴圈參數（3 個值 × 4 bytes = 12 bytes）
    ; LEAVE 目標位址被回填到 DO 時的 PUSH imm32
```

**JNO 技巧**：SP-Forth 使用 **溢出旗標**（Overflow Flag）來檢測迴圈結束。當索引遞增造成溢出時（即跨越了有號數的邊界），JNO 不跳轉，迴圈結束。這是 SP-Forth 迴圈實作的獨創設計——大多數 Forth 實作使用比較來檢測迴圈結束，而 SP-Forth 利用 CPU 的溢出旗標，避免了額外的比較指令。

### 14.6 +LOOP 的步進邏輯

```forth
\ spf_immed_loop.f:83-106
: +LOOP ( C: do-sys -- )
  ?COMP
  ['] ADD[ESP],EAX INLINE,     \ add [esp], EAX          — 索引 += 步進值
  04244401 ,                    \ ADD 4[ESP], EAX         — 界限 += 步進值
  ['] DROP INLINE,               \ 丟棄步進值
  HERE 2+ - DUP SHORT? SetOP SetJP
  IF 71 C, C,
  ELSE 4 - 0F C, 81 C, ,
  THEN    SetOP
  0C24648D ,                    \ lea esp, 0c [esp]       — 清理迴圈參數
  DP @ SWAP !
; IMMEDIATE
```

+LOOP 與 LOOP 的差異：
- LOOP 使用 `INC`（固定步進 +1）
- +LOOP 使用 `ADD`（可變步進值在 TOS 中）
- +LOOP 在迴圈體開始時 TOS 是步進值，迴圈體結束後會 DROP 步進值

### 14.7 I：迴圈索引存取

```forth
\ spf_immed_loop.f:108-114
: I ( -- n|u ) ( R: loop-sys -- loop-sys )
  ?COMP  ['] C-I  INLINE,
; IMMEDIATE
```

`I` 內聯 `C-I` 的機器碼（在核心中定義為 `MOV EAX, [ESP]`），直接從回返堆疊讀取迴圈索引，不經過任何中間層。

### 14.8 LEAVE 與 UNLOOP

```forth
\ spf_immed_loop.f:116-125
: LEAVE ( -- ) ( R: loop-sys -- )
  ?COMP
  SetOP 0824648D ,   \ lea esp, 08 [esp]     — 跳過索引和界限
  SetOP C3 C,         \ ret                    — 跳到 DO 的 PUSH imm32 指定的位址
; IMMEDIATE

: UNLOOP ( -- ) ( R: loop-sys -- )
  ?COMP
  SetOP 0C24648D ,    \ lea esp, 0c [esp]     — 清理全部 3 個值
; IMMEDIATE
```

`LEAVE` 的實作是**函式返回**技巧：它將 ESP 調整到跳過索引和界限的位置（lea esp, 8[esp]），然後 `RET`——這會跳到 DO 時 `PUSH imm32` 推入的位址（恰好是迴圈結束後的位置）。

`UNLOOP` 則是清理全部迴圈參數（3 個值 × 4 bytes = 12 bytes = 0x0C），通常在 EXIT 之前使用。

### 14.9 CASE/OF/ENDOF/ENDCASE

CASE 結構定義在 `spf.f` 中（而非 spf_immed_control.f），使用資料堆疊追蹤配對：

```forth
: CASE ( C: -- case-sys )   CSP @ SP@ CSP ! ; IMMEDIATE
: OF ( C: case-sys -- orig case-sys )   OVER = ?OF ; IMMEDIATE
: ENDOF ( C: orig case-sys -- orig case-sys )   ELSE ; IMMEDIATE
: ENDCASE ( C: orig1 orig2 ... orign case-sys -- )
  DROP DUPENDCASE ; IMMEDIATE
```

CASE 結構的編譯期堆疊追蹤：
- `CASE`：儲存目前堆疊指標到 CSP
- `OF`：編譯比較和條件跳躍
- `ENDOF`：等同 ELSE
- `ENDCASE`：編譯 DROP，回填所有跳躍

---

## 15. 模組載入（spf_modules.f）深入解析

### 15.1 MODULE: / EXPORT / ;MODULE

```forth
\ spf_modules.f:7-23
: MODULE: ( "name" -- old-current )
  >IN @
  ['] ' CATCH
  IF >IN ! VOCABULARY LATEST-NAME-XT ELSE NIP THEN
  GET-CURRENT SWAP ALSO EXECUTE DEFINITIONS
;

: EXPORT ( old-current -- old-current )
  DUP SET-CURRENT
;

: ;MODULE ( old-current -- )
  SET-CURRENT PREVIOUS
;
```

模組系統的運作方式：
1. `MODULE:` 建立或重用一個詞彙表，將其加入搜尋順序並設為 CURRENT
2. `EXPORT` 切換回模組外的詞彙表（通常是 FORTH-WORDLIST），使得後續定義對外部可見
3. `;MODULE` 恢復原始的 CURRENT 並移除模組詞彙表從搜尋順序

`MODULE:` 的技巧在於 `['] ' CATCH`：它先嘗試用 `'` 找到同名的詞彙表，若找到則重用（`NIP`），若找不到則建立新的（`VOCABULARY`）。

### 15.2 {{ }}：快速詞彙表切換

```forth
\ spf_modules.f:25-36
: {{ ( "name" -- )
  DEPTH >R ALSO ' EXECUTE
  DEPTH R> <> IF SET-ORDER-TOP THEN
; IMMEDIATE

: }} ( -- )
  PREVIOUS
; IMMEDIATE
```

`{{` 將指定詞彙表壓入搜尋順序。特殊處理：如果該名字不是 VOCABULARY（而是 wid），則 `SET-ORDER-TOP` 替換搜尋順序頂端而非壓入。

---

## 16. 內聯展開（spf_inline.f）深入解析

### 16.1 內聯最佳化字集

```forth
\ spf_inline.f:3-19
: R>     ['] C-R>    INLINE, ;   IMMEDIATE
: >R     ['] C->R    INLINE, ;   IMMEDIATE
: RDROP  ['] C-RDROP INLINE, ;   IMMEDIATE

: ?DUP   STATE @
  IF HERE TO :-SET
     ['] C-?DUP  INLINE,
     HERE TO :-SET
  ELSE ?DUP
  THEN ;   IMMEDIATE

: EXECUTE STATE @ IF
  ['] C-EXECUTE INLINE,
  ELSE EXECUTE
  THEN ; IMMEDIATE
```

這些字在編譯模式下會**內聯展開**而非產生 CALL 指令。例如：

- `>R` 不產生 `CALL C->R`，而是直接嵌入 `PUSH EAX; MOV EAX, [EBP]; LEA EBP, 4[EBP]; JMP EBX` 的機器碼
- `?DUP` 在編譯模式下內聯 `C-?DUP` 的代碼，在直譯模式下執行 `?DUP`

注意 `?DUP` 和 `EXECUTE` 有 `STATE @` 檢查——它們在直譯和編譯模式下有不同的行為。這是 Forth 的標準模式：**立即字可以根據 STATE 選擇不同的實作策略**。

### 16.2 內聯展開與非最佳化字集的關係

在 `spf_nonopt.f` 中定義的 `RDROP`、`>R`、`R>`、`?DUP`、`EXECUTE` 是**非最佳化版本**（用 `CODE1` 定義）。在 `spf_inline.f` 中同名字的是**最佳化版本**（用 `INLINE,` 定義），它們在編譯時會被內聯展開。

最佳化器在處理 `COMPILE,` 時的決策路徑：

```
COMPILE, ( xt )
  ├─ CON>LIT 回傳 FALSE？ → 已由 CON>LIT 處理（常數/USER/CREATE 等特殊序列）
  └─ CON>LIT 回傳 TRUE？
       ├─ INLINE? 偵測到短定義？ → INLINE,（內聯展開）
       └─ 否                    → _COMPILE,（產生 CALL）
```

`INLINE?` 檢查一個字的機器碼是否短到值得內聯（通常 ≤ 10~15 位元組）。`INLINE,` 將目標字的機器碼直接拷貝到目前編譯位置，省去 CALL/RET 的開銷。

---

## 17. 編譯器整體流程圖

以下是 INTERPRET 迴圈的完整決策流程：

```
┌─────────────────────────────────────────────────────────────────────┐
│                        INTERPRET 迴圈                               │
│                                                                     │
│    PARSE-NAME                                                       │
│       │                                                             │
│       ├── 空字串 → 結束（REFILL 繼續下一行）                         │
│       │                                                             │
│       ├── SFIND 搜尋                                                │
│       │    ├── 找到，旗標 = -1（非立即字）                          │
│       │    │    ├── STATE = 編譯模式 → COMPILE,                     │
│       │    │    │    ├── CON>LIT 已處理 → 不再產生一般 CALL          │
│       │    │    │    ├── CON>LIT 需續編 + INLINE? → INLINE,          │
│       │    │    │    └── CON>LIT 需續編 + 非內聯 → _COMPILE,         │
│       │    │    └── STATE = 直譯模式 → EXECUTE                       │
│       │    │                                                        │
│       │    ├── 找到，旗標 = 1（立即字）                              │
│       │    │    └── 立即執行（不論 STATE）                           │
│       │    │                                                        │
│       │    └── 未找到                                               │
│       │         ├── NOTFOUND 向量（vocname::wordname 語法）         │
│       │         └── ?SLITERAL（數字解析）                            │
│       │              ├── ?SLITERAL1（基本解析）                       │
│       │              └── ?SLITERAL2（0x 字首、INCLUDED 回退）       │
│       │                                                              │
│       └── ?STACK（堆疊溢位檢查）                                     │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### 17.1 編譯器模組互動圖

```
                    ┌──────────────────────┐
                    │   spf_parser.f       │
                    │   NextWord, PARSE    │
                    └──────────┬───────────┘
                               │
                    ┌──────────▼───────────┐
                    │   spf_find.f          │
                    │   SFIND, FIND-NAME   │
                    └──────────┬───────────┘
                               │
                    ┌──────────▼───────────┐
                    │   spf_translate.f     │
                    │   INTERPRET_          │
                    └──────────┬───────────┘
                               │
              ┌────────────────┼────────────────┐
              │                │                │
    ┌─────────▼──────┐ ┌──────▼───────┐ ┌──────▼───────┐
    │ spf_compile.f  │ │ spf_literal.f│ │ spf_defwords.f│
    │ COMPILE,       │ │ ?SLITERAL    │ │ SHEADER等    │
    │ CON>LIT hook   │ │ LITERAL      │ │ CREATE等     │
    │ INLINE         │ │ 2LITERAL     │ │ DOES>        │
    └────────┬───────┘ └──────────────┘ └───────────────┘
             │
    ┌────────▼────────────────────────────────────────┐
    │  spf_immed_control.f + spf_immed_loop.f        │
    │  IF/ELSE/THEN, DO/LOOP, BEGIN/UNTIL/REPEAT     │
    └─────────────────────────────────────────────────┘
```

---

## 18. 技術總結

### 18.1 SP-Forth 編譯器的核心設計特點

1. **TOS-in-EAX 模型貫穿全域**：從 `LIT,` 的 `MOV EAX, #imm32` 到 `>R` 的堆疊操作，所有編譯決策都圍繞 EAX 作為 TOS 快取的模型設計。

2. **三層編譯策略**：`COMPILE,` 先呼叫 `CON>LIT`；若 `CON>LIT` 已處理特殊序列則停止，否則再走 `INLINE?`（內聯展開）或 `_COMPILE,`（普通呼叫），形成遞進的最佳化策略。

3. **條件跳躍的 opcode 可變性**：`?BRANCH,` 中的 `J_COD` 變數允許最佳化器修改條件碼（如 JZ → JNZ），實現 `IF/THEN` 和 `UNTIL` 的統一處理。

4. **溢出旗標迴圈檢測**：`DO/LOOP` 使用 CPU 溢出旗標而非比較指令，這是 x86 Forth 實作中的創新設計。

5. **模組系統的詞彙表重定向**：`MODULE:` 建立暫時詞彙表，`DP` 根據 `IS-TEMP-WL` 自動切換字典指標，實現編譯隔離。

6. **NOTFOUND 的 `::` 語法**：允許 `vocname::wordname` 形式的限定位址解析，提供了類似 C++ 的命名空間限定語法。

7. **短跳躍最佳化**：`UNTIL` 和 `REPEAT` 中有 IF 距離檢測，將 6 bytes 的近條件跳躍最佳化為 2 bytes 的短跳躍。

8. **SMUDGE/HIDE 機制**：透過修改名稱欄位的第二個位元組為 12 來隱藏正在編譯的定義，防止遞迴參照未完成的定義。
