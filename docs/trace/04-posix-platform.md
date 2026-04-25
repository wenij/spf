# SP-Forth/4 原始碼追蹤 — POSIX 平台支援深入解析

> 對應原始碼：`src/posix/` 目錄下所有檔案、`src/tc-configure-lines.f`
> 原始碼版權：Copyright [C] 1992-1999 A.Cherezov ac@forth.org

> 閱讀提示：本文件聚焦 **POSIX 平台實作、FFI、執行緒與信號機制**。若你想看較高層的 I/O、初始化與例外生命週期，請接續閱讀 [05-io-error-init.md](05-io-error-init.md)。

---

## 1. 平台偵測與自動組態（posix/config.auto.f）

### 1.1 產生機制

`posix/Makefile` 從 `posix/config.c` 編譯並執行一個小型 C 程式，該程式透過 `sizeof()`、`offsetof()` 和預處理器巨集偵測系統常數，然後輸出 Forth 常數定義到 `config.auto.f`。輸出的每個常數定義都遵循以下模式：

```forth
: CONSTANT_NAME 0xHEXVAL STATE @ IF LIT, THEN ; IMMEDIATE
```

`STATE @ IF LIT, THEN` 確保這些常數在編譯模式下被編譯為常值（`LIT,`），在直譯模式下直接推入堆疊。

### 1.2 ucontext_t 暫存器偏移

這是 POSIX 信號處理的核心資料。當 SIGSEGV/SIGILL/SIGBUS/SIGFPE 發生時，核心將暫存器狀態儲存在 `ucontext_t` 結構中。SP-Forth 需要知道每個暫存器在結構中的偏移量：

| 常數 | C 對應 | 偏移（範例） | 說明 |
|------|--------|-------------|------|
| `CONTEXT_EDI` | `uc_mcontext.gregs[REG_EDI]` | 0x24 | TLS 基底指標 |
| `CONTEXT_EIP` | `uc_mcontext.gregs[REG_EIP]` | 0x4C | 指令指標 |
| `CONTEXT_ESP` | `uc_mcontext.gregs[REG_ESP]` | 0x30 | 堆疊指標 |
| `CONTEXT_EAX` | `uc_mcontext.gregs[REG_EAX]` | 0x40 | TOS 快取暫存器 |
| `CONTEXT_EBP` | `uc_mcontext.gregs[REG_EBP]` | 0x2C | 資料堆疊指標 |

這些偏移量在執行期的信號處理器中用於恢復 Forth 虛擬機器的暫存器狀態。

### 1.3 信號相關常數

| 常數 | 值 | 說明 |
|------|-----|------|
| `SIGILL` | 0x4 | 不合法指令 |
| `SIGSEGV` | 0xB | 記憶體存取違規 |
| `SIGBUS` | 0x7 | 匯流排錯誤 |
| `SIGFPE` | 0x8 | 浮點/整數例外 |
| `SIGINT` | 0x2 | 中斷（Ctrl+C） |
| `SA_RESTART` | 0x10000000 | 重啟被中斷的系統呼叫 |
| `SA_SIGINFO` | 0x4 | 提供信號資訊 |
| `SA_NODEFER` | 0x40000000 | 不遮蔽正在處理的信號 |
| `SIZEOF_SIGSET` | 0x80 | sigset_t 的大小（128 bytes） |
| `SIGINFO_CODE` | 0x8 | siginfo_t 中 si_code 的偏移 |

### 1.4 浮點例外碼

| 常數 | 值 | 對應 Forth 例外 |
|------|-----|---------------|
| `FPE_INTDIV` | 0x1 | -10（整數除以零） |
| `FPE_INTOVF` | 0x2 | -11（整數溢位） |
| `FPE_FLTDIV` | 0x3 | -42（浮點除以零） |
| `FPE_FLTOVF` | 0x4 | -43（浮點溢位） |
| `FPE_FLTUND` | 0x5 | -54（浮點下溢） |
| `FPE_FLTRES` | 0x6 | -41（浮點不精確） |
| `FPE_FLTINV` | 0x7 | -46（浮點無效操作） |

### 1.5 檔案系統常數

| 常數 | 值 | 說明 |
|------|-----|------|
| `STAT_ST_MODE` | 0x10 | struct stat 中 st_mode 的偏移 |
| `S_IFREG` | 0x8000 | 正規檔案旗標 |
| `S_IFDIR` | 0x4000 | 目錄旗標 |
| `O_CREAT` | 0x40 | 建立檔案旗標 |
| `O_TRUNC` | 0x200 | 截斷旗標 |
| `PAGESIZE` | 0x1000 | 記憶體分頁大小（4 KiB） |
| `PROT_READ/WRITE/EXEC` | 0x1/0x2/0x4 | mprotect 旗標 |

---

## 2. C 呼叫介面（posix/api.f）深入解析

### 2.1 C-CALL：cdecl 呼叫約定實作

```forth
\ api.f:7-28
CODE C-CALL ( x1 ... xn n adr -- res)
     MOV EBX, [EBP]      \ n = 引數數量
     MOV ESI, # 4         \ 偏移量 = 4（一個 cell 的大小）
@@1: OR EBX, EBX         \ 測試 n 是否為零
     JZ @@2               \ 若零，跳過引數推入
     0xFF C, 0x74 C, 0x35 C, 0x00 C,  \ PUSH [EBP+ESI]（推入第 i 個引數）
     LEA ESI, 4 [ESI]    \ ESI += 4，移到下一個引數
     DEC EBX              \ n--
     JMP @@1              \ 繼續推入
@@2: CALL EAX             \ 呼叫 C 函數
     MOV ECX, [EBP]      \ ECX = n
     SHL ECX, # 2         \ ECX = n * 4（堆疊空間大小）
     ADD ESP, ECX         \ 清理 x86 堆疊（cdecl 呼叫者清理）
     ADD ECX, # 4         \ ECX += 4（n 個引數 + 1 個 n 值）
     ADD EBP, ECX         \ 調整 Forth 資料堆疊指標
     RET
END-CODE
```

**C-CALL 的完整執行流程**：

```
呼叫前堆疊（TOS-in-EAX 模型）：
  EAX = adr（C 函數位址）
  [EBP] = n（引數數量）
  [EBP+4] = x1（第1個引數）
  [EBP+8] = x2（第2個引數）
  ...

1. 迴圈推入引數到 x86 堆疊（右到左，符合 cdecl）
   PUSH x1, PUSH x2, ..., PUSH xn

2. CALL EAX（呼叫 C 函數）
   回傳值在 EAX 中

3. 清理 x86 堆疊
   ADD ESP, n*4

4. 調整 Forth 堆疊
   ADD EBP, (n+1)*4
   （丟棄所有引數 + n + adr）
```

**關鍵細節**：

- `0xFF C, 0x74 C, 0x35 C, 0x00 C,` 是 x86 機器碼 `PUSH [EBP+ESI]`，用組合語言插入實現堆疊-堆疊間接定址
- cdecl 呼叫約定要求呼叫者清理堆疊（`ADD ESP, ECX`），這與 stdcall 不同
- 回傳值在 EAX 中，正好與 Forth 的 TOS-in-EAX 模型完美契合

### 2.2 C-CALL2：64 位元回傳值

```forth
\ api.f:30-36
CODE C-CALL2 ( x1 ... xn n adr -- dres)
  CALL ' C-CALL       \ 呼叫 C-CALL（回傳值在 EAX 中）
  LEA EBP, -4 [EBP]   \ 在資料堆疊上騰出新空間
  MOV [EBP], EAX       \ EAX → 新次項
  MOV EAX, EDX         \ EDX（高位元組）→ 新 TOS
  RET
END-CODE
```

