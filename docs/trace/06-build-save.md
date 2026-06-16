# SP-Forth/4 原始碼追蹤 — 建構系統、映像儲存與輔助檔案

> 本章目標：了解 spf4orig 如何自舉編譯出 spf4，ELF .o 如何產生，以及 SAVE / XSAVE 的流程差異。
> 
> 對應原始碼：`Makefile`、`posix/Makefile`、`posix/config.c`、`posix/config.auto.f`、
> `spf_compileoptions.f`、`spf_stub.f`、`spf_date.f`、`spf_xmlhelp.f`、
> `elf.f`、`xsave.f`、`posix/save.f`、`tsave.f`、`done.f`、`spf.f`（主控腳本）

---

## 1. 建構系統（Makefile + posix/Makefile）

### 1.1 主 Makefile 結構

Makefile（`src/Makefile`）管理 SP-Forth 的完整建構流程，支援 POSIX 和 Windows 雙平台。

**平台自動偵測**：

```makefile
ifeq ($(OSTYPE),cygwin)
  platform := win32
else
ifeq ($(OS),Windows_NT)
  platform := win32
else
  platform := posix
endif
endif
```

**跨平台編譯**：

```makefile
ifeq ($(platform),posix)
  ../spf4e.exe  ../spf4.exe       : export HOSTWRAPPER ?= wine
else ifeq ($(platform),win32)
  ../spf4e      ../spf4 spf4.o    : export HOSTWRAPPER ?= wsl
endif
```

當在 Linux 上建構 Windows 目標（`spf4.exe`）時，自動使用 `wine` 包裝；反之在 Windows 上建構 POSIX 目標時，使用 `wsl` 包裝。

**宿主編譯器下載**：

```makefile
url-binaries-base := https://github.com/rufig/spf4-cvs-archive/releases/download/v1.0/
orig-bin-lin    := spf4orig
shasum-bin-lin  := 3987f9b90257a0d49eda2cc39324b574e1b580dd
orig-bin-win    := jpf375c.exe
shasum-bin-win  := 1b1a244c615f8838ecd1bcd8a1f7907bae60664e
```

若宿主編譯器不存在，自動從 `rufig/spf4-cvs-archive` 的 GitHub releases 下載，並驗證 SHA1 校驗碼。

### 1.2 POSIX 建構流程

```makefile
posix/config.auto.f : posix/config.h posix/config.c
	$(MAKE) -C posix

spf4.o: HOSTFORTH ?= $(HOSTWRAPPER) ./$(orig-bin-lin)
spf4.o: $(common-sources) posix/config.auto.f posix/*.f $(if $(HOSTFORTH),,../$(orig-bin-lin))
	cd .. && echo "Wait a bit while compiling..." && echo 1 HALT | $(HOSTFORTH) src/spf.f

../spf4: spf4.o forth.ld
	$(CC) -v 2>&1 | grep -F --silent -- '--enable-default-pie' && gcc_nopie="-no-pie" ; \
	$(CC) -o $@ $< -Wl,forth.ld -ldl -lpthread -v -m32 -fno-pie $$gcc_nopie
```

三步流程：

1. **組態產生**：`$(MAKE) -C posix` 編譯 `posix/config.c` 並執行，產生 `posix/config.auto.f`
2. **映像編譯**：若 `HOSTFORTH` 未明確指定，Makefile 會自動要求 `../spf4orig`；之後宿主 Forth 編譯器（`spf4orig`）執行 `src/spf.f`，產生 `spf4.o`（ELF 可重定位物件檔）
3. **GCC 連結**：使用 `gcc -m32` 和連結器腳本 `forth.ld` 將 `spf4.o` 連結為可執行檔 `spf4`

`-fno-pie` 和 `-no-pie` 參數：SP-Forth 使用固定的 `IMAGE-START`（0x8050000），不支援位置無關可執行檔（PIE）。Makefile 偵測 GCC 是否啟用了 `--enable-default-pie`，若是則加上 `-no-pie`。

這和 SP-Forth 的儲存模型有直接關係：交叉編譯器與 `XSAVE` 會先以 `IMAGE-START` / `.forth` 為基準計算目標位址與重定位資訊，再交給最終連結步驟。因此若強制使用 PIE，會打亂這套「先決定位址、後做重定位」的假設。

**端到端觀察**（實際建構產物）：

```bash
cd src
make
```

這條命令在 POSIX 路徑上大致會依序產生：

1. `posix/config.auto.f`：由 `config.c` 偵測目標平台的 32 位元 ABI 常數後輸出。
2. `src/spf4.o`：由 `spf4orig src/spf.f` 產生的可重定位 ELF 物件檔。
3. `../spf4`：用 GCC 與 `forth.ld` 將 `spf4.o` 連結成最小核心可執行檔。
4. `../spf4e`：以 `../spf4` 載入 `lib/ext/spf4e.f` 後再儲存出的擴充映像。

**擴充版建構**：

```makefile
define build-spf4e
  echo '10 1024 * 1024 * S" $@" SAVE-WITH-RESERVE BYE' | $(HOSTWRAPPER) $< lib/ext/spf4e.f
endef
spf4e-sources = ../lib/include/*.f ../lib/ext/*.f
../spf4e.exe  : ../spf4.exe   $(spf4e-sources) ; $(build-spf4e)
../spf4e      : ../spf4       $(spf4e-sources) ; $(build-spf4e)
```

`spf4e` 使用 `SAVE-WITH-RESERVE` 儲存映像，並額外預留 10 MiB 可用字典空間（`10 1024 * 1024 *`）。這裡用 `S" $@"` 很重要：`$@` 是 Make 對應規則的 target 名稱，對照 `src/Makefile:74–82` 的 `target-bin-e` 變數：

- **POSIX native build**（Linux）：target 是 `../spf4e`，`$@` 展開為 `../spf4e`（**沒有 `.exe` 副檔名**）。
- **Cygwin / Win native build**：target 是 `../spf4e.exe`，`$@` 展開為 `../spf4e.exe`。
- 跨編譯路徑（在 Linux 上產出 Windows binary，或在 Windows 上產出 Linux binary）由 `src/Makefile:90–94` 的 `HOSTWRAPPER` 自動選擇 `wine` 或 `wsl` 來執行宿主 Forth；但是 `$@` 仍然由 target name 本身決定，不會因為 host 平台而換邊。

它會先載入 `lib/ext/spf4e.f`，而該檔再納入「所有可用的標準字（不含 BLOCK word set）」與部分實用延伸庫；因此較精確的理解是 extended executable，而不是單純把整個 `lib/` 目錄無差別全包進去。

### 1.3 Windows 建構流程

```makefile
../spf4.exe : HOSTFORTH ?= $(HOSTWRAPPER) ./$(orig-bin-win)
../spf4.exe: $(common-sources) win/*.f win/res/* $(if $(HOSTFORTH),,../$(orig-bin-win))
	cd .. ; echo 1 HALT | $(HOSTFORTH) src/tc-configure-lines.f src/spf.f
```

Windows 版使用 `jpf375c.exe`（或 `wine jpf375c.exe`）作為宿主編譯器；若 `HOSTFORTH` 未指定，Makefile 也會自動把 `../jpf375c.exe` 納入先決條件。建構時先載入 `tc-configure-lines.f` 處理換行模式。最終產生 PE 格式的 `spf4.exe`，並在 Windows 路徑中透過 `DONE` 間接 `INCLUDED src/done.f`，再由其中的 `tsave.f` 完成 PE 儲存。

### 1.4 POSIX 組態產生（posix/Makefile + config.c）

**posix/Makefile**（29 行）：

```makefile
config.auto.f: config.gen
		$(HOSTWRAPPER) ./$< > $@

config.gen: config.c
		$(CC) -m32 -Wall -Werror -DSPF_SRC $< -o$@ -m32
```

先編譯 `config.c` 產生 `config.gen`，然後執行 `config.gen` 輸出 `config.auto.f`。

**posix/config.c**（146 行）負責偵測系統常數：

```c
int main() {
  if (!test()) return 1;  // 前置條件驗證
  print_header();

  // ucontext_t 暫存器偏移
  CONST(CONTEXT_EDI, offsetof(ucontext_t,uc_mcontext.gregs) + REG_EDI*sizeof(greg_t))
  CONST(CONTEXT_EIP, ...)
  CONST(CONTEXT_ESP, ...)
  CONST(CONTEXT_EAX, ...)
  CONST(CONTEXT_EBP, ...)

  // 信號常數
  DEFINE(SA_RESTART)  DEFINE(SA_SIGINFO)  DEFINE(SA_NODEFER)
  DEFINE(SIGILL)  DEFINE(SIGSEGV)  DEFINE(SIGBUS)  DEFINE(SIGFPE)  DEFINE(SIGINT)
  CONST(SIGINFO_CODE, offsetof(siginfo_t,si_code))
  DEFINE(FPE_INTDIV)  DEFINE(FPE_INTOVF)  // ... 浮點例外代碼

  // 檔案系統常數
  CONST(STAT_ST_MODE, offsetof(struct stat,st_mode))
  DEFINE(S_IFREG)  DEFINE(S_IFMT)  DEFINE(S_IFDIR)
  CONST(STAT64_ST_SIZE, offsetof(struct stat64,st_size))

  // 檔案 I/O 常數
  DEFINE(O_CREAT)  DEFINE(O_TRUNC)  DEFINE(O_RDONLY)  // ...

  // 動態連結常數
  DEFINE(RTLD_GLOBAL)  DEFINE(RTDL_LAZY)

  // 記憶體映射常數
  DEFINE(PAGESIZE)
  DEFINE(PROT_READ)  DEFINE(PROT_WRITE)  DEFINE(PROT_EXEC)
  DEFINE(MAP_SHARED)
  CONST(MAP_FAILED, (long)MAP_FAILED)
}
```

**前置條件驗證**（`test()` 函數，見 §1.4）：

```c
int test() {
  ENSURE(sizeof(int) == CELL)              // int 必須是 4 位元組
  ENSURE(sizeof(void*) == CELL)             // 指標必須是 4 位元組
  ENSURE(offsetof(struct sigaction,sa_sigaction) == 0)
  ENSURE(offsetof(struct sigaction,sa_mask) == CELL)
  ENSURE(offsetof(struct sigaction,sa_flags) == sizeof(sigset_t) + CELL)
  ENSURE(offsetof(struct sigaction,sa_restorer) - offsetof(struct sigaction,sa_flags) == CELL)
  ENSURE(sizeof(struct sigaction) == 3*CELL + sizeof(sigset_t))
  ENSURE(sizeof(mode_t) == CELL)
  ENSURE(PAGESIZE != -1)
  return 1;
}
```

這些 `ENSURE` 斷言驗證 SP-Forth 對 C 結構體佈局的假設是否正確。若任何斷言失敗，程式回傳 1，建構中止。

### 1.5 config.auto.f 輸出格式

產生的 `config.auto.f` 格式範例：

```forth
\ Linux 6.8.0-64-generic  GNU libc 2.39 stable
\ Generated on Sat Apr 25 03:31:20 2026 UTC

\ REG_EDI = 4
: CONTEXT_EDI 0x24 STATE @ IF LIT, THEN ; IMMEDIATE
\ REG_EIP = 14
: CONTEXT_EIP 0x4C STATE @ IF LIT, THEN ; IMMEDIATE
```

每個常數定義為一個 `IMMEDIATE` 字，根據 `STATE` 決定行為：
- `STATE @` 為 TRUE（編譯狀態）：執行 `LIT,` 將常數編入資料流
- `STATE @` 為 FALSE（直譯狀態）：將常數留在堆疊上

