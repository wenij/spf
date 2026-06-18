# SP-Forth/4 原始碼追蹤 — `ac-lib3/` 延伸函式庫導覽

> 定位：這一章不追 kernel / compiler 本體，而是介紹 repo 內另一塊很實用、但容易被忽略的資產：`ac-lib3/`。
>
> 如果 `src/` 是 SPF 本體，`ac-lib3/` 更像是 **應用開發時可直接拿來用的函式庫與工具箱**。

---

## 1. `ac-lib3/` 是什麼？

`ac-lib3/` 不是 `spf.f` 主載入路徑的一部分，也不是 `spf4` / `spf4e` 核心映像建構時一定會走過的 kernel / compiler 模組樹。更精確地說，它是一組：

- 延伸語言機制
- 字串與文字處理工具
- Windows API / 系統整合函式庫
- 除錯 / 記憶體 / 小工具
- 社群累積的 reusable library

從檔頭註解與命名慣例看，這一區主要是 **Andrey Cherezov（`~ac`）** 與其它 SPF 社群作者（特別是 **Ruvim Pinka** 等）在 1997–2003 年間累積的應用層函式庫。目錄中的註解大量使用 **CP1251 俄文編碼**，因此若直接用 UTF-8 工具打開原檔，常會看到亂碼；閱讀時要有這個心理準備。

另一個很重要的特徵是：`ac-lib3/` **明顯偏向 Win32 應用開發**。雖然裡面也有字串、BNF、mbox 解析等比較通用的模組，但最大的子樹是 `win/`，而且多數實作都直接包 `ADVAPI32.DLL`、`USER32.DLL`、`KERNEL32.DLL`、`WSOCK32.DLL` 等 Windows API。這也是為什麼它更像「應用開發資產庫」，而不是 SPF 本體的一部分。

因此，理解 `ac-lib3/` 最好的方式不是把它當成「主系統的一部分」，而是把它當成：

> **SP-Forth 生態系裡，給實際應用開發者用的延伸函式庫與技巧包。**

如果你是在追 SPF 的核心架構，優先讀 `src/`；但如果你是在找「已經有人把這件事做過了嗎？」的答案，`ac-lib3/` 往往更快。

---

## 2. 目錄地圖：`ac-lib3/` 裡大概有什麼？

從 top-level 結構可以先把它分成幾個大類：

```forth
ac-lib3/
├── LOCALS.F / TEMPS.F / REQUIRE.F    ← 語言延伸與載入輔助
├── STR.F / STR2.F / STR3.F / str4.f  ← 字串模板 / 內插系列
├── string/                           ← regexp、MIME、大小寫、參數剖析等
├── win/                              ← Windows API 與系統整合
├── memory/                           ← 記憶體相關工具
├── debug/TRACE.F                     ← 除錯追蹤輔助
├── tools/                            ← 小工具、動態載入、WinAPI dump 類輔助
├── list/ / mbox/ / util/ / transl/   ← 小型資料處理、翻譯/規則、實驗性工具
└── ruvim/                            ← 其它作者的專用或局部功能模組
```

如果只想先抓大方向，可以把它記成下面這句：

- **top-level 單檔**：偏語言延伸 / 字串模板 / 入口工具
- **`string/`**：偏文字與內容處理
- **`win/`**：偏 Windows 系統整合
- **`tools/` / `debug/` / `memory/`**：偏輔助工具

---

## 3. 幾個最值得先看的 top-level 檔案

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

也就是說，這不是「你應該全部一起用」的四套庫，而是「你應該挑一個與當前程式風格最相容的版本」。

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
- regexp（PCRE wrapper）
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

1. 想加 trace / debug 輔助輸出
2. 想列舉 / 探查 heap 或記憶體狀態
3. 想做 WinAPI 清單整理或載入 helper

**例子**：

- `debug/TRACE.F`：程式追蹤 / debug print helper
- `tools/load_lib.f`：動態載入小工具
- `tools/dump_winapi.f`：WinAPI 相關資料整理
- `memory/heap_enum.f`：heap enumeration 類工具

其中有兩個特別值得點名：

- `tools/map.f`：不是一般 utility，而是會 **hot-patch `COMPILE,` / `LIT,`** 的插樁工具，屬於非常 SPF 味的「編譯期黑魔法」
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

## 4.6 主要 library 細部索引（逐項說明 + example）

