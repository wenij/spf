# SP-Forth/4 原始碼追蹤 — 獨立執行檔生成與 SAVE 機制

> 定位：說明 SP-Forth 如何把目前系統映像儲存成 OS 可直接執行的 ELF / PE 檔案。
>
> 本章聚焦「不需要另外用 `spf4` 去直譯 source 檔」的 standalone executable 模型：`SAVE`、`SAVE-WITH-RESERVE`、POSIX ELF、Windows PE、entry point 與 runtime startup。

---

## 1. 先釐清：SP-Forth 的 standalone 是什麼？

在 SP-Forth 裡，獨立執行檔不是「把一個 Forth source 檔翻譯成只含機器碼的小程式」。更精確地說，它是：

```text
目前的 Forth 系統狀態
  + 已編譯進字典的 words
  + Forth runtime / compiler / interpreter 機制
  + platform initialization
  + 動態連結支援
  + 可選的預留字典空間
→ SAVE
→ OS-native executable image
```

所以 `SAVE` 產出的檔案可以被 OS loader 直接執行；它不需要外部再提供一個 `spf4` interpreter 去讀 source。原因不是「完全沒有 interpreter」，而是 **interpreter / compiler / runtime 已經被包含在輸出的 executable image 裡**。

官方使用者文件也這樣描述 `SAVE`：`SAVE ( a u -- )` 會把整個系統，包括所有 wordlists（temporary wordlists 除外），儲存成指定路徑的 executable file。console mode 的 entry point 由 `<MAIN>` 設定，GUI mode 則由 `MAINX` 設定；`?CONSOLE` / `?GUI` 決定模式，`SPF-INIT?` 控制 command line 與 `spf4.ini` 自動載入行為。

---

## 2. 先看使用者層：如何儲存一個 executable？

官方文件給的 console / GUI 例子如下：

```forth
0 TO SPF-INIT?
' ANSI>OEM TO ANSI><OEM
TRUE TO ?GUI
' NOOP TO <MAIN>
' run MAINX !
S" gui.exe" SAVE
```

或 console mode：

```forth
' run TO <MAIN>
S" console.exe" SAVE
```

這裡的關鍵是：

| 字 / 變數 | 用途 |
|-----------|------|
| `SAVE ( c-addr u -- )` | 把目前系統映像儲存成 executable（POSIX 與 Windows 各有實作） |
| `<MAIN>` | console mode 的入口 VECT（vectored word） |
| `MAINX` | GUI mode 的入口 VARIABLE |
| `?CONSOLE` / `?GUI` | 選擇 PE subsystem / 啟動模式 |
| `SPF-INIT?` | 控制是否處理 command line 與 `spf4.ini` |

因此要做自己的 standalone app，概念流程是：

```forth
\ 1. 載入或定義你的應用程式
INCLUDED myapp.f

\ 2. 設定啟動入口
' MAIN TO <MAIN>

\ 3. 儲存成 executable
S" myapp" SAVE
```

實際上是否能完全「像傳統 app」一樣啟動，取決於你如何設定 `<MAIN>` / `MAINX`、是否保留 `QUIT` 互動迴圈、是否需要 command-line processing、以及平台是 POSIX 還是 Windows。

---

## 3. `SAVE`、`SAVE-WITH-RESERVE`、`XSAVE`、`TSAVE` 的角色

| 名稱 | 主要平台 / 情境 | 作用 |
|------|-----------------|------|
| `SAVE` | POSIX / Windows runtime | 把目前 Forth image 儲存成 executable |
| `SAVE-WITH-RESERVE` | 建立 `spf4e` 或需要額外字典空間時 | 儲存 image，並額外預留未使用 dictionary space |
| `XSAVE` | 產生 POSIX 目標映像（包含 native build 與交叉編譯情境） | 寫出 ELF object / image，處理 target virtual address relocation |
| `TSAVE` / `(SAVE-WITH-RESOURCES)` | Windows PE + resources | 寫出 PE executable，支援 resource section |