這種模式確保同一常數在編譯期和直譯期都能正確使用，因為在交叉編譯（TC）環境中，`LITERAL` 的行為需要判斷當前狀態。

---

## 2. 編譯選項（spf_compileoptions.f）

### 2.1 選項說明

```forth
FALSE VALUE CREATE-XML-HELP    \ 是否產生 XML 說明檔
TRUE  VALUE ARCH-P6            \ 使用 P6 指令集（CMOV 等）
TRUE  VALUE BUILD-OPTIMIZER    \ 建構時包含最佳化器
TRUE  VALUE USE-OPTIMIZER      \ 建構時使用最佳化
FALSE VALUE OPTIMIZE-BY-SIZE   \ 以大小最佳化（否則以速度最佳化）
FALSE VALUE WIDE-CHAR          \ 使用 2 位元組字元
FALSE VALUE SMALLEST-SPF       \ 最小版本
FALSE VALUE UNIX-ENVIRONMENT   \ 目標系統使用 Unix 換行
FALSE VALUE TARGET-POSIX       \ 目標平台為 POSIX
```

| 選項 | 預設值 | 說明 |
|------|--------|------|
| `CREATE-XML-HELP` | FALSE | 若 TRUE，產生 `spfhelp.xml` 字詞說明檔 |
| `ARCH-P6` | TRUE | 使用 P6（Pentium Pro+）指令集（如 CMOV） |
| `BUILD-OPTIMIZER` | TRUE | 建構時將最佳化器編入映像 |
| `USE-OPTIMIZER` | TRUE | 建構過程中使用最佳化器產生更好的程式碼 |
| `OPTIMIZE-BY-SIZE` | FALSE | TRUE = 大小最佳化（1 位元組對齊）；FALSE = 速度最佳化（4 位元組對齊） |
| `WIDE-CHAR` | FALSE | TRUE = 字元寬度 2 位元組 |
| `SMALLEST-SPF` | FALSE | TRUE = 關閉最佳化器建構 |
| `UNIX-ENVIRONMENT` | FALSE | TRUE = 目標使用 LF 換行 |
| `TARGET-POSIX` | FALSE | TRUE = 目標平台為 POSIX |

### 2.2 自動偵測邏輯

```forth
LTL @ 1 =  LT C@ 0xA =  AND [IF]
SOURCE + 1- C@ 0xD <> [IF]
  TRUE TO UNIX-ENVIRONMENT
[THEN] [THEN]

[DEFINED] PLATFORM [IF]
PLATFORM S" Linux" COMPARE 0= [IF]
  TRUE TO UNIX-ENVIRONMENT
  TRUE TO TARGET-POSIX
[THEN] [THEN]
```

兩層偵測：
1. **宿主環境偵測**：若宿主使用 Unix 換行（`LTL = 1` 且 `LT = 0x0A`），且原始碼也使用 LF（`0x0D <>`），則設定 `UNIX-ENVIRONMENT = TRUE`
2. **目標平台偵測**：若 `PLATFORM` 字詞回傳 `"Linux"`，則同時設定 `UNIX-ENVIRONMENT` 和 `TARGET-POSIX` 為 TRUE

### 2.3 compile.ini 覆寫

```forth
S" src/compile.ini" ' INCLUDED CATCH
 DUP 2 = [IF] CR .( No src/compile.ini - using defaults) DROP 2DROP [ELSE] THROW [THEN]
```

嘗試載入 `src/compile.ini`，若檔案不存在（例外碼 2），顯示提示並使用預設值。使用者可在 `compile.ini` 中覆寫任何選項，例如：

```forth
TRUE TO SMALLEST-SPF
```

### 2.4 SMALLEST-SPF 效果

```forth
SMALLEST-SPF [IF]
FALSE TO BUILD-OPTIMIZER      \ 不包含最佳化器
TRUE TO USE-OPTIMIZER         \ 使用宿主最佳化器
TRUE TO OPTIMIZE-BY-SIZE       \ 以大小最佳化
[THEN]
```

SMALLEST-SPF 模式：
- 不將最佳化器編入映像（節省空間）
- 仍使用宿主的最佳化器來編譯核心字詞
- 使用 1 位元組對齊（最小空間）

### 2.5 ALIGN-BYTES-CONSTANT

```forth
OPTIMIZE-BY-SIZE [IF]
1 CONSTANT ALIGN-BYTES-CONSTANT   \ 1 位元組對齊（節省空間）
[ELSE]
4 CONSTANT ALIGN-BYTES-CONSTANT   \ 4 位元組對齊（速度最佳化）
[THEN]
```

### 2.6 選項顯示

```forth
: O: NextWord DUP 20 SWAP - SPACES 2DUP TYPE ."  : " EVALUATE IF ." TRUE" ELSE ." FALSE" THEN CR ;

CR .( Build options : ) CR
O: CREATE-XML-HELP
O: ARCH-P6
O: BUILD-OPTIMIZER
O: USE-OPTIMIZER
O: OPTIMIZE-BY-SIZE
O: WIDE-CHAR
O: UNIX-ENVIRONMENT
O: TARGET-POSIX
CR
```

建構時顯示所有選項的當前值，格式如：

```
Build options :
CREATE-XML-HELP     : FALSE
ARCH-P6             : TRUE
BUILD-OPTIMIZER     : TRUE
USE-OPTIMIZER       : TRUE
OPTIMIZE-BY-SIZE    : FALSE
WIDE-CHAR           : FALSE
UNIX-ENVIRONMENT    : TRUE
TARGET-POSIX        : TRUE
```

---

## 3. 主控腳本（spf.f）

### 3.1 載入順序

`spf.f` 是 SP-Forth 的主控腳本。下表保留「主題分組」的可讀性，但順序已對齊實際原始碼：**先定義 `IMAGE-SIZE` / `IMAGE-START`，再載入 POSIX 的 `config.auto.f`（若適用），接著 `INCLUDED src/tc_spf.F`，最後才記錄 `.forth` 基底位址。**

```
spf.f
├── 版本號：
│   └── 429 CONSTANT SPF-KERNEL-VERSION
├── 相容性層：
│   └── UMIN, UMAX, CS-DUP, PARSE-NAME, LATEST-NAME, SYNONYM, CHAIN-WORDLIST 等
├── 組語套件：lib/ext/spf-asm.f
├── 編譯選項：src/spf_compileoptions.f
├── 記憶體映像設定：
│   └── 512 1024 * TO IMAGE-SIZE；0x8050000 CONSTANT IMAGE-START
├── 組態常數：src/posix/config.auto.f（僅 POSIX）
├── 日期：src/spf_date.f
├── XML 說明：src/spf_xmlhelp.f
├── 交叉編譯器：src/tc_spf.F
├── 影像基底記錄：
│   └── HERE TO .forth（POSIX）或 HERE TC-CALL,（Windows）
├── 核心原語：
│   ├── src/spf_defkern.f（定義字機器碼原語）
│   ├── src/spf_forthproc.f（高層 Forth 字）
│   ├── src/spf_floatkern.f（浮點核心）
│   └── src/spf_forthproc_hl.f（高層輔助字）
├── 平台 API：
│   ├── POSIX: src/posix/api.f, src/posix/dl.f, src/posix/const.f
│   └── Windows: src/win/spf_win_api.f, spf_win_proc.f, spf_win_const.f
├── 記憶體管理：
│   ├── POSIX: src/posix/memory.f
│   └── Windows: src/win/spf_win_memory.f
├── 例外處理：src/spf_except.f + posix/except.f 或 win/spf_win_except.f
├── 檔案 I/O：
│   ├── POSIX: src/posix/io.f
│   └── Windows: src/win/spf_win_io.f, spf_win_conv.f
├── 控制台 I/O：src/spf_con_io.f
├── 數值輸出：src/spf_print.f
├── 模組管理：src/spf_module.f
├── 編譯器：
│   ├── src/compiler/spf_parser.f
│   ├── src/compiler/spf_read_source.f
│   ├── src/compiler/spf_nonopt.f
│   ├── src/compiler/spf_compile0.f
│   ├── src/macroopt.f 或 src/noopt.f（取決於 BUILD-OPTIMIZER）
│   ├── src/compiler/spf_compile.f
│   ├── src/compiler/spf_wordlist.f
│   ├── src/compiler/spf_find.f
│   └── src/compiler/spf_words.f
├── 錯誤處理：src/compiler/spf_error.f
├── 直譯器：src/compiler/spf_translate.f
├── 定義字：src/compiler/spf_defwords.f
├── 即時字：
│   ├── src/compiler/spf_immed_transl.f
│   ├── src/compiler/spf_immed_lit.f
│   ├── src/compiler/spf_literal.f
│   ├── src/compiler/spf_immed_control.f
│   ├── src/compiler/spf_immed_loop.f
│   ├── src/compiler/spf_modules.f
│   └── src/compiler/spf_inline.f
├── 環境/外部函式：
│   ├── POSIX: src/posix/envir.f, src/posix/defwords.f, src/posix/mtask.f, src/win/spf_win_cgi.f
│   └── Windows: src/win/spf_win_envir.f, spf_win_defwords.f, spf_win_mtask.f,
│                spf_win_cgi.f, **spf_pe_save.f**（並定義 DONE 字以包裝 src/done.f）
├── 系統初始化：src/spf_init.f
├── 映像儲存：
│   ├── POSIX: src/posix/save.f → 之後在最終化階段再 INCLUDED src/xsave.f
│   └── Windows: 由前一段已 INCLUDED 的 spf_pe_save.f 提供 PE 寫出；src/tsave.f
│                在 src/done.f 內被 INCLUDED（透過 Windows 最終化的 EXECUTE → DONE 觸發）
├── 向量修復和最終化（spf.f:343–395）
└── XSAVE（POSIX，spf.f:369+390）或 EXECUTE → DONE → done.f / tsave.f（Windows，spf.f:380+395）
```

### 3.2 關鍵位址設定

```forth
HERE  DUP HEX .( Base address of the image 0x) U.
TARGET-POSIX [IF]
TO .forth           \ POSIX：記錄 Forth 字典起始位址
[ELSE]
HERE TC-CALL,       \ Windows：記錄為 TC-CALL 位址
[THEN]
```

`.forth` 是 Forth 字典段的起始位址，用於 ELF 符號表和重定位計算。

### 3.3 最終化步驟

```forth
TC-LATEST-> FORTH-WORDLIST     \ 修復最新字詞連結
HERE          ' (DP)      TC-ADDR!  \ 修復字典指標
_VOC-LIST @   ' _VOC-LIST TC-ADDR!  \ 修復字詞集列表連結

TARGET-POSIX [IF]
' NON-OPT-WL EXECUTE      ' NON-OPT-WL      TC-VECT!  \ 修復非最佳化字詞集
' FORTH-WORDLIST EXECUTE  ' FORTH-WORDLIST  TC-VECT!  \ 修復 FORTH 字詞集
[T] [DEFINED] MACROOPT-WL [I] [IF]
' MACROOPT-WL    EXECUTE  ' MACROOPT-WL     TC-VECT!  \ 修復最佳化字詞集
[THEN]

HERE .forth - TO .forth#       \ 計算字典段大小
ONLY DEFINITIONS
S" src/xsave.f" INCLUDED       \ 載入 XSAVE
S" src/spf4.o" XSAVE           \ 儲存 ELF 物件檔
[ELSE]
\ Windows 最終化（spf.f:371–395）
TC-WINAPLINK @ ' WINAPLINK TC-ADDR!     \ 修復 WINAPLINK 鏈
S"  DONE " GetCommandLineA ASCIIZ>      \ 取得目前命令列
S"  " SEARCH 2DROP SWAP 1+ MOVE         \ 把命令列中的 "DONE" token 蓋成空格
\ 上一步的用意：宿主 jpf375c.exe 啟動時看到 "DONE" 會 EXECUTE 它；
\ 把它在原地覆寫成空格後，下面才能用 EXECUTE 把控制權交給剛建好的
\ 目標 INIT，並由 done.f 內的 tsave.f 流程完成 PE 儲存。
EXECUTE                                  \ 跳進剛建好的 INIT
[THEN]
```