這一節把前面提到的主要 library / family 再往下展開：**每個先說它是做什麼，再給至少兩個實際會遇到的例子**。若你是第一次真正打算「拿 `ac-lib3/` 來做事」，這一節會比前面的目錄圖更實用。

### `LOCALS.F`

**它是做什麼的？**  
提供 SPF 裡的 locals 語法擴充，讓你可以在 colon definition 一開始宣告具名局部變數，減少大量 `SWAP` / `OVER` / `ROT` 導致的可讀性下降。

**你通常會在什麼情況用它？**

1. 你有一段數值或字串處理邏輯，堆疊 juggling 已經多到自己都難追。  
2. 你在維護舊 SPF 應用，想把 stack-heavy 的 code 改寫得比較像可維護的程式。  
3. 你在讀 `ac-lib3/` 其它比較新的檔案（例如 `registry2.f`、`STR2.F`），常會先看到 `REQUIRE { ~ac/lib/locals.f`。

**例子**：

- 把 `: FOO ( a b c -- ) OVER + SWAP ... ;` 改寫成使用具名區域變數的版本，讓資料流更明確。
- 在 `DO ... LOOP` 或 callback 邏輯中保留一些中間值，不必反覆從堆疊重新排列。
- 讀到 `{: ... :}` / `{ a b \ c -- }` 這類寫法時，用 `LOCALS.F` 對照其語意。

**實際 Forth 範例碼**（來自檔頭示例）：

```forth
: TEST { a b c d \ e f -- }
  a . b . c .
  b c + -> e
  e . f .
  ^ a @ .
;
```

```forth
: TEST { a b -- }
  a . b . CR
  5 0 DO I . a . b . CR LOOP
;
```

### `TEMPS.F`

**它是做什麼的？**  
`TEMPS.F` 是較舊的一代 temp / locals 方案，提供 `| ... |`、`(( ... ))`、`|| ... ||` 等語法，讓你能建立短期暫存值與類 VALUE 風格的臨時變數。

**你通常會在什麼情況用它？**

1. 你在讀較舊的 `ac-lib3/` 程式（例如 `STR.F`、`REGISTRY.F`、部分 `window/` 模組），發現它們不是用 `LOCALS.F`。  
2. 你想理解 SPF 生態從舊 temp 機制過渡到較新 locals 機制的歷史軌跡。  
3. 你只想放幾個短暫中間值，不想引入完整 locals 風格。

**例子**：

- 在較舊檔案裡看到 `|| h ||` 或 `(( a b ))` 時，用 `TEMPS.F` 理解它在做什麼。
- 維護 `STR.F` 這類依賴 `TEMPS.F` 的舊版模板字串實作。
- 比較 `TEMPS.F` 與 `LOCALS.F` 的寫法差異，決定舊專案要不要遷移。

**實際 Forth 範例碼**（依語法風格整理）：

```forth
| tmp count |
... 
123 -> tmp
tmp .
```

```forth
(( a b c ))
...
```

> `TEMPS.F` 本身不像 `LOCALS.F` 那樣附完整示範程式，但 `|`、`(( ))`、`->` 的定義已清楚顯示這套用法；讀較舊的 `STR.F`、`REGISTRY.F`、`WINDOW.F` 時通常會先碰到它。

### `REQUIRE.F`

**它是做什麼的？**  
提供 `REQUIRE` / `REQUIRED` 風格的載入機制：避免重複載入、組合 library path，並依序嘗試 local path / 預設 library path / web path。

**你通常會在什麼情況用它？**

1. 想知道 `~ac/lib/...` 這套 require 慣例是怎麼運作的。  
2. 想理解 SPF 生態早期如何管理「按需載入」的外部函式庫。  
3. 想追某個 `ac-lib3/` 檔案的依賴鏈，通常會先從它的 `REQUIRE` 列表開始。

**例子**：

- 讀到 `REQUIRE COMPARE-U ~ac/lib/string/compare-u.f` 時，知道這不只是 include，而是帶有去重與路徑處理的載入。
- 想手動在 SPF project 中導入某個 `ac-lib3` 模組，會先學 `REQUIRE` 的用法。
- 想理解為什麼 `WebLibPath` 這類設計存在（雖然目前 web branch 未實作）。

**實際 Forth 範例碼**：

```forth
REQUIRE COMPARE-U ~ac/lib/string/compare-u.f
```

```forth
S" COMPARE-U" S" ~ac/lib/string/compare-u.f" REQUIRED
```