`SAVE-WITH-RESERVE` 最常見的例子是建構 `spf4e`：

```makefile
echo '10 1024 * 1024 * S" ../spf4e" SAVE-WITH-RESERVE BYE' \
  | ./spf4 lib/ext/spf4e.f
```

意思是：

1. 用 `spf4` 載入 `lib/ext/spf4e.f`。
2. 把可用標準字與常用 extension 編進目前 image。
3. 額外預留 10 MiB dictionary space。
4. 儲存成新的 executable：`spf4e`。

這說明 `spf4e` 不是「另一套 C 程式」；它是 `spf4` 自我擴充後再 `SAVE` 出來的 executable image。

---

## 4. POSIX 路徑：ELF `.o` + gcc linker

POSIX / Linux 的生成流程是：

```text
宿主 Forth（spf4orig）執行 src/spf.f
        ↓
產生 target Forth image
        ↓
XSAVE / SAVE 寫出 ELF relocatable object：spf4.o
        ↓
產生 linker script：forth.ld
        ↓
gcc -m32 -Wl,forth.ld -ldl -lpthread -no-pie
        ↓
OS 可直接執行的 spf4 / spf4e
```

在建構 `spf4` 時，Makefile 大致做：

```text
posix/config.c → posix/config.auto.f
spf4orig src/spf.f → spf4.o
gcc spf4.o + forth.ld → spf4
spf4 + lib/ext/spf4e.f + SAVE-WITH-RESERVE → spf4e
```

### 4.1 為什麼 POSIX 要經過 gcc？

SP-Forth 產生的是 ELF relocatable object，而不是完整 executable。它負責寫出：

- ELF header
- section headers
- `.forth` / `.space`
- dynamic linking tables
- symbol table
- relocation entries

然後交給 `gcc` / `ld` 產生 OS loader 需要的 final executable layout。這樣可以把 platform-specific linking、program header、libc/libdl/pthread 等細節交給成熟 linker 處理。

### 4.2 `-no-pie` 為什麼重要？

SP-Forth 使用固定 image address model；在 POSIX 路徑中，`.forth` 會依 `IMAGE-START` 安排到固定位置附近。PIE（position independent executable）會讓載入位址可變，破壞這種固定位址與 relocation 假設。因此建構流程會偵測 GCC 是否預設 PIE，必要時加上 `-no-pie`。`IMAGE-BASE` 這個名稱則主要出現在 Windows PE 語境。

---

## 5. POSIX ELF 內部結構

POSIX `SAVE` 產生的 ELF object 主要包含這些 section：

| Section | 用途 |
|---------|------|
| `.shstrtab` | section name string table |
| `.strtab` | symbol name string table |
| `.symtab` | symbol table |
| `.rel.forth` | `.forth` 的 relocation entries |
| `.forth` | Forth dictionary、compiled code、runtime image |
| `.space` | 預留給 dictionary 擴展的 BSS-like 空間 |
| `.dltable` | 動態連結表 |
| `.dlstrings` | 動態連結字串 |

其中最重要的是：

```text
.forth = 已編譯的 Forth image
.space = executable 啟動後可繼續使用的 dictionary space
```

### 5.1 Symbol table

ELF symbol table 會包含：

- `main`：指向 Forth 初始化入口。
- `.forth` / `.space` / `.dltable` / `.dlstrings` section symbols。
- `dlopen`, `dlsym`, `realloc`, `write`, `calloc`, `dlerror` 等 undefined external symbols，由 linker / dynamic loader 解析。

也就是說，POSIX executable 的 OS-level entry 會進到 `main`，而 `main` 對應到 Forth 的初始化邏輯。

### 5.2 Relocation table

`.rel.forth` 裡的 `R_386_32` relocation 用來讓 linker 修補：

- 動態連結表位址。
- `dlopen` / `dlsym` / `dlerror` 等 C 函數指標。
- `.dltable` / `.dlstrings` 相關引用。