對應 `src/spf.f:343–395`。`xsave.f` 與 `S" src/spf4.o" XSAVE` 屬於 POSIX 路徑；Windows 路徑不走 `XSAVE`，而是讓 `done.f` / `tsave.f` 在 `EXECUTE` 後接管 PE 寫出流程。

---

## 4. 建構日期（spf_date.f）

```forth
S" lib/include/facil.f" INCLUDED

: MONTH, PARSE-NAME CHARS HERE OVER ALLOT SWAP CMOVE ;

CREATE MONTHS
MONTH, Jan  MONTH, Feb  MONTH, Mar  MONTH, Apr
MONTH, May  MONTH, Jun  MONTH, Jul  MONTH, Aug
MONTH, Sep  MONTH, Oct  MONTH, Nov  MONTH, Dec

: MONTH ( n -- addr u ) 1- 3 * MONTHS + 3 ;

: DATE ( day mt year -- addr u )
   0 <# # # # # 2DROP [CHAR] . HOLD MONTH DROP 2+ DUP C@ HOLD 1- DUP C@ HOLD 1- C@ HOLD 0
       [CHAR] . HOLD # # 2DROP 0 0 #>
;

: NOWADAYS ( -- addr u )
   TIME&DATE 2>R >R 2DROP DROP R> 2R> DATE
;
```

`DATE` 使用 `<# #S HOLD #>` 反向格式化日期：
1. `# # # #` → 年份（4 位數）
2. `[CHAR] . HOLD` → 點號分隔
3. `MONTH DROP 2+ DUP C@ HOLD 1- DUP C@ HOLD 1- C@ HOLD` → 月份三字元縮寫（逆向插入）
4. `[CHAR] . HOLD` → 點號分隔
5. `# #` → 日期（2 位數）

結果格式如 `"25.Apr.2026"`。

注意 `BUILD-DATE` 本身**不在** `spf_date.f`：`spf_date.f` 只提供 `NOWADAYS`（傳回目前日期字串）。具名的 `BUILD-DATE` 是在 `src/compiler/spf_wordlist.f:71–72` 用 `NOWADAYS` 的結果建立的計數字串：

```forth
\ src/compiler/spf_wordlist.f:71
CREATE BUILD-DATE
NOWADAYS ,"
```

之後由 `src/spf_init.f:149` 在啟動標題中印出：`."  at " BUILD-DATE COUNT TYPE CR CR`。

---

## 5. XML 說明產生器（spf_xmlhelp.f）

### 5.1 概述

當 `CREATE-XML-HELP` 為 TRUE 時，系統在編譯過程中攔截每個字詞的定義，記錄其名稱、堆疊效果、所屬詞彙表、原始碼位置，並在最終階段產生 `spfhelp.xml` 檔案。

### 5.2 攔截機制

```forth
: StartColonHelp ( flag.is-primitive -- )
  HERE TC-IMAGE-BASE < IF DROP EXIT THEN   \ 跳過目標編譯器的字詞
  EndModuleComment
  generateHelp? 0= IF DROP EXIT THEN       \ 跳過未啟用 XML 說明的情況
  >IN @ >R
  S" colon" OPEN-TAG
  PARSE-NAME S" name" ATTRIBUTE-OUT        \ 字詞名稱
  \ 取得所屬詞彙表名稱（spf_xmlhelp.f:250-258）：
  GET-CURRENT DUP FORTH-WORDLIST =         \   若是 FORTH-WORDLIST →
  IF DROP S" FORTH"                        \     直接用 "FORTH"
  ELSE CELL+ @ DUP IF COUNT                \   否則讀詞彙表名稱欄位
       ELSE DROP S" UNKNOWN" THEN          \     名稱為 0 → "UNKNOWN"
  THEN
  2DUP S" TC-TRG" COMPARE 0=               \   目標編譯器詞彙表 TC-TRG →
  IF 2DROP S" FORTH" THEN                  \     對外仍顯示為 "FORTH"
  S" vocabulary" ATTRIBUTE-OUT             \ 輸出 vocabulary 屬性
  IF S" true" S" primitive" ATTRIBUTE-OUT THEN  \ 是否為原語
  BASE @ HEX HERE S>D <# #S #> S" id" ATTRIBUTE-OUT  \ 字詞位址（十六進位）
  BASE @ DECIMAL SOURCE-FILE-LN S>D <# #S #> S" line" ATTRIBUTE-OUT  \ 行號
  PARSE-NAME S" (" COMPARE 0= IF           \ 解析堆疊效果
     S"  params=" (HELP-OUT) "h
     [CHAR] ) PARSE HandleSpecialChars HELP-OUT() "h
  THEN
  CLOSE-TAG
  StartComment
  R> >IN !
;
```

### 5.3 XML 輸出格式

產生的 XML 格式：

```xml
<?xml version="1.0" encoding="windows-1251"?>
<forthsourcecode>
 <module name="spf_print.f">
  <colon name="HOLD" vocabulary="FORTH" id="0x8051234" line="35" primitive="true">
   <comment>Insert a character into the pictured numeric output string</comment>
  </colon>
  <colon name="D." vocabulary="FORTH" id="0x8051300" line="94" params="( d -- )">
   <comment>Display d</comment>
  </colon>
 </module>
</forthsourcecode>
```

### 5.4 特殊字元處理

```forth
CHAIN SPECIAL-CHARS

SPECIAL & &amp;
SPECIAL ' &apos;
SPECIAL " &quot;
SPECIAL < &lt;
SPECIAL > &gt;
```

XML 特殊字元（`&`、`'`、`"`、`<`、`>`）自動轉換為 XML 實體。

### 5.5 INCLUDE 和 REQUIRE 的攔截

XML 說明模式會重新定義 `INCLUDED` 和 `REQUIRE`：

```forth
: INCLUDED ( addr u )
    generateHelp? 0= IF INCLUDED EXIT THEN   \ 未啟用時使用原始 INCLUDED
    EndModuleComment
    S" module" OPEN-TAG 2DUP S" name" ATTRIBUTE-OUT CLOSE-TAG
    StartModuleComment +indent
    INCLUDED
    EndModuleComment -indent
    S" </module>" HELP-OUT crh
;
```

每次 `INCLUDED` 會在 XML 中產生 `<module name="...">` 標籤，記錄模組的巢狀結構。

---

## 6. ELF 映像格式（elf.f）

### 6.1 ELF 段表（Section Table）結構

`elf.f` 定義了 ELF 可重定位物件檔的完整結構，包含 9 個**節區**（Section）：

| 節區號 | 名稱 | 類型 | 旗標 | 說明 |
|--------|------|------|------|------|
| 0 | （無） | SHT_NULL | 0 | 保留的零節區 |
| 1 | `.shstrtab` | SHT_STRTAB | 0 | 節區名稱字串表 |
| 2 | `.strtab` | SHT_STRTAB | 0 | 符號名稱字串表 |
| 3 | `.symtab` | SHT_SYMTAB | 0 | 符號表 |
| 4 | `.rel.forth` | SHT_REL | 0 | 重定位表 |
| 5 | `.forth` | SHT_PROGBITS | SHF_WRITE+SHF_ALLOC+SHF_EXECINSTR (0x7) | Forth 程式碼節區 |
| 6 | `.space` | SHT_NOBITS | SHF_WRITE+SHF_ALLOC+SHF_EXECINSTR (0x7) | 字典空間節區（BSS） |
| 7 | `.dltable` | SHT_PROGBITS | SHF_WRITE+SHF_ALLOC (0x3) | 動態連結表節區 |
| 8 | `.dlstrings` | SHT_STRTAB | SHF_ALLOC (0x2) | 動態連結字串節區 |

#### 6.1.1 Section（節區）vs Segment（段）的區別

ELF 檔案有兩種檢視方式，使用不同的組織單位：

**連結檢視（Linking View）— 使用節區（Section）**：
- **Section（節區）**：連結器使用的基本單位，用於符號解析和重定位
- 透過**節區標頭表**（Section Header Table）描述
- SP-Forth 產生的 `.o` 檔案主要包含節區資訊

**執行檢視（Execution View）— 使用段（Segment）**：
- **Segment（段）**：作業系統載入器使用的基本單位，用於建立程序記憶體映射
- 透過**程式標頭表**（Program Header Table）描述
- 最終可執行檔（由 `gcc` 連結產生）主要包含段資訊

**SP-Forth 的特殊設計**：
```
SP-Forth 產生的 spf4.o（可重定位物件檔）
    ├── 包含：節區標頭表（Section Header Table）
    ├── 包含：.forth、.space、.dltable 等節區
    └── 不含：程式標頭表（Program Header Table = 0）
            
gcc 連結後產生的 spf4（可執行檔）
    ├── 包含：程式標頭表（Program Header Table）
    ├── 包含：LOAD 段（將 .forth、.space 節區合併載入）
    └── 節區標頭表可選（通常保留供偵錯使用）
```

**關於連結器腳本的對應**：§7.2 的 `forth.ld` 只映射了 `.forth` 和 `.space` 兩個節區，這是因為其餘節區（`.shstrtab`、`.strtab`、`.symtab`、`.rel.forth`、`.dltable`、`.dlstrings`）是連結器在中間物件檔階段消費的中繼資料——節區名稱字串表、符號表、重定位表在連結後會被合併或丟棄，不會出現在最終可執行檔的記憶體視圖中。`.dltable` 和 `.dlstrings` 則由啟動時的 `dl-init` 從 Forth 字典內的資料結構重建，不需要連結器腳本映射。

### 6.2 ELF 標頭

```forth
CREATE elf-header
0x7F C, CHAR E C, CHAR L C, CHAR F C,   \ 魔術識別碼：0x7F 'E' 'L' 'F'
1 C,          \ ELFCLASS32（32 位元）
1 C,          \ ELFDATA2LSB（小端序）
1 C,          \ EV_CURRENT（版本 1）
9 ALLOT       \ 填充（ELF 識別碼共 16 位元組）
1 W,          \ ET_REL（可重定位檔案）
3 W,          \ EM_386（Intel 80386）
1 ,           \ EV_CURRENT（物件檔案版本）
0 ,           \ 進入點位址（ET_REL 為 0）
\ 程式標頭偏移（ET_REL 為 0）
0 ,
\ 段標頭偏移 = elf-header-size + 9 * elf-section-size
' elf-header-size  EXECUTE ,   \ （在 posix/save.f 中計算）
0 ,     \ 旗標
' elf-header-size EXECUTE W,   \ e_ehsize：ELF 標頭大小（0x34）
' section-size   W,            \ e_shentsize：節區標頭項大小（0x28；xsave.f 中亦為 0x28 = section-size。
                               \ 注意 0x20 是 e_phentsize / segment-size，屬不同欄位，勿混淆）
sections#       W,             \ 段數量
1                W,             \ 段名稱字串表段索引
```

#### 6.2.1 ELF 識別碼（e_ident）詳解

