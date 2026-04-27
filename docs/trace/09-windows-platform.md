# SP-Forth/4 原始碼追蹤 — Windows 平台支援深入解析

> 對應原始碼：`src/win/` 目錄下所有檔案
> 原始碼版權：Copyright [C] 1992-1999 A.Cherezov ac@forth.org

> 閱讀提示：本文件聚焦 **Windows 平台實作、PE 格式、SEH 例外處理與 Windows API 呼叫**。若你想看較高層的 I/O、初始化與例外生命週期，請接續閱讀 [05-io-error-init.md](05-io-error-init.md)。與 POSIX 平台（見 [04-posix-platform.md](04-posix-platform.md)）的對照，請見 §9。

---

## 1. Windows API 呼叫機制（spf_win_api.f）深入解析

### 1.1 與 POSIX FFI 的本質差異

POSIX 使用 `dlopen`/`dlsym` 動態載入共享函式庫（`.so`），而 Windows 使用**靜態匯入表**（import table）機制。在 SP-Forth 的 Windows 版中，所有外部 DLL 函式都透過 `LoadLibraryA`＋`GetProcAddress` 在執行期解析，並快取在 `WINAPLINK` 表中。

```
POSIX：                          Windows：
dlopen("lib.so") ──→ dlsym ──→  LoadLibraryA("kernel32.dll")
                                 GetProcAddress(h, "CreateThread")
```

### 1.2 AO_INI：WinAPI 初始化（spf_win_api.f:18-44）

```asm
CODE AO_INI ( adr -- adr|EAX )
      MOV  EBX, EAX
      MOV  EAX, 4 [EBX]        ; EAX = 函式名稱位址
      PUSH EAX
      A; 0xA1 C, AddrOfLoadLibrary  ; MOV EAX, [addr]
      CALL EAX                  ; LoadLibraryA(名稱)
      OR   EAX, EAX
      JZ   @@1                 ; 找不到 DLL → LIB-ERROR
      MOV  ECX, 8 [EBX]        ; ECX = 函式名稱位址
      PUSH ECX
      PUSH EAX                 ; EAX = DLL handle
      A; 0xA1 C, AddrOfGetProcAddress ; MOV EAX, [addr]
      CALL EAX                 ; GetProcAddress(h, 函式名)
      OR   EAX, EAX
      JZ   @@2                 ; 找不到函式 → PROC-ERROR
      RET
@@2:  MOV   EAX, EBX
      JMP ' PROC-ERROR         ; 跳到錯誤處理
@@1:  MOV   EAX, EBX
      JMP ' LIB-ERROR
END-CODE
```

**關鍵設計**：`AO_INI` 使用內嵌位址（`AddrOfLoadLibrary`）直接指向 PE 匯入表中已解析的函式位址，而非透過 `TlsIndex!` 機制。這與 POSIX 使用 `dlopen`/`dlsym` 的延遲解析方式不同。

### 1.3 API-CALL：stdcall 呼叫約定（spf_win_api.f:46-69）

```asm
CODE API-CALL ( ... extern-addr -- x )
      PUSH EDI
      PUSH EBP
      SUB  ESP, # 60            ; 分配 60 bytes 工作區
      MOV  EBX, EDI             ; 儲存 Forth EDI
      MOV  EDI, ESP             ; EDI = 新堆疊
      MOV  ESI, EBP             ; ESI = Forth 資料堆疊
      MOV  ECX, # 15
      CLD
      REP MOVS DWORD            ; 複製 15 個 DWORD（60 bytes）到工作區
      MOV  EBP, ESP             ; EBP = 新堆疊框架
      MOV  EDI, EBX             ; 恢復 Forth EDI
      CALL EAX                  ; 呼叫 Win32 API
      MOV  EBX, EBP             ; 計算堆疊調整量
      SUB  EBX, ESP
      MOV  ESP, EBP
      ADD  ESP, # 60            ; 清理工作區
      POP EBP                   ; 恢復 Forth EBP（EBP = 新 EBP - 調整量）
      SUB EBP, EBX              ; 調整 EBP 回原始位置
      POP EDI                   ; 恢復 Forth EDI
      RET
END-CODE
```

