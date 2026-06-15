# SP-Forth/4 原始碼追蹤 — 除錯與故障排查指南

> 定位：把前面各章的機制串成「壞掉時怎麼查」的操作手冊。
>
> 本章不重複完整實作細節，而是提供排查路徑：先判斷故障層級，再回到對應 trace 文件與原始碼。
>
> **本章以 SP-Forth 內建的 trace 機制為主**（`DUMP-TRACE`、`DUMP-TRACE-USING-REGS`、例外標頭與堆疊傾印），不預設依賴外部 debugger。在 Linux 上仍可搭配 `gdb`、在 Windows 上搭配 WinDbg 作為輔助；但因為 SP-Forth 使用特殊的 TOS-in-EAX 模型與自訂映像佈局，內建 trace 通常比通用 debugger 更快定位問題。

---

## 1. 先判斷故障發生在哪一層

SP-Forth 的問題通常不需要一開始就追到組語。先用症狀把問題切到正確層級：

| 症狀 | 優先懷疑層級 | 主要文件 |
|------|--------------|----------|
| 建構時找不到宿主 Forth、`gcc -m32` 失敗、linker 錯誤 | 建構 / toolchain | [06-build-save.md](06-build-save.md) |
| 啟動後立即 SIGSEGV / SEH | 平台初始化、TLS、signal/SEH bridge | [04-posix-platform.md](04-posix-platform.md), [09-windows-platform.md](09-windows-platform.md) |
| `INCLUDED`、`USE`、路徑相關錯誤 | 模組路徑、I/O、初始化 | [05-io-error-init.md](05-io-error-init.md) |
| 找不到字、錯誤字被解析、`MODULE:` 行為異常 | parser / search-order / wordlist | [02-compiler.md](02-compiler.md) |
| 控制結構產生錯誤跳躍 | immediate words、branch backpatch | [02-compiler.md](02-compiler.md), [03-cross-compiler.md](03-cross-compiler.md) |
| 只有最佳化版本壞、`noopt.f` 版本正常 | macro optimizer | [07-optimizer.md](07-optimizer.md) |
| 交叉編譯出的 image 跑不起來 | host/target 位址轉換、ELF/PE 儲存 | [03-cross-compiler.md](03-cross-compiler.md), [06-build-save.md](06-build-save.md) |
| 外部函式呼叫後堆疊錯亂 | FFI 呼叫約定、參數數、callback bridge | [04-posix-platform.md](04-posix-platform.md), [09-windows-platform.md](09-windows-platform.md) |

排查時的原則是：**先確認是哪一層破壞堆疊或位址，再往下看組語。**

---

## 2. 建構失敗排查

### 2.1 先確認工具鏈與宿主系統

POSIX 建構路徑依賴 32-bit toolchain 與宿主 Forth。先檢查：

1. `gcc -m32` 是否可編譯最小 C 程式。
2. `src/Makefile` 使用的 `HOSTFORTH` 是否存在。
3. `spf4orig` 是否位於 Makefile 預期路徑。
4. `config.c` 產生的 offset 是否和目前 libc/ucontext 結構一致。

若錯誤出在 `config.auto.f`，通常不是 Forth 原始碼本身壞掉，而是 C header / 32-bit ABI / libc 版本與文件預設不同。

### 2.2 分辨「編譯 Forth image」和「link native binary」

建構流程可粗分為：

```text
C helper / config.c
        ↓
host Forth 載入 src/spf.f
        ↓
產生 spf4.o / spf4.exe 相關 image
        ↓
gcc / linker 輸出最終執行檔
```

因此：

- 若錯誤訊息是 Forth 的 `THROW` / `未定義字`，優先查 [02-compiler.md](02-compiler.md) 與 [05-io-error-init.md](05-io-error-init.md)。
- 若錯誤訊息是 `ld` / `relocation` / `undefined reference`，優先查 [06-build-save.md](06-build-save.md)。
- 若錯誤在產生 ELF/PE 結構後才出現，優先查 image save 階段，而不是 parser。