這就是為什麼儲存 image 時不能只是把記憶體 dump 出去：dictionary 裡的指標、外部函式位址、dynamic linking table 都需要被轉成 loader/linker 可以修補的形式。

---

## 6. `forth.ld`：控制 `.forth` 與 `.space` 的位置

POSIX linker script 的核心概念是：

```ld
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

這表示：

1. `.forth` 放到固定 virtual address。
2. `_eforth` 標記 `.forth` 結束位置。
3. `.space` 緊接在 `_eforth` 後面。

這樣啟動後的 Forth 系統可以知道：

```text
已用 dictionary 到哪裡？
後面還有多少可用 dictionary space？
```

---

## 7. Windows 路徑：修改 PE template

Windows 不走 `ELF .o → gcc linker`。它的模型是：

```text
讀取既有 PE template / 目前 module
        ↓
修改 PE header 欄位
        ↓
寫入 Forth dictionary / image
        ↓
修補 import table / resources
        ↓
輸出 .exe
```

Windows `SAVE` 會設定或修補：

| 欄位 | 用途 |
|------|------|
| Subsystem | console / GUI |
| EntryPoint RVA | 程式入口 |
| ImageBase | PE 載入基底 |
| ImageSize | 載入後 image 大小 |
| Section size | `.text` / `.idata` / `.rsrc` 等大小 |

### 7.1 PE template 機制

Windows 版通常使用 PE template / stub。`spf_stub.f` 定義 DOS header、PE header、section table、import directory，最後由 `SAVE-PE` 寫出可執行檔。

PE 檔案基本結構：

```text
MZ / DOS header
DOS stub
PE\0\0 signature
COFF header
Optional header（其實 executable 必需）
Section table
.idata / .text / .rsrc
```

### 7.2 Import table 為什麼很小？

SP-Forth Windows 最小 executable 通常只靜態 import：

- `LoadLibraryA`
- `GetProcAddress`

有了這兩個函數，SP-Forth 就可以在 runtime 透過 `WINAPI:` / `AO_INI` 解析其他 Win32 API。這讓 PE import table 很小，也讓外部函式載入保持 Forth 層的彈性。

---

## 8. `XSAVE`：交叉編譯時的 address relocation

交叉編譯時最容易搞錯的是 address space：

```text
host address ≠ target address ≠ file offset ≠ runtime virtual address
```

因此 `XSAVE` 需要在寫出 ELF image 前修補：

- wordlist chain。
- vocabulary list。
- dictionary 裡的名稱 / link / class / parent 指標。
- section offsets。

核心思想是：

```text
建構時可用的 host pointer
  → 轉成 target virtual address 或 relocatable value
  → 讓 linker / loader 在執行檔載入時得到正確 runtime address
```

這是 standalone executable 能正常啟動的必要條件。否則 image 裡會殘留宿主系統的記憶體位址，目標 executable 一啟動就會跳到錯誤位置。

---

## 9. Runtime startup：為什麼 executable 啟動後能工作？

輸出的 executable 不是只有使用者程式；它還包含啟動 Forth runtime 所需的初始化流程。

啟動概念如下：

```text
OS loader
  ↓
ELF main / PE EntryPoint
  ↓
SP-Forth INIT（進一步呼叫平台初始化，如 PROCESS-INIT）
  ↓
TLS / USER 區初始化
  ↓
heap / memory pool 初始化
  ↓
POSIX dl-init 或 Windows API resolver 初始化
  ↓
signal / SEH handler 安裝
  ↓
console / file I/O 初始化
  ↓
<MAIN> / MAINX / QUIT / command line processing
```

所以使用者看到的是「直接執行 exe」，但內部其實先建立一個可運作的 Forth runtime environment。

---

## 10. `<MAIN>`、`MAINX`、`QUIT` 與 application entry

如果你只是 `SAVE` 整個系統，輸出的 executable 啟動後可能仍進入互動式 Forth 行為。要做 application-style executable，必須設定入口。

### 10.1 Console app

```forth
: run ( -- )
  \ your application body
  BYE ;