`C-CALL2` 處理 64 位元回傳值（如 `long long` 或 `off_t`）。cdecl 約定中，64 位元回傳值透過 `EAX:EDX` 傳回。C-CALL2 在呼叫 C-CALL 後，將 EAX 推入資料堆疊，並將 EDX 作為新的 TOS。

### 2.3 _WNDPROC-CODE：共用回呼函數橋接器

```forth
\ api.f:44-75
CODE _WNDPROC-CODE
      MOV  EAX, ESP            \ 儲存原始 ESP
      SUB  ESP, # 3968         \ 分配 ~4 KiB 作為 Forth 資料堆疊
      ... HERE 4 - ' ST-RES 9 + EXECUTE 產生的動態修補 ...
      PUSH EBP                 \ 儲存原本的 Forth EBP
      MOV  EBP, 4 [EAX]       \ 先取第 1 個回呼參數
      PUSH EBP                 \ 把該參數放到 Forth 資料堆疊
      MOV  EBP, EAX
      ADD  EBP, # 12          \ EBP = 原始 ESP + 12，轉成 Forth 資料堆疊指標
      PUSH EBX                 \ 儲存暫存器
      PUSH ECX
      PUSH EDX
      PUSH ESI
      PUSH EDI
     MOV  EAX, [EAX]         \ 取得 Forth XT
     MOV  EBX, [EAX]         \ XT → CFA
     MOV  EAX, -4 [EBP]      \ 取得回呼參數
     CALL EBX                 \ 呼叫 Forth 字
     ... 恢復暫存器 ...
     XCHG EAX, [ESP]         \ 將回傳值與返回位址交換
     RET
END-CODE
```

雖然名稱沿用了 Windows 世界常見的 `WNDPROC` 字眼，但在 `src/posix/api.f` 中它同樣存在，扮演的角色其實是**共用的 C callback -> Forth bridge**。這裡重點不是 Win32 視窗程序，而是「當 C 世界呼叫回來時，如何重新建立 SP-Forth 的執行環境」。

其設計要點：

1. **堆疊切換**：C 呼叫者的 ESP 儲存到 EAX，然後分配 ~4 KiB 的 Forth 資料堆疊
2. **不直接切 TLS**：`_WNDPROC-CODE` 本體不呼叫 `TlsIndex!` / `TlsIndex@`；它假設目前執行緒對應的 Forth instance 已由外圍機制建立好
3. **參數整理**：先從 `[EAX+4]` 取出第一個回呼參數，再把它放到 Forth 資料堆疊，接著把 `EBP` 重設成新的資料堆疊指標
4. **暫存器保存/恢復**：EBX, ECX, EDX, ESI, EDI
5. **回傳值處理**：`XCHG EAX, [ESP]` 將 Forth 回傳值放在 C 呼叫者期望的位置

### 2.4 FORTH-INSTANCE> 與 <FORTH-INSTANCE

```forth
\ api.f:80-84
VECT FORTH-INSTANCE>  \ 進入 Forth 環境（設定 TLS）
VECT <FORTH-INSTANCE  \ 離開 Forth 環境（恢復 EDI）
```

這兩個向量用於多執行緒支援：

- `FORTH-INSTANCE>`：在進入 Forth 程式碼前設定 EDI 暫存器為目前執行緒的 TLS 基底
- `<FORTH-INSTANCE`：在離開 Forth 程式碼後恢復 EDI（或設定為零）

在 POSIX 版本中，這兩個向量同樣透過 `TlsIndex!` / `TlsIndex@` 這組原語實作，用來切換目前執行緒的 TLS 基底。像 `ALLOCATE-THREAD-MEMORY` 與 `(errsignal)` 這類輔助流程，也是在這一層操作 TLS，而不是在 `_WNDPROC-CODE` 本體裡直接切換。

這裡的 `TlsIndex!` / `TlsIndex@` 是 **SP-Forth 自己的抽象原語名稱**。在 POSIX 版中，它們同樣存在，但語意應理解為「更新 / 讀取目前執行緒的 TLS 基底指標」，而不是直接對應 `pthread_key_*` 那類 API 名稱。

---

## 3. 動態程式庫載入（posix/dl.f）深入解析

### 3.1 執行期 vs 交叉編譯期的差異

`posix/dl.f` 是執行期版本的動態連結系統，與 `src/tc-dl.f`（交叉編譯期版本）形成對照：

| 特性 | tc-dl.f（編譯期） | posix/dl.f（執行期） |
|------|-------------------|---------------------|
| 符號表大小固定？ | 否（dlrealloc 擴展） | 否（dlrealloc 擴展） |
| 符號解析方式 | 僅記錄，不解析 | 透過 dlsym 即時解析 |
| `symbol-address` | 中止（ABORT） | 透過 dlsym 解析並快取 |
| 字串表管理 | enter-into-strtab（簡單） | enter-into-strtab（含 realloc） |

### 3.2 dlopen / dlsym / dlerror 封裝

```forth
\ dl.f:17-27
: (DLOPEN) ( file mode -- h)
  2 dlopen-adr @ C-CALL
;

: (DLSYM) ( h name -- a)
  2 dlsym-adr @ C-CALL
;

: DLERROR ( -- z/0)
  0 dlerror-adr @ C-CALL
;
```

三個 C 標準庫函數透過 `C-CALL` 封裝。`dlopen-adr`、`dlsym-adr`、`dlerror-adr` 是在初始化時設定好的函數指標變數。

```forth
\ dl.f:29-31
RTLD_GLOBAL RTLD_LAZY OR CONSTANT DLOPEN-FLAG

: DLOPEN ( addr u -- h ) DROP DLOPEN-FLAG (DLOPEN) ;
: DLSYM ( addr u h -- api-xt ) NIP SWAP (DLSYM) ;
```

`DLOPEN-FLAG` 組合了 `RTLD_GLOBAL`（使符號全域可見）和 `RTLD_LAZY`（延遲解析）。`DLOPEN` 忽略字串長度（因為 dlopen 需要 ASCIIZ 字串），`DLSYM` 同理。

### 3.3 符號解析與快取

```forth
\ dl.f:157-165
: symbol-address ( sym# -- adr)
  get-symbol-record >R
  R@ CELL+ @ ?DUP 0= IF      \ 若位址為 0（尚未解析）
    R@ @ + dlsym2 DUP R> CELL+ ! \ 透過 dlsym 解析並快取
  ELSE
    NIP                        \ 直接使用快取的位址
  THEN
  RDROP
;
```

`symbol-address` 實作了延遲解析（lazy resolution）：

1. 查找符號記錄（`get-symbol-record`）
2. 檢查 `CELL+ @`（函數位址欄位）是否為 0
3. 若為 0，透過 `dlsym2` 即時解析，並將結果寫回符號記錄（快取）
4. 若不為 0，直接使用快取的位址

`dlsym2`（第 58~65 行）封裝了 `dlsym` 呼叫，使用 `global-symbol-object` 作為模組 handle。

### 3.4 symbol-call 與 C 函數呼叫

```forth
\ dl.f:167-176
: symbol-call ( ... n sym# -- res )
  symbol-address C-CALL
;

: symbol-call2 ( ... n sym# -- dres )
  symbol-address C-CALL2
;
```

`symbol-call` 是執行期 C 函數呼叫的核心：
1. `symbol-address` 解析符號位址
2. `C-CALL` 呼叫該位址的 C 函數

`symbol-call2` 用於需要 64 位元回傳值的情況。