### 2.3 常見建構症狀

| 症狀 | 排查方向 |
|------|----------|
| `HOSTFORTH` 找不到 | 檢查 Makefile 預設路徑與 `../spf4orig` 是否存在 |
| `gcc -m32` 找不到 32-bit header | 安裝 multilib / i386 libc 開發套件 |
| ucontext offset 不符 | 重新產生 `config.auto.f`，檢查 `config.c` 的 ENSURE 條件 |
| link 時找不到 `dlopen` / `dlsym` | 檢查 `-ldl` 與 libc/linker 差異 |
| Windows PE 啟動失敗 | 查 [09-windows-platform.md](09-windows-platform.md) 的 PE import 與 SEH 初始化 |

---

## 3. 執行期崩潰排查

### 3.1 先保護三個核心暫存器假設

SP-Forth IA-32 執行模型最重要的假設是：

| 暫存器 | 語意 | 壞掉時常見症狀 |
|--------|------|----------------|
| `EAX` | TOS（堆疊頂端本體，非快取） | 算術、比較、堆疊結果錯亂 |
| `EBP` | 資料堆疊指標，指向次堆疊項 | `DROP` / `DUP` 後崩潰或讀寫錯位 |
| `EDI` | TLS / USER 區基底 | `USER` 變數、錯誤處理、signal recovery 異常 |

若 crash 發生在外部 callback、signal handler、或 C 函數返回後，優先檢查 `EDI` 是否被恢復。POSIX signal path 會從 `ucontext_t` 取回 `EDI`；Windows SEH path 則依靠 exception context 與 thread-local runtime 狀態。

### 3.2 使用 DUMP-TRACE 時看什麼

`DUMP-TRACE` 的價值不是只看最後一行，而是交叉檢查：

1. `EIP` 是否落在已知 code field / native code 範圍。
2. `EAX` 是否像合理的 TOS 值。
3. `EBP` 附近是否仍像資料堆疊。
4. `ESP` 是否仍像 return stack / x86 call stack。
5. `EDI` 是否指向目前 thread 的 USER 區。

若 `EIP` 合理但 `EBP` 不合理，常是 Forth 資料堆疊被破壞；若 `EIP` 直接跳到 0 或資料區，常是 CFA/PFA 或 callback return address 被破壞。

### 3.3 判斷是 Forth 堆疊錯還是 C ABI 錯

| 線索 | 比較可能的原因 |
|------|----------------|
| Forth primitive 之間開始錯 | `EAX` / `EBP` discipline 破壞 |
| C 函數返回後才錯 | 參數數量、cdecl/stdcall 清理責任、返回值寬度 |
| callback 進入後才錯 | `_WNDPROC-CODE` / callback bridge 沒保存必要暫存器 |
| signal 後 `THROW` 又 crash | `EDI` / USER 區恢復失敗 |

POSIX `C-CALL` 是 cdecl：呼叫者清理堆疊。Windows `API-CALL` 面對 Win32 stdcall，需要特別注意參數區與清理責任。兩者不可混用推論。

---

## 4. 字詞解析與編譯期錯誤

### 4.1 找不到字：先查搜尋順序

遇到「未定義字」時，不要先假設字不存在。按順序查：

1. 目前 `CONTEXT` 搜尋順序是否包含目標 wordlist。
2. `CURRENT` 是否寫到預期 wordlist。
3. 字是否仍處於 `HIDE` / `SMUDGE` 狀態。
4. 是否在 `MODULE:` 內，需經由 `EXPORT` 暴露。
5. 是否牽涉大小寫敏感版本差異。

`SFIND` 回傳值的語意很重要：`0` 是找不到，`1` 是 immediate，`-1` 是非 immediate。錯把 immediate 狀態當布林值，很容易導致編譯/直譯分支錯判。

### 4.1a 用 `SEE` 檢查編譯結果

若懷疑某個字「有定義但編譯結果不對」，先用 `SEE` 或系統提供的反組譯/反編譯工具觀察它目前的定義，而不是直接猜 optimizer：

