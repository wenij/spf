# SP-Forth/4 原始碼追蹤 — 快速參考

> 定位：速查手冊，方便快速查找核心概念、檔案對照與編譯流程
> 
> 完整說明請參閱各主題文件：
> - [00-overview.md](00-overview.md) — 系統概觀與閱讀導引
> - [01-kernel.md](01-kernel.md) — 核心原語
> - [02-compiler.md](02-compiler.md) — 編譯器子系統
> - [03-cross-compiler.md](03-cross-compiler.md) — 交叉編譯器
> - [04-posix-platform.md](04-posix-platform.md) — POSIX 平台
> - [05-io-error-init.md](05-io-error-init.md) — I/O、例外與初始化
> - [06-build-save.md](06-build-save.md) — 建構與映像儲存
> - [07-optimizer.md](07-optimizer.md) — 巨集最佳化器
> - [08-append-a.md](08-append-a.md) — IA-32 組語基礎
> - [09-windows-platform.md](09-windows-platform.md) — Windows 平台
> - [11-forth-compilation.md](11-forth-compilation.md) — Forth 編譯模式深入
> - [12-debugging.md](12-debugging.md) — 除錯與故障排查
> - [13-verification.md](13-verification.md) — 驗證、效能量測與安全檢查
> - [14-walkthrough.md](14-walkthrough.md) — 從一個字到可執行映像的端到端走讀
> - [15-standalone-executable.md](15-standalone-executable.md) — 獨立執行檔生成與 SAVE 機制

---

## 1. 暫存器慣例（IA-32）

### 1.1 TOS-in-EAX 模型

| 暫存器 | 名稱 | SP-Forth 用途 | Forth 語意 |
|--------|------|---------------|-----------|
| **EAX** | Accumulator | **TOS**（堆疊頂端） | 資料堆疊最上層元素 |
| **EBP** | Base Pointer | 資料堆疊指標 | 指向**次堆疊項**（second item） |
| **ESP** | Stack Pointer | 回返堆疊指標 | x86 原生堆疊 |
| **EDI** | Destination Index | TLS 基底指標 | 執行緒本地儲存（USER 變數區） |
| **EBX** | Base | 通用暫存器 | 跳躍目的、臨時儲存 |
| **ECX** | Counter | 通用/計數器 | 字串操作、迴圈計數 |
| **EDX** | Data | 通用/乘除 | 乘法高位、除法餘數 |
| **ESI** | Source Index | 字串來源 | `CMOVE`/`CMOVE>` 來源位址 |

### 1.2 關鍵組語慣用語

```asm
; TOS 操作
MOV EAX, [EBP]        ; 讀取次項到 TOS
MOV [EBP], EAX        ; 寫入 TOS 到次項
LEA EBP, 4 [EBP]      ; 彈出堆疊（EBP += 4）
LEA EBP, -4 [EBP]     ; 推入堆疊（EBP -= 4）

; 比較無分支技巧
XOR EAX, [EBP]        ; 比較兩值
SUB EAX, # 1          ; 若相等則借位
SBB EAX, EAX          ; EAX = -1（相等）或 0（不等）

; TLS/USER 變數存取
MOV EAX, [EDI + offset]  ; 讀取 USER 變數
LEA EAX, [EDI] [EAX]     ; 計算 USER 變數位址
```

---

## 2. 核心檔案對照表

### 2.1 主架構檔案（src/ 根目錄）