**stdcall vs cdecl**：Windows API 使用 `stdcall` 呼叫約定（被呼叫者清理堆疊），與 POSIX 的 cdecl（呼叫者清理）不同。`API-CALL` 手動管理堆疊框架，切換到一個獨立的 60 bytes 工作區，避免與 Forth 資料堆疊衝突。

### 1.4 _WINAPI-CODE：延遲解析包裝（spf_win_api.f:71-84）

```asm
CODE _WINAPI-CODE
      POP  EBX                  ; 取得返回位址（_WINAPI-CODE 的 caller）
      MOV  -4 [EBP], EAX        ; 儲存回傳值到 PFA
      MOV  EAX, [EBX]           ; 讀取外部函式位址
      OR   EAX, EAX
      LEA  EBP, -4 [EBP]        ; 推入回傳值到堆疊
      JNZ  SHORT @@1            ; 已解析 → 直接呼叫
      MOV  EAX, EBX
      CALL ' AO_INI             ; 呼叫 AO_INI 解析
      JZ   SHORT @@2            ; 解析失敗
      MOV  [EBX], EAX            ; 儲存解析後的位址
@@1:  JMP  ' API-CALL           ; 呼叫 API-CALL
@@2:  RET                       ; 失敗則返回
END-CODE
```

**延遲解析模式**：`_WINAPI-CODE` 的 PFA 初始值為 0；第一次呼叫時呼叫 `AO_INI` 解析並快取，後續呼叫直接使用快取的位址。

### 1.5 _WNDPROC-CODE：共用回呼橋接器（spf_win_api.f:88-119）

Windows 版的 `_WNDPROC-CODE` 與 POSIX 版實質相同（兩者共享同一個橋接器概念），但包裝的 API 不同：

```asm
CODE _WNDPROC-CODE
      MOV  EAX, ESP
      SUB  ESP, # 3968          ; 分配 ~4 KiB Forth 資料堆疊
      ; ... 儲存暫存器 ...
      MOV  EBP, 4 [EAX]         ; 取得第一個回呼參數
      PUSH EBP
      MOV  EBP, EAX
      ADD  EBP, # 12            ; 設定 Forth EBP
      ; ... 儲存 EBX,ECX,EDX,ESI,EDI ...
      MOV  EAX, [EAX]           ; 取得 Forth XT
      MOV  EBX, [EAX]           ; 讀取 CFA
      MOV  EAX, -4 [EBP]        ; 取得回呼參數
      CALL EBX                  ; 呼叫 Forth word
      ; ... 恢復暫存器 ...
      XCHG EAX, [ESP]           ; 交換回傳值與返回位址
      RET
END-CODE
```

**與 POSIX 的對稱性**：在 POSIX 中，`FORTH-INSTANCE>` / `<FORTH-INSTANCE` 透過 `TlsIndex!` 設定/恢復 EDI（TLS 基底）；在 Windows 中，TLS 機制由 `TlsIndex!` / `TlsIndex@` 同樣提供，但 SEH 例外處理使用不同的恢復路徑。

---

## 2. WINAPI: 外部函式宣告（spf_win_defwords.f）深入解析

### 2.1 __WIN: 內部 Helper

```forth
: __WIN: ( params "library" "function" -- )
  HERE >R
  0 , 0 , 0 , ,                 ; 預留空間：winproc, libname, funcname, 參數數量
  IS-TEMP-WL 0=
  IF
    HERE WINAPLINK @ , WINAPLINK !   ; 加入 WINAPLINK 鏈
  THEN
  PARSE-NAME ... S" kernel32.dll" ...
  LoadLibraryA DUP 0= IF -2009 THROW THEN
  GetProcAddress 0= IF -2010 THROW THEN
;
```

**WINAPLINK 鏈**：`WINAPLINK` 維護一個所有已宣告的 WinAPI 函式的鏈表，每個 entry 包含：winproc 位址（遲遲解析）、DLL 名稱、函式名稱、參數數量。`ERASE-IMPORTS` 遍歷此鏈並清除所有 winproc 位址，強制重新解析。

### 2.2 WINAPI: 與 EXTERN 的對比