' run TO <MAIN>
S" console.exe" SAVE
```

概念：console mode 啟動後走 `<MAIN>`。

### 10.2 GUI app

```forth
0 TO SPF-INIT?
TRUE TO ?GUI
' NOOP TO <MAIN>
' run MAINX !
S" gui.exe" SAVE
```

概念：GUI mode 由 `MAINX` 指向實際 GUI entry，並且可關掉一般 command-line / ini 自動處理。

### 10.3 是否保留 interpreter？

SP-Forth 的 `SAVE` 是 full system image model；它通常仍保留 Forth dictionary / interpreter / compiler 能力。這和其他 Forth 系統所謂 `TURNKEY` 有差別：有些 Forth 的 `TURNKEY` 會丟掉 headers / names，產生較小但不可互動除錯的 app。不要把 SP-Forth 的 `SAVE` 直接等同於「header-stripped turnkey」。

---

## 11. POSIX 與 Windows 對照表

| 面向 | POSIX | Windows |
|------|-------|---------|
| 輸出格式 | ELF executable | PE executable |
| 中間產物 | ELF relocatable `.o` | 通常直接寫 EXE / template patch |
| 最終連結 | `gcc` / `ld` + `forth.ld` | Forth 自己修改 PE header / sections |
| 主要 SAVE 檔 | `src/posix/save.f` | `src/win/spf_pe_save.f`, `src/tsave.f` |
| 交叉編譯儲存 | `src/xsave.f` | `src/tsave.f` / `src/done.f` |
| 動態連結 | `dlopen`, `dlsym`, `dlerror` | `LoadLibraryA`, `GetProcAddress` |
| 入口 | ELF `main` symbol → Forth init | PE EntryPoint RVA → Forth init |
| 額外資源 | 無 PE-style resource | 支援 `.rsrc` / `.fres` |

---

## 12. 相關原始碼入口

| 檔案 | 角色 |
|------|------|
| `src/spf.f` | 主控建構腳本；定義 `DONE`、`SAVE-WITH-RESERVE`，載入 `xsave.f` 產生 `spf4.o` |
| `src/posix/save.f` | POSIX `SAVE`：產生 ELF object、linker script，呼叫 gcc |
| `src/xsave.f` | 交叉編譯 `XSAVE`：處理 target image relocation 並寫出 ELF object |
| `src/elf.f` | ELF header、sections、symbols、relocations 的結構定義 |
| `src/forth.ld` | POSIX linker script，控制 `.forth` / `.space` placement |
| `src/win/spf_pe_save.f` | Windows `SAVE`：修改 PE header 並寫入 Forth image |
| `src/tsave.f` | Windows PE + resources 儲存流程 |
| `src/spf_stub.f` | Windows PE stub / template、import table、`SAVE-PE` |
| `src/done.f` | Windows build finalization，修補 import 位址並呼叫 `tsave.f` |
| `src/Makefile` | `spf4.o → spf4 → spf4e` 的建構規則 |

---

## 13. 建議閱讀順序

如果你第一次理解這部分，建議照這個順序：

1. [06-build-save.md §1](06-build-save.md#1-建構系統makefile--posixmakefile)：先理解 `spf4` / `spf4e` 怎麼被建出來。
2. [06-build-save.md §7](06-build-save.md#7-posix-映像儲存posixsavef--elff)：理解 POSIX `SAVE` 如何產生 ELF object 並連結。
3. [06-build-save.md §8](06-build-save.md#8-xsave--交叉編譯-elf-儲存xsavef)：理解 `XSAVE` 與 target address relocation。
4. [09-windows-platform.md §7](09-windows-platform.md#7-pe-映像儲存spf_pe_savef-深入解析)：理解 Windows PE template / import table。
5. [05-io-error-init.md](05-io-error-init.md)：理解 executable 啟動後 runtime initialization。
6. [14-walkthrough.md](14-walkthrough.md)：把 parser、compiler、optimizer、image save、runtime startup 串成端到端流程。

---

## 14. 實作一個最小 application 的建議流程

若目標是「使用者直接執行 `myapp` / `myapp.exe`，不需要另外輸入 `spf4 myapp.f`」，建議按這個順序做：

### 14.1 先讓 app 在互動系統中可執行

先寫成普通 Forth 程式：

```forth
\ myapp.f
: run ( -- )
  ." Hello from saved SP-Forth app" CR ;