### 3.5 (( 和 ))：Forth 風格的 C 函數呼叫語法

```forth
\ dl.f:208-214
: (( ( -- ) SP@ ((-stack !  (__ret2) 0! ;
: <( ( n -- ) 1+ CELLS SP@ + ((-stack !  (__ret2) 0! ;

: ())) ( -- n ) SP@ ((-stack @ SWAP - >CELLS ;
: __ret2 ( -- ) TRUE (__ret2) ! ; IMMEDIATE
```

這四個字提供了一個巧妙的語法糖，讓 Forth 程式能以類似 C 函數呼叫的語法呼叫外部函數：

```
2 (( pthread_create )) thread attr start arg
```

**執行流程**：

1. `((`：儲存目前 SP（堆疊指標）到 `((-stack`，重設 `__ret2` 旗標
2. `))`：計算自 `((` 以來推入的引數數量（`SP@ - ((-stack @`），呼叫 `symbol-call`
3. `<( n -- )`：用於指定引數數量（當編譯期無法推斷時）

`(<(` 是 `((` 的替代語法，用於明確指定引數數量。例如 PROCESSPROC: 使用 `2 <(` 來指定 2 個引數。

### 3.6 dl-init：初始化流程

```forth
\ dl.f:194-201
: dl-init
  0 DLOPEN-FLAG (DLOPEN) TO global-symbol-object  \ 開啟主程式符號表
  0 1000 dlrealloc TO dl-second-strtab             \ 分配字串表
  4 dl-second-strtab !                             \ 設定初始偏移
  0 TO dl-second
  0 TO dl-second#
  load-libraries                                   \ 載入預登記模組
;
```

`dl-init` 的初始化步驟：

1. `dlopen(NULL, ...)`：開啟主程式的符號表，使得主程式中的所有全域符號都可透過 `dlsym` 查找
2. 分配執行期符號表的字串表
3. 呼叫 `load-libraries` 載入所有預登記的動態程式庫

`load-libraries`（第 184~192 行）遍歷 `dl-first` 表中的所有記錄，對程式庫名稱（偏移為負值）呼叫 `dlopen2` 載入模組：

```forth
: load-libraries
  dl-first dl-first# dl-rec# * OVER + SWAP ?DO
    I @ 0< IF
      I @ NEGATE dl-first-strtab + dlopen2   \ 載入程式庫
    ELSE
      I CELL+ 0!                              \ 清空函數位址（延遲解析）
    THEN
  dl-rec# +LOOP
;
```

### 3.7 name-lookup 與表搜尋

```forth
\ dl.f:108-117
: table-lookup ( a # strtab symtab symtab# -- sym# T / F)
  0 ?DO
    2OVER 2OVER
    I dl-rec# * + @ DUP 0< IF NEGATE THEN + szcompare IF
      2DROP 2DROP I TRUE UNLOOP EXIT
    THEN
  LOOP
  2DROP 2DROP FALSE
;
```

`table-lookup` 的搜尋算法：
1. 遍歷符號表中的每條記錄
2. 取得記錄的名稱偏移（`I dl-rec# * + @`）
3. 若偏移為負（程式庫名稱），取反獲得字串表偏移
4. 使用 `szcompare` 比較搜尋字串與記錄名稱（ASCIIZ 比較）
5. 找到則回傳 `sym# TRUE`，未找到則回傳 `FALSE`

`name-lookup`（第 130~140 行）先搜尋 `dl-first`（預載入表），再搜尋 `dl-second`（執行期表），最後呼叫 `table-enter` 新增。

---

## 4. 檔案存取常數（posix/const.f）

```forth
\ const.f:6-16
O_RDONLY CONSTANT R/O    \ 0 — 唯讀開啟
O_WRONLY CONSTANT W/O    \ 1 — 唯寫開啟
O_RDWR   CONSTANT R/W    \ 2 — 讀寫開啟
```

這些常數直接映射 Linux 的 `fcntl.h` 定義，由 `config.auto.f` 在編譯期產生。SP-Forth 使用 `FAM`（File Access Method）概念，其中 `R/O`、`W/O`、`R/W` 是 ANSI Forth 94 標準定義的檔案存取方法常數。

---

## 5. 記憶體管理（posix/memory.f）深入解析

### 5.1 ALLOCATE：帶除錯標記的記憶體分配

```forth
\ memory.f:73-91
: ALLOCATE ( u -- a-addr ior )
  CELL ADD-SIZE DUP IF EXIT THEN DROP   \ 檢查溢位，計算 u+CELL
  1 SWAP 2 calloc-adr @ C-CALL          \ calloc(1, u+CELL)
  DUP IF CELL+ (FIX-MEMTAG) 0 EXIT THEN -300
;
```

`ALLOCATE` 的記憶體佈局：

```
  ┌──────────────┐ ← a-addr - CELL（calloc 回傳的位址 - 1）
  │ u + CELL     │ ← 除錯標記：記錄分配大小
  ├──────────────┤ ← a-addr（回傳給使用者的位址）
  │              │
  │ 使用者資料   │ ← u bytes
  │              │
  └──────────────┘
```

`(FIX-MEMTAG)`（第 65~67 行）寫入除錯標記：

```forth
: (FIX-MEMTAG) ( addr -- addr ) 2R@ DROP OVER CELL- ! ;
```

它在分配的記憶體前 4 bytes 寫入分配大小，用於除錯和 `RESIZE` 操作。

### 5.2 FREE：帶空指標檢查的釋放

```forth
\ memory.f:93-102
: FREE ( a-addr -- ior )
  DUP 0= IF DROP -12 EXIT THEN \ -12 "argument type mismatch"
  CELL- 1 <( )) free DROP 0
;
```

`FREE` 先檢查空指標（0），然後將指標向前移動一個 CELL（跳過除錯標記），呼叫 C 的 `free()`。`1 <( )) free` 表示 `free(ptr-CELL)` — 1 個引數，呼叫 `free`。

### 5.3 RESIZE：記憶體重新配置

```forth
\ memory.f:104-122
: RESIZE ( a-addr1 u -- a-addr2 ior )
  DUP 0= IF -12 EXIT THEN               \ 空指標檢查
  CELL+ SWAP CELL- SWAP 2 realloc-adr @ C-CALL  \ realloc(ptr-CELL, u+CELL)
  DUP IF CELL+ 0 ELSE -300 THEN
;
```

`RESIZE` 使用 `realloc()` 重新配置記憶體。注意引數調整：`CELL+ SWAP CELL-` 將使用者指標轉換為 `realloc` 期望的指標。

### 5.4 ALLOCATE-RWX：可執行記憶體分配

```forth
\ memory.f:129-147
: ALLOCATE-RWX ( +n -- a-addr 0 | x ior )
  MEMORY-PAGESIZE 1- CELL+ ADD-SIZE DUP IF EXIT THEN DROP
  DUP 0< IF -24 EXIT THEN
  MEMORY-PAGESIZE NEGATE AND             \ 對齊到分頁邊界
  >R (( MEMORY-PAGESIZE R@ )) aligned_alloc ( 0|a-addr1 )
  DUP 0= -300 AND ( 0|a-addr1 -300|0 )
  DUP IF NIP R> SWAP EXIT THEN DROP
  (( DUP  R>  0 PROT_READ OR PROT_WRITE OR PROT_EXEC OR  )) mprotect ?ERR NIP
  DUP IF >R  FREE  R>  ( ior2 ior ) EXIT THEN DROP
  CELL+ (FIX-MEMTAG) 0 ( a-addr 0 )
;
```

`ALLOCATE-RWX` 分配可讀、可寫、可執行的記憶體。這是 JIT 編譯和自修改程式碼的基礎：

