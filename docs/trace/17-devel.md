# SP-Forth/4 原始碼追蹤 — `devel/` 開發者工作區導覽

> 定位：如果 `src/` 是 SPF 本體、`ac-lib3/` 是可重用的延伸函式庫區，那 `devel/` 更像是 **作者群與社群成員的開發工作區、歷史資產倉與原型實驗場**。
>
> 本章的目標不是逐檔追完 `devel/`，而是回答三個問題：
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

從頂層結構看，它以 `~user` 形式分成多個作者子樹：

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

換句話說，`devel/` 並不是「單一函式庫」，而是：

> **SP-Forth 社群多年來留下的作者工作樹總集。**

---

## 2. 為什麼它重要？

雖然 `devel/` 不是 `spf.f` 主載入樹的一部分，但它**不是完全與主系統無關**。至少有幾個明確接點：

1. [`src/spf_module.f`](../../src/spf_module.f) 會把 `devel/` 拼進模組搜尋路徑。這代表 `devel/` 在 SPF 世界裡不是純粹的「封存區」，而是實際可被模組載入機制看見的函式庫根目錄。
2. [`src/win/res/res.bat`](../../src/win/res/res.bat) 會使用 [`devel/~yz/prog/fres/fres.f`](../../devel/~yz/prog/fres/fres.f)。這表示 Windows 資源建構流程真的依賴 `devel/` 裡的工具。
3. [`src/macroopt-hide.f`](../../src/macroopt-hide.f) 還留有 `~pinka/spf/compiler/...` 的來源註記，顯示 `devel/~pinka/` 與 compiler / optimizer 演進有歷史關聯。

因此，`devel/` 對讀者的價值通常不在「建構 SPF 本體時一定要讀」，而在於：

- 想找某個功能最早從哪裡長出來
- 想找社群裡已做過的原型或工具
- 想理解某個輔助工具（如 `fres.f`）或某套函式庫的來源脈絡

---

## 2.1 使用 `devel/` 前要先知道的事

`devel/` 能被 SPF 的搜尋路徑看見，但這不代表裡面每個檔案都像正式套件一樣可直接載入。使用前建議先確認幾件事：

| 檢查點 | 原因 |
|--------|------|
| 作者路徑是否可解析 | 很多檔案會用 `~ac/...`、`~pinka/...`、`~yz/...` 這種作者路徑互相引用 |
| 依賴是否在同一作者樹 | 有些檔案依賴作者自己的 `lib/`、`spf/` 或 `prog/` 子目錄 |
| 是否偏 Windows | `~yz/`、`~micro/`、`~day/`、部分 `~ac/` 內容大量碰 Win32 API |
| 是否只是草稿或原型 | `rationale/`、`samples/`、個人實驗目錄不一定保證可直接執行 |

實務上，讀 `devel/` 最穩的方式不是從任意檔案直接 `INCLUDED`，而是先看檔頭註解、`REQUIRE` 列表、同目錄的 README / history / sample，再決定它是「可重用庫」、「原型」、「工具」還是「歷史參考」。

---

## 3. 整體地圖：哪些作者子樹最值得先看？

從檔案數量與內容密度看，下面幾個子樹最值得優先認識。表中的檔案數是目前 repo 內的約略統計，用來判斷規模，不代表品質或可直接使用程度：

| 子樹 | 約略檔案數 | 性質 | 為什麼值得先看 |
|------|-----------|------|----------------|
| `~pinka/` | ~547 | SPF 核心補強 / compiler / debug / storage / throw / FFI | 最大、與 SPF 本體最接近的深水區之一 |
| `~ac/` | ~343 | `ac-lib3` 的母樹、設計草稿、作者本人的 library 工作區 | 想追 `ac-lib3` 源流時一定要看 |
| `~ygrek/` | ~264 | library + SPF 補強 + 應用程式混合 | 很多實用小庫與實驗都在這裡 |
| `~moleg/` | ~176 | 大型個人工作樹 | 歷史資產量大 |
| `~day/` | ~145 | 框架 / OOP / GUI / 大型子專案 | 很像另一個系統層級的實驗場 |
| `~micro/` | ~111 | 實際應用程式與工具 | 可以看到 SPF 被拿來做完整應用 |
| `~profit/` | ~106 | 應用與工具混合 | 中型工作區 |
| `~nn/` | ~91 | library / class / 工具 | 另一套個人 library 倉 |
| `~yz/` | ~78 | 實用工具與 Win32 函式庫 | `fres.f` 來源所在地 |
| `~mak/` | ~47 | compiler / asm / 語言工具 | 若你喜歡 compiler-side 實驗，這裡很有味道 |

如果你只想先抓核心印象，可以簡化成：

- **看 `~ac`**：追 `ac-lib3` 的源流
- **看 `~pinka`**：追 SPF 核心補強與深層技巧
- **看 `~yz`**：追實際被建構流程用到的工具
- **看 `~day` / `~micro`**：看 SPF 被拿來做應用與框架

---

## 4. 幾個最重要的作者子樹