```forth
SEE SQUARE
```

觀察重點：

| 看到的現象 | 可能原因 |
|------------|----------|
| `SEE` 找不到字 | search-order / wordlist / `HIDE` / `SMUDGE` 問題 |
| `SEE` 顯示的 body 和 source 差很多 | macro optimizer inline 或 rewrite |
| `SEE` 顯示還是舊定義 | `CURRENT` 寫入了別的 wordlist，或新定義沒有覆蓋搜尋順序中的舊字 |
| `SEE` 在某字崩潰 | 字典 header / link / CFA 可能已損壞 |

`SEE` 的輸出格式會因系統載入的工具集而不同；本章只把它當成「先確認字典裡到底長什麼樣」的排查入口。

### 4.2 控制結構錯：看 backpatch stack

`IF` / `ELSE` / `THEN`、`BEGIN` / `UNTIL`、`DO` / `LOOP` 都依賴編譯期暫存的跳躍位址。若錯誤只出現在控制結構：

1. 確認 immediate word 在編譯狀態下有被執行，而不是被編成普通 call。
2. 檢查 branch placeholder 是否留下正確位址。
3. 檢查 `HERE` / `DP` 是否被其他 word 移動。
4. 交叉編譯時確認使用的是 target 位址，而不是 host 位址。

---

## 5. 最佳化器相關故障

### 5.1 先做 noopt 對照

若懷疑 optimizer，最小化判斷是：

```text
同一段輸入：
  macroopt 啟用 → 壞
  noopt / OPT? 關閉 → 正常
```

只有這個對照成立，才把問題歸給 [07-optimizer.md](07-optimizer.md) 的規則。否則應回到 compiler / primitive / platform 層。

### 5.2 常見 optimizer 錯誤類型

| 類型 | 檢查點 |
|------|--------|
| constant folding 錯 | `CON>LIT` 是否誤判 PFA / CONSTANT layout |
| inline 後語意不同 | inline body 是否假設暫存器或堆疊深度 |
| jump shorting 錯 | short jump range、backpatch offset 是否正確 |
| peephole rewrite 錯 | rewrite 前後是否保留 flags / `EAX` / `EBP` 語意 |

特別注意：x86 指令是否改變 flags。若後續條件跳躍依賴 flags，不能只看暫存器結果相同。

---

## 6. 交叉編譯 image 故障

### 6.1 先分清 host 位址與 target 位址

交叉編譯錯誤最常見的根源是把 host address 當成 target address，或相反。排查時逐一標記：

| 值 | 應屬於 |
|----|--------|
| host Forth 目前可執行的 XT | host |
| target image 內要保存的 CFA / PFA | target |
| ELF/PE 檔案偏移 | file offset |
| 載入後執行位址 | virtual address |

`>VIRT` / `VIRT>` 的用途就是把這些空間隔開。任何直接把 `HERE`、`DP`、或 symbol value 寫進 image 的地方，都要檢查當下是否已轉成正確 address space。

### 6.2 image 能產生但不能執行

若建構成功、執行失敗，優先查：

1. entry point 是否指到初始化入口。
2. relocation 是否套用到需要修補的欄位。
3. dynamic symbol / import table 是否完整。
4. USER 區與 heap 是否在啟動時初始化。
5. POSIX signal 或 Windows SEH handler 是否安裝完成。

---

## 7. FFI 與 callback 排查

### 7.1 參數數量比函式名稱更重要

外部函式宣告錯誤時，最常見不是函式名稱拼錯，而是：

- 傳入參數數量錯。
- 32-bit / 64-bit 回傳值處理錯。
- cdecl / stdcall 清理責任搞混。
- 指標指向 Forth 暫存 buffer，但 C 端延後使用。
- callback 回到 Forth 時 thread/TLS 狀態不完整。

### 7.1a cdecl 與 stdcall 的堆疊責任

外部呼叫錯誤常不是函式名稱錯，而是「誰負責清掉參數」搞錯。IA-32 上可用這張圖理解：

