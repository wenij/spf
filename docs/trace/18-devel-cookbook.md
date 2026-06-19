# SP-Forth/4 原始碼追蹤 — `devel/` 使用索引與查找範例

> 定位：本章是 [18-devel.md](18-devel.md) 的配套使用索引。
> 主章說明 `devel/` 的角色與整體地圖；本章則回答「遇到某種需求時，該先看哪棵作者子樹、哪些檔案、怎麼查」。

---

## 1. 使用前先確認的事

`devel/` 是作者工作區集合，不是單一整理好的套件。因此查找或載入檔案前，先確認幾個前提：

| 檢查點 | 原因 |
|--------|------|
| 作者路徑是否可解析 | 很多檔案用 `~ac/...`、`~pinka/...`、`~yz/...` 互相引用 |
| 依賴是否在同一作者樹 | 有些檔案依賴作者自己的 `lib/`、`spf/` 或 `prog/` |
| 是否偏 Windows | `~yz/`、`~micro/`、`~day/`、部分 `~ac/` 內容會直接碰 Win32 API |
| 是否只是草稿或原型 | `rationale/`、`samples/`、個人實驗目錄不一定可直接執行 |

最穩的讀法是：先看檔頭註解、`REQUIRE` 列表、同目錄 README / history / sample，再判斷它是「可重用工具」、「完整應用」、「原型」還是「歷史筆記」。

---

## 2. 快速查找方法

`devel/` 不是單一路徑樹，而是多位作者的工作區集合。實際查找時，用「作者子樹 + 關鍵字」比從根目錄一路翻有效。

找依賴 `~ac/lib` 的歷史程式：

```sh
rg -n "REQUIRE .*~ac/lib" devel
```

追 Windows 資源建構工具：

```sh
rg -n "fres|FRES|resources" devel/~yz src/win/res
```

找 SPF 例外處理與 dump 相關實驗：

```sh
rg -n "THROW|exception|dump" devel/~pinka/spf
```

看完整應用專案的檔案佈局：

```sh
find devel/~micro -maxdepth 2 -type f | sort
```

判讀結果時，可以先問三個問題：

1. 這個檔案是在 `lib/`、`spf/`、`prog/` 還是 `samples/`？
2. 它是否被 `src/`、`ac-lib3/` 或其它作者樹引用？
3. 它是可重用工具、完整應用、原型，還是歷史筆記？

---

## 3. 作者子樹使用索引

### `devel/~ac/`

用途：追 `ac-lib3/` 的源流，以及讀 Andrey Cherezov 對 SPF 設計的草稿。

代表內容：

- `devel/~ac/lib/LOCALS.F`
- `devel/~ac/lib/REQUIRE.F`
- `devel/~ac/lib/STR*.F`
- `devel/~ac/lib/TEMPS.F`
- `devel/~ac/lib/string/`
- `devel/~ac/lib/win/`
- `devel/~ac/rationale/SPF4.F`
- `devel/~ac/rationale/spf4_parser.f`
- `devel/~ac/rationale/spf4_eval.f`

典型查法：

```sh
find devel/~ac/lib -maxdepth 2 -type f | sort
```

```sh
diff -u ac-lib3/STR2.F devel/~ac/lib/STR2.F
```

適合情境：

- 想確認 `ac-lib3/` 某個檔案是否來自作者工作版。
- 想比較 `ac-lib3/` 整理版與 `devel/~ac/lib/` 工作版的命名、結構或依賴差異。
- 想理解 SPF 4 parser / translator 的歷史設計背景。

### `devel/~pinka/`

用途：研究 SPF 核心補強、例外處理、compiler、wordlist、storage、FFI 等深層實驗。

代表內容：

- `devel/~pinka/spf/debug-throw.f`
- `devel/~pinka/spf/exc-dump.f`
- `devel/~pinka/spf/fix-accept.f`
- `devel/~pinka/spf/fix-refill.f`
- `devel/~pinka/spf/quoted-word.f`
- `devel/~pinka/spf/storage*.f`
- `devel/~pinka/spf/ffi/`
- `devel/~pinka/spf/compiler/`

典型查法：

```sh
rg -n "THROW|CATCH|dump|exception" devel/~pinka/spf
```

```sh
find devel/~pinka/spf/compiler -type f | sort
```

適合情境：

