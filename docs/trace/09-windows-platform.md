# SP-Forth/4 原始碼追蹤 — Windows 平台支援深入解析

> 對應原始碼：`src/win/` 目錄下所有檔案
> 原始碼版權：Copyright [C] 1992-1999 A.Cherezov ac@forth.org

> 本章目標：看懂 WINAPI: 如何延遲解析 DLL 函式、API-CALL 的 stdcall 包裝、以及 SEH 如何取代 POSIX 信號。
> 
> 閱讀提示：本文件聚焦 **Windows 平台實作、PE 格式、SEH 例外處理與 Windows API 呼叫**。若你想看較高層的 I/O、初始化與例外生命週期，請接續閱讀 [05-io-error-init.md](05-io-error-init.md)。與 POSIX 平台（見 [04-posix-platform.md](04-posix-platform.md)）的對照，請見 §11。

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

### 2.4 WINAPI: 宣告實例（spf_win_proc.f）

`spf_win_proc.f` 是 **Windows API 函式宣告的中心庫**，所有跨檔案共用的 `WINAPI:` 呼叫集中在這裡。它僅包含 41 行 `WINAPI:` 宣告（不包含任何可執行邏輯）：

```
WINAPI: GetStdHandle                  KERNEL32.DLL
WINAPI: CreateFileA                   KERNEL32.DLL
WINAPI: ReadFile                      KERNEL32.DLL
WINAPI: WriteFile                     KERNEL32.DLL
WINAPI: HeapCreate                    KERNEL32.DLL
...                                   ...
```

這些宣告在 `spf.f` 載入時解析 DLL 並寫入 `WINAPLINK` 鏈。各功能檔案（`spf_win_io.f`、`spf_win_memory.f` 等）直接使用這些已宣告的名稱，不必重複 `WINAPI:`。這相當於 POSIX 版將 `dlopen`/`dlsym` 快取在符號表中的角色。

---

## 3. 記憶體管理（spf_win_memory.f）深入解析

### 3.1 Windows 常數（spf_win_const.f）

`spf_win_const.f` 定義 Windows 平台關鍵常數，相當於 POSIX 的 `posix/const.f`：

```forth
\ spf_win_const.f:10-31
40   CONSTANT PAGE_EXECUTE_READWRITE    \ VirtualAlloc 頁面保護
1000 CONSTANT MEM_COMMIT                \ VirtualAlloc 類型
2000 CONSTANT MEM_RESERVE
-1   CONSTANT INVALID_HANDLE_VALUE      \ API 錯誤回傳值
2    CONSTANT CREATE_ALWAYS             \ CreateFile 建立模式
3    CONSTANT OPEN_EXISTING
0    CONSTANT FILE_BEGIN                \ SetFilePointer 位移基準
1    CONSTANT FILE_CURRENT
```

這些常數分散被 `spf_win_memory.f`（記憶體配置）與 `spf_win_io.f`（檔案 I/O）使用，不包含在對應功能檔案中的原因是：多個檔案共享的底層常數集中定義，避免重複。

此外也定義了 ANSI Forth 94 標準的檔案存取方法（`FAM`）常數：

```forth
80000000 CONSTANT R/O    \ 唯讀
40000000 CONSTANT W/O    \ 唯寫
C0000000 CONSTANT R/W    \ 讀寫
```

### 3.2 Windows Heap API 對比 POSIX malloc

Windows 版使用 `HeapCreate`/`HeapAlloc` 而非 `malloc`/`mmap`：

| POSIX | Windows | 說明 |
|-------|--------|------|
| `malloc`/`calloc` | `HeapAlloc` | 分配記憶體 |
| `free` | `HeapFree` | 釋放記憶體 |
| `realloc` | `HeapReAlloc` | 重新配置 |
| `mmap`(MAP_ANONYMOUS) | `HeapAlloc` | 配置匿名記憶體 |
| — | `HeapCreate`/`HeapDestroy` | 建立/銷毀私有堆 |

### 3.3 執行緒堆積（spf_win_memory.f:50-63）

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

### 3.4 ALLOCATE-RWX 的差異

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

  R@ 10 CELLS + @ ( esp )         ; 從 Context 提取 ESP
  R@ 5 CELLS + @ ( eax )          ; 提取 EAX
  R> 6 CELLS + @ ( ebp )           ; 提取 EBP
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