### `STR.F` / `STR2.F` / `STR3.F` / `str4.f`

**它們是做什麼的？**  
這是一整個「動態字串 / 模板字串」家族：目標是提供接近 Perl / PHP 風格的 `"...{expr}..."` 字串內插能力。它們不是四個獨立功能庫，而是同一主題的演進版本。

**你通常會在什麼情況用它們？**

1. 想產生 HTTP / SMTP / CGI / mail 這類大量文字輸出的應用。  
2. 想把某個 word 的輸出直接嵌進模板，而不是手工 `TYPE` / `HOLD`。  
3. 想比較 SPF 生態裡 `TEMPS` 與 `LOCALS` 風格在同一問題上的寫法差異。

**例子**：

- 組一個帶變數內插的 HTTP response body。
- 建一段包含 `{CRLF}`、`{word}`、`{FILE ...}` 的 mail / CGI 模板。
- 想選擇版本時：舊碼偏 `STR.F`，較新風格偏 `STR2.F` / `STR3.F` / `str4.f`。

**實際 Forth 範例碼**（來自原檔註解）：

```forth
: text S" hello" ;
" before {text} after" STYPE
```

```forth
" abc{TEST}123 5+5={5 5 +} Ok" STYPE CR
```

```forth
: TEST2
  " abc{TEST}123 5+5={5 5 +} Ok {ZZZ} OK!"
  STYPE CR
;
```

### `string/CONV.F`

**它是做什麼的？**  
提供一大包通用字串/編碼轉換工具：base64、KOI8-R ↔ Windows-1251、URL `%xx` 轉換、把 query-string / token stream 轉成 blank-delimited 形式等。

**你通常會在什麼情況用它？**

1. 郵件、HTTP、URL 參數、俄文字元編碼處理。  
2. 想把非空白分隔的輸入改造成 parser 易讀的形式。  
3. 想做 base64 encode/decode，而不想自己重寫。

**例子**：

- 把一段 base64 資料 decode 回 addr/u。
- 把 URL query string 中的 `%20` / `%3A` 還原。
- 把 KOI8-R 文本轉成 Windows-1251，以便和 Windows API 或舊資料互通。

**實際 Forth 範例碼**：

```forth
S" SGVsbG8=" debase64
```

```forth
S" a%20b%3Ac" CONVERT%
```

### `string/get_params.f`

**它是做什麼的？**  
專做 `name=value&x=y` 這類 query-string / form parameter 的解析與查詢。

**你通常會在什麼情況用它？**

1. CGI / HTTP form 參數處理。  
2. 想從一串 URL-style 參數快速查出特定 key。  
3. 想 dump / iterate 整個參數集合。

**例子**：

- 解析 `error_code=10060&from=http://10.1.1.11/`，再用 `GetParam` 取特定欄位。
- 先 `GetParamsFromString`，後續用 `IsSet` 判斷某個參數有沒有帶。
- 用 `DumpParams` 快速看整串參數 parse 結果。

**實際 Forth 範例碼**（檔頭已有示例）：

```forth
S" error_code=10060&from=http://10.1.1.11/" GetParamsFromString
```

```forth
S" error_code" GetParam
```

### `string/mime-decode.f`

**它是做什麼的？**  
處理 MIME / mail header 的 encoded text（RFC 2045 / 2047 / 2231），尤其適合郵件與 HTTP 文字內容解碼。

**你通常會在什麼情況用它？**

1. 郵件標頭出現 `=?charset?...?=` 形式的編碼字串。  
2. 想處理 quoted-printable / base64 兩種常見 mail encoding。  
3. 想把 KOI8-R / Windows-1251 等俄文相關 charset 正常還原。

**例子**：

- 解 `Subject: =?windows-1251?B?...?=` 類型的 mail 標頭。
- 把 folded header（跨行 header）先 `StripLwsp` 再 decode。
- 在郵件 parser 裡把 charset decoder 掛進 `CHARSET-DECODERS` 詞彙表。

**實際 Forth 範例碼**（原檔註解示意）：

```forth
" STR@ StripLwsp MimeValueDecode ANSI>OEM TYPE
```

```forth
S" =?windows-1251?B?...?=" MimeValueDecode
```

### `string/regexp.f`

**它是做什麼的？**  
這是 PCRE wrapper，提供 Perl 風格正規表示式能力，是 `ac-lib3/string/` 裡最強大的 pattern matching 工具之一。