- 想追 `THROW` / exception dump 的替代做法。
- 想找 `fix-accept`、`fix-refill` 類問題的修補原型。
- 想研究 compiler / wordlist / storage 的非正式擴充。

### `devel/~yz/`

用途：追目前 Windows 資源建構流程實際碰到的工具，也可找 Win32 / automation / db 類輔助函式庫。

代表內容：

- `devel/~yz/prog/fres/fres.f`
- `devel/~yz/lib/resources.f`
- `devel/~yz/lib/UUID.F`
- `devel/~yz/lib/winlib.f`
- `devel/~yz/lib/automation.f`

典型查法：

```sh
rg -n "fres|FRES|resources" devel/~yz src/win/res
```

```sh
find devel/~yz/lib -maxdepth 2 -type f | sort
```

適合情境：

- 想知道 `spf.res` 到 `spf.FRES` 是怎麼轉換的。
- 想確認 [`src/win/res/res.bat`](../../src/win/res/res.bat) 使用的 `fres.f` 來源。
- 想找另一套 Win32 / automation / resources 輔助工具。

### `devel/~day/`

用途：研究大型框架、OOP、GUI/application framework 與完整子系統。

代表內容：

- `devel/~day/joop/oop.f`
- `devel/~day/joop/win/`
- `devel/~day/wfl/wfl.f`
- `devel/~day/wfl/examples/`
- `devel/~day/hype3/`
- `devel/~day/fsim/`

典型查法：

```sh
find devel/~day/joop -maxdepth 2 -type f | sort
```

```sh
find devel/~day/wfl -maxdepth 3 -type f | sort
```

適合情境：

- 想看 SPF 裡如何做 OOP / 類別系統。
- 想看 GUI / application framework 類設計如何在 SPF 裡長出來。
- 想找比單一函式庫更完整的應用骨架。

### `devel/~mak/`

用途：研究 compiler、assembler、optimizer、語言前端/後端實驗。

代表內容：

- `devel/~mak/FOROPT.F`
- `devel/~mak/CFASM/CPU80486.4TH`
- `devel/~mak/WAPI.F`
- `devel/~mak/FBasComp/`
- `devel/~mak/WIN32FOR/`

典型查法：

```sh
find devel/~mak/CFASM -type f | sort
```

```sh
rg -n "locals|optimizer|assembler|compiler" devel/~mak
```

適合情境：

- 想看 80486 assembler / disassembler 實驗。
- 想找 optimizer 的平行思路。
- 想看 Forth-based compiler 或 Win32FOR 類前端實驗。

### `devel/~ygrek/`

用途：找中型通用函式庫、SPF 外圍補強、應用與工具程式。

代表內容：

- `devel/~ygrek/lib/xmlsafe.f`
- `devel/~ygrek/lib/fsm.f`
- `devel/~ygrek/lib/enum.f`
- `devel/~ygrek/lib/net/`
- `devel/~ygrek/spf/autoc.f`
- `devel/~ygrek/prog/`

典型查法：

```sh
find devel/~ygrek/lib -maxdepth 2 -type f | sort
```

```sh
find devel/~ygrek/spf -type f | sort
```

適合情境：

- 想找 XML、FSM、bit、net、parse 類中型工具。
- 想看 SPF 本體外圍的自動補完 / included / 測試補強。
- 想看「library + project」混合風格的作者工作樹。

### `devel/~micro/`

用途：看 SPF 被拿來做完整應用，而不只是小型函式庫。

代表內容：

- `devel/~micro/SHEDULER/`
- `devel/~micro/DELETER/`
- `devel/~micro/calendar/`
- `devel/~micro/wwwlib/`
- `devel/~micro/filetrunc/`

典型查法：

```sh
find devel/~micro -maxdepth 2 -type f | sort
```

```sh
find devel/~micro/SHEDULER -maxdepth 2 -type f | sort
```

適合情境：

- 想看包含 `MAKE.F`、設定檔、文件、發佈目錄的完整工具程式。
- 想研究 scheduler / reminder / file utility 類應用。
- 想理解 SPF 在 WWW / scheduler / file utility 類領域的應用範圍。

### `devel/~nn/`

用途：比較另一套個人 library / class 組織方式，對照 `ac-lib3/` 的風格。

代表內容：

- `devel/~nn/class/`
- `devel/~nn/lib/base64.f`
- `devel/~nn/lib/unicode.f`
- `devel/~nn/lib/script.f`
- `devel/~nn/lib/web/`
- `devel/~nn/lib/win/`