ELF 標頭前 16 位元組為 `e_ident` 陣列，用於檔案類型識別和基本屬性標示：

| 偏移 | 名稱 | 值 | 說明 |
|------|------|-----|------|
| 0 | EI_MAG0 | 0x7F | **魔術位元組** |
| 1 | EI_MAG1 | 'E' (0x45) | ELF 識別字元 |
| 2 | EI_MAG2 | 'L' (0x4C) | ELF 識別字元 |
| 3 | EI_MAG3 | 'F' (0x46) | ELF 識別字元 |
| 4 | EI_CLASS | 1 | 檔案類別：ELFCLASS32（32 位元）|
| 5 | EI_DATA | 1 | 資料編碼：ELFDATA2LSB（小端序）|
| 6 | EI_VERSION | 1 | 版本：EV_CURRENT（目前版本）|
| 7 | EI_OSABI | 0 | OS/ABI 識別：ELFOSABI_SYSV（System V）|
| 8-15 | EI_PAD | 0 | 填充（保留供將來使用）|

**為何魔術位元組是 0x7F？**

1. **歷史傳承**：繼承自 Unix a.out 格式的魔術數字設計
2. **可視性**：在十六進位編輯器中，位元組序列 `7F 45 4C 46` 顯示為 `ELF`（第一個字元是不可視的控制字元）
3. **避免混淆**：
   - 純文字檔案通常以可視 ASCII 字元開頭
   - 其他二進位格式（如 DOS MZ 檔案）以 `4D 5A`（"MZ"）開頭
   - 腳本檔案以 shebang（`#!`，0x23 0x21）開頭

**檔案類型識別對照**：

| 檔案類型 | 魔術位元組 | 說明 |
|----------|------------|------|
| ELF | `7F 45 4C 46` | Unix/Linux 可執行檔 |
| DOS/PE | `4D 5A` ("MZ") | Windows/DOS 可執行檔 |
| Shell Script | `23 21` ("#!") | Unix 腳本（如 `#!/bin/sh`）|
| PDF | `25 50 44 46` ("%PDF") | PDF 文件 |
| PNG | `89 50 4E 47` | PNG 圖片 |

**SP-Forth 產生的 ELF 檔案識別**：

```bash
$ xxd spf4.o | head -1
00000000: 7f45 4c46 0101 0100 0000 0000 0000 0000  .ELF...........
#       │└┬┘└┬┘ └┬┘ └┬┘
#        │  │   │    └── 作業系統/ABI（System V）
#        │  │   └── 版本（目前版本）
#        │  └── 資料編碼（小端序）
#        └── 檔案類別（32 位元）
```

### 6.3 節區名稱字串表

```forth
CREATE .shstrtab
0 C,                          \ 空位元組（索引 0 = 空名稱）
ASCIIZ" .shstrtab"            \ 索引 1
ASCIIZ" .strtab"              \ 索引 11
ASCIIZ" .symtab"              \ 索引 19
ASCIIZ" .rel.forth"           \ 索引 27
ASCIIZ" .space"               \ 索引 38
ASCIIZ" .dltable"             \ 索引 45
ASCIIZ" .dlstrings"           \ 索引 54
```

每個段的 `sh_name` 欄位是在此字串表中的偏移。

### 6.4 符號表

符號表包含 12 個項目（索引 0 至 11，對應 `src/elf.f:51–149`）。ELF 規格要求 `.symtab` 的第 0 個項目必須是全 0 的「未定義符號」（`STN_UNDEF`），因此即使內容全 0 也計入總數：

| 索引 | 名稱 | 值 | 大小 | 資訊 | 其他 | 段 |
|------|------|-----|------|------|------|-----|
| 0 | （空） | 0 | 0 | 0 | 0 | 0 |
| 1 | （.forth） | 0 | 0 | STT_SECTION (3) | 0 | 5 |
| 2 | （.space） | 0 | 0 | STT_SECTION (3) | 0 | 6 |
| 3 | （.dltable） | 0 | 0 | STT_SECTION (3) | 0 | 7 |
| 4 | （.dlstrings） | 0 | 0 | STT_SECTION (3) | 0 | 8 |
| 5 | `main` | INIT-.forth | 30 | STB_GLOBAL+STT_FUNC (18) | 0 | 5 |
| 6 | `dlopen` | 0 | 0 | STB_GLOBAL+STT_FUNC (16) | 0 | 0（UND） |
| 7 | `dlsym` | 0 | 0 | STB_GLOBAL+STT_FUNC (16) | 0 | 0 |
| 8 | `realloc` | 0 | 0 | STB_GLOBAL+STT_FUNC (16) | 0 | 0 |
| 9 | `write` | 0 | 0 | STB_GLOBAL+STT_FUNC (16) | 0 | 0 |
| 10 | `calloc` | 0 | 0 | STB_GLOBAL+STT_FUNC (16) | 0 | 0 |
| 11 | `dlerror` | 0 | 0 | STB_GLOBAL+STT_FUNC (16) | 0 | 0 |

符號 #5（`main`）是全域定義符號，指向 `INIT` 的位址（Forth 程式的入口點），大小為 30 位元組。

符號 #6-#11 是全域未定義符號（段索引 0 = SHN_UNDEF），需要由連結器從 libc/libdl 解析。

### 6.5 重定位表

`.rel.forth` 包含 8 個重定位項目，類型均為 `R_386_32`（絕對重定位）：

| 偏移 | 符號索引 | 說明 |
|------|---------|------|
| `dl-first + 5` | 3（.dltable） | dl-first 預載入表的偏移修補 |
| `dl-first-strtab + 5` | 4（.dlstrings） | dl-first 字串表偏移修補 |
| `dlopen-adr >BODY` | 6（dlopen） | dlopen 函數指標修補 |
| `dlsym-adr EXECUTE` | 7（dlsym） | dlsym 函數指標修補 |
| `realloc-adr EXECUTE` | 8（realloc） | realloc 函數指標修補 |
| `write-adr EXECUTE` | 9（write） | write 函數指標修補 |
| `calloc-adr EXECUTE` | 10（calloc） | calloc 函數指標修補 |
| `dlerror-adr EXECUTE` | 11（dlerror） | dlerror 函數指標修補 |

重定位項格式（每項 8 位元組）：

```
偏移（4 位元組） | 資訊（4 位元組）
資訊 = (符號索引 << 8) | 類型
類型 = 1 (R_386_32)
```

例如：`dlopen` 重定位項 = `dlopen-adr偏移 | (6 << 8) | 1`

### 6.6 offset,size, 巨集

```forth
: offset,size, ( n -- ) offset , DUP , +offset ;
```

這是 ELF 段標頭中 `sh_offset` 和 `sh_size` 欄位的雙重設定：
1. 將當前 `offset` 寫入 `sh_offset`
2. 將段大小 `n` 寫入 `sh_size`
3. 將 `offset + n` 設為新的 `offset`

此巨集確保所有段的偏移量連續遞增，不重疊。

### 6.7 ELF 程式標頭（Program Header）說明

> **與節區標頭表的區別**：程式標頭表（Program Header Table）用於**執行檢視**，描述作業系統載入器如何建立程序記憶體映射。這與用於**連結檢視**的節區標頭表（Section Header Table）不同。SP-Forth 產生的 `.o` 檔案**不包含**程式標頭表（e_phnum = 0），最終可執行檔的程式標頭表由 `gcc` 連結器產生。

**程式標頭項目結構（Elf32_Phdr）**：

每個項目 32 bytes，描述一個記憶體段（Segment）：

| 偏移 | 欄位 | 說明 |
|------|------|------|
| 0 | p_type | 段類型（LOAD、DYNAMIC、INTERP 等）|
| 4 | p_offset | 檔案偏移 |
| 8 | p_vaddr | 虛擬位址 |
| 12 | p_paddr | 物理位址（通常未使用）|
| 16 | p_filesz | 檔案大小 |
| 20 | p_memsz | 記憶體大小（≥ filesz，多出部分為 BSS）|
| 24 | p_flags | 旗標（R/W/X）|
| 28 | p_align | 對齊（通常為 0x1000 = 4 KiB）|

**常見段類型（p_type）**：

| 值 | 名稱 | 說明 |
|----|------|------|
| 0 | PT_NULL | 未使用項目 |
| 1 | **PT_LOAD** | **可載入段（最常見）** |
| 2 | PT_DYNAMIC | 動態連結資訊 |
| 3 | PT_INTERP | 解釋器路徑（如 `/lib/ld-linux.so.2`）|
| 4 | PT_NOTE | 輔助資訊 |

**SP-Forth 可執行檔的典型程式標頭**：

`gcc` 連結 `spf4.o` 後產生的可執行檔通常包含 2-3 個 PT_LOAD 段：

```
程式標頭 0：PT_LOAD
  虛擬位址：0x08048000（通常，由連結器決定）
  檔案偏移：0x00000
  大小：ELF 標頭 + 程式標頭表 + 節區資料
  權限：R-X（唯讀、可執行）
  內容：.text（程式碼）、.rodata（唯讀資料）

程式標頭 1：PT_LOAD
  虛擬位址：0x0804X000
  檔案偏移：0xXX000
  大小：.data（初始化資料）+ .bss（未初始化資料）
  權限：RW-（可讀、可寫）
  內容：全域變數、動態配置記憶體
```

**為何 SP-Forth 不直接產生程式標頭表？**

1. **可重定位物件檔（.o）不需要**：`.o` 檔案用於連結，還未確定最終記憶體位址
2. **連結器優化**：`gcc` 會根據連結器腳本（`forth.ld`）和系統配置決定最佳記憶體佈局
3. **平台差異**：不同 Linux 版本可能有不同的載入偏好（如 ASLR 位址隨機化）
4. **SP-Forth 的設計選擇**：專注於產生正確的節區和重定位資訊，讓專業工具（`ld`）處理底層細節

**連結器腳本（forth.ld）與程式標頭的關係**：

雖然 SP-Forth 不直接產生程式標頭表，但 `forth.ld` 間接影響其內容：

```ld
SECTIONS
{
  .forth 0x8050000 :    /* 建議虛擬位址 = 0x8050000 */
  {
    spf4.o(.forth)      /* 將 .forth 節區映射到此段 */
  }
  .space _eforth :       /* 接續 .forth 之後 */
  {
    spf4.o(.space)
  }
}
```

`gcc` 讀取此腳本後，會產生對應的 PT_LOAD 程式標頭項目，確保：
- 程式碼載入到 `0x8050000` 附近
- `.forth` 和 `.space` 在記憶體中連續
- 權限標誌正確（程式碼可執行、資料可讀寫）

---

## 7. POSIX 映像儲存（posix/save.f + elf.f）