**你通常會在什麼情況用它？**

1. 想抓取字串中的結構化片段。  
2. 想一次取出多個 capture groups。  
3. 想在 SPF 中直接用現代 regexp，而不是自己手寫 parser。

**例子**：

- 用 `PcreMatch` 做簡單 yes/no 模式比對。
- 用 `PcreGetMatch` 把 `(\S+)\s+(\S+)` 這類 capture group 全部拉出來。
- 在 mail / CGI / config parser 前先用 regexp 過濾格式。

**實際 Forth 範例碼**（檔頭註解已有）：

```forth
S" PcReIsRULEZZ:)" S" ^P(.+)Z" PcreMatch .
```

```forth
S" one two three" S" (\S+)\s+(\S+)\s+(\S+)" PcreGetMatch
```

### `string/bregexp/bregexp.f`

**它是做什麼的？**  
另一套 regexp 路線，依賴同目錄附帶的 `BREGEXP.DLL`。與 `regexp.f`（PCRE）相比，它更像是另一個外部 regex engine 的 binding。

**你通常會在什麼情況用它？**

1. 已經有 `BREGEXP.DLL` 環境，想直接重用。  
2. 想比較 PCRE 與另一套 regexp engine 的用法或效能。  
3. 在維護歷史專案時發現它原本就依賴 BRegexp。

**例子**：

- 用 `BregexpMatch` 做快速比對。
- 用 `BregexpGetMatch` 取 match 結果。
- 在 Windows-only 環境下，維護依賴 `BREGEXP.DLL` 的舊工具。

### `debug/TRACE.F`

**它是做什麼的？**  
一個非常小、但很有 SPF 特色的 debug helper：透過重新定義 `:`，讓每個新定義的 word 在執行時自動印出自己的名字。

**你通常會在什麼情況用它？**

1. 想在 legacy code 裡快速加 trace，而不重寫一堆 logging。  
2. 想觀察某段程式實際執行到了哪些 word。  
3. 想學 SPF 如何攔截 `:` 來做 trace。

**例子**：

- `DebugOn` 後，跑某段程式，觀察 word 呼叫序列。
- 維護舊服務程式時，快速知道它卡在哪個 word。
- 當成最小可讀的 trace 實作範例。

**實際 Forth 範例碼**：

```forth
DebugOn
```

```forth
: TEST-WORD ... ;
```

> 一旦 `DebugOn`，之後定義並執行的新 word 會經過 `DEBUG.`，把名稱印出來。

### `tools/load_lib.f`

**它是做什麼的？**  
動態載入 DLL，並走 `WINAPLINK` 把已宣告的 `WINAPI:` 名稱一次 resolve / 回填。

**你通常會在什麼情況用它？**

1. plugin DLL 在執行時才決定路徑。  
2. 想一次性把某個 DLL 裡已宣告的 API 都綁好。  
3. 想理解 `WINAPLINK` 這套 lazy API binding 怎麼接起來。

**例子**：

- 啟動時才決定載哪個版本的 DLL。
- 手動載入一個客製 DLL，然後重綁一批 `WINAPI:` 宣告。
- 在工具程式中做簡單 plugin loader。

**實際 Forth 範例碼**：

```forth
S" myplugin.dll" LoadInitLibrary
```

```forth
S" extraapi.dll" LoadInitLibrary DROP
```

### `tools/dump_winapi.f`

**它是做什麼的？**  
把 `WINAPLINK` 鏈上的 WinAPI 宣告 dump 出來，方便除錯與 introspection。

**你通常會在什麼情況用它？**

1. 想知道目前有哪些 `WINAPI:` 宣告已經存在。  
2. 想除錯 DLL/函式名稱綁定是否正確。  
3. 想快速看某個模組到底依賴哪些 WinAPI。

**例子**：

- 在載完模組後執行 `DUMP-WINAPI` 檢查綁定清單。
- 調查某個 `GetProcAddress` 失敗是不是因為名字拼錯。

**實際 Forth 範例碼**：

```forth
DUMP-WINAPI
```

```forth
S" kernel32.dll" LoadInitLibrary DROP
DUMP-WINAPI
```

### `tools/jmp.f`

**它是做什麼的？**  
直接在機器碼層 patch 一條 `0xE9 rel32` 跳轉。這是很低階、很 SPF 的工具。

