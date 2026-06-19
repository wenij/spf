# SP-Forth/4 原始碼追蹤 — `lib/` 與 `spf4e` 延伸庫導覽

> 定位：本章補足 `lib/` 目錄與 `spf4e` extended build 的閱讀入口。
> 如果 `src/` 是系統本體，`lib/` 就是把核心補成較完整使用環境的標準字、工具字與平台延伸集合。

---

## 1. `lib/` 是什麼？

`lib/` 不是 kernel，也不是 `ac-lib3/` 那種大型歷史延伸庫。它更接近 **SP-Forth 主系統旁邊的標準補齊層**：

- `lib/include/`：ANS Forth word set、常用 include、字串 / double / float / facility / tools 等補齊。
- `lib/ext/`：SP-Forth 自己常用的延伸工具，例如 assembler、case-insensitive search、disassembler、patch、struct、vocs。
- `lib/posix/`：POSIX 平台上可選的檔案與終端機輔助。
- `lib/win/`：Windows 平台上的可選輔助，包括檔案、mutex、常數、API 呼叫變體與 GUI 相關支援。

閱讀順序上，可以把它放在 `src/` 之後、`ac-lib3/` 和 `devel/` 之前：

1. 先讀 `src/`，理解核心、編譯器、平台與 image save。
2. 再讀 `lib/`，理解 `spf4e` 為什麼比 `spf4` 更適合日常使用。
3. 最後讀 `ac-lib3/` / `devel/`，找較大型或較歷史性的延伸庫。

---

## 2. `spf4` 與 `spf4e` 的差別

建構流程會先產生最小核心 `spf4`，再用它載入 `lib/ext/spf4e.f` 產生 `spf4e`。

`lib/ext/spf4e.f` 做的事不是「把整個 `lib/` 全包進去」，而是有選擇地載入幾組常用能力：

```forth
S" lib/include/ansi.f" INCLUDED

MODULE: disasm-voc
  REQUIRE-WORD SEE            lib/ext/disasm.f
EXPORT
  SYNONYM SEE SEE
;MODULE

REQUIRE-WORD FCONSTANT      lib/include/float2.f
REQUIRE-WORD [:             lib/include/quotations.f
REQUIRE-WORD CASE-INS       lib/ext/caseins.f
```

它也會調整 `ERROR` 對 `-1 THROW` 的顯示，並補上幾個字串比對與路徑解析工具。最後一段會改寫 `find-fullname`，讓 `./...` 這類 include 路徑可以相對目前 source base path 解析。

最簡單的判斷方式：

| 可執行檔 | 適合情境 |
|----------|----------|
| `spf4` | 追核心建構、最小 image、低層 debug |
| `spf4e` | 日常開發、較完整 ANS word set、case-insensitive search、`SEE`、quotation 等便利功能 |

---

## 3. `lib/include/`：ANS 與常用 word set 補齊

`lib/include/ansi.f` 是這一區的主要入口。它會載入多個 include 檔，補齊常用 word set：

```forth
REQUIRE CASE         lib/include/control-case.f
REQUIRE /STRING      lib/include/string.f
REQUIRE [IF]         lib/include/tools.f
REQUIRE SAVE-INPUT   lib/include/core-ext.f
REQUIRE SYNONYM      lib/include/wordlist-tools.f
REQUIRE TIME&DATE    lib/include/facil.f
REQUIRE DEFER        lib/include/defer.f
REQUIRE D0<          lib/include/double.f
REQUIRE ANSI-FILE    lib/include/ansi-file.f
```

幾個最值得先看的檔案：