| 特性 | POSIX (`EXTERN`) | Windows (`WINAPI:`) |
|------|------------------|---------------------|
| 語法 | `xt n EXTERN` | `WINAPI: libname funcname` |
| 解析時機 | 第一次呼叫時（延遲） | 定義時立即解析 |
| 匯入機制 | `dlopen`/`dlsym` | `LoadLibraryA`/`GetProcAddress` |
| 呼叫約定 | cdecl | stdcall |
| 錯誤處理 | `dl-no-library`/`dl-no-symbol` | `LIB-ERROR`/`PROC-ERROR` |

### 2.3 Windows EXTERN（spf_win_defwords.f:52-58）

```forth
: EXTERN ( xt1 n -- xt2 )
  HERE
  SWAP LIT,                      ; 編譯引數數量
  ['] FORTH-INSTANCE> COMPILE, ; 進入 Forth 環境
  SWAP COMPILE,                  ; 編譯目標 XT
  ['] <FORTH-INSTANCE COMPILE,  ; 離開 Forth 環境
  RET,
;
```

與 POSIX 版相同，但 `FORTH-INSTANCE>` / `<FORTH-INSTANCE` 在 Windows 上使用不同的 TLS 實作。

### 2.4 CALLBACK:、WNDPROC:、TASK:

```forth
: CALLBACK: ( xt n "name" -- )
  EXTERN                        ; 建立包裝器
  HEADER
  ['] _WNDPROC-CODE COMPILE,  ; 設定 WNDPROC 進入點
  ,
;

: WNDPROC: ( xt "name" -- )
  4 CELLS CALLBACK:             ; Windows 訊息處理器（4 個參數）
;

: TASK ( xt1 -- xt2 )
  CELL EXTERN
  HERE SWAP
  ['] _WNDPROC-CODE COMPILE,
  ,
;
```

這三個字與 POSIX 版完全對稱，差異僅在 `_WNDPROC-CODE` 內部棧楨設定。

---

## 3. 記憶體管理（spf_win_memory.f）深入解析

### 3.1 Windows Heap API 對比 POSIX malloc

Windows 版使用 `HeapCreate`/`HeapAlloc` 而非 `malloc`/`mmap`：

| POSIX | Windows | 說明 |
|-------|--------|------|
| `malloc`/`calloc` | `HeapAlloc` | 分配記憶體 |
| `free` | `HeapFree` | 釋放記憶體 |
| `realloc` | `HeapReAlloc` | 重新配置 |
| `mmap`(MAP_ANONYMOUS) | `HeapAlloc` | 配置匿名記憶體 |
| — | `HeapCreate`/`HeapDestroy` | 建立/銷毀私有堆 |

### 3.2 執行緒堆積（spf_win_memory.f:50-63）

```forth
: SET-HEAP ( heap-id -- )
  >R
  USER-OFFS @ EXTRA-MEM @ CELL+ + 8 R@
  HeapAlloc DUP
  IF
     CELL+ TlsIndex!             ; 設定 TLS 基底
     R> THREAD-HEAP !
     R> R@ TlsIndex@ CELL- ! >R ; 在 TLS 區塊前寫入返回位址
  ELSE
     -300 THROW
  THEN
;

: CREATE-HEAP ( -- )
  0 8000 1 HeapCreate SET-HEAP   ; 程式碼執行屬性的私有堆
;

: CREATE-PROCESS-HEAP ( -- )
  0 8000 0 HeapCreate SET-HEAP   ; 程序預設堆
;
```

**TLS 整合**：`TlsIndex!` 在 Windows 版同樣存在，用於設定執行緒的 TLS 基底指標。`HeapAlloc` 配置的記憶體區塊由 `TlsIndex!` 寫入第一個 cell，儲存回返位址。

### 3.3 ALLOCATE-RWX 的差異

```forth
: ALLOCATE-RWX ( +n -- a-addr 0 | x ior )
  MEMORY-PAGESIZE 1- CELL+ ADD-SIZE ...
  MEMORY-PAGESIZE NEGATE AND      ; 對齊到分頁邊界
  8 THREAD-HEAP @ HeapAlloc     ; Windows 不需要 mprotect
  ...
;
```