**你通常會在什麼情況用它？**

1. 想 hot-patch 一個既有 word 到另一個位址。  
2. 想做 compiler instrumentation / interception。  
3. 想學 SPF 怎麼在 runtime 改 code stream。

**例子**：

- 把某個既有 primitive 改跳到測試版實作。
- 作為 `tools/map.f` 的底層基礎，攔截 `COMPILE,` / `LIT,`。

**實際 Forth 範例碼**：

```forth
' NEW-COMPILE, ' COMPILE, JMP
```

```forth
' NEW-LIT, ' LIT, JMP
```

### `tools/map.f`

**它是做什麼的？**  
這是編譯器插樁工具：透過 `jmp.f` 改寫 `COMPILE,` 和 `LIT,`，讓編譯時把 reference map 印出來。

**你通常會在什麼情況用它？**

1. 想看大型專案裡誰編譯了誰。  
2. 想 debug 交叉參照或 dependency map。  
3. 想學 SPF 的 hot-patch compiler 技巧。

**例子**：

- 產生簡易 call/reference map。
- 找出某個 word 為什麼會被編進映像。
- 研究 compiler hook 的實作技巧。

**實際 Forth 範例碼**：

```forth
' NEW-COMPILE, ' COMPILE, JMP
' NEW-LIT, ' LIT, JMP
```

```forth
ZZZ 6 0 DO TEST ['] TEST 2DROP LOOP [ ' TEST 1+ ] LITERAL ;
```

### `list/STR_LIST.F`

**它是做什麼的？**  
提供 xcount 字串清單與單向鏈結串列的基本操作。

**你通常會在什麼情況用它？**

1. 想維護一串字串集合。  
2. 想做 membership test (`inList`)。  
3. 想找最小但實用的資料結構範例。

**例子**：

- 建一個字串黑名單 / 白名單。
- 把 parse 出來的字串值逐一 `AddNode` 存起來。

**實際 Forth 範例碼**：

```forth
value my-list
S" hello" AddNode my-list
S" world" AddNode my-list
```

```forth
S" hello" my-list inList .
```

### `transl/vocab.f`

**它是做什麼的？**  
提供 `InVoc{ ... }PrevVoc`、`Public{ ... }Public` 這類語法糖，讓 vocabulary / public API 的定義比較不囉唆。

**你通常會在什麼情況用它？**

1. 想把一批 word 收進某個 vocabulary。  
2. 想宣告 public API，而不手刻 `ALSO DEFINITIONS PREVIOUS`。  
3. 想看 SPF 如何把詞彙表操作包成 block syntax。

**例子**：

- 寫模組型 library 時，把內部字與公開字分開。
- 讀 `mbox/text_mbox_parsing.f` 時理解它怎麼建立自己的 vocabulary。

**實際 Forth 範例碼**：

```forth
InVoc{ MyModule
  Public{
    : hello ... ;
  }Public
}PrevVoc
```

```forth
InVoc{ ParserState
  : reset ... ;
}PrevVoc
```

### `transl/BNF.F`

**它是做什麼的？**  
提供一套 BNF / parser scaffolding，用來寫小型語法解析器。

**你通常會在什麼情況用它？**

1. 想 parse 某種協定語法。  
2. 想寫設定檔 / mini-language parser。  
3. 想看 SPF 世界裡「文法導向 parser」怎麼搭。

**例子**：

- 寫自訂 DSL parser。
- 寫 protocol header parser。
- 研究 `Look` / `Match` / `Expected` 這種 parser 基本骨架。

**實際 Forth 範例碼**：

```forth
CHAR ( Match
GetQuoted
CHAR ) Match
```

```forth
LookString S" BEGIN" IF ... THEN
```

### `ruvim/MASK.F`

**它是做什麼的？**  
提供 wildcard mask matching（`*` / `?` / 跳脫字元），偏向 glob 類比對。

**你通常會在什麼情況用它？**

1. 想做簡單檔名 / 模式匹配，而不需要完整 regexp。  
2. 想做大小寫不敏感的 wildcard compare。  
3. 想要比 regexp 更輕量的 match 工具。

**例子**：

- 比對 `*.txt` / `mail-??.log` 類檔名樣式。
- 在規則系統裡做 pattern filter。

**實際 Forth 範例碼**：

```forth
S" report.txt" S" *.txt" WildCMP-U
```

```forth
S" mail-01.log" S" mail-??.log" WildCMP-U
```

