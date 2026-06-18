# SP-Forth/4 原始碼追蹤 — `devel/` 開發者工作區導覽

> 定位：如果 `src/` 是 SPF 本體、`ac-lib3/` 是可重用的延伸函式庫區，那 `devel/` 更像是 **作者群與社群成員的開發工作區、歷史資產倉與原型實驗場**。
>
> 這一章的目標不是逐檔追完 `devel/`，而是回答三個問題：
> 1. `devel/` 為什麼存在？
> 2. 哪些子樹真的值得看？
> 3. 它和 `src/`、`ac-lib3/` 的關係是什麼？

---

## 1. `devel/` 是什麼？

`devel/` 不是 SPF 主系統建構樹，也不是像 `ac-lib3/` 那樣相對成形的「可直接重用函式庫集合」。它更接近：

- 多位作者各自維護的工作區
- 歷史原型與實驗實作集合
- 一部分後來被吸收到 `ac-lib3/` 或主系統的素材來源
- 一部分只在作者本人專案中有用的工具與應用程式

從 top-level 結構看，它以 `~user` 形式分成多個作者子樹：

```forth
devel/
├── ~ac/
├── ~af/
├── ~clf/
├── ~day/
├── ~diver/
├── ~ilya/
├── ~isp/
├── ~mak/
├── ~micro/
├── ~mlg/
├── ~moleg/
├── ~nn/
├── ~pi/
├── ~pig/
├── ~pinka/
├── ~profit/
├── ~spn/
├── ~ss/
├── ~vsp/
├── ~ygrek/
└── ~yz/
```

換句話說，`devel/` 並不是「一個 library」，而是：

> **SP-Forth 社群多年來留下的作者工作樹總集。**

---

## 2. 為什麼它重要？

雖然 `devel/` 不是 `spf.f` 主載入樹的一部分，但它**不是完全與主系統無關**。至少有幾個明確接點：