Windows 的 `HeapAlloc` 預設配置可讀寫可執行的記憶體，不需要像 POSIX 那樣使用 `mprotect` 設定分頁保護。

---

## 4. 多執行緒（spf_win_mtask.f）深入解析

### 4.1 Windows Thread API 對比 POSIX pthreads

| POSIX (`posix/mtask.f`) | Windows (`spf_win_mtask.f`) |
|-------------------------|-----------------------------|
| `pthread_create` | `CreateThread` |
| `pthread_kill(SIGSTOP)` | `SuspendThread` |
| `pthread_kill(SIGCONT)` | `ResumeThread` |
| `pthread_cancel` | `TerminateThread` |
| `nanosleep` | `Sleep` |
| `pthread_self` | `GetCurrentThreadId` |
| `pthread_exit` | `ExitThread` |

### 4.2 CreateThread 的 Forth 包裝（spf_win_mtask.f:8-14）

```forth
: START ( x task -- th )
  0 >R RP@
  0 2SWAP 0 0 CreateThread    ; lpThreadAttributes=0, dwStackSize=0, etc.
  RDROP                         ; th = EAX（執行緒 handle）
;
```

**關鍵差異**：POSIX `pthread_create` 需要傳遞 `start_routine` 和 `arg`；Windows `CreateThread` 同樣接受這些參數（經過 `WINAPLINK` 表解析）。Forth 的 `START` 將 task XT 和初始引數打包傳遞。

### 4.3 TERMINATE 與堆積銷毀

```forth
: TERMINATE ( -- )
  DESTROY-HEAP                  ; 銷毀執行緒私有堆
  -1 ExitThread                 ; 終止執行緒
;
```

Windows 版的 `TERMINATE` 在結束前銷毀執行緒堆積（`DESTROY-HEAP`），而 POSIX 版僅呼叫 `pthread_exit`。

---

## 5. 例外處理與 SEH（spf_win_init.f）深入解析

### 5.1 結構化例外處理（SEH）對比 POSIX 信號

| POSIX | Windows SEH |
|-------|-------------|
| `sigaction` | `SetUnhandledExceptionFilter` |
| `ucontext_t` | `EXCEPTION_POINTERS` |
| `CONTEXT_EDI` 等偏移 | 透過 `CONTEXT` 結構體成員 |
| `signum>ior` | 例外碼直接對應 Forth 例外 |
| `SA_SIGINFO` | `EXCEPTION_RECORD` |

### 5.2 EXC-DUMP1（spf_win_init.f:40-66）

```forth
: EXC-DUMP1 ( exc-info -- )
  IN-EXCEPTION @ IF DROP EXIT THEN  ; 防止遞迴
  TRUE IN-EXCEPTION !

  DUP 3 CELLS + @ OVER @ ( addr num ) DUMP-EXCEPTION-HEADER
  DROP 2 PICK

  8 CELLS 80 + 11 CELLS +         ; 跳到通用暫存器區域
  AT-EXC-DUMP                       ; 可擴充傾印點

  R> R@ 10 CELLS + @ ( esp )      ; 從 Context 提取 ESP
  R@ 5 CELLS + @ ( eax )          ; 提取 EAX
  R@ 6 CELLS + @ ( ebp )           ; 提取 EBP
  DUMP-TRACE-USING-REGS
  FALSE IN-EXCEPTION !
;
```

`EXC-DUMP1` 從 Windows 的 `EXCEPTION_POINTERS` 結構（`ContextRecord`）中提取暫存器，產生堆疊追蹤傾印。

### 5.3 PROCESS-INIT 的 SEH 設定（spf_win_init.f:16-22）

```forth
: PROCESS-INIT ( n -- )
  ERASE-IMPORTS
  CREATE-PROCESS-HEAP
  <SET-EXC-HANDLER>          ; 設定 SEH 處理器
  POOL-INIT
  ['] AT-PROCESS-STARTING ERR-EXIT
;
```

Windows 版不同於 POSIX：
- 無 `dl-init`（動態連結在 Windows 上是靜態匯入）
- 無 `set-errsignal-handler`（SEH 取代信號處理）
- 無 `ALLOCATE-THREAD-MEMORY`（每個執行緒有獨立 Heap）