### `res_ctrl.f`

**它是做什麼的？**  
這是一個 thread-aware resource table，用來追蹤資源（尤其 file handle）。很明顯帶有 Eserv2 風格。

**你通常會在什麼情況用它？**

1. 想抓 file handle leak。  
2. 想學多執行緒資源表怎麼做。  
3. 想研究 SPF 裡 vector + mutex 的組合方式。

**例子**：

- 攔截 `OPEN-FILE` / `CLOSE-FILE`，看誰沒關檔。
- 在 server 型程式裡追蹤每個 thread 持有的資源。

**實際 Forth 範例碼**：

```forth
INIT-RTABLE
DUMP-RES
```

```forth
S" test.txt" R/O OPEN-FILE DROP
DUMP-RES
```

### `memory/heap_enum.f` / `heap_enum2.f` / `less_mem.f`

**它們是做什麼的？**  
前兩者用來列舉 heap，後者用來收縮 process working set。偏 Win32 記憶體觀察/調整工具。

**你通常會在什麼情況用它們？**

1. 想看目前 process 的 heap 狀態。  
2. 想調查字串 buffer / heap allocation 流失。  
3. 想在長時間 idle 的程式裡要求 OS 回收 working set。

**例子**：

- 用 `heap_enum2.f` 配合 `str4.f` 找遺失的 STRBUF。
- 在 WinNT 上跑 `ReduceMem`，把 working set 壓下來。

**實際 Forth 範例碼**：

```forth
MEM
```

```forth
ReduceMem
```

### `win/registry2.f` / `REGISTRY.F`

**它們是做什麼的？**  
都是 Windows registry 操作庫。`REGISTRY.F` 是舊版（TEMPS 風格），`registry2.f` 是改寫成 `LOCALS.F` 風格的較新版。

**你通常會在什麼情況用它們？**

1. 想讀/寫 registry key/value。  
2. 想列舉某個 key 下的所有 subkeys / values。  
3. 想看 SPF 如何包 `RegOpenKeyA` / `RegQueryValueExA` 這一類 API。

**例子**：

- 讀某個設定值：`StrValue` / `NumValue` / `BinValue`
- 列舉 key/value：`RG_ForEachKey` / `RG_ForEachValue`
- 維護舊程式時，若看到 TEMPS 風格就看 `REGISTRY.F`；新程式優先看 `registry2.f`

**實際 Forth 範例碼**：

```forth
S" ProxyServer" S" SOFTWARE\\Example" StrValue
```

```forth
['] TYPECR SWAP RG_ForEachKey
```

### `win/ini.f`

**它是做什麼的？**  
INI 檔操作封裝，還提供 `File.Section[Key]` 類型的方便語法。

**你通常會在什麼情況用它？**

1. 應用程式配置存在 INI 檔。  
2. 想做 default / fallback ini 查詢。  
3. 想要比直接 `GetPrivateProfileStringA` 更好用的包裝。

**例子**：

- 讀 `Mail[CMCDLLNAME32]` 類設定值。
- 做兩份 ini（正式 / 原始）之間的 fallback 查詢。

**實際 Forth 範例碼**：

```forth
S" key" S" section" S" file.ini" IniFile@
```

```forth
S" g:\\WINXP\\win.ini.Mail[CMCDLLNAME32]" IniS@
```

### `win/file/`

**它是做什麼的？**  
補 Win32 檔案系統相關能力：find file、遞迴列舉、file time、share-delete、FILE* stream 包裝。

**你通常會在什麼情況用它？**

1. 想遞迴掃目錄。  
2. 想讀檔案時間戳。  
3. 想在檔案開啟時仍允許 delete/share。  
4. 想橋接到 C runtime stream。

**例子**：

- 找出某目錄下所有符合 pattern 的檔案。
- 做 recursive file scan (`findfile-r.f`)。
- 需要 `FILE_SHARE_DELETE` 的 Windows 特殊開檔模式。

**實際 Forth 範例碼**：

```forth
S" *.txt" ['] TYPE FIND-FILES
```

```forth
S" c:\\logs\\*.log" ['] TYPE FIND-FILES-R
```

### `win/process/`

**它是做什麼的？**  
封裝 process 啟動、等待、列舉、kill、pipe、child I/O 等功能。

**你通常會在什麼情況用它？**

