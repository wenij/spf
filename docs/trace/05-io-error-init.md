# SP-Forth/4 原始碼追蹤 — 輸出入、例外處理與系統初始化

> 對應原始碼：`spf_con_io.f`、`spf_print.f`、`spf_except.f`、`spf_init.f`、`spf_module.f`、
> `compiler/spf_error.f`、`compiler/spf_read_source.f`、`compiler/spf_translate.f`、
> `spf_forthproc_hl.f`、`posix/con_io.f`、`posix/io.f`、`posix/envir.f`、
> `posix/init.f`、`posix/except.f`、`posix/module.f`、
> `win/spf_win_con_io.f`、`win/spf_win_init.f`、`win/spf_win_api.f`

> 本章目標：從 ACCEPT/EMIT 到 CATCH/THROW 再到 QUIT 主迴圈，掌握 SP-Forth 執行期的完整生命週期。
>
> 範圍說明：本文件著重 **I/O、例外、初始化與互動式執行期生命週期**；若你要先看 POSIX 平台的 FFI、執行緒與信號原語本身，請先讀 [04-posix-platform.md](04-posix-platform.md)。

---

## 1. 控制台 I/O 架構（spf_con_io.f + posix/con_io.f + win/spf_win_con_io.f）

### 1.1 雙層架構

控制台 I/O 採用平台相關／跨平台雙層架構：

```forth
┌──────────────────────────────────────────┐
│  跨平台層（spf_con_io.f）                │
│  STARTLOG / ENDLOG / TO-LOG             │
│  ACCEPT1 / TYPE1 / EMIT / CR / EOLN     │
├──────────────────────────────────────────┤
│  平台相關層                               │
│  POSIX: posix/con_io.f                  │
│  Win32: win/spf_win_con_io.f            │
├──────────────────────────────────────────┤
│  VECT 向量層                             │
│  ACCEPT / TYPE / KEY / KEY? / ANSI><OEM │
└──────────────────────────────────────────┘
```

spf_con_io.f 開頭透過條件編譯選擇平台（`spf_con_io.f:8-13`）：

```forth
TARGET-POSIX [IF]
  S" src/posix/con_io.f" INCLUDED
[ELSE]
  S" src/win/spf_win_con_io.f" INCLUDED
[THEN]
```

### 1.2 POSIX 控制台 I/O（posix/con_io.f）

POSIX 版的控制台 I/O 極為精簡（僅 18 行），使用標準檔案描述詞：

```forth
0 VALUE  H-STDIN     \ 標準輸入 - 預設檔案描述詞 0
1 VALUE  H-STDOUT    \ 標準輸出 - 預設檔案描述詞 1
2 VALUE  H-STDERR    \ 標準錯誤 - 預設檔案描述詞 2
0 VALUE  H-STDLOG   \ 日誌檔案描述詞（初始為 0）

VECT ANSI><OEM
' NOOP ' ANSI><OEM TC-VECT!   \ POSIX 版為空操作（無需編碼轉換）

VECT KEY
' FALSE ' KEY  TC-VECT!        \ KEY 暫時回傳 FALSE（待終端機驅動替換）

VECT KEY?
' FALSE ' KEY? TC-VECT!       \ KEY? 暫時回傳 FALSE
```

**設計要點**：
- H-STDIN/H-STDOUT/H-STDERR 直接使用 POSIX 標準檔案描述詞 0/1/2
- `ANSI><OEM` 在 POSIX 上為空操作（NOOP）：POSIX 版不做 Windows 的 OEM/ANSI 轉換；實際編碼由終端機與 locale 決定，並非「UNIX 系統統一使用同一字元編碼」
- `KEY` 和 `KEY?` 初始為 FALSE，表示預設不支援互動式鍵盤輸入；POSIX 環境可由 `lib/posix/key.f` 以 termios 方式提供 `KEY-TERMIOS` 並替換 `KEY`
- H-STDLOG 初始為 0，僅在 STARTLOG 後才指向實際日誌檔案描述詞

### 1.3 Windows 控制台 I/O（win/spf_win_con_io.f）

Windows 版提供完整的控制台輸入支援，核心是 `EKEY` 和 `EKEY?` 系統（`spf_win_con_io.f:11-99`）。

**EKEY?**（第 11-18 行）— 檢查是否有按鍵事件：

```forth
: EKEY? ( -- flag )
  0 >R RP@ H-STDIN GetNumberOfConsoleInputEvents DROP R>
;
```

這是 ACherezov 的經典技巧：用回返堆疊（return stack）的 4 位元組空間直接當作 `DWORD` 緩衝區，避免在資料堆疊配置。`H-STDIN` 是 Windows `HANDLE`（非檔案描述詞）。

**INPUT_RECORD 結構**（第 20 行）：

```forth
CREATE INPUT_RECORD ( /INPUT_RECORD) 20 2 * CHARS ALLOT
```

`INPUT_RECORD` 佔 40 位元組（`20 * 2 CHARS`），足夠容納 Windows 的 `INPUT_RECORD` 結構（實際大小為 20 位元組，但以 2 倍空間分配以策安全）。

結構偏移（根據第 22-42 行的程式碼實際存取推斷）：

| 偏移（位元組） | 欄位 | 說明 |
|:---|:---|:---|
| 0 | EventType | 事件類型（KEY_EVENT=1） |
| 4 | bKeyDown | 按下/釋放旗標（第 42 行：`04 +`，以 `C@` 讀取） |
| 12 | wVirtualScanCode | 掃描碼（第 41 行：`12 +`，左移 16 位） |
| 14 | AsciiChar | 字元碼（第 40 行：`14 +`，低 8 位由 `EKEY>CHAR` 取出） |
| 16 | dwControlKeyState | 控制鍵狀態（第 23 行：`16 +`） |

注意：這張表描述的是 SP-Forth 程式碼實際讀取的 offset，而不是完整 Win32 `INPUT_RECORD` / `KEY_EVENT_RECORD` C 結構宣告。

**EKEY**（第 29-43 行）— 讀取擴充鍵事件：

```forth
: EKEY ( -- u )
  0 >R RP@ 2 INPUT_RECORD H-STDIN     \ 讀取 2 筆輸入記錄
  ReadConsoleInputA DROP RDROP
  INPUT_RECORD W@ KEY_EVENT <> IF 0 EXIT THEN    \ 非按鍵事件忽略
  [ INPUT_RECORD 14 + ] LITERAL W@     \ AsciiChar / 字元碼
  [ INPUT_RECORD 12 + ] LITERAL W@ 16 LSHIFT OR \ 掃描碼 << 16
  [ INPUT_RECORD 04 + ] LITERAL C@  24 LSHIFT OR \ bKeyDown << 24
;
```

回傳值 `u` 的位元佈局：

| 位元範圍 | 內容 | 說明 |
|:---|:---|:---|
| 0-7 | AsciiChar | ASCII/Unicode 字元 |
| 16-23 | wVirtualScanCode | 掃描碼 |
| 24 | bKeyDown | 1=按下，0=釋放 |

**EKEY>CHAR**（第 46-52 行）— 從擴充鍵事件中提取字元：

```forth
: EKEY>CHAR ( u -- u false | char true )
  DUP FF000000 AND 0= IF FALSE EXIT THEN   \ bKeyDown=0 → 無效
  DUP 000000FF AND DUP IF NIP TRUE EXIT THEN DROP \ ASCII≠0 → 有效字元
  FALSE                                     \ 特殊鍵（功能鍵等）
;
```

三個判斷路徑：
1. `bKeyDown=0`（按鍵釋放事件）→ 回傳原值 + FALSE
2. `AsciiChar≠0`（可列印字元）→ 回傳字元 + TRUE
3. `AsciiChar=0` 且 `bKeyDown=1`（特殊鍵按下）→ 回傳原值 + FALSE

**KEY? 和 KEY**（第 64-99 行）— 高層鍵盤輸入：

```forth
VARIABLE PENDING-CHAR   \ 暫存已讀取但未取走的字元

: KEY? ( -- flag )
  PENDING-CHAR @ 0 > IF TRUE EXIT THEN     \ 有暫存字元
  BEGIN
    EKEY?                                   \ 有按鍵事件？
  WHILE
    EKEY EKEY>CHAR                          \ 讀取並嘗試提取字元
    IF PENDING-CHAR ! TRUE EXIT THEN       \ 是可列印字元 → 暫存並回傳 TRUE
    DROP                                    \ 非可列印 → 繼續
  REPEAT FALSE                              \ 無按鍵事件
;

: KEY1 ( -- char )
  PENDING-CHAR @ 0 >
  IF PENDING-CHAR @ -1 PENDING-CHAR ! EXIT THEN  \ 取出暫存字元
  BEGIN
    EKEY EKEY>CHAR 0=                              \ 等待可列印字元
  WHILE DROP REPEAT
;
' KEY1 ' KEY TC-VECT!                             \ 設定 KEY 向量
```

`PENDING-CHAR` 是鍵盤「先讀」（look-ahead）緩衝：`KEY?` 讀取 EKEY 後發現可列印字元時暫存於此，等待後續 `KEY` 取走。原始碼只宣告 `VARIABLE PENDING-CHAR`，沒有顯式初始化為 -1；因此初始值依 Forth 變數初始化規則為 0。讀出暫存字元後，`KEY1` 會寫入 -1 作為「已取走」標記。

### 1.4 日誌系統

| 字 | 堆疊效果 | 說明 |
|----|---------|------|
| `STARTLOG` | `( -- )` | 開啟 `spf.log` 日誌檔案 |
| `ENDLOG` | `( -- )` | 關閉日誌檔案 |
| `TO-LOG` | `( addr u -- )` | 寫入日誌（若 H-STDLOG 非 0） |

**STARTLOG**實作（`spf_con_io.f:25-33`）：

```forth
: STARTLOG ( -- )
  ENDLOG                                    \ 先關閉已有日誌
  S" spf.log" W/O                          \ 唯寫模式
  CREATE-FILE-SHARED THROW                 \ 建立檔案（POSIX 版等同 CREATE-FILE）
  TO H-STDLOG                               \ 設定日誌檔案描述詞
;
```

**ENDLOG**（`spf_con_io.f:15-23`）：

```forth
: ENDLOG
  H-STDLOG IF
    H-STDLOG CLOSE-FILE                     \ 關閉日誌檔案
    0 TO H-STDLOG                            \ 重設為 0
    THROW                                    \ 例外處理
  THEN
;
```

**TO-LOG**（`spf_con_io.f:35-38`）：

```forth
: TO-LOG ( addr u -- )
  H-STDLOG IF H-STDLOG WRITE-FILE 0 THEN 2DROP
;
```

TO-LOG 使用 `0 THEN 2DROP` 模式：若 `WRITE-FILE` 失敗（回傳非零 ior），直接丟棄 ior；若 H-STDLOG 為 0，則完全跳過寫入。

### 1.5 ACCEPT1

```forth
: ACCEPT1 ( c-addr +n1 -- +n2 )
  OVER SWAP H-STDIN READ-LINE        \ READ-LINE 回傳 ( u flag ior )
  DUP 109 = IF DROP -1002 THEN THROW \ 先處理 ior：pipe 斷線相容（109 = Windows ERROR_BROKEN_PIPE）
  0= IF -1002 THROW THEN             \ 此時 TOS 是 flag；flag=false(0) → 輸入結束(EOF)
  TUCK TO-LOG                        \ 寫入日誌
  EOLN TO-LOG                        \ 寫入換行
;
```