### 5.4 例外處理器本體（spf_win_except.f）

`spf_win_init.f` 設定 SEH 鏈的**框架**，而 `spf_win_except.f` 提供**處理器本體** `(EXC)` 與 `HALT`：

```forth
\ spf_win_except.f:18-22
: HALT ( ERRNUM -> )
  AT-THREAD-FINISHING
  AT-PROCESS-FINISHING
  ExitProcess
;
```

`HALT` 是 Windows 版的「優雅死亡」：先執行執行緒最終化、再執行程序最終化（`DESTROY-HEAP`），最後呼叫 `ExitProcess`。這與 POSIX 版 `HALT` 呼叫 `_exit` 的語意相同。

#### (EXC) — SEH 處理器核心

```forth
\ spf_win_except.f:30-60
: (EXC) ( DispatcherContext ContextRecord EstablisherFrame ExceptionRecord -- flag )
  (ENTER)                           \ 進入 Forth 執行環境
  OVER DUP 0 FS!                    \ 恢復上一層 SEH 鏈
  CELL+ CELL+ @ TlsIndex!           \ 從 EstablisherFrame 恢復 TLS 基底

  DUP @ 0xC000013A = IF             \ CONTROL_C_EXIT（Wine 上的 Ctrl+C）
    0xC000013A HALT
  THEN
  DUP <EXC-DUMP>

  HANDLER @ 0= IF                   \ 無 CATCH 框架，無法恢復
     DESTROY-HEAP
     -1 ExitThread
  THEN

  FINIT                             \ 重置 x87 FPU
  @ THROW                           \ 將 Windows 例外碼轉為 Forth THROW
  R> DROP                           \ 清理 callback 返回位址
;
```

`(EXC)` 的參數是 SEH 呼叫慣例：`ExceptionRecord`（例外記錄）、`EstablisherFrame`（目前 SEH 框架位址）、`ContextRecord`（執行緒上下文）、`DispatcherContext`（分派器上下文）。它執行以下步驟：

1. **恢復 SEH 鏈**：`OVER DUP 0 FS!` 從 `EstablisherFrame` 取出上一層 SEH 記錄，寫回 `FS:[0]`。這與 POSIX 信號處理器恢復 `sa_mask` 的語意類似——防止同一例外無限遞迴。
2. **恢復 TLS**：`CELL+ CELL+ @ TlsIndex!` 從 `EstablisherFrame+8` 取出儲存的 TLS 基底，寫入 `EDI`。這是 Windows 版 `CATCH/THROW` 能跨 SEH 運作的關鍵。
3. **Ctrl+C 特殊處理**：`0xC000013A`（`CONTROL_C_EXIT`）在 Wine 上由 Ctrl+C 觸發，直接呼叫 `HALT`。
4. **無 CATCH 時終止**：若 `HANDLER @ = 0`（沒有 `CATCH` 框架），執行 `DESTROY-HEAP` 後以 `-1` 結束執行緒。這對應 POSIX 版信號處理器中的 `ABORT`。
5. **FPU 重置**：`FINIT` 清除 x87 可能的異常狀態，避免 FPU 控制字污染後續浮點運算。
6. **THROW**：`@ THROW` 將 `ExceptionRecord->ExceptionCode` 作為 Forth 例外號碼拋出，讓上層 `CATCH` 捕獲。

#### SET-EXC-HANDLER — 安裝 SEH 框架

```forth
\ spf_win_except.f:65-74
: SET-EXC-HANDLER
  R> R>
  TlsIndex@ >R                    \ 儲存目前 TLS
  ['] (EXC) >R                    \ 儲存處理器位址
  0 FS@ >R                        \ 儲存舊 SEH 鏈頂端
  RP@ 0 FS!                       \ 新 SEH 鏈頂端 = 目前返回堆疊
  RP@ EXC-HANDLER !
  ['] DROP-EXC-HANDLER >R         \ 返回後的清理器
  >R >R
;
```