```

先確認：

```forth
INCLUDED myapp.f
run
```

能正常執行。此時不要急著 `SAVE`；先排除 parser、wordlist、FFI、optimizer 等一般問題。

### 14.2 設定 entry point

console application 可用：

```forth
INCLUDED myapp.f
' run TO <MAIN>
S" myapp" SAVE
```

如果你的 app 不想處理 `spf4.ini` 或 command line 自動載入，可以依需求設定：

```forth
0 TO SPF-INIT?
' run TO <MAIN>
S" myapp" SAVE
```

GUI application 則通常走 `?GUI` / `MAINX`：

```forth
INCLUDED myapp.f
0 TO SPF-INIT?
TRUE TO ?GUI
' NOOP TO <MAIN>
' run MAINX !
S" myapp.exe" SAVE
```

### 14.3 決定是否保留字典空間

如果輸出的 executable 啟動後還要載入更多 Forth source、動態定義 word，使用 `SAVE-WITH-RESERVE`：

```forth
10 1024 * 1024 * S" myapp" SAVE-WITH-RESERVE BYE
```

如果 executable 只跑固定 app，且不需要大量動態定義，保留空間可以較小。注意：保留空間是 runtime dictionary 的容量設計，不是 app source 的大小估算。

### 14.4 儲存後必測

每次 `SAVE` 後都要真的執行產物：

```text
./myapp
myapp.exe
```

不要只看檔案成功產生。image save 階段最常見的是：檔案格式看似正確，但 entry point、relocation、USER/TLS 初始化或 import table 啟動後才爆。

---

## 15. `.space` / reserve space 的細節

`.space` 可以理解成「啟動後給字典繼續長大的空間」。在 ELF 裡它接近 BSS-like 概念：檔案中不一定真的存滿這些 bytes，而是告訴 loader 需要配置多大的記憶體區域。

因此：

| 觀察 | 正確理解 |
|------|----------|
| `SAVE-WITH-RESERVE 10MiB` 但檔案沒有大 10MiB | reserve 可能是 NOBITS/BSS-like，不等於檔案實體大小 |
| saved image 啟動後還能 `:` 新字 | `.space` / reserve 提供後續 dictionary growth |
| reserve 太小 | 啟動後載入 extension 或動態編譯可能耗盡字典空間 |
| reserve 太大 | runtime memory footprint 可能增加，但檔案大小未必等比例增加 |

這也是為什麼 `spf4e` 建構時使用 `10 1024 * 1024 * ... SAVE-WITH-RESERVE`：extended executable 載入更多標準字與 extension 後，仍預留足夠空間給使用者繼續工作。

---

## 16. Entry point 與初始化順序陷阱

`<MAIN>` / `MAINX` 指向你的 app entry，但這不代表你的程式可以在 runtime 初始化前任意執行。安全模型是：

```text
OS loader
  → SP-Forth low-level entry
  → PROCESS-INIT / platform init
  → USER/TLS / heap / I/O / dynamic linking ready
  → <MAIN> 或 MAINX