1. 想在 SPF 裡啟動外部程式。  
2. 想抓 child process 的 stdin/stdout。  
3. 想列舉或結束現有 process。  
4. 想處理 console control handler / shutdown。

**例子**：

- `StartApp` / `StartAppWait` 啟動外部工具。
- `ChildApp` 做 parent-child 的 pipe 溝通。
- `enumproc.f` / `kill.f` 做簡單 process 管理工具。

**實際 Forth 範例碼**：

```forth
S" notepad.exe" StartApp
```

```forth
S" ping 127.0.0.1" StartAppWait
```

### `win/service/`

**它是做什麼的？**  
提供 Windows service 相關結構與操作；還保留 `service95.f` 這類 Win9x 時代的替代方案。

**你通常會在什麼情況用它？**

1. 想把 SPF 應用包成 Windows service。  
2. 想建立 / 刪除 / 控制 service。  
3. 想研究 SPF 裡 service skeleton 的寫法。

**例子**：

- 寫一個背景常駐服務。
- 安裝、啟動、刪除 service。
- 維護極舊系統時看 `service95.f` 如何在 Win9x 模擬 service。

**實際 Forth 範例碼**：

```forth
S" MyService" StartService
```

```forth
S" MyService" DeleteService
```

### `win/com/`

**它是做什麼的？**  
這是 `ac-lib3/` 最龐大、也最具「應用能力展示」意味的區塊之一：

- `COM.F` 提供 COM / OLE / BSTR / Unicode 基礎封裝
- `com_server.f` / `com_server2.f` 提供 `Class:` / `METHOD` 風格的 COM server framework
- `samples/` 內有大量 ADO / CDO / Outlook / IE / XML / ActiveX / .NET 互通示例

**你通常會在什麼情況用它？**

1. 想從 SPF 呼叫 COM / ActiveX / OLE automation。  
2. 想研究 SPF 如何自己實作 COM class / vtable。  
3. 想找真實的 Outlook / ADO / IE automation 範例。  
4. 想知道 SPF 生態能做到多深的 Windows automation。

**例子**：

- 用 ADO / OLE DB 連資料庫。
- 用 Outlook / IE / Messenger / XML automation 跟 Windows application 互動。
- 研究 `com_server2.f` 的 `SPF.Application` worked example。

**實際 Forth 範例碼**：

```forth
ComInit
```

```forth
S" Some.ProgID" CLSIDFromProgID
```

```forth
ComExit
```

### `win/window/`

**它是做什麼的？**  
這是一整套 Win32 GUI 工具箱：window、dialog、listbox、icon、tray、popup menu、window enumeration 等。

**你通常會在什麼情況用它？**

1. 想在 SPF 裡做 Win32 GUI。  
2. 想做 dialog / listbox / popup menu / tray icon。  
3. 想研究 `WNDPROC:` + `DialogBoxIndirectParamA` 這類 GUI glue code。  
4. 想直接在 Forth 裡動態建立 dialog template。

**例子**：

- 做一個簡單視窗或 modal dialog。
- 做 tray icon / popup menu 小工具。
- 用 `enumwindows.f` 類工具列舉 top-level windows。

**實際 Forth 範例碼**：

```forth
... Window
```

```forth
... DialogModal
```

> 這一組 API 的實際參數通常偏長，使用時要一起看 `WINCONST.F` 的常數與 `WNDPROC:` / `CALLBACK:` 風格的 glue code。

### `win/winsock/`

**它是做什麼的？**  
提供從 raw socket API 到高階 line-based / UDP / DNS / IP helper 的完整 Winsock 工具鏈；而 `ws2/` 反映舊 `WSOCK32.DLL` 與較新版 `WS2_32.DLL` 的並行版本。

**你通常會在什麼情況用它？**

1. 想做 TCP / UDP client/server。  
2. 想做 DNS 查詢。  
3. 想拿到本機所有 IP。  
4. 想做 line-buffered socket I/O。  
5. 想看 SPF 生態怎麼包網路 API。

**例子**：

- `PSOCKET.F` 提供類 PHP 的 `fsockopen / fgets / fputs` 介面。
- `server_udp.f` / `listen_udp.f` 用於 UDP server。
- `dns_q.f` 可直接做 MX / domain 驗證。
- `foreach_ip.f` 可列出本機與外部 IP。

**實際 Forth 範例碼**：

```forth
SocketsStartup
CreateSocket
```

```forth
S" mail.example.com" 25 fsockopen
```