本節只保留各作者子樹的定位與典型用途。代表檔案、查找命令與具體使用情境已移到 [17-devel-cookbook.md](17-devel-cookbook.md)。

### 4.1 `devel/~ac/` — `ac-lib3/` 的母樹與設計草稿區

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
2. 找作者本人對 SPF 設計的草稿、替代實作與設計理由。
3. 理解為什麼某些 `ac-lib3` 檔案看起來像是「整理後的版本」。

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

### 4.3 `devel/~yz/` — 實用工具與 Windows 建構輔助

這一棵最醒目的原因不是檔案數，而是它和**實際建構流程有已知接點**：

- `prog/fres/` 被 [`src/win/res/res.bat`](../../src/win/res/res.bat) 直接使用
- 另外還有 `automation/`、`db/`、`winlib/`、`resources.f`、`UUID.F` 等

**典型用途**：

1. 想知道 `fres.f` 到底從哪來、做什麼。
2. 想找實用 Win32 / automation / db 類小工具。
3. 想看被建構流程實際依賴的 `devel/` 內容。

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
3. 想找比單一函式庫更完整的應用骨架。

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

---

## 5. `devel/` 裡常見的內容型別

把整個 `devel/` 濃縮成幾類，會比較好讀：

| 類型 | 代表子樹 | 說明 |
|------|----------|------|
| 作者工作母樹 | `~ac/`, `~pinka/`, `~yz/` | 某位作者長期累積的 library / tool / rationale / prototype 集合 |
| SPF 本體補強 / patch 區 | `~pinka/spf/`, `~ygrek/spf/` | 對 core runtime / compiler / throw / notfound / storage 的實驗與修補 |
| 獨立 framework / 子系統 | `~day/joop/`, `~day/wfl/`, `~day/hype3/` | 不只是單一工具，而是一整套設計風格 |
| 實際應用專案 | `~micro/DELETER/`, `~micro/SHEDULER/`, `~micro/calendar/` | 真正拿 SPF 寫成的應用程式 |
| library 倉 | `~nn/lib/`, `~yz/lib/`, `~ygrek/lib/` | 作者個人的可重用工具集合 |
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
- **想找整理過的可重用函式庫** → 先讀 `ac-lib3/`
- **想追源流、找原型、看作者本人怎麼玩 SPF** → 再進 `devel/`

---

## 7. 查找範例與需求索引已拆分

本章只保留 `devel/` 的地圖與閱讀策略。具體查找命令、代表檔案與需求導向索引已移到 [17-devel-cookbook.md](17-devel-cookbook.md)。

若你的目標是「我要找某一類檔案或某棵作者子樹的入口」，建議直接讀使用索引；若你的目標是「我要理解 `devel/` 在 repo 裡扮演什麼角色」，留在本章即可。

---

## 8. 與 `src/`、`ac-lib3/` 的關係

可以用一句話總結：

- **`src/`**：SP-Forth 本體
- **`ac-lib3/`**：整理過、比較可直接拿來用的延伸函式庫 / 工具箱
- **`devel/`**：作者工作區、歷史資產、原型與應用專案集合

如果你問：

> 「這個功能我應該先去哪裡找？」

可以用這個判斷：

1. **想知道 SPF 本身怎麼運作** → `src/`
2. **想直接找可重用工具** → `ac-lib3/`
3. **想追源流、找原型、看社群多樣做法** → `devel/`

---

## 9. `devel/` 最值得記住的幾件事

如果你不想記太多細節，只要記住下面幾點就夠了：

1. `devel/` 是**作者子樹集合**，不是單一函式庫。
2. `~ac` 很重要，因為它和 `ac-lib3/` 的源流直接相關。
3. `~pinka` 很重要，因為它貼近 SPF 核心修補與 debug 深水區。
4. `~yz/prog/fres/` 很重要，因為它真的被建構流程用到。
5. `~day` / `~micro` 很值得看，因為它們展示 SPF 被拿來做完整 framework / app。
6. `devel/` 最適合當**源流與範例倉**，不是主系統追蹤的第一站。

---

## 10. 與其它 trace 章節的關係

- 若你想知道為什麼 `devel/` 會出現在模組搜尋路徑，回看 [05-io-error-init.md](05-io-error-init.md) 中 `spf_module.f` 的說明。
- 若你想知道 `fres.f` 如何參與 Windows 資源建構，回看 [06-build-save.md](06-build-save.md)。
- 若你想理解 `devel/~ac/lib/` 與 `ac-lib3/` 的關係，先看 [16-ac-lib3.md](16-ac-lib3.md)。
- 若你想直接查某棵作者子樹有哪些代表檔案與查找命令，接著讀 [17-devel-cookbook.md](17-devel-cookbook.md)。
- 若你在主系統原始碼中看到 `~pinka` 或其它作者子樹的註記，可回到本章對照其作者工作區背景。

本章的目的是把 `devel/` 變成一張「可導航的地圖」：你不需要一次讀完它，但當你想找 SPF 社群留下的某一類原型、工具或歷史脈絡時，至少知道該先往哪棵子樹走。