```text
cdecl（POSIX C-CALL 常見）
  caller push arg2
  caller push arg1
  call function
  caller add esp, 8      \ 呼叫者清理參數

stdcall（WinAPI 常見）
  caller push arg2
  caller push arg1
  call function
  callee ret 8           \ 被呼叫者清理參數
```

若 Forth 端用錯呼叫約定，C 函式可能「看似成功返回」，但 `ESP` / Forth return stack 已偏移，下一個 `RET` 或 callback 才崩潰。這種錯誤常被誤判成後續 Forth word 的問題。

### 7.2 FFI 故障最小化策略

1. 先呼叫無參數、純回傳值的 C 函式。
2. 再加入一個整數參數。
3. 再加入指標參數。
4. 最後才測 callback 或跨 thread callback。

每一步都檢查資料堆疊深度是否如預期。若某一步後堆疊多一項或少一項，先修 ABI，不要繼續追高階邏輯。

---

## 8. 建議的除錯記錄格式

回報或記錄 SP-Forth trace 問題時，建議固定包含：

```text
1. 平台：POSIX / Windows / Cygwin，32-bit toolchain 版本
2. 建構選項：spf4 / spf4e、`OPT?`（執行期 VALUE）、`BUILD-OPTIMIZER` / `USE-OPTIMIZER`、`TARGET-POSIX`（注意：沒有 `TARGET-WIN`；Windows 是「`TARGET-POSIX` 為 FALSE」的分支，平台另由 Makefile 的 `PLATFORM` 變數決定）
3. 最小重現 Forth 程式
4. 失敗階段：build / include / compile / save / startup / runtime
5. 最後一個成功載入的檔案
6. THROW code 或 signal / SEH code
7. 若有 DUMP-TRACE：EIP, EAX, EBP, ESP, EDI
8. noopt 對照結果
```

這個格式能避免把 compiler、optimizer、platform 三類問題混在一起。

---

## 9. 症狀導向決策樹

遇到問題時，先不要直接跳到組語或 optimizer。建議照下面流程切層：

```text
問題發生
  │
  ├─ make / compile.bat 階段失敗？
  │    ├─ 是 → toolchain / HOSTFORTH / config.auto.f / linker
  │    └─ 否
  │
  ├─ executable 無法啟動？
  │    ├─ 是 → entry point / relocation / PE import / ELF dynamic symbols
  │    └─ 否
  │
  ├─ 啟動後進入 QUIT 但載入檔案失敗？
  │    ├─ 是 → SOURCE-ID / module path / INCLUDED / file I/O
  │    └─ 否
  │
  ├─ 特定 word 找不到或解析錯？
  │    ├─ 是 → CONTEXT / CURRENT / wordlist / HIDE / case sensitivity
  │    └─ 否
  │
  ├─ 只有最佳化版錯？
  │    ├─ 是 → macroopt/noopt A/B，查 rewrite 等價性
  │    └─ 否
  │
  └─ 只有 FFI / callback 後錯？
       ├─ 是 → ABI / pointer lifetime / TLS / USER
       └─ 否 → 回到 primitive / compiler / runtime init 層逐步縮小
```

這張樹的目的不是一次定位 root cause，而是避免一開始就把所有問題都歸咎於 optimizer 或平台。

---

## 10. 常見 THROW / signal / SEH 線索

SP-Forth 的錯誤可能以 Forth `THROW`、POSIX signal、Windows SEH 或建構工具錯誤呈現。排查時先分清：

| 類型 | 典型表現 | 意義 |
|------|----------|------|
| Forth `THROW` | 有錯誤碼、可能能回到 `CATCH` | Forth 層可恢復錯誤 |
| POSIX signal | SIGSEGV / SIGFPE / SIGBUS | native code、記憶體、除零、alignment 等問題 |
| Windows SEH | access violation / divide by zero | PE runtime 或 Win32 API 層錯誤 |
| linker / loader error | `undefined reference`, missing DLL/SO | image save / dynamic linking / toolchain 問題 |