典型查法：

```sh
find devel/~nn/lib -maxdepth 2 -type f | sort
```

```sh
find devel/~nn/class -type f | sort
```

適合情境：

- 想比較不同作者如何做 base64 / unicode / file / web 工具。
- 想看另一套 class / library 組織方式。
- 想找偏個人函式庫倉，而非單一專案的樣本。

---

## 4. 代表 library 的完整 Forth 範例

下面挑幾個比較有代表性、也適合寫成短範例的作者 library。這些範例假設你在 repo 根目錄附近啟動 SPF，且 `devel/` 可被 module / library path 看見。若你的環境無法解析 `~ac/lib/...` 這類作者路徑，就要先調整 library path，或改用實體路徑手動載入依賴。

建議每個範例在乾淨 session 單獨測試；有些檔案會定義較短的通用 word，混在同一個 session 裡容易撞名。

本節範例選擇原則如下：

| 範例 | 作者樹 | 示範面向 | 適合先讀的人 |
|------|--------|----------|--------------|
| A | `~ac` | 字串模板 | 想追 `ac-lib3` 源流 |
| B | `~nn` | base64 轉換 | 想看獨立小工具 |
| C | `~ygrek` | enum DSL | 想看 immediate word 用法 |
| D | `~ygrek` | FSM DSL | 想看小型語言設計 |
| E | `~pinka` | intrusive linked list | 想看底層資料結構 |
| F | `~nn` | 數字與字串互轉 | 想找日常工具 word |
| G | `~nn` | 分數運算 | 想看完整資料型別設計 |
| H | `~nn` | 動態 linked list | 想看配置/釋放生命週期 |
| I | `~ygrek` | GCD 與模反元素 | 想看演算法小庫 |
| J | `~ygrek` | bitset 操作 | 想看位元陣列工具 |
| K | `~ygrek` | XML/HTML escape | 想看輸出安全處理 |

### 範例 A：`~ac/lib/str2.f` 字串模板

作者樹：`devel/~ac/`
代表性：這是 `ac-lib3/STR2.F` 的母樹版本，展示 `devel/~ac/lib/` 和 `ac-lib3/` 的源流關係。

```forth
\ demo-ac-str2.f
\ 產生一段帶變數插值的 HTTP header/body 片段。

REQUIRE " ~ac/lib/str2.f

: REQ-HOST   S" example.com" ;
: REQ-PATH   S" /index.html" ;
: REQ-AGENT  S" spf-demo" ;

: DEMO-REQUEST
  " GET {REQ-PATH} HTTP/1.0{CRLF}Host: {REQ-HOST}{CRLF}User-Agent: {REQ-AGENT}{CRLF}{CRLF}"
  STYPE
;

DEMO-REQUEST
```

重點：

- `REQUIRE " ~ac/lib/str2.f` 會載入字串模板 word `"`。
- `{REQ-PATH}` / `{REQ-HOST}` / `{REQ-AGENT}` 會在模板展開時執行對應 word。
- `STYPE` 輸出字串後會釋放該字串。

### 範例 B：`~nn/lib/base64.f` base64 encode/decode

作者樹：`devel/~nn/`
代表性：`~nn/lib/` 是另一套個人 library 倉，適合拿來和 `ac-lib3/string/CONV.F` 對照。

```forth
\ demo-nn-base64.f
\ 把字串編成 base64，再解回原文。

S" devel/~nn/lib/base64.f" INCLUDED

CREATE b64-buf   256 ALLOT
CREATE plain-buf 256 ALLOT

: DEMO-BASE64
  S" Hello SP-Forth" b64-buf base64
  2DUP TYPE CR
  plain-buf debase64 TYPE CR
;

DEMO-BASE64
```

預期輸出概念：

```text
SGVsbG8gU1AtRm9ydGg=
Hello SP-Forth
```

重點：

- `base64 ( addr u dest -- addr1 u1 )` 需要呼叫端提供輸出 buffer。
- `debase64 ( addr u dest -- addr1 u1 )` 同樣需要目的 buffer。
- 這個檔案相對獨立，適合當 `devel/~nn/lib/` 的第一個閱讀入口。

### 範例 C：`~ygrek/lib/enum.f` 批次定義常數