---

## 6. 環境查詢與錯誤處理（spf_win_envir.f）

### 6.1 ENVIRONMENT? 的三層搜尋

與 POSIX 版相同結構，但第一層使用 `GetEnvironmentVariableA` 而非 `getenv`：

```forth
: ENVIRONMENT? ( c-addr u -- false | i*x true )
  NUMERIC-OUTPUT-LENGTH SYSTEM-PAD 2OVER DROP
  GetEnvironmentVariableA           ; Windows API
  DUP IF NIP NIP SYSTEM-PAD SWAP TRUE EXIT THEN DROP
  ; ... (後續與 POSIX 相同)
;
```

### 6.2 LIB-ERROR1 與 PROC-ERROR1

```forth
: LIB-ERROR1 ( addr_winapi_structure )
    CELL+ @ ASCIIZ>
    S" Forth: Can't load a library " (PREPEND-ERRMSG)
    THROW-ERRMSG
;

: PROC-ERROR1 ( addr_winapi_structure )
    DUP CELL+ @ ASCIIZ> ROT
    CELL+ CELL+ @ ASCIIZ>
    S" Forth: Can't find a proc " (PREPEND-ERRMSG)
    S"  in a library " 2SWAP (PREPEND-ERRMSG)
    (PREPEND-ERRMSG)
;
```

這兩個錯誤處理字與 `AO_INI` 的 `LIB-ERROR` / `PROC-ERROR` 向量對應，在 DLL 或函式解析失敗時呼叫。

---

## 7. PE 映像儲存（spf_pe_save.f）深入解析

### 7.1 與 POSIX ELF 儲存的架構差異

| 特性 | POSIX (`posix/save.f`) | Windows (`spf_pe_save.f`) |
|------|------------------------|--------------------------|
| 格式 | ELF 可重定位 `.o` | PE EXE（模板式） |
| 輸出 | 呼叫 gcc 連結 | 修改現有 PE 模板 |
| 動態連結 | `.dltable`/`.dlstrings` | 匯入表（import table） |
| 重定位 | ELF relocations | PE relocations |
| 基底位址 | `IMAGE-START`=0x8050000 | `IMAGE-BASE`=0x400000 |

### 7.2 PE 模板機制

Windows 版不像 POSIX 那樣從頭建立 ELF 檔案，而是：
1. 讀取一個**預先存在的 PE 模板**（`spf.exe` 殼層，見 `spf_stub.f`）
2. 修改其中的關鍵欄位（EntryPoint、ImageBase、ImageSize）
3. 將 Forth 字典資料寫入程式碼段
4. 修補 `LoadLibraryA`/`GetProcAddress` 的匯入位址

### 7.3 SAVE 的 PE 修改流程（spf_pe_save.f:24-51）

```forth
: SAVE ( c-addr u -- )
  R/W CREATE-FILE THROW >R
  ModuleName R/O OPEN-FILE-SHARED THROW >R  ; 開啟 PE 模板
  HERE 400 R@ READ-FILE THROW 400 < THROW  ; 讀取 PE 標頭
  R> CLOSE-FILE THROW

  ; 修改 PE 標頭欄位：
  ?GUI IF 2 ELSE 3 THEN HERE 0DC + C!     ; Subsystem（主控台/GUI）
  2000 HERE A8 + !                           ; EntryPointRVA
  IMAGE-BEGIN 2000 - HERE B4 + !            ; ImageBase
  IMAGE-SIZE 2000 + HERE D0 + !             ; ImageSize
  IMAGE-BEGIN HERE OVER - ...               ; VirtualSize
  ...                                        ; 更多欄位

  ; 寫出修改後的 PE
  HERE 400 R@ WRITE-FILE THROW               ; 寫入 PE 標頭
  HERE 200 ERASE                             ; 清零空間
  IMAGE-BEGIN HERE OVER - R@ WRITE-FILE     ; 寫入 Forth 字典
  R> CLOSE-FILE THROW
;
```

---

## 8. 模組路徑管理（spf_win_module.f）