| 檔案 | 角色 |
|------|------|
| `lib/include/ansi.f` | 最大的常用入口，整合多個 ANS / 常用 word set |
| `lib/include/ansi-file.f` | 讓檔名不必預先補零結尾，將 `c-addr u` 轉成底層可接受的 ASCIIZ |
| `lib/include/core-ext.f` | `SAVE-INPUT` / `RESTORE-INPUT` 等 core extension |
| `lib/include/string.f` | `/STRING`、`BLANK` 等字串工具 |
| `lib/include/tools.f` | `[IF]` / `[ELSE]` / `[THEN]`、條件編譯與工具字 |
| `lib/include/float2.f` | 浮點延伸，`spf4e.f` 會透過 `FCONSTANT` 需要它 |
| `lib/include/quotations.f` | `[: ... ;]` quotation 語法 |

這一區最容易混淆的是 **double** 與 **float**：

| 類型 | 主要檔案 | 放在哪個 stack | 適合什麼 |
|------|----------|-----------------|----------|
| double-cell integer | `lib/include/double.f` | 一般 data stack（兩個 cell） | 大整數、file offset、計數器、`<# # #S #>` 格式化、`REPOSITION-FILE` / `FILE-SIZE` 這類要用 `ud` / `d` 的 API |
| floating-point | `lib/include/float2.f` | **獨立的 floating-point stack** | 工程計算、幾何、平均值、比例、三角與開方等非整數運算 |

也就是說：

- `double.f` 不是「雙精度浮點數」，而是 **double-cell 整數**。
- `float2.f` 才是浮點數支援；在 x86 / x87 背景下，實際上通常對應 IEEE 754 類型的 double-precision 行為。

使用上最重要的判斷原則：

1. **要精確整數** → 先想 `double.f`
2. **要小數與量測值** → 先想 `float2.f`
3. **要把 file offset / size 串進系統 API** → 幾乎一定會碰到 `d` / `ud`
4. **不要把 `2VALUE` 當作 float 用**；`2VALUE` 儲存的是兩個 cell，不是浮點 stack 上的 `r`

常見誤區：

- `123.` / `0.` / `1.` 這種尾巴帶點的是 **double-cell 整數 literal**。
- `1.5E` / `3e` 這種帶 exponent 記法的是 **浮點 literal**。
- Forth 標準的 float word set 用 `( F: before -- after )` 標示獨立的 float stack；因此 `FCONSTANT` / `FVARIABLE` / `FVALUE` 與 `2CONSTANT` / `2VALUE` 不是同一套型別系統。

同樣值得一起理解的是 **alignment**：

- 一般 data space 用 `ALIGN` / `ALIGNED`
- 浮點資料空間用 `FALIGN` / `FALIGNED`
- `FVARIABLE` / `FVALUE` 會自動幫你處理 float 對齊

這件事在 x86 上平常不一定立刻炸掉，但在跨平台、結構體、FFI、或你自己手動 `HERE ... ALLOT` 存 float / double-cell 資料時，很容易變成埋雷。最穩的習慣是：

1. 存整數 cell pair → `ALIGN`
2. 存 float → `FALIGN`
3. 不確定時優先用 `2VARIABLE` / `FVARIABLE` / `FVALUE`，不要自己硬算 offset

另外，`DEFER` / `[: ... ;]` / `lib/ext/locals.f` 三組也有相容性邊界：

- `DEFER` / `IS` / `ACTION-OF`：安全，純行為抽換
- `[: ... ;]`：安全，但走獨立 quotation frame
- `lib/ext/locals.f`：安全，但 **不要**和 quotation 內部混用

也就是說，`DEFER` 比較像「換掉函式入口」，`quotation` 比較像「建立匿名 xt」，`locals` 比較像「改寫 stack 可讀性」；三者用途不同，不要把它們當同一類機制。