作者樹：`devel/~ygrek/`
代表性：`~ygrek/lib/` 有不少小型語法工具，`enum.f` 展示了如何把「重複定義一批 word」包成小 DSL。

```forth
\ demo-ygrek-enum.f
\ 從 200 開始連續建立三個 HTTP status code 常數。

S" devel/~ygrek/lib/enum.f" INCLUDED

:NONAME DUP CONSTANT 1 + ; ENUM 1+CONSTS

200 1+CONSTS HTTP-OK HTTP-CREATED HTTP-ACCEPTED ; DROP

: DEMO-ENUM
  HTTP-OK . HTTP-CREATED . HTTP-ACCEPTED . CR
;

DEMO-ENUM
```

預期輸出概念：

```text
200 201 202
```

重點：

- `ENUM` 建立一個會讀取後續名稱直到 `;` 的 immediate word。
- `:NONAME DUP CONSTANT 1 + ;` 是每讀到一個名稱時要執行的動作。
- `DROP` 用來丟掉最後遞增後留下的值。

### 範例 D：`~ygrek/lib/fsm.f` 小型有限狀態機

作者樹：`devel/~ygrek/`
代表性：`fsm.f` 是很小的 Finite State Machine DSL，適合看作者如何用 Forth 建小語言。

```forth
\ demo-ygrek-fsm.f
\ 依輸入欄位 0/1 分別執行不同 action。

S" devel/~ygrek/lib/fsm.f" INCLUDED

: SAY-LOW   ." low " ;
: SAY-HIGH  ." high " ;

2 FSM: LEVEL-FSM
\ column 0      column 1
|| SAY-LOW 0    || SAY-HIGH 0
FSM;

: DEMO-FSM
  0 LEVEL-FSM
  1 LEVEL-FSM
  CR
;

DEMO-FSM
```

預期輸出概念：

```text
low high
```

重點：

- `2 FSM: LEVEL-FSM` 表示這個 FSM 有兩個 input column。
- `|| action next-state` 定義目前 state 下某個 column 的 action 與下一個 state。
- 這個範例只有 state 0，所以兩個 transition 都回到 0。

### 範例 E：`~pinka/lib/list.f` 單向鏈結串列

作者樹：`devel/~pinka/`
代表性：`~pinka` 常偏核心修補與底層工具；`lib/list.f` 是少數適合用短範例展示的通用小庫。

```forth
\ demo-pinka-list.f
\ 建立三個節點，放進 linked list，再逐一印出節點 payload。

S" devel/~pinka/lib/list.f" INCLUDED

VARIABLE demo-list
0 demo-list !

HERE 0 , 10 , demo-list list+
HERE 0 , 20 , demo-list list+
HERE 0 , 30 , demo-list list+

: .NODE ( node -- )
  CELL+ @ .
;

: DEMO-LIST
  ['] .NODE demo-list List-ForEach
  CR
;

DEMO-LIST
```

預期輸出概念：

```text
30 20 10
```

重點：

- 每個 node 的第一個 cell 是 link，後面才是 payload。
- `list+` 會把新 node 插到 list 前端，所以輸出順序會反過來。
- `List-ForEach` 的 xt 會收到 node address，而不是 payload address。

### 範例 F：`~nn/lib/num2s.f` 與 `~nn/lib/s2num.f` 數字轉換

作者樹：`devel/~nn/`
代表性：`~nn/lib/` 裡有不少日常工具，這組檔案展示「小而明確」的轉換 word。

```forth
\ demo-nn-number-conv.f
\ 在十進位、十六進位字串與數字之間轉換。

S" devel/~nn/lib/num2s.f" INCLUDED
S" devel/~nn/lib/s2num.f" INCLUDED

: DEMO-NUMBER-CONV
  255 N>S TYPE CR
  255 N>H TYPE CR
  S" 0xFF" S>NUM . CR
  S" -42" S>NUM . CR
;

DEMO-NUMBER-CONV
```

預期輸出概念：

```text
255
FF
255
-42
```

重點：

- `N>S ( u -- addr u )` 依目前數字基底輸出字串。
- `NB>S ( n base -- addr u )` 會暫時切換 `BASE`，再恢復原本基底。
- `S>NUM` 支援一般十進位，也支援 `0x` 前綴的十六進位。

### 範例 G：`~nn/lib/fraction.f` 分數運算