```forth
S" example.com" GetMXs
```

### `win/access/`

**它是做什麼的？**  
提供 Windows 帳號、SID、ACL、privilege、LSA logon、群組列舉等安全相關工具。

**你通常會在什麼情況用它？**

1. 想知道目前執行者是誰。  
2. 想調整 process ACL 或 token privilege。  
3. 想做 impersonation / logon。  
4. 想列舉群組與使用者。

**例子**：

- `whoami.f`：快速查目前 user。
- `NT_LOGON.F`：做 user logon / impersonation。
- `nt_access.f` / `nt_privelege.f`：調安全設定。

**實際 Forth 範例碼**：

```forth
whoami TYPE
```

```forth
S" user" S" password" LoginUser
```

### `win/odbc/`

**它是做什麼的？**  
ODBC / SQL 封裝，從基本 ODBC 連線一路到資料來源列舉與 XML 輸出。

**你通常會在什麼情況用它？**

1. 想從 SPF 直接連 ODBC 資料來源。  
2. 想列出資料來源或 tables。  
3. 想把查詢結果轉成 XML。  
4. 想維護舊 TEMPS 風格的 ODBC 代碼。

**例子**：

- 用 `ODBC.F` 建立基本 DB query flow。
- 用 `odbc2.f` 做 DSN / driver connect 工具。
- 用 `xmldb.f` 把 SQL query 結果直接吐成 XML。

**實際 Forth 範例碼**：

```forth
StartSQL
```

```forth
DumpDS
```

```forth
... SqlQueryXml
```

### `win/arc/gzip/zlib.f`

**它是做什麼的？**  
封裝 `zlib.dll`，提供壓縮、解壓、CRC32 與 gzip 輸出。

**你通常會在什麼情況用它？**

1. 想壓縮資料或做 gzip 輸出。  
2. 想算 CRC32。  
3. 想把 SPF 的輸出接到 gzip writer。

**例子**：

- 用 `zlib_compress` / `zlib_uncompress` 對資料做壓縮與解壓。
- 用 `gzip_write` 把資料流直接輸出成 gzip 格式。
- 對內容做 `CRC32` 校驗。 

**實際 Forth 範例碼**：

```forth
S" hello" zlib_compress
```

```forth
S" hello" CRC32 .
```

```forth
S" hello" gzip
```

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
| 比較像可直接重用的庫 | `LOCALS.F`, `TEMPS.F`, `REQUIRE.F`, `STR*.F`, `string/`, `win/` | 先看 API / 用法，再決定要不要直接 include |
| 比較像工具與除錯輔助 | `debug/`, `tools/`, `memory/` | 遇到特定需求時再翻，常有現成小工具 |
| 比較像範例 / 實驗 / 參考倉 | `transl/`, `list/`, `mbox/`, `ruvim/`, 部分 `util/` | 更適合找思路、命名與實作風格，不一定直接搬進主專案 |

若再細分一點，可加上幾個「歷史軌跡」線索：

- `STR.F` → `STR2.F` / `STR3.F` / `str4.f`：反映字串模板系統與 locals 機制的演進
- `REGISTRY.F` → `registry2.f`：反映 `TEMPS.F` 風格往 `LOCALS.F` 風格的遷移
- `win/winsock/` 與 `win/winsock/ws2/` 兩套並行：反映 WinSock 舊版與較新版 API 的並存
- `win/com/samples/`：顯示 `ac-lib3/` 不只是一組 API wrapper，也包含大量「如何真的拿這些 wrapper 做事」的範例

#### 一句話分類法

- **Foundational**：`LOCALS.F`、`REQUIRE.F`、`STR2.F`、`string/`、`win/winver.f`
- **直接可用的應用庫**：`win/registry2.f`、`win/ini.f`、`win/winsock/`、`win/com/`
- **工具 / 除錯**：`debug/TRACE.F`、`tools/`、`memory/`
- **歷史 / 範例 / Eserv2 脈絡**：`STR.F`、`REGISTRY.F`、`mbox/`、`res_ctrl.f`、`win/com/samples/`

---

## 6.1 依賴關係速記

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
- 社群累積的 reusable solution set

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

本章的目的不是把 `ac-lib3/` 的每個檔案都拆開逐行追，而是先給你一張足夠實用的「地圖」。真正要深入某個檔案時，再沿著這張地圖找進去，會比直接從目錄樹盲翻有效得多。