實際可跑範例（`CASE` / `DEFER` / `[: ... ;]` / `2CONSTANT` / `FCONSTANT` / `INCLUDE` / `BIN` / `FILE-STATUS` 等）已拆到 [16-lib-cookbook.md §2](file:///Users/wenij/work/forth/spf/docs/trace/16-lib-cookbook.md#2-libinclude-可跑範例)。

---

## 4. `ansi-file.f` 為什麼重要？

SP-Forth kernel 的底層 file words 傾向期待檔名字串結尾已經有 `0`。`lib/include/ansi-file.f` 則包裝這些 word，讓呼叫端可以使用比較標準的 `c-addr u` 形式。

核心工具是：

```forth
: >ZFILENAME ( c-addr u -- zaddr u )
  2DUP ?Z IF EXIT THEN
  2DUP COPYFILENAME
  NIP PFILENAME SWAP 2DUP + 0 SWAP C! ;
```

因此使用者層的 file word 會變成：

```forth
: OPEN-FILE ( c-addr u fam -- fileid ior )
  >R >ZFILENAME R> OPEN-FILE ;
```

閱讀建議：

- 如果你追的是底層 platform I/O，讀 `src/posix/io.f` 或 `src/win/spf_win_io.f`。
- 如果你追的是日常 Forth 程式如何用 `S" file" R/O OPEN-FILE`，讀 `lib/include/ansi-file.f`。

完整的 `OPEN-FILE` / `READ-LINE` / `WRITE-FILE` / `BIN` 讀寫範例與常見錯誤對照，已拆到 [16-lib-cookbook.md §3](file:///Users/wenij/work/forth/spf/docs/trace/16-lib-cookbook.md#3-ansi-filef-實戰用法)。

---

## 5. `lib/ext/`：SP-Forth 常用延伸

`lib/ext/` 裡的檔案通常不是 ANS 標準字，而是 SP-Forth 自己常用的便利工具或系統級輔助。

| 檔案 | 角色 |
|------|------|
| `lib/ext/spf4e.f` | extended build 主入口 |
| `lib/ext/spf-asm.f` | SP-Forth assembler 支援，`src/spf.f` 建構時會載入 |
| `lib/ext/disasm.f` | `SEE` / disassembler 支援 |
| `lib/ext/caseins.f` | ASCII 範圍內的 case-insensitive search |
| `lib/ext/patch.f` | 替換既有 word 行為的工具 |
| `lib/ext/struct.f` | 結構欄位定義輔助 |
| `lib/ext/vocs.f` | 詞彙表相關工具 |
| `lib/ext/locals.f` | `{ ... }` 與 `LOCAL` 語法 |
| `lib/ext/onoff.f` | `ON` / `OFF` flag 設定 |
| `lib/ext/rnd.f` | 偽隨機數 (`SEED` / `RANDOM` / `CHOOSE`) |
| `lib/ext/uppercase.f` | 字元 / 字串大小寫轉換與比對 |
| `lib/ext/help.f` | `***` 區塊的線上說明 |
| `lib/ext/util.f` | 模組路徑 / library 路徑相關檔案開啟輔助 |
| `lib/ext/const.f` | 常數 vocabulary 機制（`WINAPI:` 常數動態載入用） |

`caseins.f` 的關鍵點是它不改變所有字串比較，而是替換 `FIND-NAME-IN` 的行為：

```forth
' FIND-NAME-IN.MAYBE-INSENSITIVE TO FIND-NAME-IN
```

並且只在 ASCII 範圍做大小寫不敏感，避免破壞 UTF-8。

`caseins.f` / `disasm.f` / `struct.f` / `vocs.f` / `locals.f` / `patch.f` / `onoff.f` / `rnd.f` / `uppercase.f` / `help.f` / `util.f` / `const.f` 的可跑範例，已拆到 [16-lib-cookbook.md §4](file:///Users/wenij/work/forth/spf/docs/trace/16-lib-cookbook.md#4-libext-可跑範例)。

---

## 6. `lib/posix/`：POSIX 可選輔助

`lib/posix/` 不是 `src/posix/` 的替代品。`src/posix/` 是平台實作本體；`lib/posix/` 則是使用者層或 extended library 可能載入的補助工具。

幾個入口：

| 檔案 | 角色 |
|------|------|
| `lib/posix/file.f` | POSIX 檔案輔助，常被 `lib/include/ansi.f` 依平台載入 |
| `lib/posix/key.f` | 使用 termios 實作互動式 `KEY` |
| `lib/posix/const.f` | 載入 POSIX 常數表（從 `lib/posix/const/linux.const`） |
| `lib/posix/const/` | 產生 / 保存 POSIX 常數表的腳本與成品 |

`lib/posix/key.f` 會保存目前 terminal 設定，切到非 canonical / non-echo 模式讀一個字元，再恢復設定：

```forth
: KEY-TERMIOS ( -- c )
  prepare-terminal
  0 SP@ 1 H-STDIN READ-FILE DROP DROP
  restore-terminal ;

' KEY-TERMIOS TO KEY
```

這也解釋了為什麼 `src/posix/con_io.f` 裡的 `KEY` / `KEY?` 初始只是 placeholder：完整終端機按鍵支援屬於可選載入的 library 層。

這一區最重要的不是 API 數量，而是**平台差異被收斂到檔名相似的兩套 library**：

- POSIX 常數：`lib/posix/const.f` → `linux.const`
- Windows 常數：`lib/win/const.f` → `windows.const`
- 兩邊都叫 `RENAME-FILE`、`COPY-FILE`，但底層分別走 libc / Win32 API

所以你在寫跨平台程式時，真正要做的是：

1. 先決定「常數來自哪邊」
2. 再決定「檔案 / console 行為來自哪邊」
3. 最後才決定需不需要碰更低層的 `src/posix/*` / `src/win/*`

`lib/posix/file.f` / `key.f` / `const.f` 的可跑範例與常見小工具，已拆到 [16-lib-cookbook.md §5](file:///Users/wenij/work/forth/spf/docs/trace/16-lib-cookbook.md#5-libposix-可跑範例)。

---

## 7. `lib/win/`：Windows 可選輔助

`lib/win/` 裡的檔案多半建立在 `src/win/` 已提供的 WinAPI 呼叫基礎上，用來補日常 Windows 開發會碰到的功能。

| 檔案 / 目錄 | 角色 |
|-------------|------|
| `lib/win/file.f` | Windows 檔案輔助，`lib/include/ansi.f` 會在有 `WINAPI:` 時載入 |
| `lib/win/mutex.f` | Windows mutex 輔助 |
| `lib/win/osver.f` | Windows 版本偵測 |
| `lib/win/winerr.f` | Windows error 相關輔助 |
| `lib/win/api-call/` | 替代 API 呼叫封裝與 C-style API call 實驗 |
| `lib/win/spfgui/` | GUI 相關支援 |
| `lib/win/const.f` | 載入 Windows API 常數表（`windows.const`） |
| `lib/win/winconst/` | 產生 / 保存 Windows 常數表 |

`lib/win/api-call/` 裡的 `capi.f` / `capi2.f` / `altwinapi.f` 是比較低層的呼叫封裝實驗。一般閱讀 Windows FFI 主線時，先讀 [09-windows-platform.md](file:///Users/wenij/work/forth/spf/docs/trace/09-windows-platform.md) 的 `WINAPI:` / `API-CALL`；需要比較替代呼叫模型時，再回來看這裡。

從架構角度看，`lib/win/` 比 `ac-lib3/win/` 更接近「**小而直接的 platform adapter**」：

- `lib/win/const.f`：把 Windows SDK 常數表轉成可搜尋 vocabulary
- `lib/win/file.f`：補基本檔案輔助
- `lib/win/mutex.f`：補同步 primitive
- `lib/win/winerr.f`：把 Win32 error 轉成可讀訊息

如果你只是想把 `WINAPI:` 宣告寫得比較順手、拿到 `GENERIC_READ` / `FILE_SHARE_READ` 這類常數、再補一點檔案 / mutex / error helper，`lib/win/` 通常夠用；只有當你需要 registry / COM / Winsock / ODBC / service 這類較厚的整合時，才升級到 `ac-lib3/win/`。

`lib/win/file.f` / `mutex.f` / `osver.f` / `winerr.f` / `const.f` 與 `api-call/`、`spfgui/` 的可跑範例，已拆到 [16-lib-cookbook.md §6](file:///Users/wenij/work/forth/spf/docs/trace/16-lib-cookbook.md#6-libwin-可跑範例)。

---

## 8. 什麼時候讀 `lib/`？

| 需求 | 先看 |
|------|------|
| 想知道 `spf4e` 多載了什麼 | `lib/ext/spf4e.f` |
| 想補 ANS Forth 常用 word set | `lib/include/ansi.f` |
| 想理解 `S" file" OPEN-FILE` 為什麼能用非零結尾字串 | `lib/include/ansi-file.f` |
| 想用 `[: ... ;]` quotation | `lib/include/quotations.f` |
| 想理解 case-insensitive search | `lib/ext/caseins.f` |
| 想在 POSIX console 讀單鍵 | `lib/posix/key.f` |
| 想研究 Windows API 呼叫變體 | `lib/win/api-call/` |

---

## 9. 與其它 trace 章節的關係

- `src/` 主系統如何載入與建構，先看 [00-overview.md](file:///Users/wenij/work/forth/spf/docs/trace/00-overview.md) 與 [06-build-save.md](file:///Users/wenij/work/forth/spf/docs/trace/06-build-save.md)。
- compiler / `INCLUDED` / `REQUIRE` 的核心行為，先看 [02-compiler.md](file:///Users/wenij/work/forth/spf/docs/trace/02-compiler.md)。
- POSIX / Windows 平台本體，分別看 [04-posix-platform.md](file:///Users/wenij/work/forth/spf/docs/trace/04-posix-platform.md) 與 [09-windows-platform.md](file:///Users/wenij/work/forth/spf/docs/trace/09-windows-platform.md)。
- `ac-lib3/` 是另一組較大的延伸函式庫，見 [17-ac-lib3.md](file:///Users/wenij/work/forth/spf/docs/trace/17-ac-lib3.md)。
- `devel/` 是作者工作區與歷史原型集合，見 [18-devel.md](file:///Users/wenij/work/forth/spf/docs/trace/18-devel.md)。

---

## 10. 完整 build flow：從 `spf4` 到 `spf4e`

這節把「`spf4` 是什麼、`spf4e` 是怎麼從 `spf4` 長出來的」完整跑過一次，幫助理解 `lib/ext/spf4e.f` 與 `lib/include/ansi.f` 等檔案**實際**在 build 流程中的角色。

### 10.1 階段一：用舊版 SPF 建出 `spf4` 核心

```text
src/Makefile
   ↓
src/spf.f                ← 主載入腳本
   ↓
src/spf_kernel.f         ← 載入 primitive、定義字核心
src/spf_forthproc.f      ← Forth 程序核心
src/spf_defkern.f        ← 定義字（CREATE / CONSTANT / USER）
src/compiler/*.f         ← parser / compiler / search engine
src/posix/io.f           ← POSIX 平台 I/O
... + optimizer + save ...
   ↓
spf4  ← 已可用，但只有最基本核心
```

建構細節見 [06-build-save.md](file:///Users/wenij/work/forth/spf/docs/trace/06-build-save.md)。在 Linux 上是 `cd src && make`；在 Windows 上是 `src/compile.bat`。

### 10.2 階段二：用 `spf4` 載入 `lib/ext/spf4e.f` 產出 `spf4e`

`src/Makefile`（POSIX）或 `src/compile.bat`（Windows）會在這個階段呼叫：

```bash
./spf4 lib/ext/spf4e.f
```

`lib/ext/spf4e.f` 內部大致做這幾件事（按 `lib/ext/spf4e.f` 原始順序）：

```forth
\ 1. 載入常用 ANS word set
S" lib/include/ansi.f" INCLUDED

\ 2. SEE / disasm 暴露
MODULE: disasm-voc
  REQUIRE-WORD SEE            lib/ext/disasm.f
EXPORT
  SYNONYM SEE SEE
;MODULE

\ 3. 浮點 / quotation / case-insensitive 三個核心延伸
REQUIRE-WORD FCONSTANT      lib/include/float2.f
REQUIRE-WORD [:             lib/include/quotations.f
REQUIRE-WORD CASE-INS       lib/ext/caseins.f

\ 4. 調整 ERROR 對 -1 THROW 的顯示（用 is error 安裝新的 error handler）
:noname ( 0|ior -- )
  dup -1 = if drop ." (aborted)" cr exit then
  [ action-of error compile, ]
; is error

\ 5. 補幾個輔助 word：equals / match-head / filename-existent
\    （這幾個是 [undefined] 時才定義，避免與已存在的衝突）
[undefined] equals [if] : equals ... [then]
[undefined] match-head [if] : match-head ... [then]
synonym filename-existent file-exists   \ 把 FILE-EXIST 別名成 filename-existent

\ 6. 改寫 find-fullname：當檔名以 "./" 開頭時，相對於目前 source-basepath 解析
:noname ( sd.filename1 -- sd.filename2.transient )
  s" ./" match-head 0= if [ action-of find-fullname compile, ] exit then
  source-basepath dup 0= if 2drop -2 /string \ revert "./"
  else ... 2dup filename-existent if exit then -38 throw
  then
; is find-fullname
```

完成後 `spf4e` 會：

- 多了 `[:` / `;]` / `DEFER` / `IS` / `ACTION-OF` / `MARKER` / `2CONSTANT` 等常用 word。
- `SEE` 變成內建 disassembler。
- dictionary 搜尋自動變成 ASCII case-insensitive。
- 浮點運算變成可獨立 import。

### 10.3 階段三：儲存

在 `lib/ext/spf4e.f` 的最後一段（POSIX Makefile / Windows compile.bat 內）會做：

```forth
10 1024 * 1024 * S" ../spf4e" SAVE-WITH-RESERVE BYE
```

- `10 1024 * 1024 *` = 預留 10 MiB 的 dictionary 空間（給 runtime 載入更多 source 時用）。
- `SAVE-WITH-RESERVE` 把目前 image 連同保留空間一起寫出。
- `BYE` 直接離開，不回到互動 prompt。

`SAVE-WITH-RESERVE` 的 stack effect 在 `src/spf.f:322`：

```forth
: SAVE-WITH-RESERVE ( u.target-dict-unused  sd.filename-executable )
```

### 10.4 用 spf4e 跑自己的程式

```bash
./spf4e myapp.fth 2 3 + . bye
```

這行命令做的事：

1. 啟動 `spf4e` 映像。
2. 對 `myapp.fth` 執行 `INCLUDED`。
3. 把 `2 3 + .` 與 `bye` 當作 input 餵給直譯器（每個空白分隔的 token 依序執行）。
4. 印出 `5`，然後 `BYE` 結束。

> 也可以 `S" myapp.fth" INCLUDED` 寫在程式內部，再用 SAVE 包成可獨立執行檔（見 [15-standalone-cookbook.md](file:///Users/wenij/work/forth/spf/docs/trace/15-standalone-cookbook.md)）。

### 10.5 為什麼分階段？

- `spf4` 是「自舉（bootstrap）」階段的產物：它必須夠小、夠乾淨，才能被用來建構更大的東西。
- `lib/ext/spf4e.f` 是「擴充」階段：它只載入 `spf4` 已有的能力 + `lib/` 內常用輔助，不碰 `src/` 主系統。
- 這樣分層的好處是：日後 `spf4` 內部變動時，只要 `spf4e` 重新用新 `spf4` 跑一次 `lib/ext/spf4e.f` 即可，不必重寫 `lib/`。

---

## 11. 載入策略與常見問題

### 11.1 載入順序基本原則

`lib/` 的檔案大多用 `REQUIRE` 而不是 `INCLUDED`，所以**重複 include 同一檔案不會重複執行**。但**檔案之間有先後依賴**，亂序 include 會編譯期失敗：

| 情境 | 正確順序 |
|------|----------|
| 載入完整 `spf4e` 套件 | 已經在 build 階段處理好，使用者不需手動 include |
| 在 `spf4` 上手動加載 `spf4e` 行為 | 跑 `S" lib/ext/spf4e.f" INCLUDED` 即可（包含所有依賴） |
| 只想補一個 word set | `REQUIRE <word> lib/include/<file>.f` |
| 想用 quotation | `REQUIRE [: lib/include/quotations.f` |
| 想用 locals | `S" lib/ext/locals.f" INCLUDED` |
| 想用 case-insensitive | `S" lib/ext/caseins.f" INCLUDED`（`spf4e` 已含） |
| Windows 想用 Win32 API 完整封裝 | `S" lib/win/const.f" INCLUDED` 後 `WINAPI:` 即可 |

把這幾個字分開理解會比較穩：

- `INCLUDED`：**無條件**載入檔案
- `INCLUDE`：`ansi.f` 補上的語法糖，本質上還是 `PARSE-NAME INCLUDED`
- `REQUIRE <word> file`：只有在 `<word>` 尚未定義時才載入 `file`

所以：

- 寫 library 本身時，偏好 `REQUIRE`
- 寫使用者端腳本時，偏好 `INCLUDED` / `INCLUDE`
- 需要可重複執行又不想重複定義時，偏好 `REQUIRE`

### 11.2 與 `ac-lib3/` 載入的差異

- `lib/` 是 **核心補齊層**：`spf4e` 預設就會帶，命名一致、依賴單純、適合直接 include 進商業程式。
- `ac-lib3/` 是 **歷史 / 大型延伸庫**：使用前要查 `REQUIRE` 列表、可能依賴 `~ac/lib/...` 路徑、可能用 `TEMPS.F` 風格而非 `LOCALS.F` 風格。

建議策略：

- 日常商業 / 工具類程式 → 優先用 `lib/`。
- 需要 `~ac` 風格特性（如 `STR2.F` 模板字串、`LOCALS.F`）→ 引入 `ac-lib3/` 對應檔案。
- 大型應用 / prototype → 看 [17-ac-lib3.md](file:///Users/wenij/work/forth/spf/docs/trace/17-ac-lib3.md) 找對應功能。

`lib/ext/spf4e.f` 另外做了一件重要的事：它會改寫 `find-fullname`，讓 `./...` 類路徑改成**相對目前 source-basepath** 解析，而不是單純相對啟動目錄。這對多檔案工程很重要，因為：

- 你可以在 `subdir/foo.f` 裡 `INCLUDED ./bar.f`
- `bar.f` 會相對 `foo.f` 所在路徑找
- 不用要求使用者一定從固定 cwd 啟動 `spf4e`

也就是說，`spf4e` 的 include 行為比純 `spf4` 更接近現代語言的「module-relative import」。

### 11.3 常見錯誤對照表

| 症狀 | 可能原因 | 解法 |
|------|----------|------|
| `CASE` 在 `spf4` 找不到 | 沒載入 `lib/include/control-case.f` | `REQUIRE CASE lib/include/control-case.f` |
| `DEFER` 已存在但 `IS` 報錯 | 載入了 `DEFER` 但沒載入 `lib/include/defer.f` | 改用 `lib/include/defer.f` 的版本（含 `IS`） |
| `SEE` 沒作用 | `lib/ext/spf4e.f` 的 `disasm-voc` 沒被 include | 在 `spf4` 上 `S" lib/ext/disasm.f" INCLUDED`；或直接走 `spf4e` |
| 引用 `TRAVERSE-WORDLIST` 編譯失敗 | `spf4e` 預設沒載入 `wordlist-tools.f` | `REQUIRE TRAVERSE-WORDLIST lib/include/wordlist-tools.f` |
| `Open` 出現 `0` 開頭的怪路徑 | 用 kernel 版 `OPEN-FILE` 又傳 `c-addr u` | `REQUIRE lib/include/ansi-file.f` 後再呼叫 |
| `RENAME-FILE` 報 ior 但 errno 是 ASCIIZ 截斷 | 用戶程式自己呼叫底層 `rename(2)` 而非 `RENAME-FILE` | 改用 `RENAME-FILE`，或先把字串補零 |
| `RANDOM` 結果永遠一樣 | 沒呼叫 `RANDOMIZE` 或 `SEED` 固定 | 視需求決定 seed 方式 |
| 開新檔 `R/W OPEN-FILE` 後 `WRITE-FILE` 寫入 0 bytes | `S" name" R/W OPEN-FILE` 漏 `BIN` flag，在 Windows 文字模式會被 CRLF 過濾 | 加 `BIN` flag 或確認 platform 行為 |
| 互動模式按方向鍵 / 數字鍵都沒反應 | 還在 placeholder `KEY`，沒載入 `lib/posix/key.f` | `S" lib/posix/key.f" INCLUDED` |
| Windows 下 `O_RDONLY` 找不到 | 載入了 `lib/posix/const.f`（POSIX 平台才會有） | 改用 `lib/win/const.f` 或依平台條件載入 |

### 11.4 載入時的調試技巧

- 想看「目前 dictionary 內有什麼 word」：用 `WORDS`（列出當前 wordlist）或 `VOCS`（載入 `lib/ext/vocs.f` 後可看所有 wordlist）。
- 想看某個 word 的來源：多數檔頭會有 `\ $Id$` 註解，但 git blame 比那個更可靠。
- 想確認某個 word 在哪個 include 載入：用 `FIND` + `>IN @` 與目前 SOURCE 對照，會看到該 word 的「上一個定義點」。
- 想知道哪些 lib 已載入：在 `spf4e` 啟動後立刻下 `WORDS`，命名空間來自 `lib/ext/spf4e.f` 載入的 include。

### 11.5 「我該不該 include 整包 `ansi.f`？」

依場景選擇：

| 場景 | 建議 |
|------|------|
| 寫工具 / 業務程式，建構期已用 `spf4e` | 不用手動 include；`spf4e` 已含 `ansi.f` |
| 寫小工具要直接丟給 `spf4` 跑 | `S" lib/include/ansi.f" INCLUDED` 一次補齊 |
| 只要 `CASE` 一個 word | `REQUIRE CASE lib/include/control-case.f` 最小化 |
| 要在 startup script 載入 | 同上，用 `REQUIRE` 即可（`REQUIRE` 不會重複載入） |

### 11.6 與其它章節的交叉點

- `lib/` 的 include 機制（`REQUIRE` / `INCLUDE`）底層行為見 [02-compiler.md §15](file:///Users/wenij/work/forth/spf/docs/trace/02-compiler.md#15-模組載入spf_modulesf深入解析)。
- `spf4e` 的 build 流程見 [00-overview.md §2.2](file:///Users/wenij/work/forth/spf/docs/trace/00-overview.md) 與 [06-build-save.md](file:///Users/wenij/work/forth/spf/docs/trace/06-build-save.md)。
- 想了解 `spf4` 與 `spf4e` 內部結構差異，看 `src/spf_init.f` 中 `MAINX` / `SPF-INIT?` 的初始化分支。
- `ac-lib3/` 與 `lib/` 怎麼選擇，看 [00-overview.md](file:///Users/wenij/work/forth/spf/docs/trace/00-overview.md) 的「延伸函式庫」段落。