作者樹：`devel/~nn/`
代表性：這個檔案把分數當成一組 stack value 來操作，適合看 SPF 裡如何用兩個 cell 表示一個複合值。

```forth
\ demo-nn-fraction.f
\ 用 numerator/denominator pair 做分數加減乘除。

S" devel/~nn/lib/fraction.f" INCLUDED

: DEMO-FRACTION
  1 2  1 3 FR+ FR/. CR
  3 4  2 3 FR* FR/. CR
  1 8  1 4 FR+ FR. CR
;

DEMO-FRACTION
```

預期輸出概念：

```text
5/6
1/2
0.375
```

重點：

- 分數在 stack 上以 `a b` 表示 `a/b`。
- `FR+`、`FR*` 會先 normalize，再回傳新的 `a/b`。
- `FR/.` 以分數格式輸出，`FR.` 以小數格式輸出。

### 範例 H：`~nn/lib/list.f` 動態 linked list

作者樹：`devel/~nn/`
代表性：和 `~pinka/lib/list.f` 不同，這個 list 會由 library 幫你配置 node，適合展示配置、走訪、查找與釋放的完整生命週期。

```forth
\ demo-nn-list.f
\ 建立動態 list，走訪、刪除，再釋放全部節點。

S" devel/~nn/lib/list.f" INCLUDED

VARIABLE nn-list
0 nn-list !

: .NN-NODE ( node -- )
  NodeValue .
;

: DEMO-NN-LIST
  10 nn-list AddNode
  20 nn-list AddNode
  30 nn-list AddNode

  ['] .NN-NODE nn-list DoList CR

  20 nn-list DelNode
  20 nn-list InList? 0= . CR

  nn-list FreeList
;

DEMO-NN-LIST
```

預期輸出概念：

```text
30 20 10
-1
```

重點：

- `AddNode ( value list -- )` 會配置一個兩 cell node。
- `NodeValue ( node -- value )` 取出 node 的 payload。
- `FreeList` 會釋放所有由 `AddNode` 建立的 node，範例結束前要呼叫。

### 範例 I：`~ygrek/lib/math/gcd.f` GCD 與模反元素

作者樹：`devel/~ygrek/`
代表性：`~ygrek/lib/math/` 是演算法小庫的入口之一，這個檔案同時示範一般工具 word 與帶條件檢查的數學函式。

```forth
\ demo-ygrek-gcd.f
\ 計算最大公因數與 modular inverse。

S" devel/~ygrek/lib/math/gcd.f" INCLUDED

: DEMO-GCD
  1000000 200 GCD . CR
  152 1089 InvertNumber . CR
  3 5 InvertNumber . CR
;

DEMO-GCD
```

預期輸出概念：

```text
200
566
2
```

重點：

- `GCD ( x y -- z )` 會先檢查兩個輸入都大於 0。
- `InvertNumber ( a m -- x )` 回傳 `a*x = 1 (mod m)` 的 `x`。
- 如果 `a` 與 `m` 不是互質，`InvertNumber` 會透過 `ENSURE` 丟出錯誤。

### 範例 J：`~ygrek/lib/bit.f` bitset 操作

作者樹：`devel/~ygrek/`
代表性：這個檔案展示以 byte buffer 當 bit array 使用的工具，常見於壓縮、編碼、crypto 或 protocol 類程式。

```forth
\ demo-ygrek-bit.f
\ 在 byte buffer 裡設定、讀取與列印 bit。

S" devel/~ygrek/lib/bit.f" INCLUDED

CREATE demo-bits 2 ALLOT

: CLEAR-DEMO-BITS
  demo-bits 2 ERASE
;

: DEMO-BITS
  CLEAR-DEMO-BITS

  0 demo-bits :1
  2 demo-bits :1
  9 demo-bits :1

  demo-bits 10 BITS. CR

  0 2 demo-bits BIT!

  0 demo-bits BIT@ .
  2 demo-bits BIT@ .
  9 demo-bits BIT@ . CR
;

DEMO-BITS
```

預期輸出概念：

```text
10100000 01
1 0 1
```

重點：

- `:1 ( n a -- )` 設定第 `n` 個 bit。
- `BIT! ( 0|1 n a -- )` 可用布林值設定或清除 bit。
- `BITS. ( addr bits -- )` 會依 bit 編號順序列印，不是依 byte 的十六進位表示列印。

### 範例 K：`~ygrek/lib/xmlsafe.f` XML/HTML escape