1. **大小對齊**：將分配大小向上對齊到 `MEMORY-PAGESIZE`（4 KiB）
2. **aligned_alloc**：分配分頁對齊的記憶體（`mprotect` 要求分頁對齊）
3. **mprotect**：設定記憶體保護為 `PROT_READ | PROT_WRITE | PROT_EXEC`
4. **除錯標記**：`CELL+ (FIX-MEMTAG)` 寫入分配大小標記

若 `mprotect` 失敗，分配的記憶體會被釋放，回傳錯誤碼。

### 5.5 ALLOCATE-THREAD-MEMORY：執行緒本地儲存

```forth
\ memory.f:47-57
: ALLOCATE-THREAD-MEMORY ( -- )
  USER-OFFS @ EXTRA-MEM @ CELL+ + 1 2 calloc-adr @ C-CALL DUP
  IF
     DUP CELL+ TlsIndex!        \ TLS 索引指向 CELL+1 的位置
     THREAD-MEMORY !             \ 儲存分配位址到 THREAD-MEMORY
     R> R@ TlsIndex@ CELL- ! >R \ 在 TLS 區塊前寫入回返地址（?）
  ELSE
     -300 THROW                  \ 記憶體分配失敗
  THEN
;
```

每個執行緒需要獨立的 USER 變數空間（透過 EDI 暫存器存取）。`ALLOCATE-THREAD-MEMORY` 分配 `USER-OFFS @ + EXTRA-MEM @ + CELL+` 位元組的記憶體，並透過 `TlsIndex!` 設定執行緒本地儲存指標。

### 5.6 errno 存取與錯誤檢查

```forth
\ memory.f:24-30
: errno ( -- n )
  (()) __errno_location @
;

: ?ERR ( -1 -- -1 err | x -- x 0 )
  DUP -1 = IF errno ELSE 0 THEN
;
```

`errno` 透過 `__errno_location`（glibc 的執行緒安全 errno 存取函數）取得 C 函式庫的 errno 值。`?ERR` 是便利函數：若系統呼叫回傳 -1，則查詢 errno；否則回傳原始值和 0。

---

## 6. 例外處理（posix/except.f）

### 6.1 標準 I/O Handle

```forth
\ except.f:8-11
H-STDIN  VALUE  H-STDIN    \ 標準輸入
H-STDOUT VALUE  H-STDOUT    \ 標準輸出
H-STDERR VALUE  H-STDERR    \ 標準錯誤
         0 VALUE  H-STDLOG   \ 日誌（未使用）
```

POSIX 版的 handle 值直接使用 Unix file descriptor（0, 1, 2），而非 Windows 版的 HANDLE。

### 6.2 AT-THREAD-FINISHING / AT-PROCESS-FINISHING

```forth
\ except.f:13-14
: AT-THREAD-FINISHING ( -- ) ... ;
: AT-PROCESS-FINISHING ( -- ) ... FREE-THREAD-MEMORY ;
```

這兩個字是**分散式冒號**（Scattered Colon）定義——它們使用 `...` 和 `;..` 語法（定義在 `tc_spf.F` 中），允許在不同模組中追加定義。`AT-THREAD-FINISHING` 目前為空操作（`...` 建立跳轉分支），`AT-PROCESS-FINISHING` 釋放執行緒記憶體。

### 6.3 HALT：程序終止

```forth
\ except.f:16-19
: HALT ( ERRNUM -> )
  AT-THREAD-FINISHING
  AT-PROCESS-FINISHING
  1 <( )) exit
;
```

`HALT` 執行三個步驟：
1. 執行執行緒清理鉤子
2. 執行程序清理鉤子（包括 `FREE-THREAD-MEMORY`）
3. 呼叫 `exit(1)` 終止程序

`1 <( )) exit` 是 C 函數呼叫語法：`1` 個引數，呼叫 `exit` 函數。

---

## 7. 檔案 I/O（posix/io.f）深入解析

### 7.1 C 函數呼叫語法

SP-Forth 的 POSIX 檔案 I/O 使用 `(( ... ))` 語法呼叫 C 標準庫函數：

```forth
\ io.f:6-10
: CLOSE-FILE ( fileid -- ior )
  1 <( )) close ?ERR NIP
;
```

`1 <( )) close` 表示：「1 個引數，呼叫 `close`」。`?ERR` 檢查回傳值是否為 -1，若是則查詢 `errno`。

### 7.2 CREATE-FILE 與 OPEN-FILE

```forth
\ io.f:12-23
: CREATE-FILE ( c-addr u fam -- fileid ior )
  NIP
  O_CREAT OR O_TRUNC OR 2 <( 0x1A4 ( 0644 = rw-r--r-- ) )) open64 ?ERR
;

: OPEN-FILE ( c-addr u fam -- fileid ior )
  NIP 2 <( )) open64 ?ERR
;
```

`CREATE-FILE` 使用 `open64` 系统调用，标志为 `O_CREAT | O_TRUNC | 0644`，支持大檔案（>2 GiB）。
`OPEN-FILE` 直接使用 `open64`，參數為檔案名和 FAM。

### 7.3 READ-LINE：逐行讀取的實作

```forth
\ io.f:95-135
: READ-LINE ( c-addr u1 fileid -- u2 flag ior )
  DUP >R
  FILE-POSITION IF 2DROP 0 0 THEN _fp1 ! _fp2 !
  LTL @ +
  OVER _addr !
  R@ READ-FILE ?DUP IF NIP RDROP 0 0 ROT EXIT THEN
  DUP >R 0= IF RDROP RDROP 0 0 0 EXIT THEN    \ 空檔案
  _addr @ R@ EOLN SEARCH
  IF   \ 找到換行
     DROP _addr @ -
     DUP
     LTL @ + S>D _fp2 @ _fp1 @ D+ RDROP R> REPOSITION-FILE DROP
  ELSE \ 未找到換行
     2DROP
     R> RDROP  \ 最後一行
  THEN
  TRUE 0
;
```

`READ-LINE` 的實作比標準要求更複雜：
1. 儲存目前檔案位置（`FILE-POSITION`）
2. 讀取最大行長的資料（`READ-FILE`）
3. 搜尋換行字元（`EOLN SEARCH`）
4. 若找到換行，調整檔案位置到行尾（`REPOSITION-FILE`）
5. 若未找到，回傳讀取的位元組數（最後一行）

`LTL`（Line Terminator Length）是換行終止符的長度，POSIX 下為 1（LF），Windows 下為 2（CRLF）。

### 7.4 FILE-EXIST 與 FILE-EXISTS

```forth
\ io.f:186-198
: FILE-EXIST ( addr u -- f )
  DROP >R (( _STAT_VER R> API-BUFFER )) __xstat 0=
;

: FILE-EXISTS ( addr u -- f )
  FILE-EXIST 0 = IF FALSE EXIT THEN
  API-BUFFER STAT_ST_MODE + @ S_IFDIR AND 0 =
;
```

`FILE-EXIST` 使用 `__xstat`（或 `stat`）系統呼叫檢查檔案是否存在。`FILE-EXISTS` 進一步檢查路徑是否為普通檔案（排除目錄）。

注意 `__xstat` 的使用：現代 glibc 版本使用 `__xstat`（帶版本號的 stat 系統呼叫），舊版本直接使用 `stat`。SP-Forth 透過 `[DEFINED] _STAT_VER [IF]` 來選擇。

---

## 8. 控制台 I/O（posix/con_io.f）

