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

---

## 5. `lib/ext/`：SP-Forth 常用延伸

`lib/ext/` 裡的檔案通常不是 ANS 標準字，而是 SP-Forth 自己的便利工具或系統級輔助。

| 檔案 | 角色 |
|------|------|
| `lib/ext/spf4e.f` | extended build 主入口 |
| `lib/ext/spf-asm.f` | SP-Forth assembler 支援，`src/spf.f` 建構時會載入 |
| `lib/ext/disasm.f` | `SEE` / disassembler 支援 |
| `lib/ext/caseins.f` | ASCII 範圍內的 case-insensitive search |
| `lib/ext/patch.f` | 替換既有 word 行為的工具 |
| `lib/ext/struct.f` | 結構欄位定義輔助 |
| `lib/ext/vocs.f` | 詞彙表相關工具 |

`caseins.f` 的關鍵點是它不改變所有字串比較，而是替換 `FIND-NAME-IN` 的行為：

```forth
' FIND-NAME-IN.MAYBE-INSENSITIVE TO FIND-NAME-IN
```

並且只在 ASCII 範圍做大小寫不敏感，避免破壞 UTF-8。

---

## 6. `lib/posix/`：POSIX 可選輔助

`lib/posix/` 不是 `src/posix/` 的替代品。`src/posix/` 是平台實作本體；`lib/posix/` 則是使用者層或 extended library 可能載入的補助工具。

幾個入口：

| 檔案 | 角色 |
|------|------|
| `lib/posix/file.f` | POSIX 檔案輔助，常被 `lib/include/ansi.f` 依平台載入 |
| `lib/posix/key.f` | 使用 termios 實作互動式 `KEY` |
| `lib/posix/const/` | 產生 / 保存 POSIX 常數表 |

`lib/posix/key.f` 會保存目前 terminal 設定，切到非 canonical / non-echo 模式讀一個字元，再恢復設定：

```forth
: KEY-TERMIOS ( -- c )
  prepare-terminal
  0 SP@ 1 H-STDIN READ-FILE DROP DROP
  restore-terminal ;

' KEY-TERMIOS TO KEY
```

這也解釋了為什麼 `src/posix/con_io.f` 裡的 `KEY` / `KEY?` 初始只是 placeholder：完整終端機按鍵支援屬於可選載入的 library 層。

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

`lib/win/api-call/` 裡的 `capi.f` / `capi2.f` / `altwinapi.f` 是比較低層的呼叫封裝實驗。一般閱讀 Windows FFI 主線時，先讀 [09-windows-platform.md](09-windows-platform.md) 的 `WINAPI:` / `API-CALL`；需要比較替代呼叫模型時，再回來看這裡。

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

- `src/` 主系統如何載入與建構，先看 [00-overview.md](00-overview.md) 與 [06-build-save.md](06-build-save.md)。
- compiler / `INCLUDED` / `REQUIRE` 的核心行為，先看 [02-compiler.md](02-compiler.md)。
- POSIX / Windows 平台本體，分別看 [04-posix-platform.md](04-posix-platform.md) 與 [09-windows-platform.md](09-windows-platform.md)。
- `ac-lib3/` 是另一組較大的延伸函式庫，見 [16-ac-lib3.md](16-ac-lib3.md)。
- `devel/` 是作者工作區與歷史原型集合，見 [17-devel.md](17-devel.md)。