作者樹：`devel/~ygrek/`
代表性：這是輸出安全處理的小型 module；它不改變原字串，而是提供安全版 `TYPE` / `EMIT` / `STYPE`。

```forth
\ demo-ygrek-xmlsafe.f
\ 將特殊字元輸出成 XML/HTML-safe entity。

S" devel/~ygrek/lib/xmlsafe.f" INCLUDED

: DEMO-XMLSAFE
  S" A&B <tag> " XMLSAFE::TYPE
  [CHAR] " XMLSAFE::EMIT
  S" quoted" XMLSAFE::TYPE
  [CHAR] " XMLSAFE::EMIT
  XMLSAFE::CR
;

DEMO-XMLSAFE
```

預期輸出概念：

```text
A&amp;B &lt;tag&gt; &quot;quoted&quot;<br />
```

重點：

- `XMLSAFE::TYPE` 逐字呼叫 `XMLSAFE::EMIT`，把 `<`、`>`、`&`、`"`、`'` 等字元轉成 entity。
- `XMLSAFE::STYPE` 可接 `~ac/lib/str*.f` 產生的動態 string，輸出後一併釋放。
- `XMLSAFE::CR` 不是輸出換行字元，而是輸出 `<br />`。

不建議一開始就用 `~pinka/spf/` 做 cookbook 範例；那一區更接近核心修補與替代實作，適合閱讀、對照與研究，而不是直接複製進一般應用。

---

## 5. 需求導向索引

| 需求 | 先看 |
|------|------|
| 追 `ac-lib3` 模組源頭 | `devel/~ac/lib/` |
| 追 SPF parser / translator 設計草稿 | `devel/~ac/rationale/` |
| 研究 exception / dump / throw | `devel/~pinka/spf/debug-throw.f`、`exc-dump.f` |
| 找 compiler / wordlist / storage 實驗 | `devel/~pinka/spf/`、`devel/~mak/` |
| 查 Windows 資源建構工具 | `devel/~yz/prog/fres/` |
| 看 OOP / framework | `devel/~day/joop/`、`devel/~day/wfl/` |
| 看完整應用程式 | `devel/~micro/` |
| 找另一套 library 風格 | `devel/~nn/lib/`、`devel/~yz/lib/`、`devel/~ygrek/lib/` |
| 做數字與字串轉換 | `devel/~nn/lib/num2s.f`、`devel/~nn/lib/s2num.f` |
| 做分數或有理數運算 | `devel/~nn/lib/fraction.f` |
| 找 linked list 實作差異 | `devel/~pinka/lib/list.f`、`devel/~nn/lib/list.f` |
| 做 GCD / modular inverse | `devel/~ygrek/lib/math/gcd.f` |
| 操作 bit array / bitset | `devel/~ygrek/lib/bit.f` |
| 輸出 XML/HTML-safe 文字 | `devel/~ygrek/lib/xmlsafe.f` |

---

## 6. 延伸函式庫使用對照：`lib/` vs `ac-lib3/` vs `devel/`

`SP-Forth` 的延伸函式庫分散在三個位置：`lib/`、`ac-lib3/`、`devel/`。這節提供「我看到某個需求時，要先翻哪個資料夾」的決策對照，補齊 [16-lib.md](16-lib.md)、[17-ac-lib3.md](17-ac-lib3.md) 與 [18-devel.md](18-devel.md) 三章的橫向入口。

### 6.1 三者定位一覽

| 面向 | `lib/` | `ac-lib3/` | `devel/` |
|------|--------|------------|----------|
| 角色 | 核心補齊層 | 歷史 / 大型延伸庫 | 作者工作區與歷史原型 |
| 收錄方式 | `spf4e` 預設載入 | 手動 `INCLUDE` | 視需要載入 |
| 命名風格 | 統一（`lib/include/`、`lib/ext/`） | 多元（`~ac`、`~pinka` 風格並存） | 各作者獨立風格 |
| 依賴 | `REQUIRE` 鏈，無外部 | 常用 `~ac/lib/...` 路徑 | 作者自己的子樹依賴 |
| 維護狀態 | 與 `spf4e` 同進退 | 整理過但偏歷史 | 不定期更新，無保證 |
| 直接用於專案 | ✅ | ✅（注意依賴） | ⚠️ 需先讀懂 |
| 學習 SPF 設計 | 中 | 中-高 | 高 |
| 完整章節 | [16-lib.md](16-lib.md) | [17-ac-lib3.md](17-ac-lib3.md) | [18-devel.md](18-devel.md) |

