# SP-Forth/4 原始碼追蹤技術文檔 — 系統概觀

> 版本依據：SP-Forth kernel version 429
> 追蹤日期：2026-04-25
> 本文件使用台灣資訊科技產業慣用術語

---

## 1. 專案簡介

SP-Forth（又稱 SP-Forth/4）是一套遵循 ANS Forth 94 標準的 Forth 程式語言實作，由俄羅斯 Forth 社群開發維護。原始碼多數以俄文撰寫註解，本系列文檔將其追蹤分析並以繁體中文記錄。

### 1.1 歷史背景與專案定位

根據專案自帶 README、官方網站與 SourceForge 專案頁可交叉確認：

- SP-Forth 由 **Andrey Cherezov** 於 **1992** 啟動，後續由 **Russian Forth Interest Group（RuFIG）** 與多位貢獻者持續維護。
- 官方網站仍保留 **SP-Forth 4.20** 時期的發行檔與線上文件；而目前原始碼、release 與 issue tracker 則以 **GitHub `rufig/spf`** 為主。
- 綜合 README、官方站與專案文件的描述，可以把它定位成：**能產生 IA-32 原生碼、可與作業系統深度整合、可自舉建構自身映像**的完整 Forth 系統。

也因此，閱讀 `docs/trace/*` 時有一個重要前提：這套文件關注的是**目前這份原始碼樹的實作細節**；若外部文件提到較早期的 Windows 9x/NT、4.20 安裝程式或舊版發行包，應把它們理解成歷史背景，而不是直接拿來覆蓋目前 repo 的行為描述。

### 1.2 主要能力與典型使用場景

| 類別 | 可查證的重點 |
|------|--------------|
| 語言定位 | 32 位元、Forth-94 相容、為 Intel x86 / IA-32 產生最佳化 native code |
| 平台整合 | 可呼叫 DLL / SO、建立可被外部程式呼叫的 callback、把 SEH / signal 轉成 Forth 例外、支援基於作業系統搶先式多執行緒的 multitasking |
| 輸出形式 | 可輸出 `spf4` / `spf4e`，也可把 Forth dictionary 儲存成 standalone executable |
| 歷史上的應用案例 | 舊版官方文件明確列出 CGI、HTTP/FTP/SMTP/POP3/IMAP server / proxy、以及 Windows 上的類 Unix cron scheduler（如 nnCron）等案例；至於 Win32 GUI/console，較適合視為該平台能力展示，而不是同等層級的具名歷史專案 |

這些背景資訊有助於讀者理解：SP-Forth 的設計重心是**高效能原生執行 + 系統整合 + 自舉建構**。因此後面你會看到大量和 callback、動態連結、執行緒、例外、映像輸出有關的實作細節；那不是附帶功能，而是這個系統的核心定位之一。

### 1.3 讀者定位與先備知識

本系列文件的目標是**追蹤原始碼如何對應到系統行為**，不是 Forth 或 x86 的入門教材。若你想順利閱讀後續章節，建議先具備以下背景：

| 先備知識 | 為何需要 |
|----------|----------|
| ANS Forth 94 基本語意 | 理解 `IMMEDIATE`、`STATE`、詞彙表、`CREATE ... DOES>`、`THROW/CATCH`；若對 `STATE`、`:/;`、`IMMEDIATE`、`POSTPONE`、`COMPILE,`、`DOES>` 還不熟，先讀 [11-forth-compilation.md](11-forth-compilation.md) |
| IA-32（x86 32 位元）組合語言 | 理解 `CALL rel32`、`RET`、`EAX/EBP/ESP/EDI` 的角色；若這部分還不熟，先讀 [08-append-a.md](08-append-a.md) |
| ELF / PE / 可重定位物件檔 | 理解 `spf4.o`、重定位、最終連結流程 |
| POSIX / Win32 基本觀念 | 理解平台檔案、信號、執行緒與動態連結 |

若你只想先掌握大方向，直接看本節的路徑表即可；§7 則整理完整索引與線性閱讀建議。

### 1.4 建議閱讀路徑