```

因此 app entry 裡可以假設一般 Forth runtime 已建立，但不應該繞過 initialization 直接從 PE stub 或 ELF low-level entry 呼叫高階 word。特別是這些功能依賴初始化完成：

- `USER` 變數與 `STATE`。
- `ALLOCATE` / heap。
- `TYPE` / console I/O。
- POSIX `dlopen` / Windows `LoadLibraryA` based FFI。
- signal / SEH 到 `THROW` 的橋接。

如果 saved executable 一啟動就 crash，先查 startup chain；如果能啟動但 app entry crash，再查 `<MAIN>` / `MAINX` 裡呼叫的 word。

---

## 17. saved executable 啟動即 crash 的排查流程

若 `./myapp` 或 `myapp.exe` 一執行就崩潰，先照下列順序排除：

1. **檔案格式是否正確**
   - POSIX：確認是 32-bit ELF executable。
   - Windows：確認有 `MZ` / `PE\0\0` header。
2. **entry point 是否合理**
   - POSIX：entry / `main` 應導向 Forth `INIT` 相關入口。
   - Windows：EntryPoint RVA 應落在 `.text` / stub 可執行區域。
3. **dynamic linking 是否可解析**
   - POSIX：檢查 `dlopen` / `dlsym` / `dlerror` 等符號與 `-ldl`。
   - Windows：檢查 `LoadLibraryA` / `GetProcAddress` import table。
4. **最小 app 是否也 crash**
   - 若只印一行文字的 saved app 也 crash，問題在 runtime init / image save。
   - 若最小 app 正常，你的 app entry、FFI 或初始化順序較可疑。
5. **reserve space 是否足夠**
   - 若啟動後載入 extension 或動態編譯時失敗，改用較大的 `SAVE-WITH-RESERVE` 驗證。

這個流程和 [12-debugging.md](12-debugging.md) 的一般排查互補：本節只針對 saved image startup；若已進入 app 邏輯後才錯，應回到 compiler、optimizer、FFI 或 primitive 層排查。

---

## 18. 常見錯誤與後果

| 改動 / 錯誤 | 後果 | 排查方向 |
|-------------|------|----------|
| 改 `IMAGE-START` 但 linker script 未同步 | call / pointer 落到錯誤位置 | 檢查 `forth.ld` 與 relocation |
| POSIX build 使用 PIE | 固定位址假設被打破 | 確認 `-no-pie` 生效 |
| Windows `?GUI` / `?CONSOLE` 與 subsystem 不一致 | console/GUI 行為異常 | 查 PE Optional Header `Subsystem` |
| 忘記設定 `<MAIN>` / `MAINX` | saved app 仍像互動式 Forth | 檢查 app entry 設定 |
| `SAVE` 前未載入 app source | executable 內沒有你的 app word | 先在目前系統中 `SEE`/執行 app word |
| FFI pointer 指向暫存 buffer | saved app 執行後 callback/API 崩潰 | 檢查 pointer lifetime |
| reserve space 太小 | 啟動後載入/編譯 extension 失敗 | 增加 `SAVE-WITH-RESERVE` 大小 |

---

## 19. SP-Forth `SAVE` 與其他 Forth 的 `TURNKEY` 差異

一些 Forth 系統使用 `TURNKEY` 指「丟掉 headers / names，只留下專用 app」，以縮小檔案並避免互動式除錯。SP-Forth 這裡討論的 `SAVE` 更接近 full system image：

| 概念 | SP-Forth `SAVE` | 典型 `TURNKEY` |
|------|-----------------|----------------|
| 是否保留完整 Forth 能力 | 通常保留 | 常刻意移除 |
| 是否保留 word names / headers | 通常保留 | 常丟棄以縮小 |
| 是否方便 debug | 較方便 | 較困難 |
| 目標 | 保存目前系統狀態成 executable | 封裝專用 application |

因此本文件使用「獨立執行檔」或「saved executable image」，避免把 SP-Forth 的 `SAVE` 誤稱為一定會 strip headers 的 turnkey。

---

## 20. 最小心智模型

請記住這張圖：

```text
你載入 / 定義的 Forth app
        ↓
進入目前 Forth dictionary
        ↓
設定 <MAIN> / MAINX / mode
        ↓
SAVE / SAVE-WITH-RESERVE
        ↓
POSIX: ELF .o + gcc linker
Windows: PE template patch
        ↓
OS-native executable
        ↓
OS loader 直接執行
        ↓
Forth runtime init
        ↓
你的 app entry
```

這就是 SP-Forth「生成獨立執行檔」的核心技術。