### 6.2 載入策略對照

| 場景 | 選哪邊 | 怎麼載 |
|------|--------|--------|
| 商業 / 工具 / 想一次補齊 | `lib/` | `spf4e` 啟動即用；或在 `spf4` 上 `S" lib/ext/spf4e.f" INCLUDED` |
| 模板字串、REGISTRY、BSTR、COM | `ac-lib3/` | `S" ac-lib3/STR2.F" INCLUDED` 之類 |
| 大量字串 / 編碼 / regex / MIME | `ac-lib3/string/` | `S" ac-lib3/string/CONV.F" INCLUDED` |
| Windows GUI / COM / ODBC / Winsock | `ac-lib3/win/` | 看 [17-ac-lib3-cookbook.md](17-ac-lib3-cookbook.md) §5 |
| 找另一位作者的特定實驗 | `devel/` | `S" devel/~ygrek/lib/bit.f" INCLUDED`；可能要先解析作者路徑 |
| 研究 SPF 4 parser 草稿 | `devel/~ac/rationale/` | 直接讀；不一定可載入 |

### 6.3 需求決策矩陣

下面用 `lib/` / `ac-lib3/` / `devel/` 三欄表示「這需求在哪個來源已有現成 library」。空欄表示該來源沒有對應的標準解。

| 需求 | `lib/` | `ac-lib3/` | `devel/` |
|------|:------:|:----------:|:--------:|
| 字串模板插值 |  | ✅ `STR2.F` |  |
| 動態字串（manual lifetime） |  | ✅ `STR2.F` / `str4.f` |  |
| 大小寫不敏感搜尋 | ✅ `caseins.f` |  |  |
| 反組譯 `SEE` | ✅ `disasm.f` |  |  |
| 結構定義（field offset） | ✅ `struct.f` |  |  |
| 詞彙表 / dictionary 操作 | ✅ `vocs.f` |  |  |
| quotation `[: ... ;]` | ✅ `quotations.f` |  |  |
| locals `{ ... }` | ✅ `lib/ext/locals.f` | ✅ `LOCALS.F` |  |
| `CASE` / `OF` / `ENDOF` | ✅ `control-case.f` |  |  |
| 浮點數 | ✅ `float2.f` |  |  |
| 分數運算 |  |  | ✅ `~nn/lib/fraction.f` |
| 鏈結串列 |  | ✅ `list/STR_LIST.F` | ✅ `~nn/lib/list.f` / `~pinka/lib/list.f` |
| bitset / 位元陣列 |  |  | ✅ `~ygrek/lib/bit.f` |
| base64 / URL encode |  | ✅ `string/CONV.F` | ✅ `~nn/lib/base64.f` |
| regex (PCRE) |  | ✅ `string/regexp.f` |  |
| Windows registry |  | ✅ `win/registry2.f` |  |
| Windows INI |  | ✅ `win/ini.f` |  |
| Windows service |  | ✅ `win/service/` |  |
| Windows COM / OLE |  | ✅ `win/com/` |  |
| Winsock / DNS |  | ✅ `win/winsock/` |  |
| ODBC / SQL |  | ✅ `win/odbc/` |  |
| Mutex / 同步 | ✅ `lib/win/mutex.f` | ✅ `win/process/` |  |
| heap 列舉 / 除錯 |  | ✅ `memory/heap_enum.f` | ✅ `~pinka/spf/exc-dump.f` |
| trace / hot patch |  | ✅ `debug/TRACE.F`、`tools/jmp.f` |  |
| XML/HTML escape |  |  | ✅ `~ygrek/lib/xmlsafe.f` |
| FSM DSL |  |  | ✅ `~ygrek/lib/fsm.f` |
| ENUM 批次常數 |  |  | ✅ `~ygrek/lib/enum.f` |
| OOP / framework |  |  | ✅ `~day/joop/`、`~day/wfl/` |
| 完整應用範例 |  |  | ✅ `~micro/SHEDULER` 等 |

### 6.4 混用時的注意事項