```forth
\ con_io.f:6-18
0 VALUE  H-STDIN    \ 標準輸入（file descriptor 0）
1 VALUE  H-STDOUT   \ 標準輸出（file descriptor 1）
2 VALUE  H-STDERR   \ 標準錯誤（file descriptor 2）
0 VALUE  H-STDLOG

VECT ANSI><OEM
' NOOP ' ANSI><OEM TC-VECT!    \ POSIX 不需要 OEM 轉換

VECT KEY
' FALSE ' KEY   TC-VECT!        \ 預設不實作鍵盤讀取

VECT KEY?
' FALSE ' KEY?  TC-VECT!        \ 預設不實作鍵盤檢查
```

POSIX 版的控制台 I/O 極為簡潔：
- Handle 值直接使用 Unix file descriptor
- `ANSI><OEM` 為空操作（Windows 版需要 OEM/ANSI 編碼轉換）
- `KEY` 和 `KEY?` 預設為 `FALSE`（非互動模式下無鍵盤輸入）

互動模式（REFILL-STDIN）透過 `ACCEPT` 實作鍵盤讀取，不需要 `KEY` 和 `KEY?`。

---

## 9. 環境查詢（posix/envir.f）

### 9.1 ENVIRONMENT? 的三層搜尋

```forth
\ envir.f:31-57
: ENVIRONMENT? ( c-addr u -- false | i*x true )
  OVER 1 <( )) getenv ?DUP IF NIP NIP ASCIIZ> TRUE EXIT THEN

  2DUP ENVIRONMENT-WORDLIST
  SEARCH-WORDLIST IF NIP NIP EXECUTE TRUE EXIT THEN

  S" lib/ENVIR.SPF" +ModuleDirName 2DUP FILE-EXIST 0=
  IF 2DROP S" ENVIR.SPF" +ModuleDirName THEN
  R/O OPEN-FILE-SHARED
  IF ['] (ENVIR?) RECEIVE-WITH IF 0 THEN
     DUP >R CLOSE-FILE THROW
  ELSE 2DROP DROP 0 THEN
;
```

搜尋順序：
1. **系統環境變數**：透過 `getenv()` 查詢
2. **FORTH 環境詞彙表**：`ENVIRONMENT-WORDLIST` 中定義的常數
3. **環境設定檔**：`lib/ENVIR.SPF` 或 `ENVIR.SPF`

`(ENVIR?)`（第 22~29 行）逐行讀取設定檔，比對環境字串名稱：

```forth
: (ENVIR?) ( addr u -- false | i*x true )
  BEGIN REFILL WHILE
    2DUP PARSE-NAME COMPARE
    0= IF 2DROP INTERPRET TRUE EXIT THEN
  REPEAT 2DROP FALSE
;
```

### 9.2 USE：載入動態程式庫（執行期版本）

```forth
\ envir.f:112-115
: USE ( "name" -- )
  PARSE-NAME 2DUP SYSTEM-PAD CZMOVE
  SYSTEM-PAD dlopen2 TRUE name-lookup DROP
;
```

`USE` 是執行期版本的程式庫載入（與交叉編譯期的 `USE` 不同）。它：
1. 將程式庫名稱拷貝到 `SYSTEM-PAD`（因為 `dlopen2` 需要 ASCIIZ 字串）
2. 呼叫 `dlopen2` 載入程式庫
3. 將程式庫名稱加入符號表（`name-lookup` with `library? = TRUE`）

### 9.3 )) 與 (())：執行期外部函數呼叫

```forth
\ envir.f:137-155
: )) ( "name" -- )
  PARSE-NAME symbol-lookup
  STATE @ IF
    ['] ())) COMPILE,
    compile-call
  ELSE
    ())) 1- SWAP symbol-call
  THEN ; IMMEDIATE

: (()) ( "name" -- )
  PARSE-NAME symbol-lookup
  STATE @ IF
    0 [COMPILE] LITERAL
    compile-call
  THEN ; IMMEDIATE
```

執行期版本與交叉編譯期版本的差異：

| 特性 | 交叉編譯期版本（tc-dl-imm.f） | 執行期版本（envir.f） |
|------|------|------|
| 編譯模式 | `())-adr COMPILE,` + `TC-LIT,` | `['] ())) COMPILE,` + `compile-call` |
| 直譯模式 | 不實作 | `(())` 呼叫 `symbol-call` |
| `symbol-call-adr` | 透過 `TC-VECT!` 設定 | 直接使用 `symbol-call` |

`compile-call`（第 126~134 行）編譯外部函數呼叫：

```forth
: compile-call ( n -- )
  [COMPILE] LITERAL                       \ 編譯引數數量
  ['] symbol-address COMPILE,              \ 編譯 symbol-address 呼叫
  (__ret2) @ IF
    ['] C-CALL2                           \ 64 位元回傳值
  ELSE
    ['] C-CALL                            \ 32 位元回傳值
  THEN COMPILE,
  (__ret2) 0!
;
```

### 9.4 DECODE-ERROR 與 ERROR2

```forth
\ envir.f:78-97
: DECODE-ERROR ( n u -- c-addr u )
  ... DROP
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

錯誤訊息解碼流程：
1. 嘗試開啟 `lib/SPF.ERR` 或 `SPF.ERR` 錯誤訊息檔案
2. 若檔案存在，逐行搜尋匹配的錯誤碼，回傳對應的訊息字串
3. 若檔案不存在，回傳 `"ERROR #{code}"` 格式的字串

`ERROR2`（第 99~107 行）是最終的錯誤處理：

```forth
: ERROR2 ( ERR-NUM -> )
  DUP 0= IF DROP EXIT THEN          \ 錯誤碼為 0，不處理
  PRINT-LAST-WORD                    \ 顯示錯誤位置的游標
  DUP -2 = IF DROP LAST-ERRMSG TYPE CR EXIT THEN  \ ABORT" 訊息
  BASE @ >R DECIMAL
  FORTH_ERROR DECODE-ERROR TYPE     \ 顯示錯誤碼和訊息
  R> BASE !
  CR