Windows 版使用 `GetModuleFileNameA` 取得模組路徑：

```forth
: ModuleName ( -- addr u )
  SYSTEM-PAD 256 GetModuleFileNameA
  DUP 0= IF DROP 0 THEN
  SYSTEM-PAD SWAP
;
```

`is_path_delimiter` 在 Windows 上同時檢查 `\` 和 `/`：

```forth
: is_path_delimiter ( c -- flag )
  [CHAR] \ =  [CHAR] / = OR
;
```

---

## 9. Windows vs POSIX 對照總結

### 9.1 FFI 機制對照

```
POSIX：                              Windows：
dlopen("lib.so") ──→ dlsym ──→     LoadLibraryA("DLL")
                                   GetProcAddress(h, "func")
WINAPLINK 鏈 ← AO_INI ──→         WINAPLINK 鏈
```

### 9.2 TLS 機制對照

兩者都使用 `TlsIndex!` / `TlsIndex@` 原語，但：

| 方面 | POSIX | Windows |
|------|-------|---------|
| TLS 分配 | `ALLOCATE-THREAD-MEMORY` + `calloc` | `CREATE-HEAP` + `HeapAlloc` |
| TLS 解除 | `FREE-THREAD-MEMORY` | `DESTROY-HEAP` |
| 例外時恢復 | `CONTEXT_EDI + @ TlsIndex!` | SEH `EXCEPTION_POINTERS` |

### 9.3 例外處理對照

| 方面 | POSIX | Windows |
|------|-------|---------|
| 同步例外 | `sigaction`（SIGSEGV/SIGFPE 等） | SEH（`EXCEPTION_RECORD`） |
| 非同步訊號 | `SIGINT` 等 | `SetConsoleCtrlHandler` |
| 傾印 | `DUMP-TRACE` | `EXC-DUMP1` |
| 遞迴保護 | `IN-EXCEPTION` | `IN-EXCEPTION` |

### 9.4 執行緒對照

| 方面 | POSIX | Windows |
|------|-------|---------|
| 建立 | `pthread_create` | `CreateThread` |
| 暂停/恢復 | `SIGSTOP`/`SIGCONT` | `SuspendThread`/`ResumeThread` |
| 睡眠 | `nanosleep` | `Sleep` |
| 終止 | `pthread_exit` | `ExitThread` + `DESTROY-HEAP` |
| ID | `pthread_self` | `GetCurrentThreadId` |

### 9.5 記憶體對照

| 方面 | POSIX | Windows |
|------|-------|---------|
| 堆積 API | `malloc`/`free` | `HeapAlloc`/`HeapFree` |
| 私有堆 | — | `HeapCreate` |
| 可執行記憶體 | `mmap` + `mprotect` | `HeapAlloc`（天然可執行） |
| 除錯標記 | `FIX-MEMTAG` | `FIX-MEMTAG` |

---

## 10. Windows 平台關鍵檔案一覽

| 檔案 | 主題 | 對應 POSIX 檔案 |
|------|------|----------------|
| `spf_win_api.f` | API 呼叫、CALLBACK 橋接 | `posix/api.f` |
| `spf_win_defwords.f` | WINAPI:、EXTERN、CALLBACK:、TASK | `posix/defwords.f` |
| `spf_win_mtask.f` | 多執行緒（CreateThread 等） | `posix/mtask.f` |
| `spf_win_memory.f` | HeapCreate/HeapAlloc | `posix/memory.f` |
| `spf_win_io.f` | Windows 檔案 I/O | `posix/io.f` |
| `spf_win_conv.f` | 編碼轉換 | — |
| `spf_win_envir.f` | 環境查詢、錯誤解碼 | `posix/envir.f` |
| `spf_win_init.f` | 程序初始化、SEH | `posix/init.f` |
| `spf_win_con_io.f` | 控制台 I/O、EKEY | `posix/con_io.f` |
| `spf_win_except.f` | 例外 façade | `posix/except.f` |
| `spf_win_module.f` | 路徑管理 | `posix/module.f` |
| `spf_win_cgi.f` | CGI 支援 | — |
| `spf_pe_save.f` | PE 格式儲存 | `posix/save.f` |