三條路徑：
1. **錯誤碼 109（Windows ERROR_BROKEN_PIPE 相容處理）**：管道斷線，THROW -1002。POSIX 的 `EPIPE` 通常不是 109，因此這裡不要理解成 POSIX errno 名稱。
2. **`flag = false`（EOF）**：`READ-LINE` 的旗標為 false 代表輸入結束，THROW -1002。注意檢查的是**旗標**，不是「讀取長度為 0」——空白行是 `u=0, flag=true`，屬正常讀取，不會 THROW。
3. **正常讀取**：回傳長度，並寫入日誌

注意：`H-STDIN READ-LINE` 是 POSIX 版的檔案 I/O（見第 5 節），Windows 版使用不同的 READ-LINE 實作。

### 1.6 TYPE1

```forth
: TYPE1 ( c-addr u -- )
  ANSI><OEM                \ POSIX 版為空操作；Windows 版做 OEM 編碼轉換
  2DUP TO-LOG              \ 寫入日誌
  H-STDOUT DUP 0 > IF WRITE-FILE THROW ELSE 2DROP DROP THEN
;
```

`H-STDOUT DUP 0 >` 檢查：若 H-STDOUT ≤ 0（例如在無終端機的daemon模式下），直接丟棄輸出而不發生錯誤。

### 1.7 基本輸出字

| 字 | 堆疊效果 | 實作說明 |
|----|---------|---------|
| `EMIT` | `( x -- )` | `>R RP@ 1 TYPE`：利用回返堆疊暫存字元，將回返堆疊頂端 1 位元組的位址傳給 TYPE |
| `CR` | `( -- )` | `EOLN TYPE`：輸出行結束序列（LF 或 CRLF，取決於 NATIVE-LINES 設定） |
| `BL` | `( -- 32 )` | `32 VALUE BL`：空白字元常數 |
| `SPACE` | `( -- )` | `BL EMIT` |
| `SPACES` | `( n -- )` | 迴圈輸出 n 個空白，n<1 時直接離開 |

**EMIT 的特殊技巧**（`spf_con_io.f:71-76`）：

```forth
: EMIT ( x -- ) \ 94
  >R RP@ 1 TYPE
  RDROP
;
```

這是 SP-Forth 利用 TOS-in-EAX 模型的技巧：`>R` 將字元值推入回返堆疊，`RP@` 取得回返堆疊頂端位址作為字串起始位址，長度為 1，呼叫 TYPE 輸出。最後 `RDROP` 清理回返堆疊。

---

## 2. 行結束常數與換行模式（spf_forthproc_hl.f）

### 2.1 LT 與 LTL

```forth
CREATE LT 0A0D ,    \ 行結束序列：0D0A（小端序），即 CRLF
CREATE LTL 2 ,      \ 行結束序列長度：2 位元組
```

`LT` 儲存行結束序列的位元組模式（`0A0D` 在小端序機器上存為位元組序列 `0D 0A`，即 CRLF），`LTL` 儲存長度。

### 2.2 EOLN

```forth
: EOLN ( -- a u ) LT LTL @ ;
```

`EOLN` 回傳行結束序列的位址和長度。根據 `LTL @` 的值：
- UNIX 模式：`LTL @` = 1，`LT` 包含 `0A`（LF）
- DOS/Windows 模式：`LTL @` = 2，`LT` 包含 `0D 0A`（CRLF）

### 2.3 NATIVE-LINES

```forth
UNIX-ENVIRONMENT [IF]
: NATIVE-LINES UNIX-LINES ;   \ 設定 LF 為行結束
[ELSE]
: NATIVE-LINES DOS-LINES ;    \ 設定 CRLF 為行結束
[THEN]
```

```forth
: UNIX-LINES ( -- ) 0A0A LT ! 1 LTL ! ;   \ 0A（LF）
: DOS-LINES ( -- )   0A0D LT ! 2 LTL ! ;   \ 0D 0A（CRLF）
```

注意到 `UNIX-LINES` 將 `0A0A` 寫入 LT（小端序儲存為 `0A 0A`），但實際使用時只取前 `LTL @` = 1 位元組，即 `0A`。這是因為 CELL 是 4 位元組但 `EOLN` 只回傳前 `LTL @` 個位元組。

---

## 3. 數值輸出（spf_print.f）

### 3.1 核心變數

| 變數 | 類型 | 說明 |
|------|------|------|
| `HLD` | USER | 數值輸出緩衝區指標，指向 PAD 之前的位置（逆向建構字串） |
| `BASE` | USER | 數值基數（2~36） |
| `SYSTEM-PAD` | USER-CREATE（4096 位元組） | 系統暫存區，供內部使用 |
| `/SYSTEM-PAD` | 常數 | SYSTEM-PAD 的大小（4096） |
| `PAD` | USER-CREATE（1024 位元組） | 使用者暫存區，ANS 標準 PAD |

SYSTEM-PAD 和 PAD 都是 USER-CREATE，每個執行緒有獨立的副本。PAD 位於 SYSTEM-PAD 之前，兩者共用連續記憶體空間。數值格式化從 PAD 的前一個位元組開始逆向建構（`<#` 設定 HLD = PAD - 1），以 SYSTEM-PAD 作為下界保護。

### 3.2 數值格式化流程

完整格式化流程：`<#` → `#`/`#S`/`SIGN` → `#>`

**`<#`**（`spf_print.f:48-52`）— 開始格式化：

```forth
: <# ( -- )
  PAD CHAR- HLD !     \ HLD 指向 PAD 的前一個位元組
  0 PAD CHAR- C!       \ 在 PAD-1 位置放置空字元（字串結束標記）
;
```

格式化緩衝區的記憶體佈局：

```forth
低位址                                     高位址
┌──────────────────────────────────┬───┬──┬────────────┐
│  SYSTEM-PAD                      │\0│  │  PAD       │
│  （4096 bytes）                   │  │  │  (1024B)   │
└──────────────────────────────────┴───┴──┴────────────┘
                                    ^
                                    HLD 初始值 = PAD CHAR-
                                    空字元標記
```

**`#`**（`spf_print.f:54-63`）— 轉換一位數字：

```forth
: # ( ud1 -- ud2 )
  0 BASE @ UM/MOD >R       \ ud1 / BASE → 餘數（低位）在堆疊，高位在 R
  BASE @ UM/MOD R>          \ 繼續除法，取得商和餘數
  ROT DUP 10 < 0= IF 7 + THEN 48 +   \ 數字→ASCII：0-9 直接加 48，A-Z 加 55
  HOLD                       \ 插入到 HLD 位置
;
```

數字轉換演算法的雙精確度除法步驟：

1. `0 BASE @ UM/MOD`：`(ud_low 0) / BASE` → 商（高位）+ 餘數
2. `BASE @ UM/MOD R>`：`(ud_high 商) / BASE` + 餘數 → 最終雙精確度商 + 數字值

ASCII 轉換：若數字值 ≥ 10，加 7 跳過 `:` 到 `@`（57 到 64）的 ASCII 空隙，使得 10 → 'A'(65)，35 → 'Z'(90)。

**`#S`**（`spf_print.f:65-73`）— 轉換直到為零：

```forth
: #S ( ud1 -- ud2 )
  BEGIN
    # 2DUP D0=              \ 持續轉換直到商為 0
  UNTIL
;
```

**`#>`**（`spf_print.f:75-80`）— 結束格式化：

```forth
: #> ( xd -- c-addr u )
  2DROP                    \ 丟棄商（不再需要）
  HLD @ PAD OVER - >CHARS 1-   \ 計算字串起始和長度
;
```

HLD 指向最後插入字元的前一個位元組，PAD OVER - 計算位元組數（包含空字元），減 1 排除空字元，得到格式化結果字串。

**`HOLD`**（`spf_print.f:35-42`）— 在緩衝區插入一字元：

```forth
: HOLD ( char -- )
  HLD @ CHAR-            \ HLD 往低位址移動一位元組
  DUP SYSTEM-PAD U< IF -17 THROW THEN   \ 緩衝區溢位保護
  DUP HLD ! C!            \ 更新 HLD 並寫入字元
;
```

HOLD 的溢位檢查：新 HLD 值若小於 SYSTEM-PAD（緩衝區起點），表示格式化結果已超過 4096 位元組，THROW -17（記憶體空間不足）。

**`HOLDS`**（`spf_print.f:44-46`）— 插入字串：

```forth
: HOLDS ( addr u -- )
  TUCK CHARS + SWAP 0 ?DO DUP I CHARS - CHAR- C@ HOLD LOOP DROP
;
```

從字串末端開始逆向插入每個字元到格式化緩衝區。

### 3.3 SIGN

```forth
: SIGN ( n -- )
  0< IF [CHAR] - HOLD THEN
;
```

若 n 為負數，在格式化緩衝區插入負號。必須在 `#S` 之後、`#>` 之前呼叫。

### 3.4 格式化輸出字

| 字 | 堆疊效果 | 實作 |
|----|---------|------|
| `(D.)` | `( d -- addr len )` | `DUP >R DABS <# #S R> SIGN #>` |
| `D.` | `( d -- )` | `(D.) TYPE SPACE` |
| `.` | `( n -- )` | `S>D D.`（單精確度擴展為雙精確度） |
| `U.` | `( u -- )` | `U>D D.`（無號擴展為雙精確度） |
| `.0` | `( u n -- )` | 補零至 n 位顯示 |

**`.0`**（`spf_print.f:109-113`）— 補零顯示：

```forth
: .0 ( u n -- )
  >R 0 <# #S #> R> OVER - 0 MAX DUP
  IF 0 DO [CHAR] 0 EMIT LOOP
  ELSE DROP THEN TYPE
;
```

先將 u 格式化為字串，計算 `(n - len)` 個前導零，逐一 EMIT 補零，然後 TYPE 格式化結果。

### 3.5 DUMP

```forth
: DUMP ( addr u -- )
  DUP 0= IF 2DROP EXIT THEN       \ u=0 時直接離開
  BASE @ >R HEX                     \ 暫存基數，切換至十六進位
  15 + 16 U/ 0 DO                   \ 計算行數（每行 16 位元組）
    CR DUP 4 .0 SPACE               \ 顯示位址（4 位十六進位，補零）
    SPACE DUP 16 0
      DO I 4 MOD 0= IF SPACE THEN   \ 每 4 位元組加空格
        DUP C@ 2 .0 SPACE 1+        \ 顯示十六進位值（2 位，補零）
      LOOP SWAP 16 PTYPE             \ 顯示可列印字元
  LOOP DROP R> BASE !                \ 恢復基數
;
```

DUMP 的輸出格式範例：

```forth
0010  48656C6C 6F20776F 726C6421 00000000  Hello world!.....
```

每行：4 位十六進位位址 + 空格 + 16 個十六進位值（每 4 個一組）+ 可列印字元。

**`>PRT`**和 **`PTYPE`**（`spf_print.f:120-126`）：

```forth
: >PRT ( c -- c | '.' )
  DUP BL U< IF DROP [CHAR] . THEN   \ 不可列印字元替換為 '.'
;

: PTYPE ( addr n -- )
  0 DO DUP C@ >PRT EMIT 1+ LOOP DROP
;
```

### 3.6 (.") — 字串顯示執行期碼

```forth
: (.") ( T -> )
  COUNT TYPE
;
' (.") TO (.")-CODE
```

`(.")` 是 `."` 和 `S"` 的執行期行為：從資料流讀取計數字串（`COUNT` 取得 addr+len），然後 `TYPE` 輸出。編譯期由 `."` 編譯字串到資料流中，並插入 `(.")-CODE` 的呼叫。