`SET-EXC-HANDLER` 利用**返回堆疊**直接建構 SEH 鏈節點：
- `R>` `R>` 先彈出正常的返回位址（暫存）
- 依序將 `TlsIndex`、`(EXC)` 位址、舊 `FS:[0]` 壓入返回堆疊
- `RP@ 0 FS!` 讓 `FS:[0]` 指向這個堆疊上的結構，完成 SEH 鏈安裝
- `['] DROP-EXC-HANDLER >R` 作為「返回後的清理動作」
- `>R >R` 恢復正常的返回位址

這與 POSIX 版 `CATCH` 將 `HANDLER` 串列節點壓入資料堆疊的機制異曲同工，只是 Windows 使用**硬體定義的 SEH 鏈**（`FS:[0]`），而 POSIX 使用**軟體模擬的例外鏈**（`HANDLER` 變數）。

> 對照閱讀：POSIX 版的 `(errsignal)` 與 `SET-ERR-SIGNAL-HANDLER` 請見 [04-posix-platform.md §12.2](04-posix-platform.md#122-errsignal信號處理器)。

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

### 7.4 PE 匯入表（Import Table）詳細結構

PE 的匯入表是作業系統載入器解析外部 DLL 函數位址的核心機制。與 ELF 使用重定位表不同，PE 使用專門的匯入目錄結構。

#### 7.4.1 匯入表整體架構

匯入表位於 `.idata` 節區，包含以下並行陣列結構：

```
.idata 節區佈局：
┌────────────────────────────────────────┐
│ Import Directory Table                 │
│  每個 DLL 一個項目（20 bytes）           │
│  - Import Lookup Table RVA             │
│  - TimeDateStamp                       │
│  - ForwarderChain                      │
│  - Name RVA（指向 DLL 名稱）             │
│  - Import Address Table RVA            │
├────────────────────────────────────────┤
│ Import Lookup Table（ILT）/            │
│ Import Name Table（INT）               │
│  函數序號或名稱指標陣列                   │
├────────────────────────────────────────┤
│ Import Address Table（IAT）            │
│  執行時填入實際函數位址                   │
├────────────────────────────────────────┤
│ Hint/Name Table                        │
│  函數名稱字串（含 Hint 序號提示）          │
├────────────────────────────────────────┤
│ DLL 名稱字串                           │
│  如 "KERNEL32.dll\0"                    │
└────────────────────────────────────────┘
```

#### 7.4.2 Import Directory Table 項目

每個被匯入的 DLL 對應一個 20-byte 的目錄項目：

| 偏移 | 大小 | 欄位名稱 | 說明 |
|------|------|----------|------|
| 0x00 | 4 | ImportLookupTableRVA | 指向 ILT/INT 的 RVA |
| 0x04 | 4 | TimeDateStamp | 時間戳（0 = 未繫結） |
| 0x08 | 4 | ForwarderChain | 轉發鏈索引（-1 = 無轉發） |
| 0x0C | 4 | NameRVA | 指向 DLL 名稱字串的 RVA |
| 0x10 | 4 | ImportAddressTableRVA | 指向 IAT 的 RVA（執行時由載入器填入） |

**SP-Forth 使用的兩個 DLL**：

SP-Forth 最小執行檔通常只匯入 `KERNEL32.dll` 的兩個函數：
- `LoadLibraryA`：載入其他 DLL
- `GetProcAddress`：取得函數位址

這兩個函數是 SP-Forth 動態連結的基礎，其他所有 Win32 API 都在執行時透過它們動態載入。

#### 7.4.3 Import Lookup Table / Import Name Table

每個項目 4 bytes，最高位元決定類型：

- **最高位元 = 1**：按序號（Ordinal）匯入
  - 低 31 bits = 函數序號（Ordinal Number）
  - 範例：`0x8000012F` = 序號 303

- **最高位元 = 0**：按名稱匯入
  - 指向 Hint/Name Table 的 RVA
  - 範例：`0x0000203A` = 指向檔案偏移 0x203A 的 Hint/Name 結構

**SP-Forth 範例**：

```forth
\ spf_stub.f 中的匯入表定義
CREATE ImportDirectory
  \ Import Lookup Table
  HERE ImportDirectory - 1000 + ImportDirectory ID.ImportLookupTableRVA !
  0 ,    \ LoadLibraryA：初始為 0，按名稱匯入（指向 Hint/Name）
  0 ,    \ GetProcAddress：初始為 0，按名稱匯入
  0 ,    \ 結束項目（NULL）
```

#### 7.4.4 Hint/Name Table 結構

按名稱匯入時，ILT/INT 項目指向此結構：

```
┌──────────┬────────────────────┐
│ 2 bytes  │ Hint（匯出表索引提示） │
│          │ 載入器先用此值快速查找 │
├──────────┼────────────────────┤
│ N bytes  │ 函數名稱（ASCIIZ）    │
│          │ 如 "LoadLibraryA\0"  │
├──────────┼────────────────────┤
│ 0-3 bytes│ 對齊填充（到 2-byte 邊界）│
└──────────┴────────────────────┘
```

**Hint 的作用**：
- DLL 的匯出表是一個有序陣列
- Hint 建議載入器從哪個索引開始搜尋
- 如果 Hint 正確，載入器無需字串比對即可找到函數
- 如果 Hint 過時（DLL 版本不同），載入器回退到線性搜尋

#### 7.4.5 Import Address Table（IAT）

IAT 與 ILT/INT 平行，但在執行時被覆寫：

| 階段 | IAT 內容 | 說明 |
|------|----------|------|
| 檔案中的初始值 | 與 ILT 相同 | 指向 Hint/Name 的 RVA |
| 載入後 | 函數的實際位址 | 如 `0x76E31234` = LoadLibraryA 位址 |

**SP-Forth 的動態解析**：

```forth
\ spf_win_api.f:18-44
CODE AO_INI
  \ ...
  A; 0xA1 C, AddrOfLoadLibrary
  ALSO FORTH , PREVIOUS
  A; HERE 4 - ' AOLL EXECUTE !
  CALL EAX          ; 呼叫 LoadLibraryA
  
  PUSH ECX
  PUSH EAX
  A; 0xA1 C, AddrOfGetProcAddress
  ALSO FORTH , PREVIOUS
  A; HERE 4 - ' AOGPA EXECUTE !
  CALL EAX          ; 呼叫 GetProcAddress
  \ ...
END-CODE
```

`AO_INI` 在啟動時解析 `LoadLibraryA` 和 `GetProcAddress` 的位址，並儲存到 `AOLL` 和 `AOGPA` 變數。這與 ELF 的延遲解析（lazy resolution）不同，PE 版本在啟動時就解析這兩個核心函數。

#### 7.4.6 PE vs ELF 動態連結對照

| 特性 | ELF（POSIX） | PE（Windows） |
|------|--------------|---------------|
| 匯入資訊位置 | `.dynsym`、`.dynstr`、`.rel.dyn` | `.idata`（匯入表） |
| 函數解析時機 | 延遲解析（lazy binding，首次呼叫時） | 啟動時解析（EAGER） |
| 解析機制 | PLT/GOT（Procedure Linkage Table） | IAT（Import Address Table） |
| 延遲解析控制 | `LD_BIND_NOW` 環境變數 | 無（總是啟動時解析） |
| SP-Forth 實作 | `dl-init` + `symbol-address` | `AO_INI` 直接呼叫 `LoadLibraryA`/`GetProcAddress` |

---

## 8. Windows 檔案 I/O（spf_win_io.f）深入解析

Windows 版使用 Win32 `CreateFileA`/`ReadFile`/`WriteFile` 家族實作 ANS Forth 檔案存取字詞。與 POSIX 使用檔案描述符（file descriptor，整數）不同，Windows 使用 `HANDLE`（核心物件控制代碼，本質上也是整數，但語意不同）。

### 8.1 開檔與建檔

```forth
\ spf_win_io.f:16-33
: CREATE-FILE ( c-addr u fam -- fileid ior )
  NIP SWAP >R >R
  0 FILE_ATTRIBUTE_ARCHIVE
  CREATE_ALWAYS
  0 ( secur ) 0 ( share )
  R> ( access=fam ) R> ( filename )
  CreateFileA DUP -1 = IF GetLastError ELSE 0 THEN
;
```

`CREATE-FILE` 捨棄 `fam` 中的 ` fam`（`NIP` 掉長度），保留檔名與存取模式，映射到 `CreateFileA` 的參數：

| Forth 參數 | Win32 參數 | 說明 |
|-----------|-----------|------|
| `fam`（長度被捨棄） | `dwDesiredAccess` | 存取模式（`O_RDONLY`/`O_WRONLY`/`O_RDWR`） |
| `CREATE_ALWAYS` | `dwCreationDisposition` | 總是建立新檔，若存在則覆蓋 |
| `0` | `lpSecurityAttributes` | 無安全描述元 |
| `0` | `dwShareMode` | 不共享 |

`OPEN-FILE`（第 98-113 行）類似，但使用 `OPEN_EXISTING`。若 `CreateFileA` 回傳 `-1`（`INVALID_HANDLE_VALUE`），則透過 `GetLastError` 取得錯誤碼。

### 8.2 共享開檔變體

```forth
\ spf_win_io.f:37-46
: CREATE-FILE-SHARED ( c-addr u fam -- fileid ior )
  ... 3 ( share ) ... CreateFileA ...
```

`CREATE-FILE-SHARED` 與 `OPEN-FILE-SHARED`（第 47-68 行）使用 `dwShareMode = 3`（`FILE_SHARE_READ | FILE_SHARE_WRITE`），`OPEN-FILE-SHARED` 甚至嘗試 `7`（加上 `FILE_SHARE_DELETE`）。若 `CreateFileA` 在 Win9x 上回傳錯誤碼 `87`（`ERROR_INVALID_PARAMETER`），則降級為 `3` 重試——這是針對 Win9x Bug #3104038 的 workaround。

### 8.3 讀寫與位置控制

`READ-FILE`（第 117-140 行）與 `WRITE-FILE`（第 203-218 行）分別包裝 `ReadFile` 與 `WriteFile`：

```forth
: READ-FILE ( c-addr u1 fileid -- u2 ior )
  >R 2>R
  0 lpNumberOfBytesRead R> R> R>
  ReadFile ERR
  lpNumberOfBytesRead @ SWAP
  DUP 109 = IF DROP 0 THEN  \ broken pipe — 視為正常 EOF
;
```

特別的是錯誤碼 `109`（`ERROR_BROKEN_PIPE`）被視為正常 EOF，直接回傳 `u2=0, ior=0`。這讓管道（pipe）讀取在 Windows 上與 POSIX 行為一致。

`FILE-POSITION`、`FILE-SIZE`、`REPOSITION-FILE` 使用 `SetFilePointer`/`GetFileSize` 處理 64 位元檔案偏移：

```forth
USER lpDistanceToMoveHigh

: FILE-POSITION ( fileid -- ud ior )
  >R FILE_CURRENT lpDistanceToMoveHigh DUP 0! 0 R>
  SetFilePointer
  DUP -1 = IF GetLastError ELSE 0 THEN
  lpDistanceToMoveHigh @ SWAP
;
```

`lpDistanceToMoveHigh` 作為 64 位元偏移的高 32 位元 USER 變數。這與 POSIX 版使用 `lseek64`（接受 64 位元 `off_t`）的語意相同，只是 Win32 API 將高低位分開處理。

### 8.4 逐行讀寫

`READ-LINE`（第 158-198 行）的實作與 POSIX 版幾乎一致：

1. 記錄目前檔案位置（`_fp1`、`_fp2`）
2. 讀取一塊資料（含行尾字元）
3. 用 `EOLN SEARCH` 找行尾
4. 若找到，將檔案位置重置到行尾之後，回傳該行長度
5. 若未找到，回傳已讀長度與 `flag=false`

`WRITE-LINE`（第 238-248 行）則是 `WRITE-FILE` 接著寫出 `EOLN`。

### 8.5 其他檔案操作

| Forth 字 | Win32 API | 說明 |
|---------|-----------|------|
| `DELETE-FILE` | `DeleteFileA` | 刪除檔案 |
| `FLUSH-FILE` | `FlushFileBuffers` | 強制寫入磁碟 |
| `FILE-EXIST` | `GetFileAttributesA` | 檢查檔案/目錄是否存在 |
| `FILE-EXISTS` | `GetFileAttributesA` + `FILE_ATTRIBUTE_DIRECTORY` 遮罩 | 只檢查檔案（排除目錄） |
| `RESIZE-FILE` | `SetEndOfFile` | 先 `REPOSITION-FILE` 再截斷 |

### 8.6 Windows vs POSIX 檔案 I/O 對照

| 特性 | POSIX（`posix/io.f`） | Windows（`spf_win_io.f`） |
|------|----------------------|---------------------------|
| 檔案控制代碼型別 | 檔案描述符（`int` fd） | 核心物件控制代碼（`HANDLE`） |
| 開檔 API | `open64` | `CreateFileA` |
| 讀寫 API | `read` / `write` | `ReadFile` / `WriteFile` |
| 定位 API | `lseek64` | `SetFilePointer` |
| 截斷 API | `ftruncate64` | `SetEndOfFile` |
| 共享模式 | `fcntl` 或 `open` 的旗標 | `dwShareMode` 參數 |
| 錯誤碼 | `errno` | `GetLastError` |
| broken pipe | `EPIPE`（由 `except.f` 處理） | 錯誤碼 `109`，直接視為 EOF |

---

## 9. Windows 控制台 I/O（spf_win_con_io.f）深入解析

Windows 控制台輸入不使用標準 `ReadFile`，而是使用 Win32 **Console API**（`ReadConsoleInputA`、`GetNumberOfConsoleInputEvents`），因為需要區分鍵盤事件、滑鼠事件與視窗緩衝區大小變更事件。

### 9.1 低階主控台事件讀取

```forth
\ spf_win_con_io.f:11-18
: EKEY? ( -- flag )
  0 >R RP@ H-STDIN GetNumberOfConsoleInputEvents DROP R>
;
```

`EKEY?` 詢問主控台輸入緩衝區是否有可用事件。`H-STDIN` 在 Windows 版中是主控台輸入 `HANDLE`（與 POSIX 版的 fd 不同）。

```forth
\ spf_win_con_io.f:29-43
CREATE INPUT_RECORD ( /INPUT_RECORD) 20 2 * CHARS ALLOT

: EKEY ( -- u )
  0 >R RP@ 2 INPUT_RECORD H-STDIN
  ReadConsoleInputA DROP RDROP
  INPUT_RECORD W@ KEY_EVENT <> IF 0 EXIT THEN
  [ INPUT_RECORD 14 + ] LITERAL W@           \ AsciiChar
  [ INPUT_RECORD 12 + ] LITERAL W@ 16 LSHIFT OR  \ ScanCode
  [ INPUT_RECORD  4 + ] LITERAL C@ 24 LSHIFT OR  \ KeyDownFlag
;
```

`EKEY` 讀取一個 `INPUT_RECORD` 結構（大小約 20 bytes），解析其中的 `KEY_EVENT`：
- 低 16 位元：`AsciiChar`
- 次 16 位元：`wVirtualScanCode`
- 最高 8 位元：`bKeyDown`（按鍵按下或放開）

這與 POSIX 版直接讀取原始位元組完全不同——POSIX `EKEY` 通常直接回傳終端機輸入的 escape sequence 或 Unicode byte。

### 9.2 高階鍵盤輸入

```forth
\ spf_win_con_io.f:62-81
VARIABLE PENDING-CHAR

: KEY? ( -- flag )
  PENDING-CHAR @ 0 > IF TRUE EXIT THEN
  BEGIN EKEY? WHILE
    EKEY EKEY>CHAR
    IF PENDING-CHAR ! TRUE EXIT THEN
    DROP
  REPEAT FALSE
;
```

`KEY?` 與 `KEY` 使用 `PENDING-CHAR` 變數作為單字元緩衝區，這與 POSIX 版（`spf_con_io.f`）的 `PENDING-CHAR` 機制完全一致。`EKEY>CHAR`（第 46-52 行）將 `EKEY` 回傳的複合值解碼為 ASCII 字元：若 `KeyDownFlag=0`（放開事件）或 `AsciiChar=0`（功能鍵），則回傳「無字元」。

### 9.3 與 POSIX 控制台 I/O 對照

| 特性 | POSIX（`posix/con_io.f`） | Windows（`spf_win_con_io.f`） |
|------|--------------------------|-------------------------------|
| 輸入 API | `read` / `getc` | `ReadConsoleInputA` |
| 事件類型 | 原始位元流 | `INPUT_RECORD`（鍵盤/滑鼠/視窗） |
| 特殊鍵處理 | Escape sequence 解析 | `wVirtualScanCode` + `bKeyDown` |
| 掛起字元緩衝 | `PENDING-CHAR` | `PENDING-CHAR`（相同機制） |
| 向量設定 | `VECT KEY` | `VECT KEY` + `' KEY1 ' KEY TC-VECT!` |

---

## 10. 模組路徑管理（spf_win_module.f）

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

## 11. Windows vs POSIX 對照總結

### 11.1 FFI 機制對照

```
POSIX：                              Windows：
dlopen("lib.so") ──→ dlsym ──→     LoadLibraryA("DLL")
                                   GetProcAddress(h, "func")
WINAPLINK 鏈 ← AO_INI ──→         WINAPLINK 鏈
```

### 11.2 TLS 機制對照

兩者都使用 `TlsIndex!` / `TlsIndex@` 原語，但：

| 方面 | POSIX | Windows |
|------|-------|---------|
| TLS 分配 | `ALLOCATE-THREAD-MEMORY` + `calloc` | `CREATE-HEAP` + `HeapAlloc` |
| TLS 解除 | `FREE-THREAD-MEMORY` | `DESTROY-HEAP` |
| 例外時恢復 | `CONTEXT_EDI + @ TlsIndex!` | SEH `EXCEPTION_POINTERS` |

### 11.3 例外處理對照

| 方面 | POSIX | Windows |
|------|-------|---------|
| 同步例外 | `sigaction`（SIGSEGV/SIGFPE 等） | SEH（`EXCEPTION_RECORD`） |
| 非同步訊號 | `SIGINT` 等 | `SetConsoleCtrlHandler` |
| 傾印 | `DUMP-TRACE` | `EXC-DUMP1` |
| 遞迴保護 | `IN-EXCEPTION` | `IN-EXCEPTION` |

### 11.4 執行緒對照

| 方面 | POSIX | Windows |
|------|-------|---------|
| 建立 | `pthread_create` | `CreateThread` |
| 暂停/恢復 | `SIGSTOP`/`SIGCONT` | `SuspendThread`/`ResumeThread` |
| 睡眠 | `nanosleep` | `Sleep` |
| 終止 | `pthread_exit` | `ExitThread` + `DESTROY-HEAP` |
| ID | `pthread_self` | `GetCurrentThreadId` |

### 11.5 記憶體對照

| 方面 | POSIX | Windows |
|------|-------|---------|
| 堆積 API | `malloc`/`free` | `HeapAlloc`/`HeapFree` |
| 私有堆 | — | `HeapCreate` |
| 可執行記憶體 | `mmap` + `mprotect` | `HeapAlloc`（天然可執行） |
| 除錯標記 | `FIX-MEMTAG` | `FIX-MEMTAG` |

---

## 12. Windows 平台關鍵檔案一覽

| 檔案 | 主題 | 對應 POSIX 檔案 |
|------|------|----------------|
| `spf_win_api.f` | API 呼叫、CALLBACK 橋接 | `posix/api.f` |
| `spf_win_defwords.f` | WINAPI:、EXTERN、CALLBACK:、TASK | `posix/defwords.f` |
| `spf_win_proc.f` | WINAPI: 宣告實例中心庫 | `posix/defwords.f`（同層） |
| `spf_win_mtask.f` | 多執行緒（CreateThread 等） | `posix/mtask.f` |
| `spf_win_memory.f` | HeapCreate/HeapAlloc | `posix/memory.f` |
| `spf_win_io.f` | Windows 檔案 I/O | `posix/io.f` |
| `spf_win_const.f` | 記憶體與檔案 I/O 常數 | `posix/const.f` |
| `spf_win_conv.f` | 編碼轉換 | — |
| `spf_win_envir.f` | 環境查詢、錯誤解碼 | `posix/envir.f` |
| `spf_win_init.f` | 程序初始化、SEH | `posix/init.f` |
| `spf_win_con_io.f` | 控制台 I/O、EKEY | `posix/con_io.f` |
| `spf_win_except.f` | 例外 façade | `posix/except.f` |
| `spf_win_module.f` | 路徑管理 | `posix/module.f` |
| `spf_win_cgi.f` | CGI 支援 | — |
| `spf_pe_save.f` | PE 格式儲存 | `posix/save.f` |