1. **命名衝突**：`lib/ext/locals.f` 用 `{ ... }`，`ac-lib3/LOCALS.F` 也用 `{ ... }`；兩者 frame 模型不同，**不要在同一 session 同時 include**。一般選一個貫穿整個專案。
2. **frame 模型不相容**：`lib/include/quotations.f` 的 `[: ... ;]` 與 `lib/ext/locals.f` 的 `{ ... }` 底層 frame 衝突；混用時編譯失敗或行為未定義。
3. **作者路徑解析**：`ac-lib3/STR2.F` 等檔案會用 `REQUIRE xxx ~ac/lib/...` 載入依賴；你的 SPF 環境必須能解析 `~ac/lib` 對應到 `devel/~ac/lib/`，或自己改成實體路徑。
4. **重複 include**：`REQUIRE` 機制會避免重複，但跨三個來源（`lib/`、`ac-lib3/`、`devel/`）有時會出現「同個 word 兩邊各定義一次」的情況，先 include 哪邊決定後續是哪個。
5. **spf4 vs spf4e**：`lib/` 主要設計給 `spf4e`；在純 `spf4` 環境下用 `lib/ext/caseins.f` 之類檔案不會出問題，但 `lib/include/ansi.f` 預設依賴 `spf4e` 才有的 `WINAPI:` 之類偵測。
6. **文件語言**：三個來源都沒有統一 doc，`devel/` 部分檔頭的註解偏俄文（與英文混雜）；trace 這幾章是目前最新的中文入口。
7. **build 路徑**：要把 `ac-lib3/` 的東西包進 standalone executable，記得 source basepath 能被解析（見 [15-standalone-cookbook.md](15-standalone-cookbook.md) §5）。

### 6.5 推薦閱讀順序

1. **第一次接觸**：先讀 [16-lib.md](16-lib.md) §1-§3 與 §10，理解 `spf4e` 自帶什麼；需要直接照抄 runnable examples 時接著看 [16-lib-cookbook.md](16-lib-cookbook.md)。
2. **寫應用**：缺什麼時優先在 [17-ac-lib3-cookbook.md](17-ac-lib3-cookbook.md) 找對應 entry（registry、socket、COM、ODBC 等）；找不到再回頭看 [16-lib.md](16-lib.md) §5-§7 與 [16-lib-cookbook.md](16-lib-cookbook.md) 找 `lib/ext/` 或 `lib/posix/`、`lib/win/` 的替代方案。
3. **研究底層 / 找靈感**：看本章 §3-§4 找作者子樹的代表 library 範例；想了解設計背景時看 [18-devel.md](18-devel.md) §1-§4。
4. **碰到 bug**：先看本章 §1「使用前先確認的事」對應的 `~pinka/spf/debug-throw.f`、`exc-dump.f` 與 `ac-lib3/debug/TRACE.F` 提供的 trace 工具。

### 6.6 怎麼判斷「這段程式碼應該放哪裡」

寫自己的專案時，把新工具放哪裡也是個選擇：

| 特性 | 放 `lib/ext/` 旁 | 放 `ac-lib3/` | 放 `devel/~xxx/` |
|------|:----------------:|:--------------:|:----------------:|
| 進核心 spf4e 發布 | ✅ |  |  |
| 給多個 ac-lib3 模組用 |  | ✅ |  |
| 個人實驗 / prototype |  |  | ✅ |
| 需要長期 maintain 與文件 | 高 | 中 | 低 |

實務建議：

- 想貢獻回主倉庫：先放 `ac-lib3/`，證明穩定後再提議合併入 `lib/`。
- 個人或公司內部工具：放自己的 `devel/~myhandle/`，不要污染主倉庫。
- 只是要 spf4e 多載一兩個 word：寫在自己的 `myapp.f` 裡，`S" myapp.f" INCLUDED` 後 `SAVE` 即可（見 [15-standalone-cookbook.md](15-standalone-cookbook.md)）。

---

## 7. 讀完後回到哪裡？

- 想理解 `devel/` 的定位與整體地圖，回 [18-devel.md](18-devel.md)。
- 想看整理過、比較可直接使用的延伸函式庫，讀 [17-ac-lib3.md](17-ac-lib3.md) 與 [17-ac-lib3-cookbook.md](17-ac-lib3-cookbook.md)。
- 想追 SPF 本體的載入策略，回 [05-io-error-init.md](05-io-error-init.md)。
- 想追 Windows 資源建構流程，回 [06-build-save.md](06-build-save.md)。