常見錯誤碼可先看 [10-quick-ref.md §6](10-quick-ref.md#6-常見錯誤碼對照)。排查時特別注意：

- `-13`：通常是字詞搜尋失敗，不要先追 native crash。
- `-27`：include 巢狀過深，優先查載入路徑或遞迴 include。
- SIGSEGV / access violation：先看 `EIP` 是否落在 `.forth` / `.text` 合理範圍，再看 `EBP` / `EDI`。

### 10.1 DUMP-TRACE 應該怎麼讀

實際輸出格式可能依平台與版本不同，但你應該固定抽取這些欄位：

```text
signal / exception: SIGSEGV 或 access violation
EIP = 0x........   ; 當時正在執行的指令位置
EAX = 0x........   ; TOS（堆疊頂端）
EBP = 0x........   ; Forth data stack pointer
ESP = 0x........   ; return stack / x86 stack pointer
EDI = 0x........   ; USER/TLS base
```

判讀順序：

1. **EIP**：是否像 code address？若是 0、很小、或落在資料區，常是 CFA/return address 被破壞。
2. **EBP**：是否仍指向資料堆疊範圍？若不合理，先查 stack effect。
3. **EDI**：是否仍是 USER 區基底？若錯，`STATE`、錯誤處理、I/O handle、thread-local 狀態都可能跟著壞。
4. **EAX**：若其他暫存器合理但 EAX 值錯，優先查 primitive / optimizer 對 TOS 的維護。

---

## 11. 最小重現範本

當你要回報或記錄問題，建議建立一個最小 `.f` 檔，而不是只貼互動式歷史。範本：

```forth
\ repro.f — 最小重現
.( platform: POSIX/Windows, spf4/spf4e ) CR

\ 1. 載入必要 extension，越少越好
\ REQUIRE ANSI lib/include/ansi.f

\ 2. 固定輸入資料
: INPUT  7 ;

\ 3. 被測 word
: BUGGY  INPUT DUP * ;

\ 4. 觀察結果
BUGGY . CR

\ 5. 明確結束，避免落入互動式狀態造成誤判
BYE
```

縮小時每次只移除一個依賴：先去掉 FFI，再去掉 optimizer-sensitive 寫法，再去掉 module/search-order 變化。若刪掉某個 word 後問題消失，那個 word 所在層級就是下一步排查點。

---

## 12. 平台特有陷阱

| 平台 | 陷阱 | 排查方式 |
|------|------|----------|
| POSIX | 32-bit headers / multilib 不完整 | 先確認 `gcc -m32` 可編最小 C 程式 |
| POSIX | GCC 預設 PIE | 檢查建構命令是否含 `-no-pie`，對照 [06-build-save.md](06-build-save.md) |
| POSIX | `dlopen` / `dlsym` 解析失敗 | 檢查 `-ldl`、library path、`dlerror()` 訊息 |
| Windows | console / GUI subsystem 不一致 | 檢查 `?GUI` / `?CONSOLE` 與 PE subsystem 欄位 |
| Windows | WinAPI 參數數錯 | 對照 Win32 prototype，檢查 stdcall 清理責任 |
| Windows | callback 從其他 thread 回來 | 檢查 USER/TLS 初始化與 callback bridge |

---

## 13. 排查速查表

| 問題 | 第一站 | 第二站 |
|------|--------|--------|
| `未定義字` | 搜尋順序 / wordlist | module export / HIDE 狀態 |
| `THROW -13` | `SFIND` / `INTERPRET` | source input / `SOURCE-ID` |
| SIGSEGV | `EIP` / `EBP` / `EDI` | signal bridge / FFI |
| callback crash | callback bridge | TLS / USER 區 |
| optimizer only crash | `OPT?` 對照 | peephole rule / flags preservation |
| image startup crash | entry point / relocation | USER / heap init |
| Windows API crash | stdcall 參數 | PE import / `GetLastError` |
| POSIX C call crash | cdecl 參數 | `errno` / pointer lifetime |