### 3.7 SCREEN-LENGTH

```forth
: SCREEN-LENGTH ( addr n -- n1 )
  0 UNROT CHARS OVER + SWAP ?DO
    I C@ 9 = IF 3 RSHIFT 1+ 3 LSHIFT   \ Tab → 對齊到 8 的倍數
    ELSE 1+ THEN                         \ 其他字元 → +1
  LOOP
;
```

計算字串的「顯示寬度」，Tab 字元按 8 的倍數對齊計算：
- `3 RSHIFT 1+ 3 LSHIFT` 等價於 `((pos >> 3) + 1) << 3`，即進位到下一個 8 的倍數

### 3.8 >NUMBER — 數字解析

```forth
: >NUMBER ( ud1 c-addr1 u1 -- ud2 c-addr2 u2 )
  BEGIN
    DUP                               \ u1 ≠ 0？
  WHILE
    >R DUP >R                          \ 儲存 c-addr 和 u 的副本
    C@ BASE @ DIGIT 0=                \ 取字元，嘗試轉成數字
    IF R> R> EXIT THEN                \ 失敗：回傳剩餘字串
    SWAP BASE @ UM* DROP              \ ud_low * base
    ROT BASE @ UM* D+                 \ ud_high * base + 結果相加
    R> CHAR+ R> 1-                     \ 前進到下一字元
  REPEAT
;
```

>NUMBER 的雙精確度乘法步驟（`spf_print.f:183-184`）：

```forth
輸入: ud = (ud_high, ud_low), 數字值 n, 基數 base

1. SWAP BASE @ UM* DROP  →  ud_low * base（丟棄高位，因為 n < base < 2^16）
2. ROT BASE @ UM* D+     →  ud_high * base + carry_from_step1

結果: ud' = ud * base + n
```

### 3.9 .To-LOG

```forth
: .To-LOG ( n -- )
  S>D DUP >R DABS <# BL HOLD #S R> SIGN #> TO-LOG
;
```

將整數格式化後寫入日誌，並在最前面插入一個空白（`BL HOLD`）。

---

## 4. 例外處理（spf_except.f）

### 4.1 THROW 機制

```forth
: THROW ( k*x n -- k*x | i*x n )
  DUP 0= IF DROP EXIT THEN             \ n=0：不拋出例外，直接丟棄 n

  HANDLER @  DUP IF                     \ 有 HANDLER？
    RP!                                   \ 恢復回返堆疊到 CATCH 時的位置
    R> HANDLER !                         \ 恢復前一個 HANDLER（串列回溯）
    R> SWAP >R                           \ 例外碼暫存於回返堆疊
    SP! DROP R>                           \ 恢復資料堆疊到 CATCH 時的位置
    EXIT                                  \ 跳回 CATCH 之後的程式碼
  THEN
  DROP FATAL-HANDLER                    \ 無 HANDLER：呼叫致命錯誤處理器
;
```

**THROW 的堆疊操作詳解**：

在 `CATCH` 中，回返堆疊依次壓入了 `SP@`（資料堆疊指標）和 `HANDLER @`（前一個 HANDLER），`RP@` 成為新的 HANDLER。

當 THROW 發生時：

1. `HANDLER @` 取得目前 HANDLER（即 CATCH 時的 RP@）
2. `RP!` 恢復回返堆疊到 CATCH 設定的位置
3. `R> HANDLER !` 恢復前一個 HANDLER
4. `R> SWAP >R` 從回返堆疊取出 SP@，然後將例外碼 n 暫時放入回返堆疊
5. `SP! DROP R>` 恢復資料堆疊（SP! 設定 SP，DROP 丟棄原本在資料堆疊上的 SP@ 值，R> 取回例外碼 n）

例外碼 n 最終出現在資料堆疊頂端，CATCH 之後的程式碼可以檢查它。

### 4.2 CATCH 機制

```forth
: CATCH ( i*x xt -- j*x 0 | i*x n )
  SP@ >R           \ 儲存資料堆疊指標
  HANDLER @ >R      \ 儲存前一個 HANDLER
  RP@ HANDLER !     \ 設定新 HANDLER = 目前回返堆疊指標
  EXECUTE           \ 執行 xt
  R> HANDLER !      \ 恢復前一個 HANDLER
  RDROP             \ 丟棄儲存的資料堆疊指標
  0                 \ 正常回傳：0
;
```

**CATCH/THROW 交互的堆疊佈局**：

```forth
CATCH 設定前的回返堆疊：  ... | prev_frame |
CATCH 設定後：            ... | prev_frame | SP@ | old_HANDLER | ← RP@ = new HANDLER
THROW 時的回返堆疊：      ... | prev_frame | SP@ | old_HANDLER |
```

### 4.3 例外碼慣例

| 例外碼 | 說明 | 來源 |
|--------|------|------|
| 0 | 無例外 | CATCH 正常回傳 |
| -1 | ABORT | `ABORT` 字（一般中斷） |
| -2 | ABORT" 訊息 | `ABORT"` 字（帶訊息中斷） |
| -3 | 編譯狀態錯誤 | `?COMP`：僅允許在編譯狀態 |
| -4 | 堆疊下溢 | `?STACK`：堆疊超出 S0 範圍 |
| -9 | 記憶體存取違規 | SIGSEGV/SIGILL（POSIX） |
| -10 | 整數除以零 | SIGFPE(FPE_INTDIV) |
| -11 | 整數溢位 | SIGFPE(FPE_INTOVF) |
| -12 | 引數型態不符 | Forth 標準 |
| -13 | 未定義字 | `SFIND` 找不到字 |
| -17 | 記憶體空間不足 | `HOLD` 緩衝區溢位 |
| -23 | 匯流排錯誤 | SIGBUS（POSIX） |
| -27 | 包含巢狀過深 | `INCLUDED-DEPTH > 64` |
| -41 | 浮點結果不精確 | SIGFPE(FPE_FLTRES) |
| -42 | 浮點除以零 | SIGFPE(FPE_FLTDIV) |
| -43 | 浮點溢位 | SIGFPE(FPE_FLTOVF) |
| -54 | 浮點下溢 | SIGFPE(FPE_FLTUND) |
| -46 | 浮點無效操作 | SIGFPE(FPE_FLTINV)（原始碼註記為 questionable） |
| -55 | 其他未分類的 SIGFPE | SIGFPE（非上述子碼） |
| -2001 | 數字解析失敗 | `?SLITERAL` |
| -2002 | 數字解析（含小數點）失敗 | `?SLITERAL` |
| -2003 | 字詞未找到 | `EVAL-WORD` |
| -2004 | UNTIL 缺少 BEGIN | 編譯期結構錯誤 |
| -2005 | REPEAT 缺少 BEGIN | 編譯期結構錯誤 |
| -2007 | 條件結構不配對 | 編譯期結構錯誤 |
| -1002 | 管線/輸入結束 | `ACCEPT1` |
| -300 | 記憶體配置失敗 | `ALLOCATE` |
| -312 | 編譯狀態錯誤 | `?COMP` |

### 4.4 FATAL-HANDLER

```forth
: (FATAL-HANDLER1) ( ior -- )
  HEX
  ." UNHANDLED EXCEPTION: " DUP U. CR
  ." RETURN STACK: " CR
  R0 @ RP@ DUMP-TRACE-SHRUNKEN            \ 傾印回返堆疊追蹤
  ." SOURCE: " CR ERROR CR                 \ 顯示原始碼錯誤
  ." THREAD EXITING." CR
  TERMINATE                                  \ POSIX 版呼叫 pthread_exit(-1) 結束目前執行緒
;

: FATAL-HANDLER1 ( ior -- )
  ['] (FATAL-HANDLER1) CATCH 5 ['] HALT CATCH -1 PAUSE
  \ 三層保護：
  \ 1. CATCH 包裹 (FATAL-HANDLER1)：若傾印過程出錯，得到錯誤碼 5
  \ 2. HALT：若 HALT 也失敗，得到錯誤碼 3/4
  \ 3. PAUSE -1：最後手段，暫停執行緒
  \ FATAL-HANDLER 本身不可再拋出例外！