;
```

---

## 10. 平台定義字（posix/defwords.f）

### 10.1 EXTERN：外部函數包裝

```forth
\ defwords.f:11-18
: EXTERN ( xt1 n -- xt2 )
  HERE
  SWAP LIT,                          \ 編譯引數數量
  ['] FORTH-INSTANCE> COMPILE,        \ 進入 Forth 環境
  SWAP COMPILE,                       \ 編譯目標 XT
  ['] <FORTH-INSTANCE COMPILE,        \ 離開 Forth 環境
  RET,                                \ 返回
;
```

`EXTERN` 建立一個可被 C 呼叫的函數包裝器：

```
EXTERN 包裝器的記憶體佈局：
  ┌──────────────────┐ ← xt2
  │ PUSH n            │ ← 引數數量
  │ CALL FORTH-INSTANCE> │ ← 進入 Forth 環境（設定 EDI）
  │ CALL xt1           │ ← 執行目標 Forth 字
  │ CALL <FORTH-INSTANCE │ ← 離開 Forth 環境（恢復 EDI）
  │ RET                │ ← 返回 C 呼叫者
  └──────────────────┘
```

### 10.2 CALLBACK:：回呼函數

```forth
\ defwords.f:20-26
: CALLBACK: ( xt n "name" -- )
  EXTERN
  HEADER
  ['] _WNDPROC-CODE COMPILE,
  ,
;
```

`CALLBACK:` 建立一個 Windows 風格的回呼函數（POSIX 版也使用相同框架）：
1. `EXTERN` 建立包裝器代碼
2. `HEADER` 建立字頭
3. `_WNDPROC-CODE` 是回呼入口點
4. `,` 儲存包裝器位址

若你想對照**交叉編譯期**如何生成 target 端 callback stub，可再看 [03-cross-compiler.md](03-cross-compiler.md) 裡的 `TC-CALLBACK:`；兩者解決的是不同階段的 callback 問題。

### 10.3 TASK 與 TASK:：執行緒入口

```forth
\ defwords.f:28-36
: TASK ( xt1 -- xt2 )
  CELL EXTERN                    \ 1 個引數的包裝器
  HERE SWAP
  ['] _WNDPROC-CODE COMPILE,
  ,
;

: TASK: ( xt "name" -- )
  TASK CONSTANT
;
```

`TASK` 建立一個執行緒入口點，使用 1 個引數的 `EXTERN` 包裝器。`TASK:` 將其建立為具名常數。

### 10.4 ERASE-IMPORTS

```forth
\ defwords.f:42-50
: ERASE-IMPORTS
  WINAPLINK
  BEGIN @ DUP WHILE
    DUP 4 CELLS - 0!
  REPEAT DROP
;
```

`ERASE-IMPORTS` 清除所有動態連結的函數指標。每個匯入項目的第 5 個 cell（偏移 4 cells）是函數位址，設為 0 使得下次呼叫時重新解析。

---

## 11. 多執行緒（posix/mtask.f）

### 11.1 執行緒操作字

```forth
\ mtask.f:7-47
: START ( x task -- tid )
  0 >R RP@ 0 2SWAP SWAP 4 <( )) pthread_create
  IF RDROP 0 ELSE R> THEN
;

: SUSPEND ( tid -- )
  1 <( 19 ( SIGSTOP) )) pthread_kill DROP
;

: RESUME ( tid -- )
  1 <( 18 ( SIGCONT) )) pthread_kill DROP
;

: STOP ( tid -- )
  1 <( )) pthread_cancel DROP
;

: PAUSE ( ms -- )
  BEGIN
  DUP
  U>D 1000 UM/MOD SWAP 1000000 * >R >R
  (( RP@ 0 )) nanosleep DROP RDROP RDROP
  DUP -1 <> UNTIL
  DROP
;

: TERMINATE ( -- )
  (( -1 )) pthread_exit DROP
;

: THREAD-ID ( -- tid )
  (()) pthread_self
;
```

| 字 | 底層呼叫 | 說明 |
|----|---------|------|
| `START` | `pthread_create` | 建立新執行緒，回傳 `tid` |
| `SUSPEND` | `pthread_kill(SIGSTOP)` | 暫停執行緒 |
| `RESUME` | `pthread_kill(SIGCONT)` | 恢復執行緒 |
| `STOP` | `pthread_cancel` | 取消執行緒 |
| `PAUSE` | `nanosleep` | 睡眠指定毫秒 |
| `TERMINATE` | `pthread_exit` | 終止目前執行緒 |
| `THREAD-ID` | `pthread_self` | 取得目前執行緒 ID |

`START` 的引數傳遞使用了巧妙的堆疊操作：`0 >R RP@ 0 2SWAP SWAP 4 <( )) pthread_create` 傳遞 4 個引數給 `pthread_create`：`&tid`（RP@ 指向 R 堆疊上的位置）、`attr`（0 = 預設屬性）、`start_routine`（task XT）、`arg`（x 引數）。

一個較容易閱讀的等價範例是：

```forth
\ worker 的堆疊效果假設為 ( x -- )
123 ' worker START   \ 建立執行緒，將 123 當作 arg 傳給 worker
```

對應到 `pthread_create(&tid, 0, worker, 123)` 的四個參數位置：

| 參數 | 來源 |
|------|------|
| `&tid` | `RP@` 指向回返堆疊上的暫存儲存格 |
| `attr` | `0`（預設屬性） |
| `start_routine` | `task XT` |
| `arg` | `x` |

`PAUSE` 的實作將毫秒轉換為 `timespec` 結構（秒 + 微秒），然後呼叫 `nanosleep`。

---

## 12. 信號處理（posix/init.f）深入解析

### 12.1 signum>ior：信號到 Forth 例外的對應

```forth
\ init.f:37-52
: signum>ior ( code sig -- ior )
   DUP SIGSEGV = IF 2DROP -9 EXIT THEN
   DUP SIGILL = IF 2DROP -9 EXIT THEN
   DUP SIGBUS = IF 2DROP -23 EXIT THEN
   DUP SIGFPE = IF DROP
    DUP FPE_INTDIV = IF DROP -10 EXIT THEN
    DUP FPE_INTOVF = IF DROP -11 EXIT THEN
    DUP FPE_FLTDIV = IF DROP -42 EXIT THEN
    DUP FPE_FLTOVF = IF DROP -43 EXIT THEN
    DUP FPE_FLTUND = IF DROP -54 EXIT THEN
    DUP FPE_FLTRES = IF DROP -41 EXIT THEN
    DUP FPE_FLTINV = IF DROP -46 EXIT THEN
    DROP -55 EXIT
   THEN
   256 + NEGATE
;
```

信號到例外的對應表：

| 信號 | 子代碼 | Forth 例外 | 說明 |
|------|--------|-----------|------|
| SIGSEGV | — | -9 | 記憶體存取違規 |
| SIGILL | — | -9 | 不合法指令 |
| SIGBUS | — | -23 | 匯流排錯誤 |
| SIGFPE | FPE_INTDIV | -10 | 整數除以零 |
| SIGFPE | FPE_INTOVF | -11 | 整數溢位 |
| SIGFPE | FPE_FLTDIV | -42 | 浮點除以零 |
| SIGFPE | FPE_FLTOVF | -43 | 浮點溢位 |
| SIGFPE | FPE_FLTUND | -54 | 浮點下溢 |
| SIGFPE | FPE_FLTRES | -41 | 浮點不精確 |
| SIGFPE | FPE_FLTINV | -46 | 浮點無效操作 |
| 其他 | — | -(sig+256) | 信號碼 + 256 取反 |

### 12.2 (errsignal)：信號處理器

```forth
\ init.f:63-68
: (errsignal) ( ctxt siginfo num -- x )
    2>R
    DUP CONTEXT_EDI + @ TlsIndex!   \ 恢復 TLS 基底指標
    2R@ DUMP-TRACE                   \ 傾印堆疊追蹤
    2R> SWAP SIGINFO_CODE + @ SWAP signum>ior THROW
;
```

信號處理器的執行流程：

1. **恢復 EDI**：`CONTEXT_EDI + @ TlsIndex!` — 從 ucontext 中恢復 TLS 基底指標
2. **傾印追蹤**：`DUMP-TRACE` — 顯示錯誤位置、暫存器狀態和堆疊追蹤
3. **THROW**：將信號轉換為 Forth 例外並擲回

這是 SP-Forth 穩定性的關鍵：當 SIGSEGV 等致命信號發生時，Forth 不會崩潰，而是透過 `THROW` 進入例外處理機制，可以恢復執行。

### 12.3 DUMP-TRACE：堆疊追蹤傾印

```forth
\ init.f:15-34
: DUMP-TRACE ( context siginfo signo -- )
  IN-EXCEPTION @ IF DROP EXIT THEN   \ 避免遞迴例外
  TRUE IN-EXCEPTION !
  ROT ( siginfo signo context )
  OVER OVER CONTEXT_EIP + @ SWAP ( addr code ) DUMP-EXCEPTION-HEADER
  SWAP ( signo ) ." [" 1 <( )) strsignal ASCIIZ> TYPE ." ] "
  SWAP ( siginfo )
  ." Code:" DUP 2 CELLS + @ . ." At:" 3 CELLS + @ ADDR.
  CR
  >R
  R@ CONTEXT_ESP + @ ( esp )
  R@ CONTEXT_EAX + @ ( eax )
  R> CONTEXT_EBP + @ ( ebp )
  DUMP-TRACE-USING-REGS
  ." END OF EXCEPTION REPORT" CR
  FALSE IN-EXCEPTION !