> 本章聚焦 SAVE 在建構流程中的角色（ELF 產生、gcc 連結、spf4e 擴充版）；關於 SAVE 的 POSIX 平台層實作細節（段表欄位、重定位項目格式），另見 [04-posix-platform.md §14](04-posix-platform.md#14-elf-映像儲存posixsavef-深入解析)。

### 7.1 SAVE 流程概覽

`SAVE` 字（`posix/save.f`）將 Forth 映像儲存為 ELF 可重定位物件檔，然後呼叫 gcc 連結為可執行檔。

完整流程：

```
SAVE "spf4"
  │
  ├── 1. 產生連結器腳本 "spf4.ld"
  │     └── forth.ld: .forth IMAGE-BASE : { spf4.o(.forth) }
  │                    .space _eforth : { spf4.o(.space) }
  │
  ├── 2. 產生 ELF 物件檔 "spf4.o"
  │     ├── 寫出 ELF 標頭（0x34 位元組）
  │     ├── 更新段標頭中的動態資訊
  │     │   ├── .forth 段大小 = HERE - FORTH-START
  │     │   ├── .space 段大小 = IMAGE-SIZE
  │     │   ├── .dltable 段大小 = dl-first# + dl-second# * dl-rec#
  │     │   └── .dlstrings 段大小 = dl-first-strtab + dl-second-strtab - CELL
  │     ├── 寫出段標頭表
  │     ├── 寫出 .shstrtab、.strtab、.symtab、.rel.forth
  │     ├── 保存/恢復動態連結位址
  │     │   ├── 保存：dlopen-adr, dlsym-adr, dlerror-adr, realloc-adr, calloc-adr, write-adr
  │     │   ├── 寫出 Forth 程式碼段（透過 write C-CALL）
  │     │   └── 恢復：將 C 函數指標寫回
  │     ├── 寫出 dl-first 和 dl-second 動態連結表
  │     └── 寫出 dlstrings 字串表
  │
  └── 3. 呼叫 gcc 連結
        └── gcc spf4.o -Wl,forth.ld -ldl -lpthread -m32 -o spf4
```

### 7.2 forth.ld — 連結器腳本

```forth
: (forth.ld) ( a u -- )
  ." SECTIONS" CR
  ." {" CR
  ." .forth 0x" BASE @ >R HEX IMAGE-BASE . R> BASE ! ." :" CR
  ." {" CR
  2DUP TYPE ." .o(.forth)" CR
  ." _eforth = .;" CR
  ." }" CR
  ." .space _eforth :" CR
  ." {" CR
  TYPE ." .o(.space)" CR
  ." }" CR
  ." }" CR
;
```

產生的連結器腳本（範例）：

```
SECTIONS
{
.forth 0x8050000 :
{
spf4.o(.forth)
_eforth = .;
}
.space _eforth :
{
spf4.o(.space)
}
}
```

`.forth` 段從 `IMAGE-START`（0x8050000）開始，`.space` 段緊隨其後，提供字典擴展空間。`_eforth` 符號標記 Forth 字典的末尾。

### 7.3 SAVE 的 ELF 標頭更新

```forth
: SAVE ( c-addr u -- )
  2DUP forth.ld                    \ 產生連結器腳本
  2DUP <# S" .o" HOLDS HOLDS 0 0 #>
  R/W CREATE-FILE THROW >R
  elf-header elf-header-size R@ WRITE-FILE THROW  \ 寫出 ELF 標頭

  HERE FORTH-START - DUP                          \ 計算 .forth 段大小
  sections 5 elf-section-size * + 5 CELLS + !     \ 更新 .forth 段的 sh_size

  sections 5 elf-section-size * + 4 CELLS + @      \ 取得 .forth 段的 sh_addr
  + DUP sections 6 elf-section-size * + 4 CELLS + ! \ 更新 .space 段的 sh_addr

  IMAGE-SIZE sections 6 elf-section-size * + 5 CELLS + !  \ 更新 .space 段的 sh_size

  DUP sections 7 elf-section-size * + 4 CELLS + ! \ 更新 .dltable 段的 sh_addr
  dl-first# dl-second# + dl-rec# * DUP
  sections 7 elf-section-size * + 5 CELLS + !     \ 更新 .dltable 段的 sh_size
  +                                                \ 計算 .dlstrings 段偏移

  sections 8 elf-section-size * + 4 CELLS + !      \ 更新 .dlstrings 段的 sh_addr
  dl-first-strtab @ dl-second-strtab @ + CELL -
  sections 8 elf-section-size * + 5 CELLS + !       \ 更新 .dlstrings 段的 sh_size
```

### 7.4 動態連結位址的保存和恢復

```forth
  dl-first dl-first-strtab
  0 TO dl-first  0 TO dl-first-strtab   \ 暫時清零

  dl-first#  DUP dl-second# + TO dl-first#   \ 合併預載入表和延遲解析表

  \ 保存 C 函數指標
  dlopen-adr  @  dlsym-adr  @   dlerror-adr @
  realloc-adr @  calloc-adr @   write-adr @

  \ 清零 C 函數指標（使重定位項目初始值為 0）
  dlopen-adr  0!  dlsym-adr  0!  dlerror-adr 0!
  realloc-adr 0!  calloc-adr 0!  write-adr   0!
```

在寫出 Forth 程式碼段之前，所有 C 函數指標（`dlopen-adr` 等）被清零，使 ELF 重定位表中的項目初始值為 0。這樣 gcc 連結器會正確填入 C 函數的實際位址。

```forth
  \ 寫出 Forth 程式碼段（透過 write 系統呼叫）
  R@ FORTH-START HERE OVER - 3 4 PICK C-CALL DROP

  \ 恢復 C 函數指標
  write-adr   !  calloc-adr !  realloc-adr !
  dlerror-adr !  dlsym-adr  !  dlopen-adr  !
```

寫出程式碼段後，恢復所有 C 函數指標，使當前執行中的 Forth 系統繼續正常運作。

### 7.5 動態連結表的寫出

```forth
  TO dl-first#  TO dl-first-strtab  TO dl-first    \ 恢復 dl-first 表

  dl-first-strtab @ CELL- reloc-dl-second-strings  \ 修補字串偏移

  dl-first dl-first# dl-rec# * R@ WRITE-FILE THROW   \ 寫出預載入表
  dl-second dl-second# dl-rec# * R@ WRITE-FILE THROW  \ 寫出延遲解析表

  dl-first-strtab CELL+ dl-first-strtab @ CELL - R@ WRITE-FILE THROW  \ 寫出預載入字串
  dl-second-strtab CELL+ dl-second-strtab @ CELL - R@ WRITE-FILE THROW \ 寫出延遲解析字串
```

`reloc-dl-second-strings` 修補延遲解析表中的字串偏移：由於映像的基底位址在儲存後會改變，所有絕對位址都需要修補。

### 7.6 GCC 連結命令

```forth
  (( HERE
     S" gcc -v 2>&1 | grep -F --silent -- '--enable-default-pie' && gcc_nopie='-no-pie' ;" DROP
     S" %s gcc %s.o -Wl,%s.ld -ldl -lpthread -m32 $gcc_nopie -v -o %s" DROP
     SWAP
     R@ R@ R>
  )) sprintf DROP
  HERE system
```

1. 使用 `sprintf` 格式化 gcc 命令
2. 格式字串：`gcc spf4.o -Wl,spf4.ld -ldl -lpthread -m32 [-no-pie] -v -o spf4`
3. 偵測 GCC 的 PIE 支援：若有 `--enable-default-pie`，加上 `-no-pie`
4. 透過 `system()` 呼叫 gcc 連結

連結所需的函式庫：
- `-ldl`：動態連結（dlopen、dlsym、dlerror）
- `-lpthread`：多執行緒（pthread_create 等）

---

## 8. XSAVE — 交叉編譯 ELF 儲存（xsave.f）

> 關於 XSAVE 在交叉編譯流程中的角色（virt-offset 設定、重定位語意），另見 [03-cross-compiler.md §13](03-cross-compiler.md#13-elf-儲存xsavef)；本章聚焦於 ELF 格式的實體寫出流程。

### 8.1 概述

`xsave.f` 是 POSIX 版的映像儲存字，用於從 Windows 宿主編譯器交叉編譯產生 ELF 物件檔。它使用 `elf.f` 定義的 ELF 結構，但增加了額外的重定位步驟。

### 8.2 重定位

```forth
: ?VIRT! ( addr -- )
  DUP @ 0= IF DROP EXIT THEN >VIRT!
;

: reloc-wordlist-chain ( wl-last -- )
  BEGIN ?DUP WHILE
    DUP NAME>C >VIRT!              \ 修補名稱指標
    DUP NAME>NEXT-NAME SWAP         \ 鏈結到下一個字詞
    NAME>L ?VIRT!                   \ 修補連結指標
  REPEAT
;

: reloc-wordlist ( wid -- )
  DUP @ reloc-wordlist-chain        \ 修補字詞鏈結
  DUP       ?VIRT!                  \ 修補最新字詞指標
  DUP CELL+ ?VIRT!                  \ 修補字彙表名稱
  DUP 2 CELLS + ?VIRT!              \ 修補父字彙表
  DUP 3 CELLS + ?VIRT!              \ 修補類別
  DROP
;

: reloc-wordlists-all ( -- )
  ['] reloc-wordlist ENUM-VOCS
;

: reloc-voclist ( -- )
  VOC-LIST @
  BEGIN DUP WHILE
    DUP @ SWAP ?VIRT!               \ 修補 VOC-LIST 中的指標
  REPEAT DROP
;
```

`?VIRT!` 將絕對位址轉換為虛擬位址（`>VIRT!`），跳過值為 0 的指標。這是因為 ELF 可重定位物件檔中的所有指標都需要轉換為段內偏移，讓連結器在載入時再修補為絕對位址。

### 8.3 XSAVE 流程

```forth
: XSAVE ( c-addr u -- )
  R/W CREATE-FILE THROW TO h
  elf-header header-size >elf            \ 寫出 ELF 標頭

  reloc-sections-offsets                 \ 修補段偏移
  reloc-wordlists-all                    \ 修補所有字彙表鏈結
  reloc-voclist                          \ 修補 VOC-LIST

  sections total-sections-size >elf      \ 寫出段標頭
  segments total-segments-size >elf      \ 寫出程式標頭（POSIX 版為空）
  .shstrtab .shstrtab# >elf              \ 寫出段名稱字串表
  .strtab .strtab# >elf                  \ 寫出符號名稱字串表
  .symtab .symtab# >elf                  \ 寫出符號表
  .rel.forth .rel.forth# >elf           \ 寫出重定位表
  .forth .forth# >elf                    \ 寫出 Forth 程式碼段
  dl-second .dltable# >elf              \ 寫出動態連結表
  dl-second-strtab .dlstrings# >elf     \ 寫出動態連結字串

  h CLOSE-FILE THROW
  BYE
;
```

XSAVE 與 SAVE 的差異：

| 特性 | XSAVE | SAVE |
|------|-------|------|
| 呼叫方式 | `XSAVE`（直接呼叫） | `SAVE`（透過 gcc 連結） |
| 用途 | 交叉編譯 | 自舉編譯 |
| 重定位 | 使用 `>VIRT!` 轉換 | 使用 `write` C-CALL 寫出 |
| 連結 | 不呼叫 gcc | 呼叫 gcc 產生可執行檔 |
| 寫出方式 | `>elf` 輔助字 | 直接 `WRITE-FILE` |

---

## 9. PE 可執行檔格式詳解（Windows）

> 本節詳細說明 Windows PE（Portable Executable）格式結構，涵蓋 DOS 標頭、COFF 標頭、可選標頭、段表與匯入表。理解這些結構有助於掌握 SP-Forth Windows 版的映像儲存機制。

### 9.1 PE 檔案整體佈局

PE 檔案由多個結構組成，從低址到高址依序為：

```
偏移        結構名稱                      大小（典型值）
─────────────────────────────────────────────────────────
0x0000      DOS 標頭（IMAGE_DOS_HEADER）   64 bytes
0x0040      DOS Stub（選用）                可變
0x0080      PE 簽名（"PE\0\0"）             4 bytes
0x0084      COFF 標頭（標準標頭）           20 bytes
0x0098      可選標頭（IMAGE_OPTIONAL_HEADER） 224 bytes（PE32）
0x0178      段表（Section Table）           n × 40 bytes
0x0400      段資料（.idata, .text, .rsrc）  可變

對齊說明：
- 檔案對齊（FileAlignment）：0x200（512 bytes）
- 記憶體對齊（SectionAlignment）：0x1000（4 KiB）
```

### 9.2 DOS 標頭與 DOS Stub

#### 9.2.1 DOS 標頭結構（IMAGE_DOS_HEADER）

DOS 標頭存在是為了向後相容 MS-DOS。當在 DOS 模式下執行 PE 檔案時，會執行 DOS Stub 中的程式碼。

| 偏移 | 大小 | 欄位名稱 | 值 | 說明 |
|------|------|----------|-----|------|
| 0x00 | 2 | e_magic | "MZ" (0x5A4D) | 魔數，Mark Zbikowski 的縮寫 |
| 0x02 | 2 | e_cblp | - | 最後頁面位元組數 |
| 0x04 | 2 | e_cp | - | 檔案頁面數 |
| ... | ... | ... | ... | 其他 DOS 時期欄位 |
| 0x3C | 4 | **e_lfanew** | 0x80 | **PE 標頭偏移（重要）** |

**關鍵欄位 e_lfanew**：指向 PE 簽名的檔案偏移，通常為 0x80。Windows 載入器藉由此欄位找到真正的 PE 標頭。

#### 9.2.2 DOS Stub

DOS Stub 是一段簡單的 DOS 程式碼，當使用者在 MS-DOS 模式下執行 PE 檔案時顯示錯誤訊息：

```
"This program cannot be run in DOS mode."
```

**為何需要 DOS Stub？** — 向後相容性設計

1. **歷史淵源**：Windows NT（1993）需要與 MS-DOS（1981）和早期 Windows（3.x/9x）保持檔案格式相容
2. **雙模式檔案**：許多 Windows 工具（如壓縮程式、安裝程式）在 DOS 和 Windows 下都有不同實作
3. **優雅降級**：當使用者在純 DOS 環境下誤執行 Windows 程式時，顯示友善訊息而非當機

**標準 DOS Stub 的組成**：

```asm
; 標準 Windows 執行檔的 DOS Stub（約 64-128 bytes）
BITS 16
    push    cs
    pop     ds
    mov     dx, msg         ; DX = 訊息偏移
    mov     ah, 09h         ; DOS 功能：顯示字串
    int     21h             ; 呼叫 DOS 中斷
    mov     ax, 4C01h       ; DOS 功能：結束程式（返回碼 1）
    int     21h
msg:
    db      "This program cannot be run in DOS mode.$"
```

**SP-Forth 的特殊設計**：

在 SP-Forth 的 `spf_stub.f` 中，DOS Stub 被替換為更複雜的測試程式碼（見 §9.7）。這段程式碼在 Windows 下執行時：
1. 嘗試載入 `USER32.dll`
2. 取得 `MessageBoxA` 函數位址
3. 顯示 "SPF-STUB" 訊息框

這個設計的目的是在 SP-Forth 無法正常啟動時（例如缺少執行時 DLL），提供一個可見的錯誤指示，而非無聲無息地當機。

**現代意義**：

在現代 Windows（XP/Vista/7/8/10/11）中，DOS Stub 幾乎不再被執行，因為：
- Windows NT 系列的 DOS 模擬器（NTVDM）已於 64 位元版本中移除
- 純 DOS 環境已極少見
- 但仍保留作為 PE 格式的歷史特徵和檔案識別用途

### 9.3 COFF 標頭（標準標頭）

COFF（Common Object File Format）標頭緊接在 PE 簽名之後，大小固定為 20 bytes：

| 偏移 | 大小 | 欄位名稱 | SP-Forth 典型值 | 說明 |
|------|------|----------|-----------------|------|
| 0x00 | 2 | Machine | 0x014C | i386（Intel 80386） |
| 0x02 | 2 | **NumberOfSections** | 2-3 | 段數量（.text + .idata [+ .rsrc]） |
| 0x04 | 4 | TimeDateStamp | - | 編譯時間戳 |
| 0x08 | 4 | PointerToSymbolTable | 0 | 符號表偏移（EXE 通常為 0） |
| 0x0C | 4 | NumberOfSymbols | 0 | 符號數量（EXE 通常為 0） |
| 0x10 | 2 | **SizeOfOptionalHeader** | 0x00E0 | 可選標頭大小（224 = PE32） |
| 0x12 | 2 | **Characteristics** | 0x0102 | 檔案特性（可執行、32位元） |

**Characteristics 標誌位**（部分）：
- 0x0002：可執行檔（IMAGE_FILE_EXECUTABLE_IMAGE）
- 0x0100：32 位元機器（IMAGE_FILE_32BIT_MACHINE）
- 0x0200：無重定位資訊（EXE 通常設定）

### 9.4 可選標頭（IMAGE_OPTIONAL_HEADER）

可選標頭雖名為「可選」，但對可執行檔而言是**必需的**。它包含作業系統載入器所需的關鍵資訊。

#### 9.4.1 可選標頭 Magic 與基本資訊

| 偏移 | 大小 | 欄位名稱 | 值 | 說明 |
|------|------|----------|-----|------|
| 0x00 | 2 | Magic | 0x010B | PE32（32位元可執行檔） |
| 0x02 | 1 | MajorLinkerVersion | - | 連結器主版本 |
| 0x03 | 1 | MinorLinkerVersion | - | 連結器次版本 |
| 0x04 | 4 | SizeOfCode | - | 程式碼段總大小 |
| 0x08 | 4 | SizeOfInitializedData | - | 已初始化資料總大小 |
| 0x0C | 4 | SizeOfUninitializedData | - | 未初始化資料總大小 |

#### 9.4.2 關鍵欄位（SP-Forth 使用）

| 偏移 | 大小 | 欄位名稱 | SP-Forth 值 | 說明 |
|------|------|----------|-------------|------|
| 0x10 | 4 | **AddressOfEntryPoint** | 0x2000 | 程式入口點 RVA |
| 0x14 | 4 | BaseOfCode | 0x2000 | 程式碼段基底 RVA |
| 0x18 | 4 | BaseOfData | - | 資料段基底 RVA |
| 0x1C | 4 | **ImageBase** | 0x400000 | 映像首選載入位址 |
| 0x20 | 4 | **SectionAlignment** | 0x1000 | 記憶體中段對齊（4 KiB） |
| 0x24 | 4 | **FileAlignment** | 0x200 | 檔案中段對齊（512 B） |
| 0x28 | 2 | MajorOSVersion | - | 作業系統主版本 |
| 0x2A | 2 | MinorOSVersion | - | 作業系統次版本 |
| 0x2C | 2 | MajorImageVersion | - | 映像主版本 |
| 0x2E | 2 | MinorImageVersion | - | 映像次版本 |
| 0x30 | 2 | MajorSubsystemVersion | 4 | 子系統主版本 |
| 0x32 | 2 | MinorSubsystemVersion | 0 | 子系統次版本 |
| 0x34 | 4 | Win32VersionValue | 0 | 保留 |
| 0x38 | 4 | **SizeOfImage** | - | **映像總大小（載入時）** |
| 0x3C | 4 | **SizeOfHeaders** | 0x400 | 標頭總大小 |
| 0x40 | 4 | CheckSum | 0 | 檔案總和檢查 |
| 0x44 | 2 | **Subsystem** | 2/3 | **子系統（GUI=2, CUI=3）** |
| 0x46 | 2 | DllCharacteristics | - | DLL 特性 |
| 0x48 | 4 | SizeOfStackReserve | - | 堆疊保留大小 |
| 0x4C | 4 | SizeOfStackCommit | - | 堆疊初始提交大小 |
| 0x50 | 4 | SizeOfHeapReserve | - | 堆積保留大小 |
| 0x54 | 4 | SizeOfHeapCommit | - | 堆積初始提交大小 |
| 0x58 | 4 | LoaderFlags | 0 | 保留 |
| 0x5C | 4 | **NumberOfRvaAndSizes** | 16 | 資料目錄項目數 |

#### 9.4.3 RVA（Relative Virtual Address）概念

**RVA** 是 PE 格式的核心概念：

```
虛擬位址（VA）= ImageBase + RVA
```

例如：
- 若 ImageBase = 0x400000，EntryPoint RVA = 0x2000
- 則實際入口點位址 = 0x400000 + 0x2000 = 0x402000

**為何使用 RVA？**
1. **位置無關**：載入器可以將映像載入不同位址（如 ASLR），只需調整基底，RVA 保持不變
2. **節省空間**：相對於絕對位址，RVA 值較小（通常 < 0x10000），可用較小欄位儲存

**RVA 與檔案偏移轉換**：
```
檔案偏移 = 段的 PointerToRawData + (RVA - 段的 VirtualAddress)
```

#### 9.4.4 資料目錄（Data Directory）

可選標頭末尾包含 16 個資料目錄項目，每個項目 8 bytes（RVA + Size）：

| 索引 | 名稱 | 說明 | SP-Forth 使用 |
|------|------|------|---------------|
| 0 | EXPORT | 匯出表 | 否 |
| 1 | **IMPORT** | **匯入表** | **是（KERNEL32.dll）** |
| 2 | RESOURCE | 資源表 | 選用 |
| 3 | EXCEPTION | 例外處理表 | 否 |
| 4 | SECURITY | 安全憑證 | 否 |
| 5 | BASERELOC | 基底重定位表 | 否（SP-Forth 使用固定基底）|
| 6 | DEBUG | 偵錯資訊 | 否 |
| ... | ... | ... | ... |

SP-Forth 主要使用 **IMPORT 資料目錄** 來載入 `LoadLibraryA` 和 `GetProcAddress`。

### 9.5 段表（Section Table）

段表緊接在可選標頭之後，每個段描述一個記憶體區域（程式碼、資料、匯入表等）。

#### 9.5.1 段表項目結構（IMAGE_SECTION_HEADER）

每個段表項目固定 40 bytes：

| 偏移 | 大小 | 欄位名稱 | 說明 |
|------|------|----------|------|
| 0x00 | 8 | **Name** | 段名稱（ASCIIZ，如 ".text\0\0\0"） |
| 0x08 | 4 | **VirtualSize** | 段在記憶體中的大小 |
| 0x0C | 4 | **VirtualAddress** | 段的 RVA（記憶體中） |
| 0x10 | 4 | **SizeOfRawData** | 段在檔案中的大小 |
| 0x14 | 4 | **PointerToRawData** | 段在檔案中的偏移 |
| 0x18 | 4 | PointerToRelocations | 重定位偏移（OBJ 檔案使用） |
| 0x1C | 4 | PointerToLinenumbers | 行號表偏移 |
| 0x20 | 2 | NumberOfRelocations | 重定位項目數 |
| 0x22 | 2 | NumberOfLinenumbers | 行號數 |
| 0x24 | 4 | **Characteristics** | **段特性** |

#### 9.5.2 SP-Forth 使用的段

| 段名稱 | 用途 | Characteristics |
|--------|------|-----------------|
| **.text** | 程式碼段，包含 Forth 字典 | 0x60000020（可執行、可讀、程式碼） |
| **.idata** | 匯入表，包含 Import Directory 和 IAT | 0x40000040（已初始化、可讀、資料） |
| **.rsrc**（選用） | 資源段（圖示、版本資訊等） | 0x40000040（已初始化、可讀、資料） |

**Characteristics 標誌位**：
- 0x00000020：包含程式碼（IMAGE_SCN_CNT_CODE）
- 0x00000040：包含已初始化資料（IMAGE_SCN_CNT_INITIALIZED_DATA）
- 0x20000000：可執行（IMAGE_SCN_MEM_EXECUTE）
- 0x40000000：可讀（IMAGE_SCN_MEM_READ）
- 0x80000000：可寫（IMAGE_SCN_MEM_WRITE）

### 9.6 匯入表（Import Table）結構

匯入表是 PE 檔案載入 DLL 並解析函數位址的關鍵機制。

#### 9.6.1 匯入表整體結構

匯入表位於 .idata 段，包含以下並行陣列：

```
┌─────────────────────────────────────┐
│ Import Directory Table              │ 每個 DLL 一個項目（20 bytes）
│  - Import Lookup Table RVA          │
│  - TimeDateStamp                    │
│  - ForwarderChain                   │
│  - Name RVA                         │
│  - Import Address Table RVA         │
├─────────────────────────────────────┤
│ Import Lookup Table (ILT) /         │ 函數名稱/序號陣列
│ Import Name Table (INT)             │
├─────────────────────────────────────┤
│ Import Address Table (IAT)          │ 解析後的函數位址陣列
│ （執行時由載入器填入）               │
├─────────────────────────────────────┤
│ Hint/Name Table                     │ 函數名稱字串
│  - Hint（2 bytes）：匯出表索引提示    │
│  - Name：函數名稱（ASCIIZ）           │
├─────────────────────────────────────┤
│ DLL 名稱字串                        │ 如 "KERNEL32.dll\0"
└─────────────────────────────────────┘
```

#### 9.6.2 Import Directory Table 項目

每個 DLL 對應一個 20-byte 項目：

| 偏移 | 大小 | 欄位 | 說明 |
|------|------|------|------|
| 0x00 | 4 | ImportLookupTableRVA | 指向 ILT/INT（Import Name Table） |
| 0x04 | 4 | TimeDateStamp | 時間戳（0 = 未繫結） |
| 0x08 | 4 | ForwarderChain | 轉發鏈索引（-1 = 無轉發） |
| 0x0C | 4 | NameRVA | 指向 DLL 名稱字串的 RVA |
| 0x10 | 4 | ImportAddressTableRVA | 指向 IAT 的 RVA |

#### 9.6.3 Import Lookup Table / Import Name Table

每個項目 4 bytes，最高位元決定類型：

- **最高位元 = 1**：按序號匯入
  - 低 31 bits = 函數序號（Ordinal）
- **最高位元 = 0**：按名稱匯入
  - 指向 Hint/Name Table 的 RVA

#### 9.6.4 SP-Forth 匯入表示例

```forth
\ spf_stub.f 中的匯入表定義
CREATE ImportDirectory
  \ Import Directory Table（2 個項目 + 結束項目）
  /ImportDirectory 2 * DUP ALLOT ERASE

  \ Import Lookup Table / Import Address Table
  HERE ImportDirectory - 1000 + ImportDirectory ID.ImportLookupTableRVA !
  0 , \ LoadLibraryA 的 RVA（偏移 0x34）
  0 , \ GetProcAddress 的 RVA（偏移 0x38）
  0 , \ 結束項目

  HERE ImportDirectory - 1000 + ImportDirectory ID.ImportAddressTableRVA !
  0 , 0 , 0 ,  \ IAT（填入時與 ILT 相同）

  \ 函數名稱提示
  HERE 101 W, S" GetProcAddress" HERE SWAP DUP ALLOT MOVE 0 C, 0 C,
  HERE 16D W, S" LoadLibraryA" HERE SWAP DUP ALLOT MOVE 0 C, 0 C,
  HERE S" KERNEL32.dll" HERE SWAP DUP ALLOT MOVE 0 C, 0 C,
```

此匯入表匯入 `KERNEL32.dll` 的兩個函數：
- `LoadLibraryA`：載入 DLL
- `GetProcAddress`：取得 DLL 函數位址

### 9.7 測試程式碼（DOS Stub 用途）

啟動殼層包含一段組語測試程式碼，嘗試載入 USER32.dll 並顯示訊息框。

> **注意：`PUSH # 100000` 之類的立即值不是真的字串位址，而是 placeholder。** 原始碼（`src/spf_stub.f:262–286`）在每個 `PUSH #` 之後都緊接一段 `A; HERE 4 - ADDROF... !` 的 metaprogramming：`A;` 先把剛 emit 的指令收尾，`HERE 4 -` 回到剛寫出的那 4-byte 立即值欄位，再用 `ADDROFUSER32 !` 之類把該欄位位址記下來，留待之後填入真正的字串位址。下面為了易讀略去了這些 `A; HERE 4 - ... !` 行；真正的原始碼長這樣：

```forth
\ src/spf_stub.f:262（節錄，保留 metaprogramming 慣例）
INIT-ASM
    MOV  EAX , 401034            \ LoadLibraryA 的位址
    PUSH # 100000                \ 之後填 Z" USER32.DLL" 的位址
     A; HERE 4 - ADDROFUSER32 !  \   記下這個 4-byte 欄位的位址
    CALL EAX                     \ LoadLibraryA(...)
    PUSH # 200000                \ 之後填 Z" MessageBoxA" 的位址
     A; HERE 4 - ADDROFMESSAGEBOX !
    PUSH EAX                     \ hModule
    MOV  EAX , 401038            \ GetProcAddress 的位址
    CALL EAX                     \ GetProcAddress(hModule, "MessageBoxA")
    \ ...（其餘 MessageBoxA 參數同樣以 PUSH # + A; HERE 4 - ... ! 方式預留）...
    CALL EAX                     \ MessageBoxA(NULL, text, title, MB_OK)
    RET
END-ASM PREVIOUS
```

這段程式碼在 SP-Forth 無法自行啟動時（例如缺少 DLL），提供一個可見的錯誤訊息。

### 9.8 PE 儲存

```forth
: SAVE-PE ( addr u -- )
  R/W CREATE-FILE THROW >R
  R@ WRITE-EXE-HEADER    \ 寫出 PE 標頭
  R@ WRITE-ID             \ 寫出匯入表
  R@ WRITE-PROGRAM        \ 寫出程式碼
  R> CLOSE-FILE THROW
;
```

### 9.9 PE 資源段（src/win/res/）

Windows 建構流程會額外編譯資源檔，產生 `spf.FRES`，最終連結進 `spf4.exe`：

| 檔案 | 作用 |
|------|------|
| `spf.rc` | 資源腳本：定義圖示（`spf.ico`）、應用程式清單（`spf.manifest`）與 `VERSIONINFO`（版本 4.29.0.0） |
| `spf.ico` | 執行檔圖示 |
| `spf.manifest` | 宣告 Common Controls v6 相依性（讓 Windows XP 以上使用主題化控制項） |
| `res.bat` | 建構腳本：呼叫 `rc`（`rc.exe`）編譯 `spf.rc` → `spf.res`，再用 SP-Forth 工具 `fres.f`（位於 `devel/~yz/prog/fres/fres.f`，`res.bat` 中以相對 spf4 working tree root 的路徑 `~yz/prog/fres/fres.f` 載入）把 `spf.res` 轉為 `spf.FRES` |
| `spf.FRES` | 編譯後的資源物件檔，由連結器併入 `.rsrc` 段 |

`spf.manifest` 中的 `assemblyIdentity` 宣告處理器架構為 `X86`、版本 `4.29.0.0`，這與 `spf.f` 中定義的 `SPF-KERNEL-VERSION` 一致。資源段讓最終的 `spf4.exe` 擁有正確的圖示、版本資訊與 UAC/DPI 感知行為。

---

## 10. TSAVE — Windows PE 儲存（tsave.f）

### 10.1 概述

`tsave.f` 提供 Windows 的 PE 格式映像儲存功能。它讀取現有的 `spf4.exe`（由啟動殼層產生的 PE 模板），修改其中的 Forth 程式碼段和資源段，然後寫出新的執行檔。

### 10.2 重定位

```forth
: relocate ( adr xt -- )
  >R
  DUP 12 + W@ ( 段標頭大小) OVER 14 + W@ ( 段資料大小) +
  SWAP 16 + SWAP
  BEGIN ( adr #) DUP WHILE
    OVER CELL+ @ 0x7FFFFFFF AND END-CODE-SEG + R@ EXECUTE
  SWAP 2 CELLS + SWAP 1-
  REPEAT 2DROP RDROP
;

: relocate3 ( leaf -- ) IMAGE-SIZE BASEOFCODE + SWAP +! ;
: relocate2 ( dir -- ) ['] relocate3 relocate ;
: relocate1 ( dir -- ) ['] relocate2 relocate ;
```

三層重定位：
1. `relocate3`：修補資源樹葉節點中的位址（加上 `IMAGE-SIZE + BASEOFCODE`）
2. `relocate2`：遍歷資源目錄，修補子目錄
3. `relocate1`：遍歷資源目錄，修補葉節點

### 10.3 (SAVE-WITH-RESOURCES)

> **重要前提（避免被誤認為 PE32 標準偏移）**：下面 `START-PE-HEADER + 0x06 / 0x28 / 0x34 / 0x50 / 0x5C` 等位移**不是** PE32 標準 IMAGE_OPTIONAL_HEADER 內部欄位的偏移；它們是針對 SP-Forth 自帶的 PE 模板（由 `src/spf_stub.f` 產生並被 `tsave.f` 讀回修改的 `spf4.exe` template）的硬編碼位移。`START-PE-HEADER` 本身固定為 0x80（PE 簽名「`PE\0\0`」在這個 stub 中的檔案偏移），所以這裡看到的偏移要先加上 0x80 才對到該 stub 的真實檔案偏移；而且這些位移已經配合 stub 的具體佈局調整過，**不能直接套用到 MSVC / link.exe 產出的任意 PE32 檔案**。若 stub 結構日後改動，這些常數也必須同步更新。

```forth
: (SAVE-WITH-RESOURCES) ( u.offset.section-resources sd.filename-exe -- )
  R/W CREATE-FILE THROW >R
  ModuleName R/O OPEN-FILE-SHARED THROW >R      \ 開啟原始 spf4.exe
  HERE SIZE-HEADER R@ READ-FILE THROW SIZE-HEADER < THROW  \ 讀取 PE 標頭
  R> CLOSE-FILE THROW

  \ 修改 PE 標頭中的欄位（所有偏移皆相對 spf_stub.f 產生的 PE template，非通用 PE32）
  ?Res IF 3 ELSE 2 THEN HERE START-PE-HEADER 0x06 + + W!  \ NumberOfSections（stub-relative）
  ?GUI IF 2 ELSE 3 THEN HERE START-PE-HEADER 0x5C  + + W!  \ Subsystem（stub-relative，非 PE32 標準 0x44）
  BASEOFCODE            HERE START-PE-HEADER 0x28  + +  !   \ EntryPointRVA（stub-relative）
  IMAGE-BASE            HERE START-PE-HEADER 0x34  + +  !   \ ImageBase（stub-relative）
  IMAGE-SIZE BASEOFCODE + END-RES-SEG END-CODE-SEG - 0xFFF + 0x1000 / 0x1000 * +
                        HERE START-PE-HEADER 0x50  + +  !   \ ImageSize（stub-relative）
  \ ... 更多標頭修改 ...

  HERE SIZE-HEADER R@ WRITE-FILE THROW      \ 寫出修改後的標頭
  IMAGE-BEGIN HERE OVER -                      \ Forth 字典資料
  ROT ALLOT
  R@ WRITE-FILE THROW                         \ 寫出 Forth 字典
  R> CLOSE-FILE THROW
;
```

### 10.4 資源段

```forth
?Res IF
  S" .rsrc"             START-RES-TABLE SWAP CMOVE       \ 段名稱
  END-RES-SEG END-CODE-SEG - 0xFFF + 0x1000 / 0x1000 * START-RES-TABLE 0x08 + ! \ VirtualSize
  IMAGE-SIZE BASEOFCODE + 0xFFF + 0x1000 TUCK / * START-RES-TABLE 0x0C + ! \ VirtualAddress
  END-RES-SEG END-CODE-SEG - START-RES-TABLE 0x10 + ! \ SizeOfRawData
  END-CODE-SEG IMAGE-BEGIN - SIZE-HEADER + START-RES-TABLE 0x14 + ! \ PointerToRawData
  0x40 0x40000000 OR   START-RES-TABLE 0x24 + ! \ Characteristics
THEN
```

資源段（`.rsrc`）的旗標為 `0x40000040`（`IMAGE_SCN_CNT_INITIALIZED_DATA | IMAGE_SCN_MEM_READ`），僅在存在資源時加入。

---

## 11. DONE 標記（done.f）

> **重要：`done.f` 是 Windows 專屬檔案。** 它只在 Windows 建構路徑中被 `INCLUDED`（`spf.f:306–309` 的 `: DONE ... S" src/done.f" INCLUDED ;`），POSIX 路徑完全不使用 `done.f`。下面 §11.1 是 POSIX 路徑在 `spf.f` 內的最終化步驟（沒有 done.f），§11.2 才是真正的 `done.f`（Windows）。

### 11.1 POSIX 最終化（不使用 done.f，直接在 spf.f 內完成）

POSIX 路徑不需要 `done.f`，因為映像儲存由 `XSAVE` 直接完成。`spf.f` 中的 POSIX 最終化步驟：

```forth
\ POSIX: 完成向量修復，呼叫 XSAVE
TC-LATEST-> FORTH-WORDLIST
HERE ' (DP) TC-ADDR!
_VOC-LIST @ ' _VOC-LIST TC-ADDR!
' NON-OPT-WL EXECUTE ' NON-OPT-WL TC-VECT!
' FORTH-WORDLIST EXECUTE ' FORTH-WORDLIST TC-VECT!
[T] [DEFINED] MACROOPT-WL [I] [IF]
' MACROOPT-WL EXECUTE ' MACROOPT-WL TC-VECT!
[THEN]
HERE .forth - TO .forth#
ONLY DEFINITIONS
S" src/xsave.f" INCLUDED
S" src/spf4.o" XSAVE    \ 儲存 ELF 物件檔
```

### 11.2 Windows 版（這才是真正的 src/done.f）

```forth
HEX
\ 修補 LoadLibraryA 和 GetProcAddress 的位址
AOLL  @ @ @ IMAGE-BASE 1034 + !
AOGPA @ @ @ IMAGE-BASE 1038 + !

\ 更新動態連結位址
IMAGE-BASE 1034 + AOLL @ !
IMAGE-BASE 1038 + AOGPA @ !
DECIMAL

S" spf4.exe" S" src\win\res\spf.fres" src\tsave.f
.(  The system has been saved) CR
BYE
```

Windows 版的 `done.f` 執行：
1. 修補 PE 標頭中 `LoadLibraryA` 和 `GetProcAddress` 的匯入位址
2. 呼叫 `tsave.f` 儲存 PE 格式的執行檔
3. 顯示儲存完成訊息

---

## 12. SAVE-WITH-RESERVE

```forth
: SAVE-WITH-RESERVE ( u.target-dict-unused sd.filename-executable )
  IMAGE-SIZE >R 2>R
  HERE IMAGE-BASE -                    \ u.dict-used：字典已使用空間
  ( u.target-dict-unused u.dict-used ) + TO IMAGE-SIZE
  2R> SAVE                              \ 儲存映像
  R> TO IMAGE-SIZE                      \ 恢復原始 IMAGE-SIZE
;
```

`SAVE-WITH-RESERVE` 允許以指定的字典空間大小儲存映像：

```
新 IMAGE-SIZE = u.target-dict-unused + (HERE - IMAGE-BASE)
```

例如 `spf4e` 使用 `10 1024 * 1024 * SAVE-WITH-RESERVE`，即額外預留 10 MiB 的可用字典空間。

這個機制使得 `spf4e` 啟動後有大量字典空間可供使用者擴充，而 `spf4`（最小版）的字典空間較小。

---

## 13. 完整建構流程摘要

```
宿主 Forth（spf4orig / jpf375c.exe）
  │
  ├── 1. 前置步驟
  │     ├── 下載宿主編譯器（若缺少）
  │     └── posix/Makefile → posix/config.c → config.gen → config.auto.f
  │
  ├── 2. 載入 spf.f（主控腳本）
  │     ├── spf_compileoptions.f（編譯選項）
  │     ├── posix/config.auto.f（系統常數）
  │     ├── spf_date.f（建構日期）
  │     ├── spf_xmlhelp.f（XML 說明產生器）
  │     ├── tc_spf.F（交叉編譯器）
  │     ├── spf_defkern.f（定義字機器碼原語）
  │     ├── spf_forthproc.f（高層 Forth 字）
  │     ├── spf_floatkern.f（浮點核心）
  │     ├── spf_forthproc_hl.f（輔助字）
  │     ├── 平台 API（posix/*.f 或 win/*.f）
  │     ├── spf_except.f（例外處理）
  │     ├── spf_con_io.f（控制台 I/O）
  │     ├── spf_print.f（數值輸出）
  │     ├── spf_module.f（模組管理）
  │     ├── 編譯器（compiler/*.f）
  │     ├── macroopt.f 或 noopt.f（最佳化器）
  │     ├── spf_error.f（錯誤追蹤）
  │     ├── spf_translate.f（直譯器）
  │     ├── spf_init.f（系統初始化）
  │     └── posix/save.f 或 win/spf_pe_save.f（映像儲存）
  │
  ├── 3. 交叉編譯產生目標映像
  │     ├── TC-LATEST→ FORTH-WORDLIST
  │     ├── (DP) TC-ADDR!       （修復字典指標）
  │     ├── _VOC-LIST TC-ADDR! （修復字彙表列表）
  │     ├── 修復 NON-OPT-WL、FORTH-WORDLIST、MACROOPT-WL 向量
  │     └── HERE .forth - TO .forth#（計算字典段大小）
  │
  ├── 4. 儲存映像
  │     ├── POSIX: spf4.o → XSAVE → gcc 連結 → spf4
  │     │         ├── .forth 段（Forth 字典）
  │     │         ├── .space 段（字典擴展空間，BSS）
  │     │         ├── .dltable 段（動態連結表）
  │     │         ├── .dlstrings 段（動態連結字串）
  │     │         ├── .symtab（符號表：main, dlopen, dlsym, realloc, write, calloc, dlerror）
  │     │         ├── .rel.forth（重定位表：8 個 R_386_32 項目）
  │     │         └── gcc spf4.o -Wl,forth.ld -ldl -lpthread -m32 -o spf4
  │     │
  │     └── Windows: spf4.exe → TSAVE → PE 格式
  │                  ├── 讀取 PE 模板
  │                  ├── 修改 PE 標頭（ImageBase, EntryPoint, ImageSize）
  │                  ├── 寫入 Forth 字典資料
  │                  ├── 修補 LoadLibraryA/GetProcAddress 位址
  │                  └── 加入 .rsrc 段（若有資源）
  │
  └── 5. 產生擴充版
        └── echo '10 1024 * 1024 * S" ../spf4e" SAVE-WITH-RESERVE BYE' | ../spf4 lib/ext/spf4e.f
```

---

## 14. 關鍵常數與參數

### 14.1 映像常數

| 常數 | 值 | 說明 |
|------|-----|------|
| `SPF-KERNEL-VERSION` | 429 | 核心版本號 |
| `IMAGE-START` | 0x8050000 | Forth 字典起始位址 |
| `IMAGE-SIZE` | 524288（512 KiB） | 預設字典大小 |
| `MM_SIZE` | 0x20 | 記憶體管理區塊大小 |

### 14.2 ELF 結構常數

| 常數 | 值 | 說明 |
|------|-----|------|
| `elf-header-size` | 0x34 | ELF 標頭大小（posix/save.f） |
| `elf-section-size` | 0x28 | 段標頭大小（posix/save.f） |
| `elf-symbol-size` | 0x10 | 符號表項大小（posix/save.f） |
| `elf-rel-size` | 0x08 | 重定位項大小 |
| `header-size` | 0x34 | ELF 標頭大小（elf.f） |
| `section-size` | 0x28 | 段標頭大小（elf.f） |
| `segment-size` | 0x20 | 程式標頭大小（elf.f） |
| `symbol-size` | 0x10 | 符號表項大小（elf.f） |

### 14.3 Windows PE 常數

| 常數 | 值 | 說明 |
|------|-----|------|
| `START-PE-HEADER` | 0x80 | PE 標頭起始偏移 |
| `SIZE-HEADER` | 0x400 | 標頭總大小 |
| `BASEOFCODE` | 0x2000 | 程式碼段起始 RVA |
| `IMAGE-BASE`（Windows） | `ORG-ADDR − 0x2000`（見 `spf_pe_save.f:14` `DUP 8 1024 * -`） | SP-Forth 的可載入映像基底常數；**不是** PE 預設的 0x400000。PE 標頭的 ImageBase 欄位另由 `SAVE` 以 `IMAGE-BEGIN − 0x2000` 寫入（`spf_pe_save.f:32`） |

### 14.4 config.auto.f 常數（Linux x86_64，glibc 2.39）

這裡的「Linux x86_64」指的是**產生 `config.auto.f` 的宿主環境**，不是 SP-Forth 目標系統改成 64 位元。`posix/config.c` 在建構時會以 `-m32` 編譯，因此輸出的常數仍然反映 **IA-32 / 32-bit ABI** 的結構佈局。

| 常數 | 值 | 說明 |
|------|-----|------|
| `CONTEXT_EDI` | 0x24 | ucontext_t 中 EDI 的偏移 |
| `CONTEXT_EIP` | 0x4C | ucontext_t 中 EIP 的偏移 |
| `CONTEXT_ESP` | 0x30 | ucontext_t 中 ESP 的偏移 |
| `CONTEXT_EAX` | 0x40 | ucontext_t 中 EAX 的偏移 |
| `CONTEXT_EBP` | 0x2C | ucontext_t 中 EBP 的偏移 |
| `SA_RESTART` | 0x10000000 | sigaction SA_RESTART 旗標 |
| `SA_SIGINFO` | 0x4 | sigaction SA_SIGINFO 旗標 |
| `SA_NODEFER` | 0x40000000 | sigaction SA_NODEFER 旗標 |
| `SIZEOF_SIGSET` | 0x80 | sigset_t 大小（128 位元組） |
| `O_RDONLY` | 0x0 | 唯讀開啟旗標 |
| `O_WRONLY` | 0x1 | 唯寫開啟旗標 |
| `O_RDWR` | 0x2 | 讀寫開啟旗標 |
| `O_CREAT` | 0x40 | 建立檔案旗標 |
| `O_TRUNC` | 0x200 | 截斷旗標 |
| `PAGESIZE` | 0x1000 | 記憶體頁大小（4096） |
| `PROT_READ` | 0x1 | 記憶體保護：可讀 |
| `PROT_WRITE` | 0x2 | 記憶體保護：可寫 |
| `PROT_EXEC` | 0x4 | 記憶體保護：可執行 |