;
```

> `(FATAL-HANDLER1)` 最後呼叫 `TERMINATE`：POSIX 版是 `pthread_exit(-1)`（結束目前執行緒，`mtask.f:40-43`），Windows 版是 `ExitThread`。程序層級的終止則由 `HALT` 呼叫 C 的 `exit()` 完成，兩者層級不同。

### 4.5 ABORT

```forth
: ABORT  -1 THROW ;
```

`ABORT` 等價於 `-1 THROW`，清除資料堆疊和回返堆疊，回到最外層的 CATCH（即 QUIT 迴圈）。

### 4.6 `<SET-EXC-HANDLER>`

```forth
VECT <SET-EXC-HANDLER>   \ 平台相關的結構化例外處理設定
```

- POSIX：使用 `sigaction` 設定信號處理器（見 `posix/init.f` 的 `set-errsignal-handler`）
- Windows：`SET-EXC-HANDLER`（`spf_win_except.f:65-74`）直接操作 `FS:[0]` 安裝 per-thread SEH frame；**不是** `SetUnhandledExceptionFilter`，也不是 Vectored Exception Handling

---

## 5. 檔案 I/O（posix/io.f）

### 5.1 檔案操作一覽

| 字 | 堆疊效果 | 底層系統呼叫 |
|----|---------|------------|
| `CLOSE-FILE` | `( fileid -- ior )` | `close(fd)` |
| `CREATE-FILE` | `( c-addr u fam -- fileid ior )` | `open64(path, O_CREAT&#124;O_TRUNC&#124;fam, 0644)` |
| `DELETE-FILE` | `( c-addr u -- ior )` | `unlink(path)` |
| `FILE-POSITION` | `( fileid -- ud ior )` | `lseek64(fd, 0, SEEK_CUR)` |
| `OPEN-FILE` | `( c-addr u fam -- fileid ior )` | `open64(path, fam)` |
| `READ-FILE` | `( c-addr u1 fileid -- u2 ior )` | `read(fd, buf, count)` |
| `REPOSITION-FILE` | `( ud fileid -- ior )` | `lseek64(fd, offset, SEEK_SET)` |
| `WRITE-FILE` | `( c-addr u fileid -- ior )` | `write(fd, buf, count)` |
| `RESIZE-FILE` | `( ud fileid -- ior )` | `ftruncate64(fd, length)` |
| `WRITE-LINE` | `( c-addr u fileid -- ior )` | `WRITE-FILE + EOLN WRITE-FILE` |
| `FLUSH-FILE` | `( fileid -- ior )` | `fsync(fd)` |

需要檔案位移或大小的操作使用 64 位元 API（`open64`、`lseek64`、`fstat64`、`ftruncate64`），支援大檔案；一般的讀寫與關閉（`read`、`write`、`close`、`unlink`、`fsync`）仍使用一般 POSIX 呼叫，並非全部都是 `*64`。

### 5.2 (( / )) FFI 語法

POSIX I/O 大量使用 `(( addr count ))` FFI 語法（在 `04-posix-platform.md` 中詳述），例如：

```forth
: CLOSE-FILE ( fileid -- ior )
  1 <( )) close ?ERR NIP
;
```

`1 <( )) close` 表示：推入 1 個引數（fileid），呼叫 `close` 函數，結果透過 `?ERR` 檢查。

`?ERR`（定義於 `src/posix/memory.f:28-30`）：

```forth
: ?ERR ( -1 -- -1 err | x -- x 0 )
  DUP -1 = IF errno ELSE 0 THEN
;
```

它保留原始回傳值，並在回傳值為 `-1`（C 慣例的錯誤指標）時附上 `errno`，否則附上 `0`（無錯誤）。呼叫端通常用 `NIP` 丟掉原始回傳值、只留下 ior（例如 `... close ?ERR`）。`errno` 本身定義在 `memory.f:24-26`（`(()) __errno_location @`）。

### 5.3 FILE-POSITION

```forth
: FILE-POSITION ( fileid -- ud ior )
  1 <( 0. SEEK_CUR __ret2 )) lseek64
  2DUP -1. D= IF errno ELSE 0 THEN
;
```

使用 `lseek64(fd, 0, SEEK_CUR)` 取得目前檔案位置。`__ret2` 用於接收 64 位元回傳值（透過 `C-CALL2` 機制）。若 `lseek64` 回傳 -1，則取得 `errno` 作為 ior。

### 5.4 READ-LINE — 逐行讀取

```forth
: READ-LINE ( c-addr u1 fileid -- u2 flag ior )
  DUP >R
  FILE-POSITION IF 2DROP 0 0 THEN _fp1 ! _fp2 !   \ 儲存當前檔案位置
  LTL @ +                                            \ 加上行結束序列長度
  OVER _addr !                                         \ 儲存緩衝區位址

  R@ READ-FILE ?DUP IF NIP RDROP 0 0 ROT EXIT THEN   \ 讀取失敗

  DUP >R 0= IF RDROP RDROP 0 0 0 EXIT THEN           \ 檔案結束

  _addr @ R@ EOLN SEARCH                               \ 搜尋行結束序列
  IF   \ 找到行結束序列
     DROP _addr @ -                                    \ 計算行長度
     DUP
     LTL @ + S>D _fp2 @ _fp1 @ D+ RDROP R> REPOSITION-FILE DROP  \ 回溯檔案位置
  ELSE \ 未找到行結束序列（最後一行）
     2DROP
     R> RDROP                                          \ 行長度 = 已讀位元組數
  THEN
  TRUE 0                                               \ flag=TRUE, ior=0
;
```

READ-LINE 演算法：
1. 記錄當前檔案位置（`_fp1`, `_fp2`）
2. 讀取 `u1 + LTL @` 位元組到緩衝區（多讀 EOLN 長度以防行結束序列被截斷）
3. 在緩衝區中搜尋 `EOLN`（行結束序列）
4. 若找到行結束序列：回溯檔案位置到行結束序列之後
5. 若本次緩衝區內未找到 `EOLN`：回傳本次讀到的 bytes、`flag=true`。這**可能**是最後一行，也可能只是超過緩衝區的一行片段（下一次 `READ-LINE` 會繼續讀同一實體行）；原始碼註解也指出 `u1=u2` 時可能只是行的一部分

USER 變數 `_fp1`、`_fp2`、`_addr` 用於避免堆疊操作過於複雜。

### 5.5 FILE-EXIST 和 FILE-EXISTS

```forth
: FILE-EXIST ( addr u -- f )
  [DEFINED] _STAT_VER [IF]
  DROP >R (( _STAT_VER R> API-BUFFER )) __xstat 0=
  [ELSE]
  DROP >R (( R> API-BUFFER )) stat 0=
  [THEN]
;

: FILE-EXISTS ( addr u -- f )
  FILE-EXIST 0 = IF FALSE EXIT THEN
  API-BUFFER STAT_ST_MODE + @ S_IFDIR AND 0 =
;
```

`FILE-EXIST` 使用 `stat`/`__xstat` 檢查檔案是否存在。新版 glibc 需要 `_STAT_VER` 版本號（透過 `__xstat`），舊版直接呼叫 `stat`。

`FILE-EXISTS` 進一步排除目錄：檢查 `st_mode & S_IFDIR`，確保不是目錄。

`API-BUFFER` 是一個 200 位元組的 USER-CREATE 緩衝區，供系統呼叫結構體使用。

### 5.6 FILE-SIZE

```forth
: FILE-SIZE ( fileid -- ud ior )
  [DEFINED] _STAT_VER [IF]
  >R (( _STAT_VER R> API-BUFFER )) __fxstat64
  [ELSE]
  >R (( R> API-BUFFER )) fstat64
  [THEN]
  -1 = IF 0. errno ELSE API-BUFFER STAT64_ST_SIZE + 2@ SWAP 0 THEN
;
```

使用 `fstat64` 取得檔案大小。`2@ SWAP` 從 `stat64` 結構中讀取 64 位元檔案大小（小端序，需 SWAP）。

### 5.7 CREATE-FILE-SHARED 和 OPEN-FILE-SHARED

```forth
: CREATE-FILE-SHARED ( c-addr u fam -- fileid ior )
  CREATE-FILE           \ POSIX 版等同 CREATE-FILE（無共享模式差異）
;
: OPEN-FILE-SHARED ( c-addr u fam -- fileid ior )
  OPEN-FILE             \ POSIX 版等同 OPEN-FILE
;
```

這兩個字在 POSIX 上分別等同於 CREATE-FILE 和 OPEN-FILE。它們的存在是為了與 Windows 版本保持 API 一致性——Windows 上的 `CREATE-FILE-SHARED` 使用 `FILE_SHARE_READ|FILE_SHARE_WRITE` 共享模式。

### 5.8 WRITE-FILE 的特殊實作

```forth
: WRITE-FILE ( c-addr u fileid -- ior )
  UNROT DUP >R
  3 write-adr @ C-CALL           \ 呼叫 write(fd, buf, count)
  DUP -1 = IF
    R> 2DROP errno                \ 寫入失敗 → errno
  ELSE
    R> <>                           \ 寫入位元組數 ≠ 請求位元組數 → 部分寫入
  THEN
;
```

注意這裡使用 `write-adr @ C-CALL` 而非 `<( ))` 語法。`write-adr` 是 `write` 函數的指標（由 `dl.f` 的動態連結設定），`C-CALL` 是間接呼叫。回傳值為寫入的位元組數，若等於請求的位元組數則 ior=0（因為 `<>` 回傳 FALSE=0）。

---

## 6. 環境查詢與錯誤解碼（posix/envir.f）

### 6.1 ENVIRONMENT? — 三層搜尋

```forth
: ENVIRONMENT? ( c-addr u -- false | i*x true )
  OVER 1 <( )) getenv ?DUP IF NIP NIP ASCIIZ> TRUE EXIT THEN   \ 第 1 層：環境變數

  2DUP ENVIRONMENT-WORDLIST                                       \ 第 2 層：字詞集
  SEARCH-WORDLIST IF NIP NIP EXECUTE TRUE EXIT THEN

  S" lib/ENVIR.SPF" +ModuleDirName 2DUP FILE-EXIST 0=            \ 第 3 層：檔案
  IF
    2DROP S" ENVIR.SPF" +ModuleDirName
  THEN
  R/O OPEN-FILE-SHARED 0=
  IF  DUP >R
      ['] (ENVIR?) RECEIVE-WITH  IF 0 THEN
      R> CLOSE-FILE THROW
  ELSE 2DROP DROP 0 THEN
;
```

三層搜尋順序：
1. **環境變數**：`getenv()` 系統呼叫，如 `HOME`、`PATH`
2. **ENVIRONMENT-WORDLIST**：Forth 字詞集中的查詢字
3. **ENVIR.SPF 檔案**：模組目錄或 `lib/` 子目錄中的環境定義檔案

**`(ENVIR?)`**（`envir.f:22-29`）— 檔案式查詢：

```forth
: (ENVIR?) ( addr u -- false | i*x true )
  BEGIN REFILL WHILE
    2DUP PARSE-NAME COMPARE
    0= IF 2DROP INTERPRET TRUE EXIT THEN
  REPEAT 2DROP FALSE
;
```

逐行讀取 ENVIR.SPF，每行格式為 `name value`。比對名稱成功後，`INTERPRET` 執行值定義。

### 6.2 USE — 載入共享函式庫

```forth
: USE ( "name" -- )
  PARSE-NAME 2DUP SYSTEM-PAD CZMOVE
  SYSTEM-PAD dlopen2 TRUE name-lookup DROP
;
```

`USE` 載入一個共享函式庫（`.so` 檔案）：
1. 將名稱複製到 SYSTEM-PAD（必須為 ASCIIZ 格式）
2. `dlopen2` 開啟函式庫
3. `TRUE name-lookup` 將函式庫標記為預載入（所有後續的 `(( ))` 呼叫都可使用其符號）

### 6.3 )) — 外部函式呼叫語法

```forth
: )) ( "name" -- )
  PARSE-NAME symbol-lookup
  STATE @ IF
    ['] ())) COMPILE,               \ 編譯期：嵌入呼叫引數數量
    compile-call                     \ 編譯 C-CALL 或 C-CALL2
  ELSE
    ())) 1- SWAP symbol-call         \ 直譯期：直接呼叫
  THEN
; IMMEDIATE
```

### 6.4 DECODE-ERROR — 錯誤碼解碼

```forth
: DECODE-ERROR ( n u -- c-addr u )
  ... DROP                                          \ AT-PROCESS-STARTING 附加點
  S" lib/SPF.ERR" +ModuleDirName 2DUP FILE-EXIST 0=
  IF 2DROP S" SPF.ERR" +ModuleDirName THEN
  R/O OPEN-FILE-SHARED
  IF DROP DUP >R ABS 0 <# #S R> SIGN S" ERROR #" HOLDS #>
     TUCK SYSTEM-PAD SWAP CHARS MOVE SYSTEM-PAD SWAP
  ELSE
    DUP >R
    ['] (DECODE-ERROR) RECEIVE-WITH DROP
    R> CLOSE-FILE THROW
    2DUP -TRAILING + 0 SWAP C!
  THEN
;
```

DECODE-ERROR 使用分散式冒號定義（見第 9 節），允許模組擴充錯誤碼解碼邏輯。搜尋路徑：
1. `+ModuleDirName` + `lib/SPF.ERR`
2. `+ModuleDirName` + `SPF.ERR`

若找不到 SPF.ERR 檔案，回傳 `ERROR #<code>` 形式的字串（例如 `ERROR #-9`）。注意 Forth 的 pictured numeric output 是逆向組字，最終結果是 `ERROR #` 在前、數字在後，不是「數字 + ERROR #」。

**`(DECODE-ERROR)`**（`envir.f:61-76`）— 檔案式錯誤碼查詢：

```forth
: (DECODE-ERROR) ( n -- c-addr u )
  STATE @ >R STATE 0!                 \ 暫時切換到直譯模式
  BEGIN REFILL WHILE ( n )
    PARSE-NAME ['] ?SLITERAL CATCH
    IF 2DROP DROP S" Error while error decoding!" R> STATE ! EXIT THEN
    OVER = IF ( n )                   \ 找到匹配的錯誤碼
      DROP >IN 0! [CHAR] \ PARSE      \ 取錯誤訊息（到行尾或反斜線）
      TUCK SYSTEM-PAD SWAP CHARS MOVE
      SYSTEM-PAD SWAP R> STATE ! EXIT
    THEN
  REPEAT ( n )                        \ 未找到
  <# SOURCE SWAP CHAR+ SWAP 1 - HOLDS  DUP 0< IF DUP S>D #(SIGNED) 2DROP THEN U>D #S #>
  R> STATE !
;
```

SPF.ERR 檔案格式範例：

```forth
-9 \Access violation
-10 \Division by zero
-1002 \End of input stream
```

### 6.5 dl-no-library 和 dl-no-symbol

```forth
: dl-no-library ( z )
  DROP DLERROR ASCIIZ> THROW-ERRMSG
;

: dl-no-symbol ( z -- )
  ASCIIZ> S" : undefined symbol" 2SWAP
  (PREPEND-ERRMSG) THROW-ERRMSG
;
```

這兩個字是動態連結錯誤處理器：
- `dl-no-library`：無法開啟函式庫，取得 `dlerror()` 錯誤訊息後 THROW-ERRMSG（即 THROW -2）
- `dl-no-symbol`：找不到符號，組合錯誤訊息 `"symbol: undefined symbol"` 後 THROW-ERRMSG

---

## 7. 錯誤追蹤系統（compiler/spf_error.f）

### 7.1 ERR-DATA 結構

```forth
128 CHARS CONSTANT /errstr_

0 \
1 CELLS     -- err.number      \ 錯誤碼
1 CELLS     -- err.line#       \ 行號
1 CELLS     -- err.in#         \ 行內偏移（>IN 的值）
1 CHARS     -- err.notseen     \ 是否已顯示過此錯誤（旗標）
[T] /errstr_ [I]
  CELL+     -- err.line        \ 原始碼行內容（計數字串）
[T] /errstr_ [I]
  CELL+     -- err.file        \ 檔案路徑（計數字串）
CONSTANT /err-data
```

ERR-DATA 是 USER-CREATE，每個執行緒有自己的錯誤資料結構。`/err-data` 計算總大小：

```forth
/err-data = 1 CELL (err.number)
          + 1 CELL (err.line#)
          + 1 CELL (err.in#)
          + 1 CHAR (err.notseen)
          + 1 CELL + 128 CHARS (err.line：計數字串)
          + 1 CELL + 128 CHARS (err.file：計數字串)
```

### 7.2 SAVE-ERR — 儲存錯誤資訊

```forth
: SAVE-ERR ( err-num -- )
  ERR-DATA err.number !                                     \ 錯誤碼
  SOURCE-FILE-LN DUP 0= IF DROP SOURCE-LN THEN
             ERR-DATA err.line# !                            \ 行號
  >IN @      ERR-DATA err.in#   !                            \ 行內偏移
  SOURCE /errstr_ >CHARS UMIN  DUP
             ERR-DATA err.line C!
             ERR-DATA err.line CHAR+ SWAP  CMOVE             \ 原始碼行
           0  ERR-DATA err.line COUNT CHARS + C!
  SOURCE-FILE-PATH DUP 0= IF 2DROP SOURCE-PATH THEN
  /errstr_ >CHARS UMIN  DUP
             ERR-DATA err.file C!
             ERR-DATA err.file CHAR+ SWAP CHARS MOVE             \ 檔案路徑
           0  ERR-DATA err.file COUNT CHARS + C!
  NOTSEEN-ERR                                               \ 標記為未顯示
;
```

SAVE-ERR 儲存完整的錯誤上下文：錯誤碼、行號、行內偏移、原始碼行內容、檔案路徑。注意它會將 SOURCE（當前輸入緩衝區）和 SOURCE-FILE-PATH 截斷到 `/errstr_`（128）個字元。

### 7.3 ERR-STRING — 錯誤字串格式化

```forth
: ERR-STRING ( -- a u )
  BASE @ DECIMAL
  <#
  ERR-LINE HOLDS                  \ 原始碼行
  EOLN HOLDS                      \ 換行
  S" :" HOLDS                     \ 行號分隔符
  ERR-IN# 0 #S 2DROP              \ 行內偏移
  S" :" HOLDS
  ERR-LINE# 0 #S 2DROP            \ 行號
  S" :" HOLDS
  ERR-FILE HOLDS                  \ 檔案路徑
  S"  at: " HOLDS
  ERR-NUMBER DUP ABS 0 #S 2DROP 0< IF [CHAR] - HOLD THEN [CHAR] # HOLD
  S" Exception " HOLDS            \ 最前面
  0 0 #> ROT BASE !
;
```

格式化結果範例：
```forth
Exception #-9 at: /path/to/file.f:42:15
source code line here
```

### 7.4 PRINT-LAST-WORD — 指示錯誤位置

```forth
: PRINT-LAST-WORD ( -- )
  SEEN-ERR?
  IF
    SOURCE OVER >IN @ SCREEN-LENGTH     \ 首次顯示：從原始碼行
  ELSE
    SEEN-ERR
    ERR-STRING
    ERR-LINE DROP ERR-IN# SCREEN-LENGTH \ 非首次：從 ERR-DATA
  THEN
  UNROT TYPE0 CR
  2- 0 MAX SPACES [CHAR] ^ EMIT SPACE  \ 顯示 ^ 指標
;
```

`TYPE0` 與 `TYPE` 的差異：TYPE0 將 NUL 字元替換為空白（`I C@ ?DUP 0= IF BL THEN EMIT`）。

### 7.5 ERROR2 — 錯誤顯示

```forth
: ERROR2 ( ERR-NUM -> )
  DUP 0= IF DROP EXIT THEN              \ ior=0：無錯誤
  PRINT-LAST-WORD                       \ 顯示錯誤位置
  DUP -2 = IF DROP LAST-ERRMSG TYPE CR EXIT THEN  \ ABORT"：顯示訊息
  BASE @ >R DECIMAL
  FORTH_ERROR DECODE-ERROR TYPE         \ 解碼並顯示錯誤碼
  R> BASE !
  CR
;
```

ERROR2 是向量 `ERROR` 的預設實作，負責：
1. 若 ior=0，不做任何事
2. 呼叫 PRINT-LAST-WORD 顯示錯誤位置和 `^` 指標
3. 若 ior=-2，顯示 ABORT" 的錯誤訊息
4. 否則，透過 DECODE-ERROR 解碼錯誤碼並顯示

### 7.6 (ABORT1") — ABORT" 執行期

```forth
: (ABORT1") ( flag c-addr -- )
  SWAP IF COUNT THROW-ERRMSG ELSE DROP THEN
;
```

若旗標為 TRUE，從資料流讀取計數字串並 THROW-ERRMSG（即 THROW -2）；否則丟棄字串位址。

---

## 8. POSIX 信號處理與初始化（posix/init.f）

### 8.1 POSIX 信號處理器機制（概述）

POSIX 信號處理機制包含四個元素的協作：**信號處理器安裝**（`set-errsignal-handler`）、**信號→例外轉換**（`signum>ior`）、**堆疊追蹤傾印**（`DUMP-TRACE`）、與 **例外橋接**（`(errsignal)`）。這四個元素的原始碼與詳細分析已在 [04-posix-platform.md §12](04-posix-platform.md#12-信號處理posixinitf深入解析) 完整覆蓋，此處僅說明它們在執行期生命週期中的角色：

- `(errsignal)` 從 `ucontext_t` 恢復 EDI 暫存器（TLS 基底），確保 THROW 能正確存取 USER 變數（詳見 01-kernel.md §6.3 與 04-posix-platform.md §12.2）。
- 信號透過 `signum>ior` 轉換為 Forth 例外碼後 THROW，使 `CATCH`/`THROW` 機制能攔截 SIGSEGV、SIGFPE 等同步信號。
- `IN-EXCEPTION` 遞迴保護、`sigact` 結構的配置與 `set-errsignal-handler` 的安裝流程，請見 `04-posix-platform.md §12.4`。

### 8.2 PROCESS-INIT — POSIX 進程初始化

初始化流程的實作細節已在 [04-posix-platform.md §12.5](04-posix-platform.md#125-process-init程序初始化) 分析。此處僅列出執行期生命週期中的七個步驟：

1. 清除動態連結匯入表（`ERASE-IMPORTS`）
2. 初始化動態連結子系統（`dl-init`）
3. 設定動態連結錯誤處理器
4. 分配主執行緒的 TLS 記憶體（`ALLOCATE-THREAD-MEMORY`）
5. 初始化堆疊與全域狀態（`POOL-INIT`，詳見 §10.4）
6. 安裝信號處理器（`set-errsignal-handler`）
7. 執行進程啟動鉤子（`AT-PROCESS-STARTING`）

### 8.3 USER-INIT 和 USER-EXIT

```forth
: USER-INIT ( n -- )
  ALLOCATE-THREAD-MEMORY      \ 分配 TLS
  POOL-INIT                    \ 初始化堆疊等
  AT-THREAD-STARTING           \ 執行執行緒啟動鉤子
;

: USER-EXIT
  AT-THREAD-FINISHING          \ 執行執行緒結束鉤子
  FREE-THREAD-MEMORY            \ 釋放 TLS
;
```

### 8.4 平台識別

```forth
: PLATFORM ( -- a u ) S" Linux" ;
: OS-API   ( -- a u ) S" posix" ;
```

### 8.5 IN-EXCEPTION 變數

```forth
VARIABLE IN-EXCEPTION
```

全域變數，用於防止 DUMP-TRACE 的遞迴呼叫。若在 DUMP-TRACE 執行期間又觸發信號，第二次的 DUMP-TRACE 會直接離開。

---

## 9. Windows 初始化與例外處理（win/spf_win_init.f）

### 9.1 Windows 版的 USER-INIT 和 PROCESS-INIT

```forth
: USER-INIT ( n -- )
  CREATE-HEAP                \ 建立執行緒堆積（Windows 專屬記憶體管理）
  <SET-EXC-HANDLER>         \ 設定結構化例外處理器（SEH）
  POOL-INIT                  \ 初始化堆疊等
  AT-THREAD-STARTING
;

: PROCESS-INIT ( n -- )
  ERASE-IMPORTS
  CREATE-PROCESS-HEAP       \ 建立進程堆積
  <SET-EXC-HANDLER>         \ 設定 SEH
  POOL-INIT
  ['] AT-PROCESS-STARTING ERR-EXIT
;
```

Windows 版與 POSIX 版的差異：
- `CREATE-HEAP` / `CREATE-PROCESS-HEAP`：Windows 使用HeapCreate/HeapAlloc API，POSIX 使用 malloc
- `<SET-EXC-HANDLER>`：Windows 使用手動安裝的 SEH frame（`FS:[0]` chain，非 Vectored EH），POSIX 使用 sigaction
- 無 `set-errsignal-handler`（Windows 使用 SEH 代替信號）

### 9.2 EXC-DUMP1 — Windows 例外傾印

```forth
: EXC-DUMP1 ( exc-info -- )
  IN-EXCEPTION @ IF DROP EXIT THEN
  TRUE IN-EXCEPTION !

  DUP 3 CELLS + @ OVER @ ( addr num ) DUMP-EXCEPTION-HEADER

  ( DispatcherContext ContextRecord EstablisherFrame ExceptionRecord )
  DROP 2 PICK

  8 CELLS 80 + \ FLOATING_SAVE_AREA
    11 CELLS + \ 浮點暫存器區塊開始偏移
  +              \ 總偏移量：8*4 + 80 + 11*4 = 124 位元組

  AT-EXC-DUMP ( addr -- addr )           \ 可擴充傾印點

  >R
  R@ 10 CELLS + @ ( esp )
  R@ 5 CELLS + @ ( eax )
  R> 6 CELLS + @ ( ebp )
  DUMP-TRACE-USING-REGS
  ." END OF EXCEPTION REPORT" CR
  FALSE IN-EXCEPTION !
;
```

Windows `EXCEPTION_POINTERS` 結構的記憶體佈局：

| 偏移 | 欄位 | 說明 |
|------|------|------|
| 0 | ExceptionRecord | 指標 |
| 4 | ContextRecord | 指標 |
| 8+ | Context 結構開始 | |

從 Context 結構中提取暫存器：
- EIP（或 RIP）：`Context + 0x？` → 例外位址
- ESP：`Context + 10 CELLS`（偏移 0x28，即 40 位元組）
- EAX：`Context + 5 CELLS`（偏移 0x14，即 20 位元組）
- EBP：`Context + 6 CELLS`（偏移 0x18，即 24 位元組）

這個偏移是加在 `ContextRecord`（`CONTEXT` 結構指標，由 `2 PICK` 取得）上的，用來越過 `CONTEXT` 開頭欄位與 `FLOATING_SAVE_AREA`（80 位元組），到達保存通用暫存器（含 EDI）的區域；它**不是**在記憶體上跳過 `EXCEPTION_RECORD`。

### 9.3 HALT

```forth
: HALT ( ERRNUM -> )
  AT-THREAD-FINISHING
  AT-PROCESS-FINISHING
  1 <( )) exit       \ 呼叫 exit(errnum)
;
```

POSIX 版的 HALT 呼叫 `exit()` 系統呼叫（透過 FFI）終止程式。Windows 版使用 `ExitProcess`。

---

## 10. 系統初始化（spf_init.f）

### 10.1 全域變數

```forth
VARIABLE MAINX          \ 主程式執行標記（0=互動模式，非0=執行後離開）
ALIGN-BYTES-CONSTANT CONSTANT ALIGN-BYTES-CONSTANT
                                         \ 對齊常數（4 或 8，取決於平台）
TC-USER-HERE ALIGNED ' USER-OFFS EXECUTE !  \ 設定 USER 變數起始偏移
```

### 10.2 分散式冒號定義

SP-Forth 支援「分散式冒號定義」（Scattered Colon Definitions），允許在已定義的字詞中加入額外邏輯：

```forth
: (SCATTER-HOOK,) ( colon-sys -- colon-sys )
  0 BRANCH, >MARK DUP , 1 >RESOLVE ;

: BUILD-SCATTER ( -- xt.scattered )
  :NONAME (SCATTER-HOOK,) POSTPONE ; ;

: UNSEAL-SCATTER ( xt.scattered -- sys.scattered )
  >BODY DUP @ 1 >RESOLVE ] ;

: RESEAL-SCATTER ( sys.scattered -- )
  DUP CELL+ BRANCH, >MARK SWAP ! POSTPONE [ ;
```

**運作原理**：

`BUILD-SCATTER` 建立一個 `:NONAME` 定義，其體包含一個 `0 BRANCH,`（無條件跳躍，目標暫時為 0），跳躍目標的修補位址被放置在資料流中作為 `DUP ,`。之後 `1 >RESOLVE` 修補這個跳躍，使其跳過整個定義體。這樣呼叫此定義時直接 `EXIT`。

`UNSEAL-SCATTER` 打開定義體：解析 `>BODY` 取得資料流中的修補位址，使用 `1 >RESOLVE` 修補 `BRANCH` 跳過原始碼，然後進入編譯狀態（`]`），新的編譯內容會跟隨在原始碼之後。

`RESEAL-SCATTER` 關閉定義體：編譯一個 `BRANCH` 跳回 EXIT 點，修補原始 `BRANCH` 的目標到新的結束位置，然後回到直譯狀態（`POSTPONE [`）。

**使用語法**：

```forth
: AT-THREAD-STARTING ( -- ) ... ;          \ 初始定義（空體或基本邏輯）
: AT-PROCESS-STARTING ( -- ) ... AT-THREAD-STARTING ;

..: AT-THREAD-STARTING  新的邏輯  ;..      \ 擴充定義
```

分散式定義的記憶體佈局：

```forth
┌─────────────────────────────────────────────────┐
│  :NONAME 頭部                                     │
├─────────────────────────────────────────────────┤
│  0 BRANCH → ─────────────────────────┐            │
│                                      │            │
│  原始碼（初始為 EXIT 或跳躍到尾部）   │            │
│                                      │            │
│  ← 第 1 次 ..: 追加的碼 ─┐          │            │
│                            │          │            │
│  ← 第 2 次 ..: 追加的碼 ─┼──┐       │            │
│                            │  │       │            │
│  BRANCH ←────┘  │       │            │
├─────────────────────────────────────────────────┤
│  修補位址 ←───────────────────────────┘            │
└─────────────────────────────────────────────────┘
```

### 10.3 AT-THREAD-STARTING 和 AT-PROCESS-STARTING

```forth
: AT-THREAD-STARTING ( -- ) ...  ;
: AT-PROCESS-STARTING ( -- ) ... AT-THREAD-STARTING ;
```

這兩個字使用分散式定義模式，允許模組透過 `..:` 和 `;..` 在其中追加邏輯。

`AT-PROCESS-STARTING` 在進程啟動時呼叫（在 PROCESS-INIT 中），`AT-THREAD-STARTING` 在每個執行緒啟動時呼叫（在 USER-INIT 中）。

### 10.4 POOL-INIT — 執行緒/進程局部初始化

```forth
: POOL-INIT ( n -- )
  SP@  + CELL+ S0 !    \ 設定資料堆疊基底（S0 = SP + n + CELL）
  RP@ R0 !              \ 設定回返堆疊基底（R0 = RP）
  DECIMAL                \ 基數設為 10
  ATIB TO TIB            \ TIB 指向執行緒的終端輸入緩衝區
  0 TO SOURCE-ID         \ 輸入來源 = 標準輸入
  0 TO SOURCE-ID-XT      \ 無自訂 REFILL XT
  ONLY FORTH DEFINITIONS \ 搜尋順序 = 僅 FORTH 字詞集
  POSTPONE [             \ 直譯模式
  HANDLER 0!             \ 清除例外處理器鏈結
  CURSTR 0!              \ 清除當前行計數
  CURFILE 0!             \ 清除當前檔案指標
  (BASEPATH) 0!          \ 清除基礎路徑
  INCLUDE-DEPTH 0!       \ 清除包含深度
  TRUE WARNING !         \ 開啟警告訊息
  12 C-SMUDGE !          \ 設定 SMUDGE 遮罩字元
  ALIGN-BYTES-CONSTANT ALIGN-BYTES !  \ 設定對齊位元組數
  INIT-MACROOPT-LIGHT    \ 初始化巨集最佳化器
;
```

POOL-INIT 的 17 個初始化步驟：

1. **S0**：資料堆疊基底指標，用於 `DEPTH` 和 `?STACK`
2. **R0**：回返堆疊基底指標，用於 `DUMP-TRACE`
3. **DECIMAL**：設定 BASE 為 10
4. **TIB**：終端輸入緩衝區（Thread-Local）
5. **SOURCE-ID = 0**：STDIN
6. **SOURCE-ID-XT = 0**：無自訂 REFILL
7. **ONLY FORTH DEFINITIONS**：搜尋順序重設
8. **POSTPONE [**：切換到直譯模式
9. **HANDLER 0!**：清除例外處理鏈結
10. **CURSTR 0!**：行號計數器歸零
11. **CURFILE 0!**：檔案指標歸零
12. **(BASEPATH) 0!**：基礎路徑歸零
13. **INCLUDE-DEPTH 0!**：包含深度歸零
14. **WARNING ! TRUE**：開啟警告（未定義字詞時顯示訊息）
15. **C-SMUDGE = 12**：設定 SMUDGE 字元（ASCII 12 = Ctrl-L）
16. **ALIGN-BYTES**：設定對齊位元組數（通常為 4）
17. **INIT-MACROOPT-LIGHT**：初始化輕量巨集最佳化器

### 10.5 ERR-EXIT — 安全執行包裹器

```forth
: ERR-EXIT ( xt -- )
  CATCH
  ?DUP IF ['] ERROR CATCH IF 4 ELSE 3 THEN HALT THEN
;
```

三層錯誤處理：
1. `CATCH`：執行 xt，若有例外則取得例外碼
2. `['] ERROR CATCH`：嘗試顯示錯誤，若 ERROR 本身也出錯 → 回傳 4
3. 若 ERROR 成功 → 回傳 3
4. `HALT`：以回傳值 3 或 4 終止程式

### 10.6 (INIT) — 主程式進入點

```forth
: (INIT) ( env argv argc -- )
  TO ARGC TO ARGV                           \ 儲存命令列引數
  \ 組合命令列字串
  HERE
  ARGC 1 ?DO
   BL C,
   ARGV I CELLS + @ ASCIIZ> S,
  LOOP
  HERE OVER - TO #CMDLINE TO CMDLINE        \ CMDLINE 和 #CMDLINE
  0 C,                                       \ 終止 NULL 位元組
  NATIVE-LINES                               \ 設定換行模式
  0 TO H-STDLOG                             \ 日誌初始關閉
  CONSOLE-HANDLES                            \ 設定 I/O handle
  ['] CGI-OPTIONS ERR-EXIT                   \ 處理 CGI 選項
  MAINX @ ?DUP IF ERR-EXIT THEN             \ 若有主程式則執行
  SPF-INIT?                                  \ 是否執行初始化檔案？
  IF
    ['] SPF-INI ERR-EXIT                     \ 載入 spf4.ini
    ['] OPTIONS CATCH ERROR                  \ 處理命令列選項
  THEN
  CGI? @ 0= POST? @ OR IF ['] <MAIN> ERR-EXIT THEN  \ 進入互動模式
  BYE                                         \ 結束程式
;
```

(CONSOLE-HANDLES 在 POSIX 上為空操作，在 Windows 上取得 GetStdHandle)

### 10.7 向量修復

初始化完成後，系統修復以下向量（`spf_init.f:131-141`）：

```forth
' NOOP         ' <PRE>      TC-VECT!   \ 前處理向量（NOP）
' FIND1        ' FIND       TC-VECT!   \ 搜尋引擎
' ?LITERAL2    ' ?LITERAL   TC-VECT!   \ 常值解析
' ?SLITERAL2   ' ?SLITERAL  TC-VECT!   \ 字串常值解析
' OK1          ' OK         TC-VECT!    \ 提示顯示
' ERROR2       ' ERROR      TC-VECT!   \ 錯誤處理
' (ABORT1")    ' (ABORT")   TC-VECT!   \ ABORT" 執行期
' USER-INIT    ' FORTH-INSTANCE>  TC-VECT!  \ 執行緒進入
' USER-EXIT    ' <FORTH-INSTANCE  TC-VECT!  \ 執行緒離開
' QUIT         ' <MAIN>           TC-VECT!  \ 主迴圈
```

`TC-VECT!`（Target-Compile VECT store）將向量從「啟動版」（簡陋實作）替換為「正式版」。例如：
- `FIND` 在啟動期使用簡單的線性搜尋，啟動後替換為優化版 `FIND1`
- `<PRE>` 在啟動期不做任何事（NOOP），啟動後替換為完整的前處理器
- `OK` 在啟動期為空白，啟動後顯示堆疊深度和 `Ok` 提示

### 10.8 SPF-INI — 初始化檔案搜尋

```forth
: SPF-INI
  S" spf4.ini" INCLUDED-EXISTING IF EXIT THEN         \ 1. 當前目錄
  +ModuleDirName INCLUDED-EXISTING IF EXIT THEN 2DROP  \ 2. 模組目錄
  S" .spf4.ini" +HomeDirName INCLUDED-EXISTING IF EXIT THEN 2DROP \ 3. 家目錄
;
```

三個搜尋位置，按優先順序：
1. **當前目錄** 的 `spf4.ini`
2. **模組目錄**（可執行檔所在目錄）的 `spf4.ini`
3. **家目錄** 的 `.spf4.ini`

`INCLUDED-EXISTING` 在檔案不存在時回傳 FALSE，並將字串留在堆疊上（需 `2DROP` 清理）。

### 10.9 +HomeDirName

```forth
: +HomeDirName ( a u -- a2 u2 )
  S" HOME" ENVIRONMENT? 0= IF EXIT THEN     \ 取得 HOME 環境變數
  SYSTEM-PAD DUP >R /SYSTEM-PAD CROP S" /" CROP- CROP ( a2-rest u2-rest )
  DROP 0 OVER C! R> TUCK -
;
```

將路徑與 `$HOME/` 結合，使用 `CROP` 和 `CROP-` 確保不超過 SYSTEM-PAD 的大小限制。

### 10.10 (TITLE) — 啟動標題

```forth
: (TITLE)
  ." SP-FORTH - ANS FORTH 94 for " PLATFORM TYPE CR
  ." Open source project at https://github.com/rufig/spf" CR
  ." Version " VERSION 1000 / 0 <# # # [CHAR] . HOLD # #> TYPE
  ."  Build " VERSION 0 <# # # # #> TYPE
  ."  at " BUILD-DATE COUNT TYPE CR CR
;
```

VERSION 格式：`XXYYY`，其中 XX 是主版號，YYY 是建置號。例如 `429` → `Version 0.42 Build 0429`。

`1000 /` 取得主版號（VERSION / 1000），`0 <# # # [CHAR] . HOLD # #>` 格式化為 `0.XX`。

### 10.11 STACK-ADDR. 和 ADDR.

```forth
: (ADDR.) BASE @ >R HEX 8 .0 R> BASE ! ;
: ADDR. ( n -- ) (ADDR.) SPACE ;

: STACK-ADDR. ( addr -- addr )
      DUP ADDR. ." :  "
      DUP ['] @ CATCH
      IF DROP
      ELSE DUP ADDR. WordByAddrSilent TYPE CR THEN
;
```

`STACK-ADDR.` 嘗試讀取指定位址的值（`@`），然後透過 `WordByAddrSilent` 查找該位址對應的字詞名稱。若位址不可讀取（`CATCH` 捕捉例外），則跳過。

### 10.12 DUMP-TRACE 和 DUMP-TRACE-SHRUNKEN

```forth
: DUMP-TRACE ( addr-h addr-l -- )
  BEGIN 2DUP U< 0= WHILE STACK-ADDR. CELL+ REPEAT 2DROP
;

12 VALUE TRACE-HEAD-SIZE
15 VALUE TRACE-TAIL-SIZE

: DUMP-TRACE-SHRUNKEN ( addr-h addr-l -- )
  2DUP - TRACE-HEAD-SIZE TRACE-TAIL-SIZE + 5 + CELLS
  U< IF DUMP-TRACE EXIT THEN                \ 堆疊不大，直接傾印
  DUP TRACE-HEAD-SIZE CELLS + SWAP DUMP-TRACE ." [...]" CR
  DUP TRACE-TAIL-SIZE CELLS - DUMP-TRACE    \ 只顯示頭部和尾部
;
```

`DUMP-TRACE-SHRUNKEN` 避免傾印過大的堆疊：若堆疊大小 ≤ (12+15+5)=32 個 CELL，直接傾印全部；否則只顯示前 12 個和後 15 個項目，中間以 `[...]` 表示。

### 10.13 DUMP-TRACE-USING-REGS

```forth
: DUMP-TRACE-USING-REGS ( esp eax ebp -- )
  BASE @ >R DECIMAL
  ." STACK: (" S0 @ OVER - 1 CELLS / 1+ S>D (D.) TYPE ." ) "
  R> BASE !
  ( ebp ) DUP 6 CELLS + BEGIN CELL- DUP ['] @ CATCH IF DROP ELSE ADDR. THEN 2DUP = UNTIL 2DROP
  ( eax ) ." [" (ADDR.) ." ]" CR
  ( esp )

  ." RETURN STACK:" CR
  R0 @

  2DUP U<
  IF ( top bottom )
    2DUP HANDLER @ WITHIN IF
      >R HANDLER @ SWAP DUMP-TRACE-SHRUNKEN
      HANDLER @ CELL+ R>
    THEN
    2DUP TRACE-HEAD-SIZE TRACE-TAIL-SIZE + CELLS - 10 CELLS -
    U< IF 10 CELLS - THEN     \ 跳過早期底部
    SWAP DUMP-TRACE-SHRUNKEN
  ELSE ( esp bottom )
    NIP DUP 50 CELLS - DUMP-TRACE
  THEN
;
```

此字接收三個暫存器值（POSIX 來自 `ucontext_t`；Windows 來自 SEH 傳入的 `ContextRecord`，即 `CONTEXT` 結構，**不是** `EXCEPTION_RECORD`），用於重建堆疊追蹤：

1. **EBP 路徑**：從 EBP 開始掃描回返堆疊框架（`6 CELLS +` 跳過前 6 個 CELL，然後向前掃描直到找到匹配的位址）
2. **EAX（TOS）**：顯示為 `[位址]`
3. **ESP**：從 ESP 到 R0 之間的回返堆疊傾印

若 HANDLER 在回返堆疊範圍內，分開傾印 HANDLER 之前和之後的部分，確保例外處理邊界清晰。

---

## 11. 來源追蹤與 INCLUDE 系統（compiler/spf_translate.f）

### 11.1 SOURCE-ID 與來源追蹤

```forth
USER-VALUE SOURCE-ID ( -- 0|-1 )    \ 輸入來源：0=STDIN, -1=EVALUATE, >0=檔案
USER-VALUE SOURCE-ID-XT              \ 自訂 REFILL 的 XT（用於外部函式庫）
USER CURSTR                           \ 當前行號（用於錯誤報告）
USER (BASEPATH)                       \ 當前基礎路徑（ASCIIZ 字串或 0）
```

### 11.2 REFILL 多層向量系統

REFILL 有三層實作，透過向量替換逐步升級：

```forth
' REFILL-STDIN ' REFILL TC-VECT!     \ 啟動期：從 STDIN 讀取
' REFILL-FILE  ' REFILL TC-VECT!      \ INCLUDE-FILE：從檔案讀取
' REFILL-SOURCE ' REFILL TC-VECT!     \ 完整版：支援 SOURCE-ID-XT
```

**REFILL-STDIN**（`spf_read_source.f:89-96`）：

```forth
: REFILL-STDIN ( -- flag )
  SOURCE-ID -1 = IF FALSE EXIT THEN     \ EVALUATE 字串不充填
  TIB C/L ['] ACCEPT CATCH
  DUP -1002 = IF DROP 2DROP 0 0 ELSE THROW -1 THEN
  TAKEN-TIB
;
```

**REFILL-FILE**（`spf_read_source.f:118-122`）：

```forth
: FREFILL ( h -- flag )
  TIB C/L ROT READ-LINE THROW TAKEN-TIB
;

: REFILL-FILE ( -- flag )
  SOURCE-ID DUP 0 > IF FREFILL EXIT THEN   \ 檔案模式
  DROP REFILL-STDIN                         \ STDIN 模式
;
```

**REFILL-SOURCE**（`spf_read_source.f:131-139`）：

```forth
: REFILL-SOURCE ( -- flag )
  SOURCE-ID-XT IF
    SOURCE-ID 0 > IF
      TIB C/L SOURCE-ID SOURCE-ID-XT EXECUTE THROW
      TAKEN-TIB EXIT
    THEN THEN
  REFILL-FILE
;
```

### 11.3 TAKEN-TIB

```forth
: TAKEN-TIB ( u flag -- flag )
  IF CURSTR 1+! TIB SWAP SOURCE! <PRE> -1 ELSE DROP 0 THEN
;
```

成功讀取一行後：
1. 遞增行號計數器 `CURSTR`
2. 設定 SOURCE 為 TIB 緩衝區
3. 執行 `<PRE>` 前處理器
4. 回傳 TRUE（成功）

### 11.4 CONSOLE-HANDLES

```forth
TARGET-POSIX [IF]
: CONSOLE-HANDLES ;       \ POSIX：空操作（H-STDIN/OUT/ERR 已設定）
[ELSE]
: CONSOLE-HANDLES
  -10 GetStdHandle TO H-STDIN      \ STD_INPUT_HANDLE
  -11 GetStdHandle TO H-STDOUT     \ STD_OUTPUT_HANDLE
  -12 GetStdHandle TO H-STDERR     \ STD_ERROR_HANDLE
  ?GUI IF
    H-STDOUT 65537 = IF -1 TO H-STDOUT THEN   \ 無效 handle
  THEN
;
[THEN]
```

POSIX 版的 CONSOLE-HANDLES 為空操作——因為 stdin/stdout/stderr 在程式啟動時已經由核心設定為檔案描述詞 0/1/2。

Windows 版使用 `GetStdHandle` API 取得標準 I/O 控制代碼。GUI 模式下若 `GetStdHandle` 回傳特殊值 `65537`（0x10001），程式會把 `H-STDOUT` 改成 `-1` 作為無效輸出處理。注意 `65537` 不是 Win32 的 `INVALID_HANDLE_VALUE`（後者是 `-1`/`0xFFFFFFFF`），不要把它稱為 `INVALID_HANDLE_VALUE` 的近似值。

### 11.5 QUIT — 主互動迴圈

```forth
: QUIT ( -- ) ( R: i*x )
  BEGIN
    CONSOLE-HANDLES             \ 重新取得控制代碼
    0 TO SOURCE-ID              \ 設定輸入為 STDIN
    0 TO SOURCE-ID-XT
    ATIB 0 SOURCE!             \ 重設終端輸入緩衝區
    [COMPILE] [                  \ 切換到直譯模式
    ['] MAIN1 CATCH         DUP SOURCE NIP 2>R
    ['] ERROR CATCH DROP    2R> 0= IF HALT THEN DROP
    S0 @ SP!                    \ 重設資料堆疊（但不清回返堆疊）
  AGAIN
;

: MAIN1 ( -- )
  BEGIN
    REFILL
  WHILE
    INTERPRET OK
  REPEAT BYE
;
```

QUIT 迴圈的關鍵設計：
1. `CONSOLE-HANDLES`：每次迴圈開始時重新取得控制代碼（因為前一次迴圈可能關閉了 stdin）
2. `SOURCE NIP 2>R` ... `2R> 0=`：檢查例外是否消耗了原始碼
3. `['] MAIN1 CATCH` ... `['] ERROR CATCH`：雙層 CATCH 保護
4. `S0 @ SP!`：重設資料堆疊。注意註解提到「不清理回返堆疊」，因為 QUIT 本身就是回返堆疊的底層

### 11.6 EVALUATE-WITH — 安全求值

```forth
: EVALUATE-WITH ( i*x c-addr u xt -- j*x )
  SAVE-SOURCE N>R              \ 儲存當前來源狀態（6 個值）
  >R SOURCE! -1 TO SOURCE-ID  \ 設定新來源為 EVALUATE 字串
  R> ( xt ) CATCH              \ 執行並捕捉例外
  NR> RESTORE-SOURCE           \ 恢復來源狀態
  THROW                        \ 重新拋出例外（若有的話）
;
```

`SAVE-SOURCE` 儲存的 6 個值：`SOURCE-ID-XT`、`SOURCE-ID`、`>IN @`、`SOURCE`、`CURSTR @`、6（計數）。

### 11.7 INCLUDE-FILE 與 INCLUDED

```forth
: INCLUDE-FILE ( i*x fileid -- j*x )
  BLK 0!
  DUP >R
  ['] TranslateFlow RECEIVE-WITH   \ 安全執行檔案內容
  R> CLOSE-FILE THROW
  THROW
;

: INCLUDED ( i*x c-addr u -- j*x )
  FIND-FULLNAME INCLUDED_STD
;
```

`FIND-FULLNAME` 搜尋檔案的三個路徑：
1. 原始路徑
2. `+LibraryDirName`（模組目錄 + `/devel/`）
3. `+ModuleDirName`（模組目錄）

### 11.8 FIND-FULLNAME

```forth
: FIND-FULLNAME1 ( a u -- a u )
  2DUP FILE-EXISTS IF EXIT THEN
  2DUP +LibraryDirName 2DUP FILE-EXISTS IF 2SWAP 2DROP EXIT THEN 2DROP
  2DUP +ModuleDirName  2DUP FILE-EXISTS IF 2SWAP 2DROP EXIT THEN 2DROP
  2 ( ERROR_FILE_NOT_FOUND ) THROW
;
```

### 11.9 PROCESS-ERR — 處理程序錯誤向量

```forth
VECT PROCESS-ERR ( ior -- ior )

: PROCESS-ERR1 ( ior -- ior )
  DUP IF SEEN-ERR? IF DUP SAVE-ERR THEN THEN
;
```

在 INCLUDE-FILE 的錯誤路徑中，PROCESS-ERR 被呼叫以保存錯誤上下文。`SEEN-ERR?` 檢查此錯誤是否已被保存過（避免重複保存）。

---

## 12. 模組管理（spf_module.f + posix/module.f）

### 12.1 路徑操作

```forth
: CUT-PATH ( a u -- a u1 )
  CHARS OVER +                          \ 指向字串末尾
  BEGIN 2DUP <> WHILE                   \ 從末尾向前掃描
    CHAR- DUP C@ is_path_delimiter UNTIL  \ 找到路徑分隔符
    CHAR+                                 \ 跳過分隔符
  THEN
  OVER - >CHARS                          \ 計算路徑長度
;
SYNONYM PATH-PREFIX CUT-PATH
```

`CUT-PATH` 從路徑字串中擷取目錄部分：
- `"some/path/name"` → `"some/path/"`
- `"some/path/"` → `"some/path/"`
- `"name"` → `""`

POSIX 版的 `is_path_delimiter` 只匹配 `/`，Windows 版匹配 `/` 和 `\`。

### 12.2 ModuleName

```forth
: ModuleName ( -- addr u )
  (( S" /proc/self/exe" DROP SYSTEM-PAD 1024 )) readlink
  DUP -1 = IF DROP 0 THEN
  SYSTEM-PAD SWAP
;
```

POSIX 版透過 `readlink("/proc/self/exe")` 取得可執行檔的絕對路徑。Windows 版使用 `GetModuleFileName`。

### 12.3 +ModuleDirName 和 +LibraryDirName

```forth
: +ModuleDirName ( addr u -- addr2 u2 )
  2>R ModuleDirName 2DUP +     \ 模組目錄路徑 + 原始路徑
  2R> DUP >R ROT SWAP CHAR+ CHARS MOVE R> +
;

: +LibraryDirName ( addr u -- addr2 u2 )
  2>R ModuleDirName 2DUP +
  S" devel/" ROT SWAP CHARS MOVE      \ 追加 "devel/"
  6 + 2DUP +
  2R> DUP >R ROT SWAP CHAR+ CHARS MOVE R> +
;
```

`+ModuleDirName`：`可執行檔目錄/原始路徑`
`+LibraryDirName`：`可執行檔目錄/devel/原始路徑`

### 12.4 CROP 和 CROP-

```forth
: CROP ( a1 u1 a-dst u-dst-max -- a-rest u-rest )
  DUP >R ROT UMIN DUP >R 2DUP + >R MOVE R> 2R> -
;

: CROP- ( a-dst u-dst-max a1 u1 -- a-rest u-rest )
  ROT DUP >R UMIN >R SWAP R@ 2DUP + >R MOVE R> 2R> -
;
```

安全複製函式，確保不超過目標緩衝區大小。回傳值 `(a-rest u-rest)` 為剩餘未複製的部分。

---

## 13. Windows API 呼叫機制（win/spf_win_api.f）

### 13.1 AO_INI — 延遲載入 API 函數

```forth
CODE AO_INI
  MOV  EBX, EAX              \ EBX = 結構指標
  MOV  EAX, 4[EBX]           \ EAX = 函式庫名稱指標
  PUSH EAX
  MOV  EAX, AddrOfLoadLibrary
  CALL EAX                    \ LoadLibraryA(libname)
  OR   EAX, EAX
  JZ   @@1                   \ 載入失敗

  MOV  ECX, 8[EBX]           \ ECX = 函數名稱指標
  PUSH ECX
  PUSH EAX
  MOV  EAX, AddrOfGetProcAddress
  CALL EAX                    \ GetProcAddress(hModule, procname)
  OR   EAX, EAX
  JZ   @@2                   \ 找不到函數
  RET                         \ 回傳函數位址

@@2:  MOV  EAX, EBX           \ 找不到函數 → 跳到 PROC-ERROR
  JMP ' PROC-ERROR
@@1:  MOV  EAX, EBX           \ 找不到函式庫 → 跳到 LIB-ERROR
  JMP ' LIB-ERROR
END-CODE
```

AO_INI 實作 Windows API 的動態連結：先用 `LoadLibraryA` 載入 DLL，再用 `GetProcAddress` 取得函數位址。結構指標 `EBX` 指向 `{link, libname, procname}` 三欄結構。

### 13.2 API-CALL — 呼叫 API 函數

```forth
CODE API-CALL ( ... extern-addr -- x )
  PUSH EDI                   \ 儲存 TLS 指標
  PUSH EBP                   \ 儲存資料堆疊指標
  SUB  ESP, # 60             \ 在呼叫堆疊上分配 60 位元組
  MOV  EBX, EDI              \ 儲存 EDI
  MOV  EDI, ESP              \ EDI = 呼叫堆疊頂端
  MOV  ESI, EBP              \ ESI = 資料堆疊指標
  MOV  ECX, # 15             \ 複製 15 個 CELL（60 位元組）
  CLD
  REP MOVS DWORD             \ 從資料堆疊複製到呼叫堆疊
  MOV  EBP, ESP              \ EBP = 新的資料堆疊指標
  MOV  EDI, EBX              \ 恢復 EDI
  CALL EAX                   \ 呼叫 API 函數
  MOV  EBX, EBP
  SUB  EBX, ESP              \ EBX = 呼叫後 ESP 的偏移
  MOV  ESP, EBP              \ 恢復 ESP
  ADD  ESP, # 60             \ 釋放呼叫堆疊空間
  POP  EBP                   \ 恢復 EBP
  SUB  EBP, EBX              \ 調整資料堆疊指標（移除已消費的引數）
  POP  EDI                   \ 恢復 EDI
  RET
END-CODE
```

API-CALL 將資料堆疊上的引數複製到呼叫堆疊。Win32 API 通常使用 stdcall（被呼叫者清理堆疊），而這段程式會在呼叫後比較 `EBP` / `ESP` 的差值，據此調整 Forth 資料堆疊，反映 API 實際消耗的引數數量。

值得注意的是 15 個 CELL（60 位元組）的限制：Windows API 最多可傳遞 15 個 32 位元引數。`SUB EBP, EBX` 會根據 API 函數實際消耗的引數數量調整堆疊。

---

## 14. 系統架構總覽

### 14.1 初始化流程圖

```forth
進程入口
  │
  ├─ PROCESS-INIT (posix/init.f 或 win/spf_win_init.f)
  │   ├─ ERASE-IMPORTS
  │   ├─ dl-init / CREATE-PROCESS-HEAP
  │   ├─ 設定動態連結錯誤處理器
  │   ├─ ALLOCATE-THREAD-MEMORY
  │   ├─ POOL-INIT
  │   ├─ set-errsignal-handler / <SET-EXC-HANDLER>
  │   └─ AT-PROCESS-STARTING (分散式定義，模組可擴充)
  │
  ├─ (INIT) (spf_init.f)
  │   ├─ 儲存 ARGC/ARGV
  │   ├─ 組合命令列字串 → CMDLINE/#CMDLINE
  │   ├─ NATIVE-LINES（設定換行模式）
  │   ├─ 0 TO H-STDLOG
  │   ├─ CONSOLE-HANDLES（POSIX: 空操作；Windows: GetStdHandle）
  │   ├─ CGI-OPTIONS（ERR-EXIT 包裹）
  │   ├─ MAINX @ ?DUP IF ERR-EXIT THEN（若指定主程式）
  │   ├─ SPF-INI（搜尋 spf4.ini）
  │   ├─ OPTIONS（處理命令列）
  │   ├─ <MAIN>（QUIT 迴圈，互動模式）
  │   └─ BYE
  │
  執行緒入口
  │
  ├─ FORTH-INSTANCE> (= USER-INIT)
  │   ├─ ALLOCATE-THREAD-MEMORY / CREATE-HEAP
  │   ├─ POOL-INIT
  │   └─ AT-THREAD-STARTING (分散式定義，模組可擴充)
  │
  執行緒離開
  │
  ├─ <FORTH-INSTANCE (= USER-EXIT)
  │   ├─ AT-THREAD-FINISHING
  │   └─ FREE-THREAD-MEMORY / DESTROY-HEAP
```

### 14.2 I/O 向量層級

```forth
應用層             EMIT / TYPE / ACCEPT / KEY / KEY?
                     │
向量層             TYPE1 → TYPE向量    ACCEPT1 → ACCEPT向量
                   KEY1 → KEY向量      EKEY?/EKEY
                     │
平台層             ANSI><OEM（POSIX: NOP；Windows: 編碼轉換）
                   WRITE-FILE / READ-LINE（posix/io.f 或 win/spf_win_io.f）
                     │
日誌層             TO-LOG（條件寫入 H-STDLOG）
                     │
系統層             POSIX: read/write/close/open64...
                   Windows: ReadFile/WriteFile/CloseHandle...
```

### 14.3 例外處理流程

```forth
硬體例外（SIGSEGV/SIGFPE 等）
  │
  ├─ POSIX: sigaction → (errsignal) → THROW
  │          ├─ 恢復 EDI（TLS 指標）
  │          ├─ DUMP-TRACE（傾印資訊）
  │          └─ signum>ior → THROW → CATCH 鏈
  │
  ├─ Windows: FS:[0] SEH frame → EXC-DUMP1 → DUMP-TRACE-USING-REGS
  │
Forth 例外（THROW n）
  │
  ├─ n=0: 丟棄，繼續
  ├─ CATCH 找到 HANDLER: 恢復 SP/RP，回到 CATCH 之後
  └─ 無 HANDLER: FATAL-HANDLER → DUMP-TRACE → TERMINATE/exit()
```

### 14.4 來源追蹤器

```forth
INCLUDE / REQUIRED / EVALUATE
  │
  ├─ SAVE-SOURCE: 儲存 SOURCE-ID, SOURCE-ID-XT, >IN, SOURCE, CURSTR
  ├─ RECEIVE-WITH: 設定新來源，CATCH 執行
  └─ RESTORE-SOURCE: 恢復來源狀態
```