;
```

`DUMP-TRACE` 從 ucontext 中提取暫存器狀態：
- `CONTEXT_EIP + @`：錯誤發生位址
- `CONTEXT_ESP + @`：堆疊指標
- `CONTEXT_EAX + @`：TOS（堆疊頂端）
- `CONTEXT_EBP + @`：資料堆疊指標

`DUMP-EXCEPTION-HEADER` 和 `DUMP-TRACE-USING-REGS` 使用這些暫存器值來重建 Forth 堆疊追蹤。

### 12.4 sigact 結構與信號處理器安裝

```forth
\ init.f:72-87
CREATE sigact
' errsignal >VIRT ,          \ sa_handler（指向 Forth 信號處理器）
SIZEOF_SIGSET ALLOT          \ sa_mask（信號遮罩，128 bytes）
SA_RESTART SA_SIGINFO + SA_NODEFER + , \ sa_flags
0  ,                           \ sa_restarter（未使用）

: set-errsignal-handler
   (( sigact CELL+ )) sigemptyset DROP
   (( SIGILL  sigact 0 )) sigaction DROP
   (( SIGBUS  sigact 0 )) sigaction DROP
   (( SIGFPE  sigact 0 )) sigaction DROP
   (( SIGSEGV sigact 0 )) sigaction DROP