1. [`src/spf_module.f:49`](file:///Users/wenij/work/forth/spf/src/spf_module.f#L49) 會把 `devel/` 拼進模組搜尋路徑。這代表 `devel/` 在 SPF 世界裡不是純粹的「封存區」，而是實際可被模組載入機制看見的 library root。
2. [`src/win/res/res.bat:6`](file:///Users/wenij/work/forth/spf/src/win/res/res.bat#L6) 會使用 [`devel/~yz/prog/fres/fres.f`](file:///Users/wenij/work/forth/spf/devel/~yz/prog/fres/fres.f)。這表示 Windows 資源建構流程真的依賴 `devel/` 裡的工具。
3. [`src/macroopt-hide.f:43`](file:///Users/wenij/work/forth/spf/src/macroopt-hide.f#L43) 與 [`:56`](file:///Users/wenij/work/forth/spf/src/macroopt-hide.f#L56) 還留有 `~pinka/spf/compiler/...` 的來源註記，顯示 `devel/~pinka/` 與 compiler/optimizer 演進有歷史關聯。

因此，`devel/` 對讀者的價值通常不在「建構 SPF 本體時一定要讀」，而在於：

- 想找某個功能最早從哪裡長出來
- 想找社群裡已做過的原型或工具
- 想理解某個 helper（如 `fres.f`）或某套 library 的來源脈絡

---

## 3. 整體地圖：哪些作者子樹最值得先看？

從檔案數量與內容密度看，下面幾個子樹最值得優先認識：

| 子樹 | 約略檔案數 | 性質 | 為什麼值得先看 |
|------|-----------|------|----------------|
| `~pinka/` | ~547 | SPF 核心補強 / compiler / debug / storage / throw / FFI | 最大、與 SPF 本體最接近的深水區之一 |
| `~ac/` | ~343 | `ac-lib3` 的母樹、rationale、作者本人的 library 工作區 | 想追 `ac-lib3` 源流時一定要看 |
| `~ygrek/` | ~264 | library + SPF 補強 + 應用程式混合 | 很多實用小庫與實驗都在這裡 |
| `~moleg/` | ~176 | 大型個人工作樹 | 歷史資產量大 |
| `~day/` | ~145 | 框架 / OOP / GUI / 大型子專案 | 很像另一個系統層級的實驗場 |
| `~micro/` | ~111 | 實際應用程式與 utility | 可以看到 SPF 被拿來做完整應用 |
| `~profit/` | ~106 | 應用與工具混合 | 中型工作區 |
| `~nn/` | ~91 | library / class / utilities | 另一套個人 library 倉 |
| `~yz/` | ~78 | 實用工具與 Win32 library | `fres.f` 來源所在地 |
| `~mak/` | ~47 | compiler / asm / 語言工具 | 若你喜歡 compiler-side 實驗，這裡很有味道 |

如果你只想先抓核心印象，可以簡化成：

- **看 `~ac`**：追 `ac-lib3` 的源流
- **看 `~pinka`**：追 SPF 核心補強與深層技巧
- **看 `~yz`**：追實際被 build 流程用到的工具
- **看 `~day` / `~micro`**：看 SPF 被拿來做應用與框架

---

## 4. 幾個最重要的作者子樹

### 4.1 `devel/~ac/` — `ac-lib3/` 的母樹與 rationale 區

這一棵對現在的 repo 特別重要，因為它看起來幾乎就是 `ac-lib3/` 的工作母樹：

```forth
devel/~ac/
├── lib/
│   ├── LOCALS.F / REQUIRE.F / STR*.F / TEMPS.F
│   ├── string/ / win/ / memory/ / debug/ / tools/ / list/ / transl/
│   └── ...
├── pipes/
└── rationale/
```

這表示：

- 若你想知道 `ac-lib3/` 裡某個檔案的「更早版本 / 工作版」從哪來，通常會先回頭看 `devel/~ac/lib/`
- `rationale/` 看起來像作者對 SPF / parser / translator / array 等主題的設計筆記與原型思路

**典型用途**：

1. 追 `ac-lib3/` 裡某些 library 的來源脈絡。  
2. 找作者本人對 SPF 設計的草稿、替代實作與 rationale。  
3. 理解為什麼某些 `ac-lib3` 檔案看起來像是「整理後的版本」。

**例子**：

- 想對照 `ac-lib3/STR2.F` 與 `devel/~ac/lib/STR2.F` 的演進差異。
- 想看 `rationale/spf4_parser.f`、`spf4_eval.f` 這類檔案，理解 parser / translator 的歷史思路。

**代表內容**：

- `devel/~ac/lib/LOCALS.F`、`REQUIRE.F`、`STR*.F`、`TEMPS.F`
- `devel/~ac/lib/string/`、`win/`、`memory/`、`debug/`、`tools/`
- `devel/~ac/rationale/SPF4.F`
- `devel/~ac/rationale/spf4_parser.f`
- `devel/~ac/rationale/spf4_eval.f`

**實際例子**：

1. 如果你在 `ac-lib3/` 看到某個 library 想知道「它是不是從作者工作版整理出來的」，就先回頭找 `devel/~ac/lib/` 的同名檔案。  
2. 如果你想理解 SPF 4 的 parser / translator 設計背景，`devel/~ac/rationale/` 是看原作者草稿的第一站。  
3. 如果你想比較 `ac-lib3/` 的整理版與作者工作版在命名、結構或依賴上的差異，`~ac` 幾乎是最直接的對照來源。

### 4.2 `devel/~pinka/` — SPF 核心補強與實驗深水區

這是整個 `devel/` 裡最大的子樹，而且內容明顯貼近 SPF 核心本體：

- `spf/compiler/`
- `debug-throw.f`
- `exc-dump.f`
- `fix-accept.f`
- `fix-refill.f`
- `storage*.f`
- `ffi/`
- `os-detection.f`

這一類檔案名稱直接透露它關注的是：

- exception / throw / dump
- compiler / wordlist / notfound
- storage / memory / user area
- FFI 與 runtime 修補

**典型用途**：

1. 想研究 SPF 哪些核心行為曾被修補或重寫。  
2. 想找 throw / exception / dump 的替代實作或 debug 實驗。  
3. 想看 compiler / wordlist / storage 的非正式擴充。  
4. 想了解某些註解裡提到的 `~pinka` 來源脈絡。

**例子**：

- 如果你在主系統裡追 `THROW` / exception dump，`debug-throw.f`、`exc-dump.f` 這些檔案很值得翻。
- 如果你想找 compiler / wordlist 行為的額外 patch，`spf/compiler/` 與 `wid-extra*.f` 很可能有現成思路。

**代表內容**：

- `devel/~pinka/spf/debug-throw.f`
- `devel/~pinka/spf/exc-dump.f`
- `devel/~pinka/spf/fix-accept.f`
- `devel/~pinka/spf/fix-refill.f`
- `devel/~pinka/spf/quoted-word.f`
- `devel/~pinka/spf/storage*.f`
- `devel/~pinka/spf/ffi/`
- `devel/~pinka/spf/compiler/`

**實際例子**：

1. 你若想追 SPF 例外處理 / dump 的替代做法，可以直接從 `debug-throw.f` 與 `exc-dump.f` 下手。  
2. 你若在主系統裡看到 `fix-accept`、`fix-refill` 類問題，`~pinka/spf/` 很可能已經有對應 patch prototype。  
3. 若你對 SPF 的 compiler / wordlist 深水區有興趣，`~pinka/spf/compiler/` 比一般 library 更接近「核心實驗場」。 

### 4.3 `devel/~yz/` — 實用工具與 Windows build helper

這一棵最醒目的原因不是檔案數，而是它和**實際 build 流程有已知接點**：

- `prog/fres/` 被 [`res.bat`](file:///Users/wenij/work/forth/spf/src/win/res/res.bat#L6) 直接使用
- 另外還有 `automation/`、`db/`、`winlib/`、`resources.f`、`UUID.F` 等

**典型用途**：

1. 想知道 `fres.f` 到底從哪來、做什麼。  
2. 想找實用 Win32 / automation / db 類小工具。  
3. 想看被 build 流程實際依賴的 `devel/` 內容。

**例子**：

- 研究 Windows 資源檔 `spf.res → spf.FRES` 的轉換工具，就去看 `devel/~yz/prog/fres/`。
- 想找另一套 Win32 helper library / automation 工具，可以先翻 `devel/~yz/lib/` 與 `prog/`。

**代表內容**：

- `devel/~yz/prog/fres/fres.f`
- `devel/~yz/lib/resources.f`
- `devel/~yz/lib/UUID.F`
- `devel/~yz/lib/winlib.f`
- `devel/~yz/lib/automation.f`

**實際例子**：

1. 若你在 build 流程中追 `fres.f` 的來源，就直接看 `devel/~yz/prog/fres/fres.f`；這不是純歷史檔，而是目前 repo 的 Windows 資源建構流程還會碰到的實際工具。  
2. 若你想找另一套 Win32 / automation / resources helper，可先翻 `devel/~yz/lib/`。  
3. 若你想理解 SPF 社群如何做 database / automation / winlib 類工具，`~yz/prog/` 是個不錯的入口。

### 4.4 `devel/~day/` — 大型框架 / OOP / 子系統實驗

這棵很像另一個平行世界，有多個大塊：

- `joop/`
- `wfl/`
- `hype3/`
- `fsim/`
- `reminder/`

從名稱看，這裡比較像：

- OOP / framework
- GUI / application framework
- 大型子專案
- 作者自己完整維護的一套工具鏈

**典型用途**：

1. 想看 SPF 世界裡的大型框架型實驗。  
2. 想學 OOP / framework 類設計在 SPF 裡怎麼長。  
3. 想找比單一 library 更完整的應用骨架。

**例子**：

- 看 `joop/` 學 SPF 裡的 OOP 風格。
- 看 `wfl/` / `hype3/` 理解作者如何把 SPF 拉到 framework 層級。

**代表內容**：

- `devel/~day/joop/oop.f`
- `devel/~day/joop/win/`
- `devel/~day/wfl/wfl.f`
- `devel/~day/wfl/examples/`
- `devel/~day/hype3/`
- `devel/~day/fsim/`

**實際例子**：

1. `joop/` 很適合拿來看 SPF 裡如何做 OOP / 類別系統，而不只是單純的函式庫。  
2. `wfl/` 看起來是更接近 GUI / application framework 的方向；如果你想看 SPF 如何長成完整框架，這裡很值得翻。  
3. `wfl/examples/` 和 `joop/samples/` 這種子目錄，對於想看「能跑的範例程式」的讀者比主系統原始碼更友善。

### 4.5 `devel/~mak/` — compiler / asm / 語言工具實驗

這一棵對喜歡語言實作的人很有味道：

- `CFASM/`
- `WIN32FOR/`
- `FBasComp/`
- `FOROPT.F`
- `WAPI.F`
- 多個 `locals*.f`

它看起來不像應用層工具，而比較像：

- compiler / assembler
- 語言擴充
- 實驗型 frontend / backend

**典型用途**：

1. 想看 SPF 周邊的 compiler / asm / parser 實驗。  
2. 想找 locals / optimizer 的另一路實作。  
3. 想看作者如何把 SPF 推向 Win32FOR / Basic compiler 類方向。

**例子**：

- 看 `FBasComp/` 理解 Forth-based compiler 實驗。
- 看 `CFASM/` 或 `FOROPT.F` 對照主系統 optimizer / asm 的另一路脈絡。

**代表內容**：

- `devel/~mak/FOROPT.F`
- `devel/~mak/CFASM/CPU80486.4TH`
- `devel/~mak/WAPI.F`
- `devel/~mak/FBasComp/`
- `devel/~mak/WIN32FOR/`

**實際例子**：

1. 想看 SPF 周邊的 80486 assembler / disassembler 實驗，就先看 `CFASM/CPU80486.4TH`。  
2. 想找與 optimizer 相關的平行思路，`FOROPT.F` 是很自然的入口。  
3. 想看作者如何把 SPF 推向 Win32FOR / Basic compiler 類前端，則可看 `FBasComp/` 與 `WIN32FOR/`。

### 4.6 `devel/~ygrek/` — library + SPF 補強 + 應用專案混合區

這棵介於 library 倉與應用倉之間：

- `lib/`
- `prog/`
- `spf/`

而且名稱很實際：

- `xmlsafe.f`
- `included.f`
- `env.f`
- `fsm.f`
- `bit.f`
- `autoc.f`

**典型用途**：

1. 想找中型通用 library。  
2. 想看作者怎麼補 SPF 本體的小功能。  
3. 想找已成形但不算核心的應用 / 工具程式。

**例子**：

- 想找 XML safe / enum / FSM 類小工具時先翻 `~ygrek/lib/`。
- 想看 `spf/` 子樹裡對 SPF 本體行為的補充或測試。

**代表內容**：

- `devel/~ygrek/lib/xmlsafe.f`
- `devel/~ygrek/lib/fsm.f`
- `devel/~ygrek/lib/enum.f`
- `devel/~ygrek/lib/net/`
- `devel/~ygrek/spf/autoc.f`
- `devel/~ygrek/prog/`

**實際例子**：

1. 若你想找中型、可直接借用的 utility 庫（XML、FSM、bit、net、parse），`~ygrek/lib/` 很值得翻。  
2. 若你想看 SPF 本體外圍的自動補完 / included / 測試小補強，`~ygrek/spf/` 會比主系統 `src/` 更實驗性。  
3. 若你想找「library + project」混合風格的作者工作樹，`~ygrek` 是很好的樣本。

### 4.7 `devel/~micro/` — 真正做成產品 / 工具的應用程式群

這裡不像 library 倉，比較像一組完整應用程式：

- `calendar/`
- `wwwlib/`
- `filetrunc/`
- `DELETER/`
- `SHEDULER/`
- `calc/`

**典型用途**：

1. 想看 SPF 被拿來做完整應用，而不只是小型 library。  
2. 想找「真實產品感」較重的範例。  
3. 想看 Windows / WWW / scheduler / calculator 這類實用專案。

**例子**：

- 想研究 SPF 如何做 scheduler / reminder 類應用，就看 `SHEDULER/` 或相關工具。
- 想看完整應用的專案佈局，而不是單一 `.f` 檔，就看 `DELETER/`、`calendar/` 等目錄。

**代表內容**：

- `devel/~micro/SHEDULER/`
- `devel/~micro/DELETER/`
- `devel/~micro/calendar/`
- `devel/~micro/wwwlib/`
- `devel/~micro/filetrunc/`

**實際例子**：

1. 想看 SPF 做成完整工具程式的樣子（含 `MAKE.F`、`cfg`、`doc.txt`、`DISTRIB/`），`SHEDULER/` 是很好的案例。  
2. 想看實際產品感較重的專案佈局，不只是 library，`DELETER/`、`calendar/` 很值得翻。  
3. 想理解 SPF 在 WWW / scheduler / file utility 類領域的應用範圍，`~micro` 比 core docs 更直觀。

### 4.8 `devel/~nn/` — 另一套個人 library / class 倉

`~nn/` 裡最醒目的結構是：

- `class/`
- `lib/`

而 `lib/` 下又有：

- `base64.f`
- `unicode.f`
- `script.f`
- `winapi.f`
- `sock2.f`
- `file/`
- `web/`

**典型用途**：

1. 想比較別的作者如何組一套自己的 SPF library。  
2. 想找 class / library 風格的替代做法。  
3. 想看另一套 base64/unicode/file/web/sock 類工具。

**例子**：

- 對照 `ac-lib3/string/CONV.F` 與 `~nn/lib/base64.f` 的不同風格。
- 看 `class/` 了解另一位作者的 OOP / class 思路。

**代表內容**：

- `devel/~nn/class/`
- `devel/~nn/lib/base64.f`
- `devel/~nn/lib/unicode.f`
- `devel/~nn/lib/script.f`
- `devel/~nn/lib/web/`
- `devel/~nn/lib/win/`

**實際例子**：

1. 若你想比較不同作者如何做 base64 / unicode / file / web 工具，`~nn/lib/` 很適合拿來和 `ac-lib3` 對照。  
2. 若你想看另一套 class / library 組織方式，`~nn/class/` 與 `~nn/lib/` 會提供不同於 `~day` 或 `ac-lib3` 的風格。  
3. 若你想找一套偏「個人 library 倉」而非單一專案的樣本，`~nn` 很典型。

---

## 5. `devel/` 裡常見的內容型別

把整個 `devel/` 濃縮成幾類，會比較好讀：

| 類型 | 代表子樹 | 說明 |
|------|----------|------|
| 作者工作母樹 | `~ac/`, `~pinka/`, `~yz/` | 某位作者長期累積的 library / tool / rationale / prototype 集合 |
| SPF 本體補強 / patch 區 | `~pinka/spf/`, `~ygrek/spf/` | 對 core runtime / compiler / throw / notfound / storage 的實驗與修補 |
| 獨立 framework / 子系統 | `~day/joop/`, `~day/wfl/`, `~day/hype3/` | 不只是單一工具，而是一整套設計風格 |
| 實際應用專案 | `~micro/DELETER/`, `~micro/SHEDULER/`, `~micro/calendar/` | 真正拿 SPF 寫成的應用程式 |
| library 倉 | `~nn/lib/`, `~yz/lib/`, `~ygrek/lib/` | 作者個人的 reusable 工具集合 |
| 歷史 / 教學 / rationale | `~ac/rationale/`, 各種 `AUTHOR.TXT`, `history.txt`, `index.html` | 幫助理解背景與演進，但不一定可直接拿來跑 |

---

## 6. 讀 `devel/` 時應該抱持什麼心態？

`devel/` 最容易讓人誤判的地方，是把它當成：

- 另一份 `src/`
- 或是另一份 `ac-lib3/`

但它其實比較像這三件事的混合：

1. **作者的工作區**  
   很多東西是「某人當時正在做的版本」，不一定是最終整理後的 library。

2. **歷史與演進記錄**  
   有些功能後來被吸收進 `ac-lib3/` 或主系統，但源頭 / 平行版本還留在這裡。

3. **大型範例倉**  
   如果你想知道 SPF 能拿來做什麼，`devel/` 常常比 `src/` 更直接地展示答案。

所以閱讀策略應該是：

- **想理解 SPF 本體** → 先讀 `src/`
- **想找整理過的 reusable library** → 先讀 `ac-lib3/`
- **想追源流、找 prototype、看作者本人怎麼玩 SPF** → 再進 `devel/`

---

## 7. 幾個具體的「遇到什麼需求就先看哪棵」

### 情境 A：我想追某個 `ac-lib3` 模組的源頭

先看：

- `devel/~ac/lib/`

**例子**：

- 想知道 `ac-lib3/STR2.F` 是不是還有更早版本 / 工作版。
- 想找 `ac-lib3` 某個工具最初的作者版與 rationale。

### 情境 B：我想研究 SPF 核心行為的修補或替代實作

先看：

- `devel/~pinka/spf/`
- `devel/~ygrek/spf/`

**例子**：

- 想找 `THROW` / exception dump / refill / accept 的修補版。
- 想看 compiler / wordlist / storage / os detection 的額外實驗。

### 情境 C：我想找實際被 build 或工具鏈引用的東西

先看：

- `devel/~yz/prog/fres/`

**例子**：

- 想知道 `spf.res → spf.FRES` 是怎麼轉的。
- 想確認 `res.bat` 用到的 `fres.f` 到底在哪。

### 情境 D：我想看 SPF 能不能做完整應用 / framework

先看：

- `devel/~day/`
- `devel/~micro/`

**例子**：

- 想看 OOP / framework 類子系統：`~day/joop/`, `~day/wfl/`, `~day/hype3/`
- 想看完整應用：`~micro/DELETER/`, `~micro/SHEDULER/`, `~micro/calendar/`

### 情境 E：我想找另一套 library 風格，拿來對照 `ac-lib3`

先看：

- `devel/~nn/lib/`
- `devel/~yz/lib/`
- `devel/~ygrek/lib/`

**例子**：

- 對照不同作者如何實作 base64 / unicode / file / web / socket 類工具。
- 想看同一問題在不同作者手下怎麼被拆解與命名。

---

## 8. 與 `src/`、`ac-lib3/` 的關係

可以用一句話總結：

- **`src/`**：SP-Forth 本體
- **`ac-lib3/`**：整理過、比較可直接拿來用的延伸 library/toolkit
- **`devel/`**：作者工作區、歷史資產、原型與應用專案集合

如果你問：

> 「這個功能我應該先去哪裡找？」

可以用這個判斷：

1. **想知道 SPF 本身怎麼運作** → `src/`
2. **想直接找可重用工具** → `ac-lib3/`
3. **想追源流、找 prototype、看社群多樣做法** → `devel/`

---

## 9. `devel/` 最值得記住的幾件事

如果你不想記太多細節，只要記住下面幾點就夠了：

1. `devel/` 是**作者子樹集合**，不是單一 library。
2. `~ac` 很重要，因為它和 `ac-lib3/` 的源流直接相關。
3. `~pinka` 很重要，因為它貼近 SPF 核心修補與 debug 深水區。
4. `~yz/prog/fres/` 很重要，因為它真的被 build 流程用到。
5. `~day` / `~micro` 很值得看，因為它們展示 SPF 被拿來做完整 framework / app。
6. `devel/` 最適合當**源流與範例倉**，不是主系統追蹤的第一站。

---

## 10. 與其它 trace 章節的關係

- 若你想知道為什麼 `devel/` 會出現在模組搜尋路徑，回看 [05-io-error-init.md](05-io-error-init.md) 中 `spf_module.f` 的說明。
- 若你想知道 `fres.f` 如何參與 Windows 資源建構，回看 [06-build-save.md](06-build-save.md)。
- 若你想理解 `devel/~ac/lib/` 與 `ac-lib3/` 的關係，先看 [16-ac-lib3.md](16-ac-lib3.md)。
- 若你在主系統原始碼中看到 `~pinka` 或其它作者子樹的註記，可回到本章對照其作者工作區背景。

本章的目的是把 `devel/` 變成一張「可導航的地圖」：你不需要一次讀完它，但當你想找 SPF 社群留下的某一類原型、工具或歷史脈絡時，至少知道該先往哪棵子樹走。