| 檔案 | 主題 | 對應文件 |
|------|------|----------|
| `spf.f` | 主控載入腳本 | 所有文件 |
| `spf_compileoptions.f` | 編譯選項 | [06-build-save.md §2](06-build-save.md#2-編譯選項spf_compileoptionsf) |
| `spf_defkern.f` | 定義字核心原語（CREATE, CONSTANT, USER 等） | [01-kernel.md §2](01-kernel.md#2-定義字核心原語spf_defkernf-深入解析) |
| `spf_forthproc.f` | Forth 程序核心（堆疊、算術、記憶體） | [01-kernel.md §3](01-kernel.md#3-forth-程序核心spf_forthprocf-深入解析) |
| `spf_forthproc_hl.f` | 高階 Forth 程序（HASH, MOVE 等） | [01-kernel.md §5](01-kernel.md#5-高階-forth-程序spf_forthproc_hlf-深入解析) |
| `spf_floatkern.f` | 浮點運算核心（x87 FPU） | [01-kernel.md §4](01-kernel.md#4-浮點運算核心spf_floatkernf-深入解析) |
| `spf_except.f` | 例外處理 façade（THROW/CATCH） | [05-io-error-init.md §4](05-io-error-init.md#4-例外處理spf_exceptf) |
| `spf_init.f` | 系統初始化與啟動 | [05-io-error-init.md §10](05-io-error-init.md#10-系統初始化spf_initf) |
| `spf_print.f` | 數值輸出與格式化 | [05-io-error-init.md §3](05-io-error-init.md#3-數值輸出spf_printf) |
| `spf_con_io.f` | 控制台 I/O façade | [05-io-error-init.md §1](05-io-error-init.md#1-控制台-io-架構spf_con_iof--posixcon_iof--winspf_win_con_iof) |
| `spf_module.f` | 模組管理 façade（路徑操作） | [05-io-error-init.md §12](05-io-error-init.md#12-模組管理spf_modulef--posixmodulef) |
| `spf_date.f` | 建置日期 | [06-build-save.md §4](06-build-save.md#4-建構日期spf_datef) |
| `spf_xmlhelp.f` | XML 說明產生器 | [06-build-save.md §5](06-build-save.md#5-xml-說明產生器spf_xmlhelpf) |
| `spf_stub.f` | Windows PE 啟動殼層 | [06-build-save.md §9](06-build-save.md#9-pe-啟動殼層spf_stubf) |

### 2.2 編譯器子系統（src/compiler/）

| 檔案 | 主題 | 對應文件 |
|------|------|----------|
| `spf_parser.f` | 語法剖析器（NextWord, PARSE） | [02-compiler.md §2](02-compiler.md#2-語法剖析器spf_parserf-深入解析) |
| `spf_read_source.f` | 原始碼讀取（REFILL, SOURCE） | [02-compiler.md §3](02-compiler.md#3-原始碼讀取spf_read_sourcef-深入解析) |
| `spf_nonopt.f` | 非最佳化字集（RDROP, >R, R>） | [02-compiler.md §4](02-compiler.md#4-非最佳化字集spf_nonoptf-深入解析) |
| `spf_compile0.f` | 基本編譯控制（DP, ALLOT, ,） | [02-compiler.md §5](02-compiler.md#5-基本編譯控制spf_compile0f-深入解析) |
| `spf_compile.f` | 主要編譯器（COMPILE, BRANCH,） | [02-compiler.md §8](02-compiler.md#8-主要編譯器spf_compilef-深入解析) |
| `spf_wordlist.f` | 詞彙表管理（WORDLIST, +SWORD） | [02-compiler.md §7](02-compiler.md#7-詞彙表管理spf_wordlistf-深入解析) |
| `spf_find.f` | 搜尋引擎（SFIND, FIND1） | [02-compiler.md §6](02-compiler.md#6-搜尋引擎spf_findf-spf_find_cdrf-深入解析) |
| `spf_find_cdr.f` | CDR-BY-NAME 組合語言版 | [02-compiler.md §6](02-compiler.md#6-搜尋引擎spf_findf-spf_find_cdrf-深入解析) |
| `spf_error.f` | 錯誤處理（ERR-DATA, SAVE-ERR） | [02-compiler.md §11](02-compiler.md#11-錯誤處理spf_errorf-深入解析) |
| `spf_translate.f` | 直譯器核心（INTERPRET, QUIT） | [02-compiler.md §10](02-compiler.md#10-直譯器spf_translatef-深入解析) |
| `spf_defwords.f` | 定義字定義（SHEADER, CREATE, VARIABLE） | [02-compiler.md §9](02-compiler.md#9-定義字spf_defwordsf-深入解析) |
| `spf_immed_transl.f` | 立即字—直譯分支（TO, POSTPONE, ;） | [02-compiler.md §12](02-compiler.md#12-立即字--直譯分支spf_immed_translf-深入解析) |
| `spf_immed_lit.f` | 立即字—常值分支（LITERAL, SLITERAL） | [02-compiler.md §13](02-compiler.md#13-立即字--常值分支spf_immed_litf-深入解析) |
| `spf_literal.f` | 常值編譯（?LITERAL1, HEX-SLITERAL） | [02-compiler.md §13](02-compiler.md#13-立即字--常值分支spf_immed_litf-spf_literalf-深入解析) |
| `spf_immed_control.f` | 控制結構立即字（IF/THEN/ELSE） | [02-compiler.md §14](02-compiler.md#14-控制結構spf_immed_controlf-spf_immed_loopf-深入解析) |
| `spf_immed_loop.f` | 迴圈立即字（DO/LOOP/+LOOP） | [02-compiler.md §14](02-compiler.md#14-控制結構spf_immed_controlf-spf_immed_loopf-深入解析) |
| `spf_modules.f` | 模組載入（MODULE:, EXPORT, {{） | [02-compiler.md §15](02-compiler.md#15-模組載入spf_modulesf-深入解析) |
| `spf_inline.f` | 內聯展開（>R, R>, RDROP 內聯版） | [02-compiler.md §16](02-compiler.md#16-內聯展開spf_inlinef-深入解析) |

### 2.3 POSIX 平台（src/posix/）

| 檔案 | 主題 | 對應文件 |
|------|------|----------|
| `api.f` | C 呼叫介面（C-CALL, _WNDPROC-CODE） | [04-posix-platform.md §2](04-posix-platform.md#2-c-呼叫介面posixapif-深入解析) |
| `dl.f` | 動態程式庫載入（dlopen, dlsym） | [04-posix-platform.md §3](04-posix-platform.md#3-動態程式庫載入posixdlf-深入解析) |
| `memory.f` | 記憶體管理（ALLOCATE, ALLOCATE-RWX） | [04-posix-platform.md §5](04-posix-platform.md#5-記憶體管理posixmemoryf-深入解析) |
| `io.f` | 檔案 I/O（open64, read, write） | [04-posix-platform.md §7](04-posix-platform.md#7-檔案-ioposixiof-深入解析) |
| `con_io.f` | 控制台 I/O | [04-posix-platform.md §8](04-posix-platform.md#8-控制台-ioposixcon_iof) |
| `envir.f` | 環境查詢（getenv, ENVIRONMENT?） | [04-posix-platform.md §9](04-posix-platform.md#9-環境查詢posixenvirf-深入解析) |
| `defwords.f` | 平台定義字（EXTERN, CALLBACK:） | [04-posix-platform.md §10](04-posix-platform.md#10-平台定義字posixdefwordsf-深入解析) |
| `mtask.f` | 多執行緒（pthread_create, pthread_kill） | [04-posix-platform.md §11](04-posix-platform.md#11-多執行緒posixmtaskf-深入解析) |
| `init.f` | 程序初始化、信號處理 | [04-posix-platform.md §12](04-posix-platform.md#12-信號處理posixinitf-深入解析) |
| `save.f` | ELF 映像儲存 | [04-posix-platform.md §14](04-posix-platform.md#14-elf-映像儲存posixsavef-深入解析) |
| `module.f` | 模組路徑管理（readlink /proc/self/exe） | [04-posix-platform.md §13](04-posix-platform.md#13-模組路徑管理posixmodulef) |
| `except.f` | 例外 façade | [04-posix-platform.md §6](04-posix-platform.md#6-例外處理posixexceptf) |
| `const.f` | 檔案存取常數（O_RDONLY, O_WRONLY） | [04-posix-platform.md §4](04-posix-platform.md#4-檔案存取常數posixconstf) |

### 2.4 Windows 平台（src/win/）

| 檔案 | 主題 | 對應文件 |
|------|------|----------|
| `spf_win_api.f` | Win32 API 呼叫（API-CALL, _WINAPI-CODE） | [09-windows-platform.md §1](09-windows-platform.md#1-windows-api-呼叫機制spf_win_apif-深入解析) |
| `spf_win_defwords.f` | Win32 定義字（WINAPI:, CALLBACK:） | [09-windows-platform.md §2](09-windows-platform.md#2-winapi-外部函式宣告spf_win_defwordsf-深入解析) |
| `spf_win_memory.f` | Windows 堆積管理（HeapCreate, HeapAlloc） | [09-windows-platform.md §3](09-windows-platform.md#3-記憶體管理spf_win_memoryf-深入解析) |
| `spf_win_mtask.f` | Windows 多執行緒（CreateThread, SuspendThread） | [09-windows-platform.md §4](09-windows-platform.md#4-多執行緒spf_win_mtaskf-深入解析) |
| `spf_win_init.f` | Windows 初始化、SEH | [09-windows-platform.md §5](09-windows-platform.md#5-例外處理與-sehspf_win_initf-深入解析) |
| `spf_win_envir.f` | Windows 環境查詢（GetEnvironmentVariableA） | [09-windows-platform.md §6](09-windows-platform.md#6-環境查詢與錯誤處理spf_win_envirf-深入解析) |
| `spf_pe_save.f` | PE 映像儲存 | [09-windows-platform.md §7](09-windows-platform.md#7-pe-映像儲存spf_pe_savef-深入解析) |
| `spf_win_con_io.f` | Windows 控制台 I/O | [09-windows-platform.md §9](09-windows-platform.md#9-windows-控制台-iospf_win_con_iof-深入解析) |
| `spf_win_io.f` | Windows 檔案 I/O | [09-windows-platform.md §8](09-windows-platform.md#8-windows-檔案-iospf_win_iof-深入解析) |
| `spf_win_except.f` | Windows 例外 façade | [09-windows-platform.md §5](09-windows-platform.md#5-例外處理與-sehspf_win_initf-深入解析) |
| `spf_win_module.f` | Windows 路徑管理（GetModuleFileName） | [09-windows-platform.md §10](09-windows-platform.md#10-模組路徑管理spf_win_modulef) |
| `spf_win_conv.f` | 編碼轉換（CharToOemBuffA, OemToCharBuffA） | [09-windows-platform.md §12](09-windows-platform.md#12-windows-平台關鍵檔案一覽) |
| `spf_win_cgi.f` | CGI 支援 | [09-windows-platform.md §12](09-windows-platform.md#12-windows-平台關鍵檔案一覽) |
| `spf_win_const.f` | Windows 常數 | [09-windows-platform.md §3.1](09-windows-platform.md#31-windows-常數spf_win_constf) |
| `spf_win_proc.f` | WINAPI: 宣告實例中心庫 | [09-windows-platform.md §2.4](09-windows-platform.md#24-winapi-宣告實例spf_win_procf) |

### 2.5 交叉編譯器與輔助檔案

| 檔案 | 主題 | 對應文件 |
|------|------|----------|
| `tc_spf.F` | 交叉編譯器主框架 | [03-cross-compiler.md](03-cross-compiler.md) |
| `tc-dl.f` | 動態連結表（編譯期） | [03-cross-compiler.md §9](03-cross-compiler.md#9-動態連結表tc-dlftc-dl-tcftc-dl-immf-深入解析) |
| `tc-dl-tc.f` | USE 命令 stub（73 bytes） | [03-cross-compiler.md §9.6](03-cross-compiler.md#96-tc-dl-tcfuse-命令) |
| `tc-dl-imm.f` | )) 和 (()) 立即字 | [03-cross-compiler.md §9.7](03-cross-compiler.md#97-tc-dl-immf--和--立即字) |
| `tc-configure-lines.f` | 換行模式設定 | [03-cross-compiler.md §14](03-cross-compiler.md#14-tc-configure-linesf行尾設定) |
| `macroopt.f` | 巨集最佳化器（5548 行） | [07-optimizer.md](07-optimizer.md) |
| `macroopt-hide.f` | 最佳化器輔助規則 | [07-optimizer.md §1.4](07-optimizer.md#14-輔助規則檔macroopt-hidef) |
| `noopt.f` | 無最佳化替代方案 | [07-optimizer.md §2](07-optimizer.md#2-nooptf--最小最佳化器) |
| `elf.f` | ELF 格式定義 | [06-build-save.md §6](06-build-save.md#6-elf-映像格式elff) |
| `xsave.f` | POSIX 交叉編譯 ELF 儲存 | [06-build-save.md §8](06-build-save.md#8-xsave--交叉編譯-elf-儲存xsavef) |
| `tsave.f` | Windows PE 儲存 | [06-build-save.md §10](06-build-save.md#10-tsave--windows-pe-儲存tsavef) |
| `done.f` | Windows 建構最終化 | [06-build-save.md §11](06-build-save.md#11-done-標記donef) |
| `forth.ld` | ELF 連結器腳本 | [06-build-save.md §7.2](06-build-save.md#72-forthld--連結器腳本) |

---

## 3. 平台對照表（POSIX vs Windows）

### 3.1 系統呼叫/FFI 對照

| 功能 | POSIX | Windows |
|------|-------|---------|
| 載入動態函式庫 | `dlopen(path, flags)` | `LoadLibraryA(path)` |
| 取得函式位址 | `dlsym(handle, name)` | `GetProcAddress(handle, name)` |
| 錯誤訊息 | `dlerror()` | `GetLastError()` |
| 呼叫約定 | cdecl（呼叫者清理） | stdcall（被呼叫者清理） |
| 外部函式宣告 | `(( ... ))` 語法 | `WINAPI:` 語法 |
| 回呼包裝 | `EXTERN` + `_WNDPROC-CODE` | `EXTERN` + `_WNDPROC-CODE`（相同） |

### 3.2 執行緒對照

| 功能 | POSIX | Windows |
|------|-------|---------|
| 建立執行緒 | `pthread_create` | `CreateThread` |
| 暫停執行緒 | `pthread_kill(SIGSTOP)` | `SuspendThread` |
| 恢復執行緒 | `pthread_kill(SIGCONT)` | `ResumeThread` |
| 取消執行緒 | `pthread_cancel` | `TerminateThread` |
| 睡眠 | `nanosleep` | `Sleep` |
| 取得執行緒 ID | `pthread_self` | `GetCurrentThreadId` |
| 終止自身 | `pthread_exit` | `ExitThread` |
| TLS 機制 | `TlsIndex!` / `TlsIndex@`（相同） | `TlsIndex!` / `TlsIndex@`（相同） |

### 3.3 記憶體管理對照

| 功能 | POSIX | Windows |
|------|-------|---------|
| 分配記憶體 | `malloc`/`calloc` | `HeapAlloc` |
| 釋放記憶體 | `free` | `HeapFree` |
| 重新配置 | `realloc` | `HeapReAlloc` |
| 可執行記憶體 | `mmap` + `mprotect` | `HeapAlloc`（天然可執行） |
| 執行緒私有堆 | — | `HeapCreate`/`HeapDestroy` |
| 分頁大小 | `sysconf(_SC_PAGESIZE)` | 4096（常數） |

### 3.4 例外處理對照

| 功能 | POSIX | Windows |
|------|-------|---------|
| 同步例外 | `sigaction`（SIGSEGV/SIGFPE 等） | SEH（`EXCEPTION_RECORD`） |
| 例外資訊 | `ucontext_t`（CONTEXT_EDI/EIP/EAX） | `EXCEPTION_POINTERS`（CONTEXT 結構） |
| 中斷訊號 | `SIGINT`（Ctrl+C） | `SetConsoleCtrlHandler` |
| 傾印函式 | `DUMP-TRACE` | `EXC-DUMP1` |
| 遞迴保護 | `IN-EXCEPTION` 變數 | `IN-EXCEPTION` 變數 |
| TLS 恢復 | `CONTEXT_EDI + @ TlsIndex!` | SEH handler 內部恢復 |

### 3.5 映像儲存對照

| 特性 | POSIX | Windows |
|------|-------|---------|
| 輸出格式 | ELF 可重定位 `.o` | PE EXE（模板式修改） |
| 輸出檔案 | `spf4.o` → gcc 連結 → `spf4` | 直接產生 `spf4.exe` |
| 關鍵檔案 | `posix/save.f`, `xsave.f`, `elf.f` | `spf_pe_save.f`, `tsave.f`, `spf_stub.f` |
| 連結器腳本 | `forth.ld`（自訂） | 無（直接修改 PE 模板） |
| 動態連結 | `.dltable`/`.dlstrings` ELF 段 | PE 匯入表（Import Table） |
| 基底位址 | `0x8050000` | `0x400000`（預設）或 `0x8050000` |

---

## 4. 編譯流程速查

### 4.1 完整建構流程（POSIX）

```forth
┌─────────────────────────────────────────────────────────────┐
│  前置：下載 spf4orig（若不存在）                               │
│       產生 posix/config.auto.f（由 config.c 偵測系統常數）    │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│  1. 載入 src/spf.f（主控腳本）                               │
│     ├── src/spf_compileoptions.f（編譯選項）                  │
│     ├── src/posix/config.auto.f（系統常數）                  │
│     ├── src/tc_spf.F（交叉編譯器框架）                       │
│     │     ├── src/macroopt.f 或 noopt.f（最佳化器）          │
│     │     └── src/tc-dl.f, tc-dl-tc.f, tc-dl-imm.f          │
│     ├── src/spf_defkern.f（定義字核心）                      │
│     ├── src/spf_forthproc.f（程序核心）                      │
│     ├── src/spf_floatkern.f（浮點核心）                      │
│     ├── src/posix/*.f（平台實作）                            │
│     └── src/compiler/*.f（編譯器子系統）                      │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│  2. 產生目標映像（記憶體中）                                  │
│     ├── TC-LATEST→ FORTH-WORDLIST（修復字詞連結）            │
│     ├── (DP) TC-ADDR!（修復字典指標）                        │
│     ├── _VOC-LIST TC-ADDR!（修復詞彙表列表）                 │
│     └── HERE .forth - TO .forth#（計算字典大小）             │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│  3. 儲存映像                                                 │
│     ├── 產生 forth.ld（連結器腳本）                          │
│     ├── 產生 spf4.o（ELF 可重定位物件）                      │
│     │     ├── ELF 標頭（0x34 bytes）                         │
│     │     ├── 段表（.forth, .space, .dltable, .dlstrings）   │
│     │     ├── 符號表（main, dlopen, dlsym, ...）             │
│     │     └── 重定位表（8 個 R_386_32 項目）                 │
│     └── gcc -m32 spf4.o -Wl,forth.ld -ldl -lpthread -o spf4  │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│  4. 產生擴充版 spf4e                                         │
│     echo '10 1024 * 1024 * S" ../spf4e" SAVE-WITH-RESERVE BYE' │
│     | ./spf4 lib/ext/spf4e.f                                 │
│     （預留 10 MiB 字典空間）                                  │
└─────────────────────────────────────────────────────────────┘
```

### 4.2 載入順序（spf.f）

```forth
spf.f
  ├── 版本常數（429）
  ├── 相容性補丁（CS-DUP, PARSE-NAME 等）
  ├── lib/ext/spf-asm.f（組合語言套件）
  ├── src/spf_compileoptions.f（編譯選項）
  ├── CASE ... ENDCASE 定義
  ├── 記憶體映像設定（IMAGE-SIZE, IMAGE-START）
  ├── src/posix/config.auto.f 或 Windows 對應檔
  ├── src/spf_date.f（建置日期）
  ├── src/spf_xmlhelp.f（XML 說明產生器）
  ├── src/tc_spf.F（交叉編譯器框架）
  │     ├── src/tc-dl.f, tc-dl-tc.f, tc-dl-imm.f
  │     ├── src/macroopt.f 或 noopt.f（第一次載入）
  │     └── 目標字定義系統
  ├── src/spf_defkern.f（定義字核心原語）
  ├── src/spf_forthproc.f（Forth 程序核心）
  ├── src/spf_floatkern.f（浮點運算核心）
  ├── src/spf_forthproc_hl.f（高階 Forth 程序）
  ├── src/posix/*.f 或 src/win/*.f（平台 API）
  ├── src/spf_except.f（例外 façade）
  ├── src/spf_con_io.f（控制台 I/O façade）
  ├── src/spf_print.f（數值輸出）
  ├── src/spf_module.f（模組管理 façade）
  ├── src/compiler/*.f（編譯器子系統，19 個檔案）
  ├── src/macroopt.f 或 noopt.f（第二次載入，BUILD-OPTIMIZER）
  ├── src/spf_init.f（系統初始化）
  └── src/xsave.f 或 src/done.f + src/tsave.f（映像儲存）
```

---

## 5. 核心資料結構速查

### 5.1 Forth 字詞記憶體佈局

```forth
         ←── 低位址                                              高位址 ──→
┌────────┬──────────────┬───────┬────────────┬───────────────────────────┐
│ flags  │ 名稱 (可變長度) │ LFA(4) │ CALL rel32 │         PFA              │
│ (1 B)  │              │        │   (5 B)    │   （定義類型決定的資料）    │
└────────┴──────────────┴───────┴────────────┴───────────────────────────┘
 ↑                                              ↑
NFA（名稱欄位位址）                             此處 + 5 bytes = PFA 起始
```

**名稱欄位存取子**：
- `NAME>C` (nt → cfa-addr)：CFA 位址 = NFA - 5
- `NAME>F` (nt → flags-addr)：旗標位址 = NFA - 1
- `NAME>L` (nt → lfa-addr)：LFA 位址 = NFA + len + 1
- `NAME>` (nt → xt)：xt = [NFA - 5]（PFA 位址）

### 5.2 詞彙表（WORDLIST）結構

```forth
wid 指向的記憶體佈局：

  -4 [wid]    VOC-LIST link（隱藏前置欄位）
   0 [wid]    HEAD：指向最新字詞的 nt
   4 [wid]    CSTRING：詞彙表名稱
   8 [wid]    PAR：父詞彙表（parent）
  12 [wid]    CLASS：類別
  16 [wid]    WID-EXTRA：延伸欄位起點
```

### 5.3 輸入緩衝區（TIB）結構

```forth
USER 變數：
  #TIB    → 輸入緩衝區字元數（行長度）
  >IN     → 輸入流偏移量（目前解析位置）
  TIB     → 輸入緩衝區起始位址（USER-VALUE，可重定向）

SOURCE-ID 值：
  0   → 終端機（stdin）
  -1  → EVALUATE 字串
  >0  → 檔案 handle
```

### 5.4 例外處理鏈

```forth
回返堆疊（由 ESP 指向）：

  CATCH 設定後：
    ESP+12  → 迴圈界限（若無則為返回位址）
    ESP+8   → 前一個 HANDLER
    ESP+4   → SP@（資料堆疊指標，CATCH 時儲存）
    ESP+0   → 返回位址

THROW 時：
  1. HANDLER @ 取得 CATCH 時的 RP@
  2. RP! 恢復回返堆疊
  3. 從堆疊取出 SP@ 和前一個 HANDLER
  4. SP! 恢復資料堆疊
  5. 將例外碼推上資料堆疊
  6. EXIT（跳回 CATCH 之後）
```

---

## 6. 常見錯誤碼對照

| 錯誤碼 | 名稱 | 說明 | 常見來源 |
|--------|------|------|----------|
| 0 | 無錯誤 | CATCH 正常返回 | CATCH |
| -1 | ABORT | 一般中斷 | `ABORT` 字 |
| -2 | ABORT" | 帶訊息中斷 | `ABORT"` |
| -3 | 編譯狀態錯誤 | 僅允許在編譯狀態 | `?COMP` |
| -4 | 堆疊下溢 | 堆疊超出 S0 範圍 | `?STACK` |
| -9 | 記憶體存取違規 | SIGSEGV/SIGILL | POSIX 信號 |
| -10 | 整數除以零 | SIGFPE(FPE_INTDIV) | 算術運算 |
| -11 | 整數溢位 | SIGFPE(FPE_INTOVF) | 算術運算 |
| -12 | 引數型態不符 | Forth 標準 | 型態檢查 |
| -13 | 未定義字 | `SFIND` 找不到 | 字詞查找 |
| -17 | 記憶體空間不足 | `HOLD` 緩衝區溢位 | 數值格式化 |
| -23 | 匯流排錯誤 | SIGBUS | POSIX 信號 |
| -27 | 包含巢狀過深 | `INCLUDE-DEPTH > 64` | 巢狀載入 |
| -1002 | 管線/輸入結束 | `ACCEPT1` | 輸入結束 |
| -2001 | 數字解析失敗 | `?SLITERAL` | 數字轉換 |
| -2003 | 字詞未找到 | `EVAL-WORD` | 直譯器 |
| -2010 | 程序未找到 | Windows | `WINAPI:` |
| -2011 | 詞彙表未找到 | `NOTFOUND` | 詞彙表限定語法 |

---

## 7. 編譯選項速查

定義於 `src/spf_compileoptions.f`，可由 `src/compile.ini` 覆寫：

| 選項 | 預設值 | 說明 |
|------|--------|------|
| `CREATE-XML-HELP` | FALSE | 產生 `spfhelp.xml` 說明檔 |
| `ARCH-P6` | TRUE | 使用 P6（Pentium Pro+）指令集（CMOV 等） |
| `BUILD-OPTIMIZER` | TRUE | 建構時包含最佳化器 |
| `USE-OPTIMIZER` | TRUE | 建構過程中使用最佳化 |
| `OPTIMIZE-BY-SIZE` | FALSE | TRUE = 1 位元組對齊（大小最佳化）；FALSE = 4 位元組對齊（速度） |
| `WIDE-CHAR` | FALSE | TRUE = 使用 2 位元組字元 |
| `SMALLEST-SPF` | FALSE | TRUE = 關閉最佳化器，最小化映像 |
| `UNIX-ENVIRONMENT` | 自動 | TRUE = 使用 LF 換行 |
| `TARGET-POSIX` | 自動 | TRUE = 目標平台為 POSIX |

---

## 8. ANS Forth / SP-Forth 支援速查

SP-Forth/4 的定位是 **Forth-94 compatible**，但不是「只含標準字」的最小系統；它同時包含大量 SP-Forth extension 與平台相關字。若要最大化 ANS 相容性，專案既有文件建議載入：

```forth
REQUIRE ANSI lib/include/ansi.f
```

其中 `lib/include/ansi.f` 會補入多個標準相容性檔案，例如 `core-ext.f`、`string.f`、`double.f`、`ansi-file.f`、`tools.f`、`defer.f`、`control-case.f` 等。`spf4e` 則是擴充版執行檔：包含可用的標準字與大小寫不敏感搜尋，但 **BLOCK word set 不在預設 spf4e 內**，需另外看 `lib/include/ansi-block.f`。

> 注意：下表是「trace 閱讀與維護」用的能力地圖，不是正式標準認證報告。更細的 ANS system documentation 請對照 `docs/ans.en.mdt`、`docs/intro.en.md` 與 `lib/include/ansi.f`。

### 8.1 Word set / extension matrix

| 類別 | 狀態 | 主要來源 / 載入點 | trace 對應 |
|------|------|-------------------|------------|
| CORE | 內建核心 | `src/spf_forthproc.f`, `src/spf_defkern.f`, compiler 基礎檔 | [01-kernel.md](01-kernel.md), [02-compiler.md](02-compiler.md) |
| CORE EXT | 部分內建，部分由 `ansi.f` 補齊 | `lib/include/core-ext.f`，如 `MARKER`, `SAVE-INPUT`, `RESTORE-INPUT`, `U.R`, `UNUSED`, `BUFFER:` | [02-compiler.md](02-compiler.md), [05-io-error-init.md](05-io-error-init.md) |
| SEARCH | 內建搜尋順序 / wordlist 支援 | `src/compiler/spf_wordlist.f`, `src/compiler/spf_find.f` | [02-compiler.md §6](02-compiler.md#6-搜尋引擎spf_findf-spf_find_cdrf-深入解析)、[§7](02-compiler.md#7-詞彙表管理spf_wordlistf-深入解析) |
| STRING | 由核心與 include 檔補齊 | `CMOVE`, `CMOVE>` 內建；`lib/include/string.f` 補 `/STRING`, `BLANK` 等 | [01-kernel.md](01-kernel.md), [02-compiler.md](02-compiler.md) |
| DOUBLE | include 檔提供 | `lib/include/double.f` | [13-verification.md §2](13-verification.md#2-primitive-驗證) |
| FLOATING | 浮點核心與 include 檔 | `src/spf_floatkern.f`, `lib/include/float*.f` | [01-kernel.md §4](01-kernel.md#4-浮點運算核心spf_floatkernf-深入解析) |
| FILE | 平台 I/O + ANS 相容修正 | `src/posix/io.f`, `src/win/*io*.f`, `lib/include/ansi-file.f` | [04-posix-platform.md](04-posix-platform.md), [05-io-error-init.md](05-io-error-init.md), [09-windows-platform.md](09-windows-platform.md) |
| FACILITY | include 檔補充常用字 | `lib/include/facil.f`，例如 `TIME&DATE` | [05-io-error-init.md](05-io-error-init.md) |
| TOOLS | include 檔提供條件編譯等工具 | `lib/include/tools.f`，如 `[IF]`, `[ELSE]`, `[THEN]` | [02-compiler.md](02-compiler.md) |
| BLOCK | 可選，不在預設 spf4e | `lib/include/ansi-block.f` | 建議另查 source；trace 目前未深入展開 |
| EXCEPTION | 內建 `CATCH` / `THROW` 與平台 signal/SEH bridge | `src/spf_except.f`, POSIX signal, Windows SEH | [05-io-error-init.md §4](05-io-error-init.md#4-例外處理spf_exceptf), [12-debugging.md](12-debugging.md) |
| LOCALS | 有核心支援片段，但使用面需對照 include / extension | `N>R` / `NR>` 等 primitive，相關 locals library | [01-kernel.md §3.7](01-kernel.md#37-locals區域變數原語) |
| SP-Forth FFI | 非 ANS extension，SP-Forth 平台能力 | POSIX `EXTERN` / `(( ... ))`，Windows `WINAPI:` | [04-posix-platform.md](04-posix-platform.md), [09-windows-platform.md](09-windows-platform.md), [13-verification.md §6](13-verification.md#6-ffi-安全檢查) |
| SP-Forth image save | 非 ANS extension，系統能力 | `SAVE`, `SAVE-WITH-RESERVE`, ELF/PE writer | [06-build-save.md](06-build-save.md), [15-standalone-executable.md](15-standalone-executable.md) |
| SP-Forth optimizer | 非 ANS extension，native code generation 能力 | `macroopt.f`, `noopt.f` | [07-optimizer.md](07-optimizer.md) |

### 8.2 驗證與測試線索

| 目的 | 入口 |
|------|------|
| 最大 ANS 相容載入 | `lib/include/ansi.f` |
| FILE word set 相容修正 | `lib/include/ansi-file.f` |
| BLOCK word set | `lib/include/ansi-block.f` |
| CORE 測試樣本 | `samples/ans/tester.f` |
| ANS system documentation 模板 | `docs/ans.en.mdt` |
| SP-Forth extension 說明 | `docs/intro.en.md`, `docs/devel.en.md` |

---

## 9. Forth 基礎概念速查（給初學者）

本文件預設讀者已熟悉 ANS Forth 94。若你是 Forth 新手，以下最小知識能幫助你理解 trace 內容；完整學習請參考 "Starting Forth" (Brodie) 或 "Thinking Forth" (Brodie)。

### 9.1 堆疊模型

Forth 使用兩個堆疊：**資料堆疊**（Data Stack，SP-Forth 中 TOS 快取於 EAX，EBP 為指標）與**回返堆疊**（Return Stack，對應 ESP）。堆疊注記 `( before -- after )` 左側為執行前（底→頂），右側為執行後。

### 9.2 字詞與字典

每個關鍵字稱為一個**字詞**（word，相當於函式），存於**字典**（單向鏈結串列）。字典項結構：

| 欄位 | 說 明 | 取得方式 |
|------|-------|----------|
| NFA（名稱欄位） | 長度前綴 + 字詞名稱 | `>NAME` |
| LFA（鏈結欄位） | 指向前一個字典項 | `>LINK` |
| CFA（執行碼欄位） | 指向機器碼入口 | `>CODE` |
| PFA（參數欄位） | 字詞的資料/參數 | `>BODY` |

`' name` 取得 name 的 XT（執行令牌，即指向 CFA 的指標）；`EXECUTE` 接收 XT 並執行。

### 9.3 編譯 vs 直譯

| 概念 | 說 明 |
|------|-------|
| `STATE` | 0 = 直譯模式，非 0 = 編譯模式 |
| `[` / `]` | 切換到直譯模式 / 切回編譯模式 |
| `: name ... ;` | 定義新字詞（進入編譯，`;` 結束並回直譯） |
| `IMMEDIATE` | 標記該字在編譯模式下仍立即執行 |
| `POSTPONE name` | 將 name 的編譯語意推遲至執行期 |
| `COMPILE, xt` | 在編譯期將 xt 編入字典 |

### 9.4 常見定義字

| 字 | 效 果 |
|---|--------|
| `VARIABLE name` | 建立一個 cell 的變數（執行回傳位址） |
| `CONSTANT name` | 建立常數（執行回傳值） |
| `USER name` | 執行緒私有變數（以 EDI 為基底偏移） |
| `VALUE name` | 可寫的常數（`TO name` 改值） |
| `CREATE name` | 建立字典項，留參數空間；可用 `DOES>` 自訂執行行為 |

關於 `DOES>`：`CREATE name ... DOES> body` — `name` 被呼叫時執行 `body`，`body` 可存取 `name` 的 PFA 區域。SP-Forth 使用 `(DOES1)`/`(DOES2)` 實作（見 [02-compiler.md §9](02-compiler.md#9-定義字spf_defwordsf-深入解析)）。

### 9.5 例外與向量

| 字 | 效 果 |
|---|--------|
| `CATCH` | 執行 XT，捕獲內部 `THROW` |
| `THROW n` | 拋出例外號碼；0 不拋出 |
| `VECT name` | 宣告可重定向的字（同 `DEFER`） |
| `' xt TO name` | 設定 VECT 的行為 |

詳見 [05-io-error-init.md §4](05-io-error-init.md#4-例外處理spf_exceptf)。

### 9.6 除錯與驗證入口

| 任務 | 優先閱讀 |
|------|----------|
| 建構失敗、啟動崩潰、FFI/callback 崩潰 | [12-debugging.md](12-debugging.md) |
| 修改 primitive 後確認 stack effect | [13-verification.md §2](13-verification.md#2-primitive-驗證) |
| 修改 compiler / immediate words 後確認 backpatch | [13-verification.md §3](13-verification.md#3-compiler-與-wordlist-驗證) |
| 修改 optimizer 後做 macroopt/noopt A/B | [13-verification.md §4](13-verification.md#4-optimizer-等價性檢查) |
| 修改 POSIX/Windows FFI 後檢查 ABI safety | [13-verification.md §6](13-verification.md#6-ffi-安全檢查) |
| 從一個小程式串起整條 trace 路徑 | [14-walkthrough.md](14-walkthrough.md) |
| 產生不需外部 interpreter 的獨立 executable | [15-standalone-executable.md](15-standalone-executable.md) |

### 9.7 參考

- [00-overview.md §8](00-overview.md#8-核心術語速查) — 核心術語對照表
- **"Starting Forth"** (Leo Brodie) — 經典免費入門書
- **"Thinking Forth"** (Leo Brodie) — 設計哲學

---

## 10. 版本與授權資訊

- **系統名稱**：SP-Forth/4（ SPF4 ）
- **核心版本**：429（定義於 `src/spf.f` 第 3 行）
- **版權**：Copyright [C] 1992-2000 A.Cherezov ac@forth.org
- **專案網站**：https://github.com/rufig/spf
- **文件語言**：繁體中文（台灣資訊科技產業慣用術語）

---

**文件版本**：與 SP-Forth kernel version 429 對應

**編輯建議**：本文件為速查參考，詳細說明請參閱對應主題文件。若發現錯誤或過時資訊，請對照原始碼確認。