;
```

`sigact` 是 `struct sigaction` 的 Forth 表示：
- `sa_handler`：指向 `errsignal`（透過 `>VIRT` 轉換為目標位址）
- `sa_mask`：信號遮罩（初始化為空）
- `sa_flags`：`SA_RESTART | SA_SIGINFO | SA_NODEFER`

`SA_SIGINFO` 使得信號處理器接收三個引數（siginfo_t），而不僅僅是信號碼。`SA_NODEFER` 避免信號處理期間遮蔽自身，防止遞迴死鎖。

### 12.5 PROCESS-INIT：程序初始化

```forth
\ init.f:89-98
: PROCESS-INIT ( n -- )
  ERASE-IMPORTS                    \ 清除動態連結表
  dl-init                          \ 初始化動態連結
  ['] dl-no-symbol  TO symbol-not-found-error
  ['] dl-no-library TO library-not-found-error
  ALLOCATE-THREAD-MEMORY           \ 分配 TLS 記憶體
  POOL-INIT                        \ 初始化堆疊池
  set-errsignal-handler            \ 安裝信號處理器
  ['] AT-PROCESS-STARTING ERR-EXIT \ 執行程序啟動鉤子
;
```

PROCESS-INIT 是 SP-Forth POSfix 正式啟動流程的核心：

1. **ERASE-IMPORTS**：清除所有動態連結的函數指標
2. **dl-init**：初始化動態連結子系統（dlopen 主程式）
3. **設定錯誤處理向量**：`dl-no-symbol` 和 `dl-no-library` 提供友善的錯誤訊息
4. **ALLOCATE-THREAD-MEMORY**：分配主執行緒的 TLS 記憶體
5. **POOL-INIT**：初始化資料堆疊和回返堆疊的記憶體池
6. **set-errsignal-handler**：安裝 SIGILL/SIGBUS/SIGFPE/SIGSEGV 處理器
7. **AT-PROCESS-STARTING**：執行程序啟動鉤子

---

## 13. 模組路徑管理（posix/module.f）

```forth
\ module.f:4-17
0 VALUE ARGC          \ 命令列引數數量
0 VALUE ARGV           \ 命令列引數陣列

: is_path_delimiter ( c -- flag )
  [CHAR] / =
;

: ModuleName ( -- addr u )
  (( S" /proc/self/exe" DROP SYSTEM-PAD 1024 )) readlink
  DUP -1 = IF DROP 0 THEN
  SYSTEM-PAD SWAP
;
```

POSIX 版的模組路徑管理使用 Linux 特有的 `/proc/self/exe` 符號連結和 `readlink` 系統呼叫來取得可執行檔的絕對路徑。這比 Windows 版的 `GetModuleFileName` 更簡潔。

`is_path_delimiter` 只需檢查 `/`（POSIX 路徑分隔字元），而 Windows 版需要檢查 `\` 和 `/` 兩種。

---

## 14. ELF 映像儲存（posix/save.f）深入解析

### 14.1 XSAVE 流程詳解

```forth
\ save.f:382-457
: SAVE ( c-addr u -- )
  2DUP forth.ld                    \ 產生連結器腳本
  2DUP <# S" .o" HOLDS HOLDS 0 0 #>
  R/W CREATE-FILE THROW >R           \ 開啟 .o 檔案
  elf-header elf-header-size R@ WRITE-FILE THROW    \ ELF 標頭
  
  HERE FORTH-START - DUP            \ 計算 .forth 段大小
  sections 5 elf-section-size * + 5 CELLS + !       \ 更新段表
  
  ... 更新 .space, .dltable, .dlstrings 段 ...
  
  sections 9 elf-section-size * R@ WRITE-FILE THROW \ 段表
  
  .shstrtab .shstrtab# R@ WRITE-FILE THROW          \ 段名稱字串表
  .strtab .strtab# R@ WRITE-FILE THROW              \ 符號名稱字串表
  .symtab .symtab# R@ WRITE-FILE THROW               \ 符號表
  .rel.forth .rel.forth# R@ WRITE-FILE THROW         \ 重定位表
  
  dl-first dl-first-strtab                          \ 儲存前：儲存動態連結表
  0 TO dl-first  0 TO dl-first-strtab              \ 清空指標（避免寫入舊值）
  dl-first# DUP dl-second# + TO dl-first#           \ 合併計數
  
  dlopen-adr @ dlsym-adr @ dlerror-adr @           \ 儲存前：備份 C 函數指標
  realloc-adr @ calloc-adr @ write-adr @
  
  dlopen-adr 0! dlsym-adr 0! dlerror-adr 0!        \ 清空指標（寫入 0）
  realloc-adr 0! calloc-adr 0! write-adr 0!
  
  R@ FORTH-START HERE OVER - 3 4 PICK C-CALL DROP   \ 寫入 .forth 段
  
  write-adr ! calloc-adr ! realloc-adr !             \ 恢復 C 函數指標
  dlerror-adr ! dlsym-adr ! dlopen-adr !
  
  TO dl-first# TO dl-first-strtab TO dl-first        \ 恢復動態連結表指標
  
  dl-first-strtab @ CELL- reloc-dl-second-strings
  
  dl-first dl-first# dl-rec# * R@ WRITE-FILE THROW   \ 第一符號表
  dl-second dl-second# dl-rec# * R@ WRITE-FILE THROW \ 第二符號表
  
  ... 寫入字串表 ...
  
  R> CLOSE-FILE THROW
  
  DROP >R                         \ gcc 連結
  (( HERE S" gcc ..." DROP ... sprintf DROP HERE system
;
```

XSAVE 的關鍵步驟：

1. **產生連結器腳本**（`.ld` 檔案）：定義 `.forth` 和 `.space` 段的佈局
2. **寫入 ELF 標頭**：包含 ELF 魔數、架構資訊、段表偏移等
3. **更新段表**：修正 `.forth`、`.space`、`.dltable`、`.dlstrings` 的大小和位置
4. **寫入符號表和重定位表**：包含 `main`、`dlopen`、`dlsym` 等外部符號
5. **寫入 .forth 段**：透過 `C-CALL write()` 寫入 Forth 映像資料
6. **寫入動態連結表**：`.dltable` 和 `.dlstrings`
7. **呼叫 gcc 連結**：產生最終可執行檔

### 14.2 ELF 段表結構

```forth
\ save.f:230-341
CREATE sections
\ 段 0：空段（NULL）
0 , 0 , 0 , 0 , 0 , 0 , 0 , 0 , 0 , 0

\ 段 1：.shstrtab（段名稱字串表）
1 , 3 , 0 , 0 , ' .shstrtab# EXECUTE offset,size, 0 , 0 , 1 , 0

\ 段 2：.strtab（符號名稱字串表）
11 , 3 , 0 , 0 , ' .strtab# EXECUTE offset,size, 0 , 0 , 1 , 0

\ 段 3：.symtab（符號表）
19 , 2 , 0 , 0 , ' .symtab# EXECUTE offset,size, 2 , 5 , 4 , ' elf-symbol-size EXECUTE ,

\ 段 4：.rel.forth（重定位表）
27 , 9 , 0 , 0 , ' .rel.forth# EXECUTE offset,size, 3 , 5 , 4 , ' elf-rel-size EXECUTE ,

\ 段 5：.forth（程式碼段）
31 , 1 , 0x7 , 0 , ' elf-offset EXECUTE , 0 , 0 , 4 , 0

\ 段 6：.space（BSS 段）
38 , 8 , 0x7 , 0 , 0 , 0 , 0 , 4 , 0

\ 段 7：.dltable（動態連結表）
45 , 1 , 0x3 , 0 , 0 , 0 , 0 , 4 , 0

\ 段 8：.dlstrings（動態連結字串表）
54 , 3 , 0x2 , 0 , 0 , 0 , 0 , 4 , 0
```

每個段表項目包含 10 個 32 位元欄位（40 bytes），符合 ELF32 段表格式：

| 偏移 | 欄位 | 說明 |
|------|------|------|
| +0 | sh_name | 名稱偏移（.shstrtab 中） |
| +4 | sh_type | 段類型（SHT_PROGBITS 等） |
| +8 | sh_flags | 段旗標 |
| +12 | sh_addr | 虛擬位址 |
| +16 | sh_offset | 檔案偏移 |
| +20 | sh_size | 段大小 |
| +24 | sh_link | 關聯段索引 |
| +28 | sh_info | 額外資訊 |
| +32 | sh_addralign | 對齊要求 |
| +36 | sh_entsize | 項目大小 |

### 14.3 重定位項目

```forth
\ save.f:166-198
CREATE .rel.forth
\ .dltable 指標
' dl-first 5 + .forth - , 3 8 LSHIFT 1 OR ,
\ .dlstrings 指標
' dl-first-strtab 5 + .forth - , 4 8 LSHIFT 1 OR ,
\ dlopen 函數指標
' dlopen-adr >BODY .forth - , 6 8 LSHIFT 1 OR ,
\ dlsym 函數指標
' dlsym-adr EXECUTE .forth - , 7 8 LSHIFT 1 OR ,
\ ... 更多重定位項目 ...
```

每個重定位項目是 8 bytes：

| 欄位 | 大小 | 說明 |
|------|------|------|
| r_offset | 4 bytes | 重定位位址（段內偏移） |
| r_info | 4 bytes | 符號索引（高 24 bits）+ 類型（低 8 bits） |

類型 `1` = `R_386_32`（絕對 32 位元重定位），是 ELF386 最常見的重定位類型。

### 14.4 gcc 連結命令

```forth
\ save.f:448-457
(( HERE
  S" gcc -v 2>&1 | grep -F --silent -- '--enable-default-pie' && gcc_nopie='-no-pie' ;" DROP
  S" %s gcc %s.o -Wl,%s.ld -ldl -lpthread -m32 $gcc_nopie -v -o %s" DROP
  SWAP
  R@ R@ R>
)) sprintf DROP
HERE system
```

連結命令的組成：
- `gcc -m32`：32 位元編譯
- `-Wl,xxx.ld`：使用自訂連結器腳本
- `-ldl -lpthread`：連結動態載入和執行緒程式庫
- `$gcc_nopie`：若 gcc 啟用 PIE（Position Independent Executable），加入 `-no-pie` 選項
- `-v`：詳細輸出

### 14.5 reloc-dl-second-strings

```forth
\ save.f:344-353
: reloc-dl-second-strings ( off -- )
  dl-second# 0 ?DO
    dl-second I dl-rec# * +
    DUP >R @ DUP 0< IF
      NEGATE OVER + NEGATE       \ 程式庫名稱：調整為新偏移
    ELSE
      OVER +                      \ 函數名稱：加上新偏移
    THEN R> !
  LOOP DROP
;
```

在儲存 ELF 時，第二符號表的字串偏移需要重新定位。程式庫名稱（負偏移）和函數名稱（正偏移）的調整方式不同。

---

## 15. 技術總結

### 15.1 SP-Forth POSIX 平台的核心設計特點

1. **C 呼叫約定橋接**：`C-CALL` 使用 cdecl 呼叫約定，從 Forth 堆疊推入 x86 堆疊，呼叫 C 函數後回收堆疊。回傳值透過 EAX（32 位元）或 EAX:EDX（64 位元）自然對應 TOS-in-EAX 模型。

2. **動態連結兩層架構**：預載入符號表（dl-first）在編譯期填充，執行期符號表（dl-second）按需增長。符號解析透過 `dlsym` 延遲進行，解析後快取。

3. **`((` / `))` 外部函數語法**：提供類似 C 函數呼叫的語法糖，自動計算引數數量並透過 `symbol-call` 呼叫。`__ret2` 旗標控制 64 位元回傳值。

4. **信號處理器與例外橋接**：POSIX 信號（SIGSEGV/SIGILL/SIGFPE 等）透過 `sigaction` 處理器轉換為 Forth 例外（THROW），並自動恢復 EDI（TLS 基底）暫存器。

5. **ELF 可重定位輸出**：POSIX 版將 Forth 映像儲存為 ELF `.o` 檔案，透過 gcc 連結為可執行檔。重定位處理確保所有內部指標在載入時被正確修正。

6. **帶除錯標記的記憶體管理**：`ALLOCATE` 在分配的記憶體前 4 bytes 儲存分配大小，用於除錯和 `RESIZE`。`ALLOCATE-RWX` 使用 `aligned_alloc` + `mprotect` 分配可執行記憶體。

7. **多執行緒支援**：透過 `pthread_create`/`pthread_kill`/`pthread_cancel` 實作執行緒管理。`FORTH-INSTANCE>` 和 `<FORTH-INSTANCE` 在執行緒邊界切換 TLS 基底指標（EDI），確保每個執行緒有獨立的 USER 變數空間。

8. **分散式冒號定義**（Scattered Colon）：`AT-THREAD-FINISHING`、`AT-PROCESS-FINISHING` 等字使用 `...` 和 `;..` 語法，允許在不同模組中追加行為，實現模組化的初始化/清理流程。

9. **ENVIRONMENT? 的三層搜尋**：先查系統環境變數（`getenv`），再查 Forth 詞彙表，最後查環境設定檔（`ENVIR.SPF`）。

10. **READ-LINE 的位置追蹤**：使用 `FILE-POSITION` 儲存目前位置，讀取後搜尋換行，再透過 `REPOSITION-FILE` 回到行尾，確保跨行讀取的正確性。
