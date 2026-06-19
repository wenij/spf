# SP-Forth/4 原始碼追蹤 — `ac-lib3/` 延伸函式庫導覽

> 定位：本章不追 kernel / compiler 本體，而是介紹 repo 內另一塊很實用、但容易被忽略的資產：`ac-lib3/`。
>
> 如果 `src/` 是 SPF 本體，`ac-lib3/` 更像是 **應用開發時可直接拿來用的函式庫與工具箱**。
>
> 如果你還不確定應該先看 `lib/`、`ac-lib3/` 還是 `devel/`，先回 [00-overview.md §2.1a](file:///Users/wenij/work/forth/spf/docs/trace/00-overview.md#21a-補充目錄ac-lib3-與-devel) 看三者對照表。

---

## 1. `ac-lib3/` 是什麼？

`ac-lib3/` 不是 `spf.f` 主載入路徑的一部分，也不是 `spf4` / `spf4e` 核心映像建構時一定會走過的 kernel / compiler 模組樹。更精確地說，它是一組：

- 延伸語言機制
- 字串與文字處理工具
- Windows API / 系統整合函式庫
- 除錯 / 記憶體 / 小工具
- 社群累積的可重用函式庫

從檔頭註解與命名慣例看，這一區主要是 **Andrey Cherezov（`~ac`）** 與其它 SPF 社群作者（特別是 **Ruvim Pinka** 等）在 1997–2003 年間累積的應用層函式庫。目錄中的註解大量使用 **CP1251 俄文編碼**，因此若直接用 UTF-8 工具打開原檔，常會看到亂碼；閱讀時要有這個心理準備。

另一個很重要的特徵是：`ac-lib3/` **明顯偏向 Win32 應用開發**。雖然裡面也有字串、BNF、mbox 解析等比較通用的模組，但最大的子樹是 `win/`，而且多數實作都直接包 `ADVAPI32.DLL`、`USER32.DLL`、`KERNEL32.DLL`、`WSOCK32.DLL` 等 Windows API。這也是為什麼它更像「應用開發資產庫」，而不是 SPF 本體的一部分。

因此，理解 `ac-lib3/` 最好的方式不是把它當成「主系統的一部分」，而是把它當成：

> **SP-Forth 生態系裡，給實際應用開發者用的延伸函式庫與技巧包。**

如果你是在追 SPF 的核心架構，優先讀 `src/`；但如果你是在找「已經有人把這件事做過了嗎？」的答案，`ac-lib3/` 往往更快。

---

## 2. 目錄地圖：`ac-lib3/` 裡大概有什麼？

從頂層結構可以先把它分成幾個大類：

```forth
ac-lib3/
├── LOCALS.F / TEMPS.F / REQUIRE.F    ← 語言延伸與載入輔助
├── STR.F / STR2.F / STR3.F / str4.f  ← 字串模板 / 內插系列
├── string/                           ← 正規表示式、MIME、大小寫、參數剖析等
├── win/                              ← Windows API 與系統整合
├── memory/                           ← 記憶體相關工具
├── debug/TRACE.F                     ← 除錯追蹤輔助
├── tools/                            ← 小工具、動態載入、WinAPI dump 類輔助
├── list/ / mbox/ / util/ / transl/   ← 小型資料處理、翻譯/規則、實驗性工具
└── ruvim/                            ← 其它作者的專用或局部功能模組
```

如果只想先抓大方向，可以把它記成下面這句：

- **頂層單檔**：偏語言延伸 / 字串模板 / 入口工具
- **`string/`**：偏文字與內容處理
- **`win/`**：偏 Windows 系統整合
- **`tools/` / `debug/` / `memory/`**：偏輔助工具

---

## 3. 幾個最值得先看的頂層檔案

### 3.1 `LOCALS.F` — locals 語法擴充

從檔頭註解與範例可看出，`LOCALS.F` 提供類似下面這種 locals 寫法：

```forth
{ a b c d \ e f -- i j }
```

這表示：

- 可以在 colon definition 一開始宣告具名局部變數
- 語法風格接近後來標準化的 locals 寫法
- 適合把 SPF 程式從「大量堆疊 juggling」稍微拉回可讀性更高的形式

**什麼時候會先看它？**

- 你覺得某段 SPF 應用程式全是 `SWAP OVER ROT`，可讀性很差
- 想確認舊 SPF 生態裡 locals 通常怎麼寫
- 想把某段範例改寫成比較像高階語言的風格

**例子**：

1. 若你想把：
   ```forth
   : FOO ( a b c -- ) OVER + SWAP ... ;
   ```
   改寫成較容易追的版本，通常會先看 `LOCALS.F`。

2. 若你在讀某份歷史 SPF 程式碼時看到 `{ a b -- }` 這類語法，`LOCALS.F` 是第一個該對照的地方。

### 3.2 `TEMPS.F` — temp / 暫存變數語法

`TEMPS.F` 和 `LOCALS.F` 很接近，但偏向以 `| ... |` 形式提供暫存命名空間。從檔頭註解來看，它的目標是：

- 提供短期暫存值的命名方式
- 降低需要一直把中間值留在堆疊上的壓力

**什麼時候會先看它？**

- locals 太重，你只想要幾個短暫中間值
- 想看 SPF 舊系統中 temp 變數的典型寫法

### 3.3 `REQUIRE.F` — library 載入輔助

`REQUIRE.F` 提供 `REQUIRE` / `REQUIRED` 風格的載入機制，檔頭裡還能看到：

- `LocalLibPath`
- `WebLibPath`

這表示它不只是「防止重複載入」，還帶有一套 SPF 舊時代的 library path / web path 組裝思路。

**什麼時候會先看它？**

1. 想知道 SPF 生態過去如何管理「需要時才載入」的庫
2. 想理解為什麼一些舊程式會寫出 `REQUIRE foo ~someone/lib/bar.f`
3. 想看 library path 拼接與 fallback 思路

### 3.4 `STR.F` / `STR2.F` / `STR3.F` / `str4.f` — 字串模板與插值系列

這四個檔案不是彼此獨立、平行存在的四套不同字串庫，而比較像**同一個主題逐步演進的版本族譜**：

- `STR.F`：較舊，依賴 `TEMPS.F`
- `STR2.F` / `STR3.F` / `str4.f`：較新，依賴 `LOCALS.F`
- `STR3.F`：再往前多加 `%WORD` / `%I` / `%J` 這類巨集槽
- `str4.f`：再往下接上自訂記憶體管理（`SALLOCATE` / `FREESTR`）

其中要特別分清楚：一般用 `"` / `STRBUF` 建出來的動態字串，正常釋放 API 是 `STRFREE`；`FREESTR` 則比較像搭配 `heap_enum.f` 做 heap 掃描 / 清理的工具，不是日常成對使用的 free 函式。

也就是說，這不是「你應該全部一起用」的四套庫，而是「你應該挑一個與當前程式風格最相容的版本」。

快速選擇可以這樣抓：

| 需求 | 優先看 |
|------|--------|
| 維護較舊、依賴 `TEMPS.F` 的程式 | `STR.F` |
| 一般模板字串 / 動態字串 | `STR2.F` |
| 需要 `%WORD`、`%I`、`%J` 這類巨集槽 | `STR3.F` |
| 想研究自訂 allocation、heap 掃描與 STR buffer 清理 | `str4.f` |

檔頭說明直接提到它們想提供比較接近 **Perl / PHP 風格**的字串能力，例如：

- 多行字串
- 模板字串
- 內插 `{word}`

簡單說，它們不是只做 `COUNT TYPE` 這種低階字串操作，而是想把 SPF 的字串寫法往「應用層可讀性」拉高。

**什麼時候會先看它們？**

1. 想把某個字詞結果嵌進字串中，而不是手動 `TYPE` / `HOLD` 拼接
2. 想產生 HTTP / SMTP / POP3 / CGI 類型的文字協定訊息
3. 想看 SPF 生態過去怎麼做 template string

**例子**：

- 想輸出包含變數值的 mail header / HTTP request line
- 想產生帶參數的 command string
- 想做多行模板而不是手刻大量 `CR TYPE`

---

## 4. 主要功能分類

### 4.1 語言延伸：讓 SPF 比較像「應用開發語言」

代表檔案：

- `ac-lib3/LOCALS.F`
- `ac-lib3/TEMPS.F`
- `ac-lib3/REQUIRE.F`

這類檔案的共通點是：

- 不直接改 kernel，但讓寫程式的體驗更高階
- 幫忙解決「程式太堆疊化，不好讀」或「library 載入麻煩」的問題

**典型用途**：

1. 想要 locals / temps，降低 `SWAP` / `OVER` / `ROT` 的密度
2. 想要 `REQUIRE` 風格的庫管理
3. 想看 SPF 舊代碼如何把語言本身補成更適合應用開發的樣子

### 4.2 字串與文字處理：`STR*` 與 `string/`

代表檔案：

- `ac-lib3/STR.F`
- `ac-lib3/STR2.F`
- `ac-lib3/STR3.F`
- `ac-lib3/str4.f`
- `ac-lib3/string/mime-decode.f`
- `ac-lib3/string/regexp.f`
- `ac-lib3/string/get_params.f`
- `ac-lib3/string/uppercase.f`

這一類是 `ac-lib3/` 最容易直接拿來用的部分之一。從檔名與檔頭可見，它涵蓋：

- 模板字串
- MIME / 郵件內容解碼
- 正規表示式（PCRE wrapper）
- 參數剖析
- 大小寫轉換

**典型用途**：

1. 郵件、HTTP、CGI 內容的字串處理
2. 做搜尋 / 擷取 / 正規表示式比對
3. 解析 query string / command line / 表單參數
4. 做大小寫正規化或比較

**例子**：

- 想 decode email header / MIME body → `string/mime-decode.f`
- 想用 PCRE 做模式比對 → `string/regexp.f`
- 想把 `a=b&c=d` 類字串拆參數 → `string/get_params.f`
- 想統一輸入大小寫 → `string/uppercase.f`

### 4.3 Windows API / 系統整合：`win/`

代表檔案：

- `ac-lib3/win/REGISTRY.F`
- `ac-lib3/win/ini.f`
- `ac-lib3/win/process/`
- `ac-lib3/win/winsock/`
- `ac-lib3/win/service/`
- `ac-lib3/win/com/`
- `ac-lib3/win/odbc/`

這一類很明顯是為 Windows 應用開發者準備的，而且其實可以再細分成幾個子群：

- **registry / ini / file / date**：設定、檔案系統與時間工具
- **process / service / access**：程序、服務與帳號權限管理
- **winsock**：TCP/UDP/DNS/IP helper
- **com**：COM / OLE / automation / ActiveX 整合
- **window**：GUI / dialog / tray icon / popup menu

它的價值在於：

- 不用每次都從 `WINAPI:` 宣告開始包整套 API
- 某些常見系統功能已經整理成 SPF 可直接調用的庫

**典型用途**：

1. registry 讀寫
2. INI 檔操作
3. process / service 管理
4. Winsock 網路功能
5. COM / ODBC 之類的系統整合

**例子**：

- 想把設定寫進 registry → `win/REGISTRY.F`（舊版）或 `win/registry2.f`（較新、改寫成 `LOCALS.F` 風格）
- 想讀/寫 ini 設定檔 → `win/ini.f`
- 想啟動/管理外部 process → `win/process/`
- 想做 socket client/server → `win/winsock/`
- 想做 ADO / Outlook / IE / XML / ActiveX 這類 Windows automation → `win/com/` 與它的 `samples/`

### 4.4 記憶體、除錯與小工具：`memory/`、`debug/`、`tools/`

代表檔案：

- `ac-lib3/debug/TRACE.F`
- `ac-lib3/tools/load_lib.f`
- `ac-lib3/tools/dump_winapi.f`
- `ac-lib3/memory/heap_enum.f`

這一類通常不直接出現在「主功能」程式裡，但在除錯、掃描系統狀態、動態載入或做工具程式時非常有價值。

**典型用途**：

1. 想加 trace / 除錯輔助輸出
2. 想列舉 / 探查 heap 或記憶體狀態
3. 想做 WinAPI 清單整理或載入 helper

**例子**：

- `debug/TRACE.F`：程式追蹤 / 除錯輸出 helper
- `tools/load_lib.f`：動態載入小工具
- `tools/dump_winapi.f`：WinAPI 相關資料整理
- `memory/heap_enum.f`：heap enumeration 類工具

其中有兩個特別值得點名：

- `tools/map.f`：不是一般工具，而是會 **hot-patch `COMPILE,` / `LIT,`** 的插樁工具，屬於非常 SPF 味的「編譯期黑魔法」
- `res_ctrl.f`：偏 **Eserv2 專案** 的 resource tracking 模式，適合拿來學如何做多執行緒資源表，但不一定適合直接搬進一般專案

### 4.5 翻譯 / 規則 / 小型專題：`transl/`、`list/`、`mbox/`、`util/`

這一類不像前面那麼「立即可辨識」，但很適合當成範例倉：

- `transl/`：文法 / 詞彙 / BNF 類實驗
- `list/`：清單資料結構或字串清單處理
- `mbox/`：郵件箱文字處理
- `util/`：零散但實用的小工具

**典型用途**：

1. 想找某種資料結構的 SPF 寫法範例
2. 想看文法處理 / 小型 parser 的舊做法
3. 想找社群成員留下的實用小片段

---

### 4.6 如何載入 `ac-lib3/` 的 library？

在實際使用各 library 之前，先搞懂「**怎麼把它載進來**」很重要；否則範例裡的字（如 `STR@`、`RG_OpenKey`、`PcreMatch`）根本還不存在。`ac-lib3/` 主要有兩種載入方式。

先提醒一個容易踩到的前提：很多 `ac-lib3/` 檔案不是完全獨立的單檔，它們開頭就會寫 `REQUIRE ... ~ac/lib/...`。因此「直接 `INCLUDED` 某個檔案」通常還隱含兩件事：

1. 目前 SPF session 裡已經有 `REQUIRE` / `REQUIRED`。
2. `~ac/lib/...` 這類作者路徑能透過 module / library 搜尋路徑找到對應檔案。

### 方式 A：用 SP-Forth 內建的 `INCLUDED`（最直接）

SP-Forth 本體就有 `INCLUDED` / `INCLUDE`，可以直接載入一個 `.f` 檔：

```forth
S" ac-lib3/LOCALS.F" INCLUDED
```

```forth
S" ac-lib3/string/regexp.f" INCLUDED
```

`spf_module.f` 的模組搜尋路徑（見 [05-io-error-init.md](05-io-error-init.md) 的 `+LibraryDirName`）會把相對路徑接到「**可執行檔目錄 + `/devel/`**」之下，因此在某些建構配置裡，`~ac/lib/...` 風格的路徑會被解析到 `devel/~ac/lib/...`（也就是 `ac-lib3/` 的母樹，見 [18-devel.md](18-devel.md)）。

### 方式 B：用 `REQUIRE`（去重 + 路徑慣例）

SPF4 本體已經有 `REQUIRE` / `REQUIRED`，而 `ac-lib3/REQUIRE.F` 則保留了一份早期、獨立的 require 實作。兩者核心概念相同：用一個代表 word 判斷 library 是否已載入，避免重複載入。這也是 `ac-lib3` 內部檔案彼此相依時最常見的寫法：

```forth
S" ac-lib3/REQUIRE.F" INCLUDED   \ 先載入 REQUIRE 機制本身
REQUIRE RG_OpenKey ~ac/lib/win/REGISTRY.F
```

它的語意是：

- `REQUIRE word libpath`
  - 先查字典，看 `word` 是否已存在
  - 已存在 → 什麼都不做（**去重**，避免重複載入）
  - 不存在 → 載入 `libpath`
- 也可以用字串形式：
  ```forth
  S" RG_OpenKey" S" ~ac/lib/win/REGISTRY.F" REQUIRED
  ```

> **路徑代號小提醒**：`ac-lib3/` 原始檔內部大量使用 `~ac/lib/...`、`~yz/lib/...` 這種「作者路徑代號」。在這個 repo 的實體佈局裡，`~ac/lib/...` 對應的主要是 `devel/~ac/lib/...`（`ac-lib3/` 是整理後的副本）。所以你在範例裡看到 `REQUIRE x ~ac/lib/...`，可以理解成「載入某個 `devel/~ac` 作者母樹下的檔案；而這份 repo 也另外保留了一份整理到 `ac-lib3/` 的副本」。

### 環境前提小抄

使用 `ac-lib3/` 時，最好先把下面幾個前提放在心裡：

| 前提 | 影響 |
|------|------|
| Win32 偏重 | `win/`、`memory/`、`tools/` 裡很多檔案直接呼叫 `KERNEL32.DLL`、`ADVAPI32.DLL`、`USER32.DLL` 等 Windows API |
| 外部 DLL | `string/regexp.f` 需要 `pcre.dll`，`string/bregexp/bregexp.f` 需要 `BREGEXP.DLL`，`win/arc/gzip/zlib.f` 需要 `zlib.dll` |
| 作者路徑 | `REQUIRE ... ~ac/lib/...` 通常期待 module/library path 能找到 `devel/~ac/lib/...` |
| 原檔編碼 | 註解多為 CP1251 俄文，UTF-8 工具直接打開常會看到亂碼 |

### 一個最小可跑的載入流程

以「我想用模板字串」為例，在已經能解析 `~ac/lib/...` 路徑的 SPF4 環境裡，完整流程通常是：

```forth
\ STR2.F 自己會 REQUIRE { ~ac/lib/locals.f
S" ac-lib3/STR2.F" INCLUDED

\ 現在 STR@ / STR+ / STYPE 等字才存在，可以開始用
: text S" hello" ;
" before {text} after" STYPE
```

如果你的環境無法解析 `~ac/lib/...`，就要先調整 library path，或改用對應的實體路徑手動載入依賴。之後各 library 的範例，都假設你已經用上面任一方式把對應檔案與其依賴載入了；為了精簡，下面不會在每個範例都重複貼載入指令。

---

### 4.7 詳細用法索引已拆分

本章只保留 `ac-lib3/` 的地圖與閱讀路線；逐項 library 說明、載入範例與堆疊效果備註已移到 [17-ac-lib3-cookbook.md](17-ac-lib3-cookbook.md)。

若你的目標是「我要直接拿某個檔案來用」，建議先讀使用索引；若你的目標是「我要知道 `ac-lib3/` 在 SPF repo 中扮演什麼角色」，留在本章即可。

---

## 5. 幾個具體的「遇到什麼問題就先看哪裡」

下面是最實用的讀法，不是按目錄，而是按需求：

### 情境 A：我想把 SPF 程式寫得不要那麼難讀

先看：

- `LOCALS.F`
- `TEMPS.F`

**典型例子**：

- 你有一段數值轉換或字串處理程式，全程靠堆疊 juggling，自己一週後就看不懂
- 想把中間值命名，而不是一直 `ROT SWAP OVER`

### 情境 B：我想做字串模板 / 內容組裝

先看：

- `STR.F` / `STR2.F` / `STR3.F` / `str4.f`

**典型例子**：

- 產生 HTTP header
- 產生 SMTP 命令字串
- 把某個字詞輸出嵌進一段模板中

### 情境 C：我想做 regex、MIME 或參數處理

先看：

- `string/regexp.f`
- `string/mime-decode.f`
- `string/get_params.f`

**典型例子**：

- 想解一段 MIME encoded text
- 想抓一串文字裡的 pattern
- 想 parse 一組 `name=value` 參數

### 情境 D：我想碰 Windows 系統功能

先看：

- `win/REGISTRY.F`
- `win/ini.f`
- `win/process/`
- `win/winsock/`

**典型例子**：

- registry 設定讀寫
- INI 設定檔處理
- 啟動外部程式
- socket 通訊

### 情境 E：我只想找範例，不一定要直接重用

先看：

- `debug/TRACE.F`
- `tools/`
- `transl/`
- `list/`
- `mbox/`

這些檔案很適合用來學：

- SPF 常見寫法
- 社群成員怎麼命名
- 某個問題在 SPF 裡通常怎麼拆

---

## 6. 哪些部分比較適合「直接拿來用」？哪些比較像「歷史/參考」？

大致可以用下面這個經驗法則：

| 類型 | 代表 | 建議心態 |
|------|------|----------|
| 比較像可直接重用的庫 | `LOCALS.F`, `TEMPS.F`, `REQUIRE.F`, `STR*.F`, `string/`, `win/` | 先看 API / 用法，再決定要不要直接載入 |
| 比較像工具與除錯輔助 | `debug/`, `tools/`, `memory/` | 遇到特定需求時再翻，常有現成小工具 |
| 比較像範例 / 實驗 / 參考倉 | `transl/`, `list/`, `mbox/`, `ruvim/`, 部分 `util/` | 更適合找思路、命名與實作風格，不一定直接搬進主專案 |

若再細分一點，可加上幾個「歷史軌跡」線索：

- `STR.F` → `STR2.F` / `STR3.F` / `str4.f`：反映字串模板系統與 locals 機制的演進
- `REGISTRY.F` → `registry2.f`：反映 `TEMPS.F` 風格往 `LOCALS.F` 風格的遷移
- `win/winsock/` 與 `win/winsock/ws2/` 兩套並行：反映 WinSock 舊版與較新版 API 的並存
- `win/com/samples/`：顯示 `ac-lib3/` 不只是一組 API wrapper，也包含大量「如何真的拿這些 wrapper 做事」的範例

### 6.1 一句話分類法

- **Foundational**：`LOCALS.F`、`REQUIRE.F`、`STR2.F`、`string/`、`win/winver.f`
- **直接可用的應用庫**：`win/registry2.f`、`win/ini.f`、`win/winsock/`、`win/com/`
- **工具 / 除錯**：`debug/TRACE.F`、`tools/`、`memory/`
- **歷史 / 範例 / Eserv2 脈絡**：`STR.F`、`REGISTRY.F`、`mbox/`、`res_ctrl.f`、`win/com/samples/`

---

### 6.2 依賴關係速記

如果你想用最少的心智負擔記住 `ac-lib3/` 的結構，可以用下面這個簡化圖：

```forth
                 REQUIRE.F   ← 載入機制 / 路徑組裝
                      │
        ┌─────────────┴─────────────┐
        │                           │
   LOCALS.F（現代）            TEMPS.F（較舊）
        │                           │
   ┌────┴──────────────┐            ├── STR.F
   │                   │            ├── REGISTRY.F
 STR2/3/4 + string/    registry2.f  └── 部分舊 Win32 庫
   │                   │
   ├── MIME / regexp   ├── win/ini.f
   ├── get_params      ├── win/file/
   ├── uppercase       ├── win/winsock/
   └── pattern         └── 其他較新 win/* 子樹
```

這不是精確的 require graph，而是一個足夠實用的閱讀心智模型：

- `LOCALS.F` 與 `TEMPS.F` 是兩代語法基礎
- `STR*`、`registry*`、大量 `win/*` 都沿著這條演進軸分成新舊兩路
- `string/` 與 `win/` 是兩個最肥、最有實際用途的分支

實務上，若你是：

- **想快速做功能** → 先看 `LOCALS.F`、`REQUIRE.F`、`STR*.F`、`string/`、`win/`
- **想找可借鏡的 SPF 應用寫法** → 再翻 `tools/`、`debug/`、`transl/` 等

---

## 7. `ac-lib3/` 與主系統的關係

再次強調：`ac-lib3/` 不是 `spf.f` 的核心建構樹；但它也不是完全孤立。它更像：

- SPF 生態的延伸函式庫倉
- 應用層與工具層的高價值資產
- 社群累積的可重用解法集合

因此，它最適合的角色不是「追 kernel 時必讀」，而是：

> **當你已經知道 SPF 本體怎麼運作，接下來想『真的拿 SPF 來做事』時，`ac-lib3/` 通常是下一站。**

---

## 8. 建議閱讀順序

如果你是第一次認真看 `ac-lib3/`，建議順序：

1. `LOCALS.F` / `TEMPS.F` / `REQUIRE.F`
   先理解它怎麼補語言層工具
2. `STR*.F`
   看 SPF 生態怎麼做高階字串模板
3. `string/`
   找實用文字處理模組
4. `win/`
   若你做 Windows 系統整合，再深入這裡
5. `debug/` / `tools/` / `memory/`
   當成工具箱與範例庫
6. `transl/` / `list/` / `mbox/` / `ruvim/`
   當成歷史與應用範例倉慢慢翻

如果你只想先抓住一句話，那就是：

> `src/` 讓你理解 SPF 怎麼工作；`ac-lib3/` 讓你更快拿 SPF 去做實際應用。

---

## 9. 與其它 trace 章節的關係

- 若你想理解 SPF 本體的 module / include / 載入策略，先讀 [00-overview.md](00-overview.md) 與 [02-compiler.md](02-compiler.md)。
- 若你想知道 `devel/` 為什麼也會進模組搜尋路徑，回看 [05-io-error-init.md](05-io-error-init.md) 中 `spf_module.f` 的路徑處理。
- 若你想理解 build helper（如 `fres.f`）如何與 `devel/` 發生關聯，回看 [06-build-save.md](06-build-save.md)。
- 若你想直接查某個 `ac-lib3/` 檔案怎麼用，接著讀 [17-ac-lib3-cookbook.md](17-ac-lib3-cookbook.md)。

本章的目的不是把 `ac-lib3/` 的每個檔案都拆開逐行追，而是先給你一張足夠實用的「地圖」。真正要深入某個檔案時，再沿著這張地圖找進去，會比直接從目錄樹盲翻有效得多。