| 目的 | 建議順序 | 說明 |
|------|----------|------|
| 先看懂系統全貌 | `00 -> 01 -> 02` | 先建立堆疊模型、核心原語與編譯器心智模型 |
| 先補組語基礎 | `00 -> 08 -> 01` | 若你對 IA-32 組語或 `CODE ... END-CODE` 不熟，先補這條 |
| 先補 Forth 編譯模式 | `00 -> 11 -> 02` | 若你對 `STATE`、`:/;`、`IMMEDIATE`、`POSTPONE`、`DOES>` 還不清楚，先補這條 |
| 追蹤自舉與建構 | `00 -> 03 -> 06` | 先懂 host/target，再看映像輸出與連結 |
| 追蹤端到端執行檔 | `00 -> 14 -> 15` | 先用 walkthrough 串起流程，再深入 `SAVE` / ELF / PE standalone executable |
| 維護、除錯與驗證 | `00 -> 12 -> 13` | 先建立排查路徑，再看修改後如何驗證 |
| 追蹤平台與執行期 | `00 -> 04 -> 05` | 先看 POSIX/FFI/執行緒，再看 I/O、例外與初始化 |
| 追蹤 Windows 平台 | `00 -> 09 -> 05` | 先看 Windows PE/SEH/API 呼叫，再看 I/O、例外與初始化 |
| 研究最佳化器 | `00 -> 01 -> 02 -> 03 -> 07` | `07` 是進階選讀，預設你已熟悉核心、編譯器與交叉編譯的前置概念 |
| 追蹤標準字與 extended build | `00 -> 16` | `16-lib.md` 說明 `lib/`、ANS include、`spf4e` 與平台可選延伸庫 |
| 想找可重用延伸函式庫 | `00 -> 17` | `17-ac-lib3.md` 介紹 `ac-lib3/` 的功能分組、典型用途與實際 Forth 範例 |
| 想追作者工作區 / 歷史原型 | `00 -> 18` | `18-devel.md` 把 `devel/` 當成作者子樹地圖來讀，適合追源流、找 prototype 與大型範例 |
| 選用延伸函式庫時跨三章對照 | `00 -> 18-devel-cookbook §6` | [18-devel-cookbook.md §6](18-devel-cookbook.md#6-延伸函式庫使用對照lib-vs-ac-lib3-vs-devel) 提供 `lib/` vs `ac-lib3/` vs `devel/` 的決策矩陣、載入策略與混用注意事項 |

### 1.5 核心特徵

| 特徵 | 說明 |
|------|------|
| 架構 | 32 位元 x86（IA-32），暫存器直定址 |
| 資料堆疊模型 | EAX = TOS（堆疊頂端），EBP = 資料堆疊指標，ESP = 回返堆疊指標 |
| 執行緒模型 | EDI = 執行緒資料區指標（TLS 基底） |
| 自舉方式 | 使用舊版 `spf4orig`（Linux）或 `jpf375c.exe`（Windows）作為宿主編譯器 |
| 自我承載 | 系統可自行編譯自身映像檔 |
| 輸出 | `spf4`（最小核心）、`spf4e`（擴充版，建構時會載入 `lib/ext/spf4e.f` 所納入的標準字與部分延伸庫） |
| 平台支援 | Linux（POSIX）與 Windows（Win32），透過 `TARGET-POSIX` 條件編譯切換 |

---

## 2. 目錄結構與載入順序

### 2.1 原始碼目錄

```forth
src/
├── spf.f                          ← 主進入點，載入所有模組
├── spf_compileoptions.f           ← 編譯選項設定
├── spf_defkern.f                  ← 定義字核心原語（CREATE/CONSTANT 等）
├── spf_forthproc.f                ← Forth 程序核心（堆疊、算術、記憶體原語）
├── spf_forthproc_hl.f             ← 高階 Forth 程序（FALSE/TRUE/MOVE/HASH 等）
├── spf_floatkern.f                ← 浮點運算核心
├── spf_except.f                   ← 例外處理（THROW/CATCH）
├── spf_init.f                     ← 系統初始化與啟動
├── spf_print.f                    ← 數值輸出與格式化
├── spf_con_io.f                   ← 控制台 I/O
├── spf_module.f                   ← 模組管理
├── spf_date.f                     ← 建置日期
├── spf_xmlhelp.f                  ← XML 說明產生器
├── spf_stub.f                     ← 啟動殼層（stub）
├── tc_spf.F                       ← 交叉編譯器/目標編譯器框架
├── tc-configure-lines.f           ← 換行模式設定
├── tc-dl.f / tc-dl-tc.f / tc-dl-imm.f ← 動態連結表（編譯期用）
├── elf.f                          ← ELF 映像輸出
├── xsave.f / tsave.f              ← 映像儲存
├── done.f                         ← Windows 最終化腳本（由 `DONE` 間接載入）
├── macroopt.f                     ← 巨集最佳化器（5548 行）
├── macroopt-hide.f                ← 最佳化器輔助規則/隱藏字
├── noopt.f                        ← 無最佳化替代方案
├── compile / compile.bat          ← 建構腳本（Linux / Windows）
├── Makefile                       ← GNU Make 建構檔
├── forth.ld                       ← 連結器腳本
├── compiler/                      ← 編譯器子系統
│   ├── spf_parser.f               ← 語法剖析器
│   ├── spf_read_source.f          ← 原始碼讀取
│   ├── spf_nonopt.f               ← 非最佳化字集
│   ├── spf_compile0.f             ← 基本編譯控制
│   ├── spf_compile.f              ← 主要編譯器
│   ├── spf_wordlist.f             ← 詞彙表管理
│   ├── spf_find.f                 ← 字詞搜尋
│   ├── spf_words.f                ← 字詞定義輔助
│   ├── spf_error.f                ← 錯誤處理
│   ├── spf_translate.f            ← 直譯器
│   ├── spf_defwords.f             ← 定義字
│   ├── spf_immed_transl.f         ← 立即字直譯
│   ├── spf_immed_lit.f            ← 立即字常值
│   ├── spf_literal.f              ← 常值編譯
│   ├── spf_immed_control.f        ← 控制結構立即字
│   ├── spf_immed_loop.f           ← 迴圈立即字
│   ├── spf_modules.f              ← 模組載入
│   ├── spf_inline.f               ← 內聯展開
│   └── spf_find_cdr.f             ← 尋找 CDR（由 `spf_find.f` 內部載入）
├── posix/                         ← POSIX 平台實作
│   ├── Makefile                   ← config.auto.f 產生規則
│   ├── config.c / config.h        ← 組態偵測 C 原始碼
│   ├── config.auto.f              ← 自動產生的系統常數
│   ├── api.f                      ← C 呼叫介面
│   ├── dl.f                       ← 動態程式庫載入
│   ├── const.f                    ← 檔案存取常數
│   ├── memory.f                   ← 記憶體管理
│   ├── except.f                   ← 例外/程序終止
│   ├── io.f                       ← 檔案 I/O
│   ├── con_io.f                   ← 控制台 I/O（POSIX 版）
│   ├── envir.f                    ← 環境查詢
│   ├── defwords.f                 ← 平台定義字（EXTERN/CALLBACK 等）
│   ├── mtask.f                    ← 多執行緒
│   ├── save.f                     ← ELF 映像儲存
│   ├── module.f                  ← 模組路徑管理
│   └── init.f                     ← 程序初始化（信號處理等）
└── win/                           ← Windows 平台實作（此處省略）
```

### 2.1a 補充目錄：`ac-lib3/` 與 `devel/`

除了 `src/`、`lib/`、`docs/` 這些主體目錄之外，repo 裡還有兩個很容易讓初次閱讀者疑惑、但其實很值得認識的補充區：`ac-lib3/` 與 `devel/`。

#### `ac-lib3/`：額外函式庫與工具集合

`ac-lib3/` 不是 kernel / compiler 的主程式碼，也不是 `spf.f` 建構時必載的核心目錄；更精確地說，它是一組**額外函式庫、工具與平台擴充集合**。從目錄內容來看，它主要包含：

```forth
ac-lib3/
├── LOCALS.F / REQUIRE.F / TEMPS.F   ← 額外語言機制與載入輔助
├── STR.F / STR2.F / STR3.F / str4.f ← 字串處理系列函式庫
├── string/                          ← 正規表示式、大小寫轉換、MIME、pattern 等
├── memory/                          ← 記憶體相關工具
├── debug/TRACE.F                    ← 除錯追蹤輔助
├── tools/                           ← 小工具與 WinAPI 相關輔助程式
├── transl/                          ← 文法 / 詞彙處理實驗
└── win/                             ← Windows 專用擴充（registry、ini、winsock、process、service、com、odbc 等）
```

因此，把 `ac-lib3/` 理解成「**SP-Forth 生態系的延伸函式庫區**」會比把它當成 kernel 的一部分更準確。它比較接近 reusable library / optional toolkit，而不是 `src/` 那種「建構 `spf4` 本體時必須追蹤的主路徑」。

如果你想深入了解 `ac-lib3/` 的功能分類、代表檔案與實際用途，請直接看 [17-ac-lib3.md](17-ac-lib3.md)。那一章會更完整地說明：

- 哪些 top-level 檔案最值得先看（如 `LOCALS.F`、`TEMPS.F`、`REQUIRE.F`、`STR*.F`）
- `string/`、`win/`、`tools/`、`debug/`、`memory/` 等子樹適合拿來做什麼
- 若你要做 locals、字串模板、MIME/regexp、Windows registry/INI/process/socket，應該先去哪裡找範例

這裡先把它當成一個**補充目錄導覽**即可；真正要用它時，再跳去專章讀會比較清楚。

#### `devel/`：開發者工作區、歷史資源與實驗程式

`devel/` 更不像單一產品模組；它是一個**開發者工作區（developer workspace）**，裡面以 `~user` 的形式分成多位貢獻者的子樹，例如：

```forth
devel/
├── ~mak/
├── ~yz/
├── ~ygrek/
├── ~micro/
├── ~day/
├── ~ac/
├── ~nn/
└── ...
```

這些子樹下混合了額外 library、prototype / experimental code、samples、build / conversion tools，以及大量作者自己的歷史資產。簡單說，`devel/` 比較像「**社群與作者群的開發資產倉庫**」，而不是 `src/` 那種穩定、直接進入主系統建構流程的正式模組樹。

如果你想更深入了解 `devel/` 的作者子樹、主要工作區（例如 `~ac`、`~pinka`、`~yz`、`~day`、`~micro`）、它們和 `src/` / `ac-lib3/` 的關係，以及該從哪幾棵子樹開始讀，請直接看 [18-devel.md](18-devel.md)。那一章會把 `devel/` 當成「作者工作樹地圖」來整理，而不只是概觀提及。

當你想在 `lib/`、`ac-lib3/`、`devel/` 三個延伸函式庫區之間選邊時，請看 [18-devel-cookbook.md §6](18-devel-cookbook.md#6-延伸函式庫使用對照lib-vs-ac-lib3-vs-devel) 的決策矩陣與載入策略對照。

#### 它們與主系統的實際關聯

雖然這兩個目錄都不是 `spf.f` 主載入路徑的一部分，但它們**不是完全無關**。目前 repo 中至少可以看到幾個明確的接點：

- [`src/spf_module.f`](../../src/spf_module.f) 會把 `devel/` 拼進模組搜尋路徑；也就是說，模組載入機制會把 `devel/` 視為一個可搜尋的 library root。
- [`src/win/res/res.bat`](../../src/win/res/res.bat) 會呼叫 `~yz/prog/fres/fres.f`，實際上就是 repo 中的 [`devel/~yz/prog/fres/fres.f`](../../devel/~yz/prog/fres/fres.f) —— 這表示 Windows 資源檔建構流程確實依賴 `devel/` 裡的工具。

#### 閱讀這份 trace 文件時，應怎麼看待這兩個目錄？

如果你的目的，是**追蹤 `spf4` / `spf4e` 主系統如何建構、啟動、編譯、儲存映像**，那優先順序仍然是：

1. `src/`
2. `lib/`
3. `docs/trace/`

而 `ac-lib3/` 與 `devel/` 則比較適合在以下情境再深入：

- 想找額外函式庫與可重用工具
- 想追社群歷史實作或作者個人實驗
- 想理解某些 build helper（例如 `fres.f`）從哪來
- 想知道模組搜尋路徑為什麼會碰到 `devel/`

也就是說：

- **`ac-lib3/` = 延伸函式庫與工具集**
- **`devel/` = 開發者 / 歷史 / 實驗資源區**

把這兩個目錄從一開始就和 `src/` 區分開來，能避免讀者把所有樹狀結構誤解成「主系統建構所必須追蹤的核心實作」。

### 2.2 `src/*` 主題地圖：從原始碼樹到追蹤文件

專案自帶的舊版 `docs/src.ru.md`，其實已經把 `src/*` 的核心主題濃縮成幾個閱讀入口：**暫存器配置、雙堆疊模型、映像/字典、heap / USER 記憶體、詞條結構、kernel 建構、macro optimizer、`>VIRT` 位址轉換**。`docs/trace/*` 可以視為把這些主題拆開、補齊細節後的新版追蹤。

如果你是從 `src/*` 反推系統結構，下面這張表會比單看檔名更好用：

| `src/*` 主題 | 主要檔案 | 建議對照文件 | 讀者應先抓住的重點 |
|--------------|----------|--------------|--------------------|
| 暫存器配置 / 雙堆疊模型 | `spf_defkern.f`, `spf_forthproc.f` | [01-kernel.md](01-kernel.md) | `EAX = TOS`、`EBP = data stack`、`ESP = return stack`、`EDI = USER/TLS base` |
| 編譯器與 search order | `compiler/*.f` | [02-compiler.md](02-compiler.md) | token 如何被解析、字詞如何查找、`STATE` / `CURRENT` / `CONTEXT` 怎麼互動 |
| target image / `>VIRT` / 交叉編譯 | `tc_spf.F`, `tc-dl*.f` | [03-cross-compiler.md](03-cross-compiler.md) | host/target 是兩套位址語意，`IMAGE-START` 與 `virtual-address` 決定 target 映像如何落位 |
| 平台 API / callback / threads / signal | `posix/*.f`, `win/*.f` | [04-posix-platform.md](04-posix-platform.md), [05-io-error-init.md](05-io-error-init.md) | 外部函式呼叫、callback、TLS、多執行緒、signal/exception 與 Forth 執行期如何接起來 |
| build / bootstrap / save image | `Makefile`, `compile*`, `save.f`, `xsave.f`, `elf.f` | [06-build-save.md](06-build-save.md) | 系統如何用舊版 SPF 自舉、如何產生 `spf4.o`、如何儲存 `spf4` / `spf4e` |
| macro optimizer | `macroopt.f`, `noopt.f` | [07-optimizer.md](07-optimizer.md) | 最佳化器不是獨立後端，而是直接介入 target machine code 生成流程 |

也就是說，`docs/trace/*` 並不是和 `src/*` 平行的第二份說明，而是把 `src/*` 裡原本分散在 `spf.f`、`tc_spf.F`、`compiler/*.f`、`posix/*.f`、`macroopt.f` 的核心邏輯重新編排成較容易追的閱讀路徑。

### 2.3 載入順序（`spf.f`）

`spf.f` 是整個系統的主控載入腳本，依序載入模組。以下為 Linux（POSIX）建構的載入流程：

```forth
spf.f
  ├── 版本常數 (429)
  ├── 相容性補丁（CS-DUP, PARSE-NAME, SYNONYM 等）
  ├── lib/ext/spf-asm.f            ← 組合語言套件
  ├── src/spf_compileoptions.f     ← 編譯選項
  ├── CASE ... ENDCASE 定義
  ├── 記憶體映像設定（IMAGE-SIZE, IMAGE-START）
  ├── src/posix/config.auto.f      ← 系統常數（自動產生）
  ├── src/spf_date.f               ← 建置日期
  ├── src/spf_xmlhelp.f            ← XML 說明產生器
  ├── src/tc_spf.F                 ← 交叉編譯器框架
  │     ├── src/tc-dl.f            ← 動態連結表
  │     ├── src/macroopt.f / src/noopt.f ← 第一次載入：由 `USE-OPTIMIZER` 控制，供交叉編譯器本身使用
  │     └── 目標字定義系統
  ├── src/spf_defkern.f            ← 定義字核心原語
  ├── src/spf_forthproc.f          ← Forth 程序核心原語
  ├── src/spf_floatkern.f          ← 浮點運算核心
  ├── src/spf_forthproc_hl.f       ← 高階 Forth 程序
  ├── [POSIX] 平台檔案：
  │   ├── src/posix/api.f          ← C 呼叫介面
  │   ├── src/posix/dl.f           ← 動態程式庫
  │   ├── src/posix/const.f        ← 常數定義
  │   ├── src/posix/memory.f       ← 記憶體管理
  │   ├── src/posix/except.f       ← 例外處理
  │   ├── src/posix/io.f           ← 檔案 I/O
  ├── src/spf_except.f             ← 例外 façade
  │   └── POSIX: src/posix/except.f / Windows: src/win/spf_win_except.f
  ├── src/spf_con_io.f             ← 控制台 I/O façade
  │   └── POSIX: src/posix/con_io.f / Windows: src/win/spf_win_con_io.f
  ├── src/spf_print.f              ← 格式化輸出
  ├── src/spf_module.f             ← 模組管理 façade
  │   └── POSIX: src/posix/module.f / Windows: src/win/spf_win_module.f
  ├── src/compiler/*.f             ← 編譯器子系統
  │   ├── spf_parser.f             ← 語法剖析
  │   ├── spf_read_source.f       ← 原始碼讀取
  │   ├── spf_nonopt.f             ← 非最佳化字
  │   ├── spf_compile0.f           ← 記憶體管理
  │   ├── src/macroopt.f 或 src/noopt.f（取決於 `BUILD-OPTIMIZER`；這是第二次載入，詳見 [07-optimizer.md](07-optimizer.md) §1.3）
  │   ├── spf_compile.f            ← 主要編譯器
  │   ├── spf_wordlist.f           ← 詞彙表
  │   ├── spf_find.f               ← 搜尋引擎（內部再 `INCLUDED` `spf_find_cdr.f`）
  │   ├── spf_words.f              ← 定義輔助
  │   ├── spf_error.f              ← 錯誤處理
  │   ├── spf_translate.f          ← 直譯器
  │   ├── spf_defwords.f           ← 定義字
  │   ├── spf_immed_transl.f       ← 立即字直譯
  │   ├── spf_immed_lit.f          ← 常值立即字
  │   ├── spf_literal.f            ← 常值編譯
  │   ├── spf_immed_control.f     ← 控制結構
  │   ├── spf_immed_loop.f         ← 迴圈結構
  │   ├── spf_modules.f            ← 模組載入
  │   └── spf_inline.f            ← 內聯展開
  ├── [POSIX] 環境/多執行緒/CGI：
  │   ├── src/posix/envir.f        ← 環境查詢
  │   ├── src/posix/defwords.f     ← 平台定義字
  │   ├── src/posix/mtask.f        ← 多執行緒
  │   └── src/win/spf_win_cgi.f    ← CGI 支援（歷史上沿用 `win/` 路徑，但在這裡也被 POSIX 建構流程共用）
  ├── src/spf_init.f               ← 系統初始化 façade
  │   └── POSIX: src/posix/init.f / Windows: src/win/spf_win_init.f
  ├── [POSIX] src/posix/save.f     ← ELF 映像儲存
  └── src/xsave.f                 ← 映像寫出（Windows 則由 `DONE` 間接載入 `done.f` / `tsave.f` 完成）
```

---

## 3. 編譯選項

定義於 `spf_compileoptions.f`，可透過選用的 `src/compile.ini` 覆寫。repo 預設可以沒有這個檔案；缺檔時會使用原始碼中的預設值與自動偵測結果。

| 選項 | 預設值 | 說明 |
|------|--------|------|
| `CREATE-XML-HELP` | FALSE | 是否產生 `spfhelp.xml` 說明檔 |
| `ARCH-P6` | TRUE | 使用 P6（Pentium Pro+）指令集最佳化 |
| `BUILD-OPTIMIZER` | TRUE | 建構時是否包含最佳化器 |
| `USE-OPTIMIZER` | TRUE | 建構過程中是否使用最佳化 |
| `OPTIMIZE-BY-SIZE` | FALSE | 以大小最佳化（否則以速度最佳化） |
| `WIDE-CHAR` | FALSE | 使用 2 位元組字元（寬字元） |
| `SMALLEST-SPF` | FALSE | 建構最小版本（關閉最佳化器） |
| `UNIX-ENVIRONMENT` | 自動偵測 | 目標系統是否使用 Unix 換行 |
| `TARGET-POSIX` | 自動偵測 | 目標平台是否為 POSIX |

### 自動偵測機制

- 若 `LTL @ 1 =` 且 `LT C@ 0xA =`（目前模式為 Unix 換行且原始檔使用 LF），則自動設定 `UNIX-ENVIRONMENT`
- 若 `PLATFORM` 常數等於 `"Linux"`，則同時設定 `UNIX-ENVIRONMENT` 與 `TARGET-POSIX`

其中 `LT` / `LTL` 的來源與換行模式語意，詳見 [05-io-error-init.md](05-io-error-init.md) 第 2 節。

---

## 4. 建構流程

### 4.1 Linux 建構

POSIX 建構流程實際上偏向 Linux 環境，並需要 32-bit toolchain：`gcc -m32` / multilib、GNU `make`、`sha1sum`（或相容的 coreutils）與一般連結工具。macOS 或未安裝 multilib 的 Linux 會在工具鏈檢查或 `gcc -m32` 階段失敗。

```bash
cd src/ && make
```

流程：
1. 若缺少 `spf4orig`，自 `rufig/spf4-cvs-archive` 的 GitHub releases 下載並驗證 SHA1
2. 若缺少 `posix/config.auto.f`，執行 `posix/Makefile` 產生（編譯 `config.c` 執行檔偵測系統常數）
3. 執行 `spf4orig src/spf.f`，產生 `spf4.o`（可重定位物件檔）
4. 以 `gcc -m32 -Wl,forth.ld -ldl -lpthread` 連結，輸出 `../spf4`
5. 執行 `../spf4 lib/ext/spf4e.f`，載入 extended build 所需的標準字與部分延伸庫，產生 `../spf4e`

### 4.2 Windows 建構

```cmd
src\compile.bat
```

流程類似，使用 `jpf375c.exe` 作為宿主編譯器，輸出 `spf4.exe` 與 `spf4e.exe`。

---

## 5. 兩種可執行檔

| 可執行檔 | 說明 |
|----------|------|
| `spf4` | 最小核心，區分大小寫，僅含主系統 |
| `spf4e` | 擴充版，不區分大小寫；建構時會載入 `lib/ext/spf4e.f` 所納入的標準字與部分延伸庫，並預留 10 MiB 可用字典空間 |

---

## 6. 暫存器慣例（IA-32 呼叫約定）

SP-Forth 採用獨特的暫存器對應，所有核心原語均以 `CODE` 定義（內聯組合語言）：

| 暫存器 | SP-Forth 用途 | 慣例說明 |
|--------|---------------|----------|
| `EAX` | TOS（資料堆疊頂端） | 快取最佳化，避免反覆記憶體存取 |
| `EBP` | 資料堆疊指標 | 指向堆疊第二個元素（次堆疊項） |
| `ESP` | 回返堆疊指標 | 標準 x86 堆疊 |
| `EDI` | TLS（執行緒本地儲存）基底指標 | 用於 USER 變數存取 |
| `EBX` | 暫存/跳躍目的 | 通用暫存器 |
| `ECX` | 暫存/計數 | 通用暫存器 |
| `EDX` | 暫存/乘除 | 通用暫存器 |
| `ESI` | 暫存/字串操作 | 保留給 CMOV/字串指令 |

### 堆疊模型

```forth
資料堆疊（Data Stack）：
        ↑ 高位址
        +--------+
        |  TOS-3 |
        +--------+
  EBP → |  TOS-2 |  ← EBP 指向次堆疊項
        +--------+
        |  TOS-1 |
        +--------+
  EAX = |  TOS    |  ← 堆疊頂端快取在 EAX
        +--------+
        ↓ 低位址

回返堆疊（Return Stack）：
        ↑ 高位址
  ESP → |  返回位址  |
        +----------+
        ↓ 低位址
```

此設計使得許多原語只需要 1-3 條指令即可完成。例如 `DUP` 僅需：

```asm
LEA EBP, -4 [EBP]   ; EBP -= 4
MOV [EBP], EAX       ; 堆疊次項 = TOS
RET
```

---

## 7. 閱讀索引

### 7.1 推薦閱讀順序

1. `00-overview.md`：先建立全貌與術語。
2. `11-forth-compilation.md`：若你對 `STATE`、`:/;`、`IMMEDIATE`、`POSTPONE`、`COMPILE,`、`DOES>` 還不熟，先補這章。
3. `08-append-a.md`：若你對 IA-32 組語與 SP-Forth assembler 還不熟，先補這章。
4. `01-kernel.md`：理解 TOS-in-EAX、定義字與核心原語。
5. `02-compiler.md`：理解 parser / search-order / interpreter / compiler。
6. `03-cross-compiler.md`：理解 host / target / meta-compilation。
7. `07-optimizer.md`：理解最佳化器如何介入目標機器碼生成。
8. `04-posix-platform.md`：理解 POSIX 平台抽象、FFI、執行緒與信號。
9. `05-io-error-init.md`：理解 I/O、例外、初始化與互動式迴圈。
10. `06-build-save.md`：最後再看建構與映像輸出細節，最容易對上前面概念。
11. `14-walkthrough.md`：用一個小字詞端到端串起 parser、compiler、optimizer、target image 與 runtime startup。
12. `15-standalone-executable.md`：深入理解 `SAVE` / `SAVE-WITH-RESERVE` 如何把目前 Forth 系統映像儲存成可直接執行的 ELF / PE。
13. `15-standalone-cookbook.md`：若你要直接做 console / GUI standalone app，再看 recipe。
14. `12-debugging.md`：當你已理解主流程後，建立故障排查路徑：build、runtime、compiler、optimizer、FFI、image 問題各自怎麼切層。
15. `13-verification.md`：理解修改後如何驗證 primitive、compiler、optimizer、platform、ELF/PE image 與 FFI safety。
16. `16-lib.md`：若你想理解 `lib/`、ANS include 檔、`spf4e` 擴充載入與平台可選延伸庫，再看這章。
17. `16-lib-cookbook.md`：若你想直接照抄 `lib/include/`、`lib/ext/`、`lib/posix/`、`lib/win/` 的 runnable examples，再看 recipe。
18. `17-ac-lib3.md`：若你想找整理過的延伸函式庫與工具箱，先看這章；它會告訴你 `ac-lib3/` 各 library family 適合解哪些問題。
19. `18-devel.md`：若你想追作者工作區、歷史原型、framework/app 範例與 build helper 來源，再看這章。

### 7.2 文件索引

| 文件 | 主題 | 建議程度 |
|------|------|----------|
| [01-kernel.md](01-kernel.md) | 核心原語：定義字、堆疊操作、算術、記憶體存取 | 必讀 |
| [02-compiler.md](02-compiler.md) | 編譯器子系統：語法剖析、字詞搜尋、編譯流程 | 必讀 |
| [03-cross-compiler.md](03-cross-compiler.md) | 交叉編譯器與目標系統框架 | 必讀 |
| [04-posix-platform.md](04-posix-platform.md) | POSIX 平台支援：動態連結、檔案 I/O、信號處理 | 選讀（平台向） |
| [05-io-error-init.md](05-io-error-init.md) | 輸出入、例外處理與系統初始化 | 選讀（執行期向） |
| [06-build-save.md](06-build-save.md) | 建構系統、映像儲存與 ELF 產生 | 選讀（建構向） |
| [07-optimizer.md](07-optimizer.md) | 巨集最佳化器、內聯展開與跳躍最佳化 | 進階選讀 |
| [08-append-a.md](08-append-a.md) | IA-32 組語基礎、SP-Forth 內建 assembler 語法與常見技巧 | 先修 / 參考附錄 |
| [09-windows-platform.md](09-windows-platform.md) | Windows 平台支援：PE 格式、SEH、Win32 API 呼叫 | 選讀（平台向） |
| [10-quick-ref.md](10-quick-ref.md) | 快速參考：暫存器、檔案對照、編譯流程 | 速查參考 |
| [11-forth-compilation.md](11-forth-compilation.md) | Forth 編譯模式深入：STATE, :/;, IMMEDIATE, POSTPONE, COMPILE,, DOES> | 先修 / 參考附錄 |
| [12-debugging.md](12-debugging.md) | 除錯與故障排查：建構、執行期、compiler、optimizer、FFI、image 問題定位 | 維護 / 排錯 |
| [13-verification.md](13-verification.md) | 驗證、效能量測與安全檢查：分層測試、optimizer 等價性、FFI safety | 維護 / 驗證 |
| [14-walkthrough.md](14-walkthrough.md) | 端到端走讀：從一個 Forth 字到 parser、compiler、optimizer、image save 與 runtime startup | 實作串接 |
| [15-standalone-executable.md](15-standalone-executable.md) | 獨立執行檔生成：`SAVE`、`SAVE-WITH-RESERVE`、ELF/PE、entry point 與 runtime startup | 應用封裝 |
| [15-standalone-cookbook.md](15-standalone-cookbook.md) | Standalone executable 實作 recipe：console / GUI entry、`SPF-INIT?`、儲存後 smoke test | 應用封裝 cookbook |
| [16-lib.md](16-lib.md) | `lib/` 與 `spf4e` 導覽：ANS include、extended build、POSIX/Windows 可選延伸庫 | 標準字 / 延伸庫 |
| [16-lib-cookbook.md](16-lib-cookbook.md) | `lib/` 使用索引：`lib/include/`、`lib/ext/`、`lib/posix/`、`lib/win/` 的可跑範例與最小依賴選擇 | 標準字 / 延伸庫 cookbook |
| [17-ac-lib3.md](17-ac-lib3.md) | `ac-lib3/` 延伸函式庫導覽：功能分類、代表檔案、實際 Forth 範例、使用情境 | 延伸函式庫 / 工具箱 |
| [17-ac-lib3-cookbook.md](17-ac-lib3-cookbook.md) | `ac-lib3/` 使用索引：載入慣例、各 family 的代表 word 與可跑範例 | 延伸函式庫 cookbook |
| [18-devel.md](18-devel.md) | `devel/` 開發者工作區導覽：作者子樹、歷史原型、實用工具與大型範例專案 | 歷史 / 原型 / 社群工作區 |
| [18-devel-cookbook.md](18-devel-cookbook.md) | `devel/` 使用索引：作者子樹查找、代表 library 完整 Forth 範例、三大延伸函式庫（`lib/` vs `ac-lib3/` vs `devel/`）對照 | 工作區 cookbook |

## 8. 核心術語速查

| 術語 | 說明 |
|------|------|
| TOS | Top Of Stack，資料堆疊頂端；在 SP-Forth 中快取於 `EAX` |
| XT | Execution Token，字詞的執行令牌 |
| CFA | Code Field Address，執行碼欄位位址 |
| PFA | Parameter Field Address，參數欄位位址 |
| NFA | Name Field Address，名稱欄位位址 |
| LFA | Link Field Address，鏈結欄位位址 |
| nt | Name Token，指向字頭/名稱結構的令牌 |
| wid | Wordlist Identifier，詞彙表識別碼 |
| `STATE` | 0 = 直譯模式，非 0 = 編譯模式 |
| `[` / `]` | 切換到直譯模式 / 切回編譯模式 |
| `: name ... ;` | 定義新字詞（自動進入編譯狀態，`;` 結束） |
| `IMMEDIATE` | 編譯狀態下仍會立即執行的字 |
| `POSTPONE name` | 將 name 的編譯語意推遲至執行期 |
| `COMPILE, xt` | 在編譯期將 xt 編入字典 |
| `' name` | 取得 name 的 XT（執行令牌） |
| `EXECUTE` | 接收 XT 並執行對應的字詞 |
| `CREATE name` | 在字典中建立字詞並預留參數空間 |
| `DOES>` | 與 `CREATE` 搭配，定義執行期行為 |
| `CATCH` / `THROW` | 例外處理：`CATCH` 執行 XT 並捕獲 `THROW` |
| `VARIABLE` | 建立一個 cell 的變數 |
| `CONSTANT` | 建立常數 |
| `VALUE` | 可重新賦值的常數（`TO` 改值） |
| `VECT` | 可重新導向行為的向量字 |
| `USER` | 每執行緒各自擁有的變數空間 |
| `CURRENT` | 目前新定義會寫入的詞彙表 |
| `CONTEXT` | 目前搜尋順序的詞彙表 |
| `DP` | Dictionary Pointer，字典目前的寫入位置 |
| `HERE` | 字典寫入位置（同 DP） |
| `SOURCE` | 目前正在解析的輸入緩衝區 |
| `>IN` | 輸入緩衝區內的解析偏移 |
| `ALLOT` | 在字典中預留 n bytes 空間 |
| `,` / `C,` | 在字典中寫入 1 cell / 1 byte |
| `[T]` / `[I]` | 切換到目標詞彙表 / 切回宿主詞彙表 |
| `CON>LIT` | 將執行期查找摺疊為編譯期常值的最佳化 |
