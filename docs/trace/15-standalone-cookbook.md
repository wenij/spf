# SP-Forth/4 原始碼追蹤 — Standalone Executable Cookbook

> 定位：本章是 [15-standalone-executable.md](15-standalone-executable.md) 的配套 cookbook。
> 主章說明 `SAVE` / ELF / PE / entry point 的機制；本章整理可照抄後再調整的最小 recipe。

---

## 1. 使用前先確認的事

Standalone app 不是把某個 `.f` 檔「編譯成 C 那種二進位」；它是把目前 Forth image 的 dictionary、compiled code 與 runtime 狀態儲存成可執行檔。

因此 recipe 的共同前提是：

| 檢查點 | 原因 |
|--------|------|
| 先在互動系統中跑通 | `SAVE` 只保存目前 image；source 本身若有 parser / wordlist / FFI 問題，存成 executable 後仍會壞 |
| `INCLUDED` 要給 `addr u` | SP-Forth 的 `INCLUDED` 是 `( c-addr u -- )`，所以用 `S" myapp.f" INCLUDED` |
| 明確設定 entry point | console app 通常設定 `<MAIN>`；GUI app 通常設定 `?GUI` 與 `MAINX` |
| 決定是否保留初始化流程 | `SPF-INIT?` 會影響 command line 與 `spf4.ini` 類初始化行為 |
| 平台要分開驗證 | POSIX 走 ELF / gcc linker；Windows 走 PE template / import table |

範例驗證狀態：

| 範圍 | 建議環境 | 平台 | 外部依賴 |
|------|----------|------|----------|
| console `SAVE` | `spf4` 或 `spf4e` | POSIX / Windows | 無 |
| `SPF-INIT?` / `<MAIN>` | `spf4` 或 `spf4e` | POSIX / Windows | 無 |
| GUI `?GUI` / `MAINX` | Windows 版 SP-Forth | Windows only | Win32 GUI runtime |
| `SAVE-WITH-RESERVE` | `spf4` 或 `spf4e` | POSIX / Windows | 依 app 載入的 library 而定 |

---

## 2. 最小 console app

先建立 `myapp.f`：

```forth
\ myapp.f

: run ( -- )
  ." Hello from saved SP-Forth app" CR
;
```

在互動系統中先測：

```forth
S" myapp.f" INCLUDED
run
```

確認可執行後，儲存：

```forth
S" myapp.f" INCLUDED
' run TO <MAIN>
S" myapp" SAVE
```

重點：

- `S" myapp.f" INCLUDED` 會把應用程式載入目前 image。
- `' run TO <MAIN>` 把 console 啟動入口改成 `run`。
- `S" myapp" SAVE` 把目前 image 寫成 executable。

---

## 3. 不處理 `spf4.ini` / command line 的 console app

如果你希望 executable 啟動後只跑你的 entry point，不走一般 SPF 初始化檔與 command line 載入流程，可以關閉 `SPF-INIT?`：

```forth
S" myapp.f" INCLUDED

0 TO SPF-INIT?
' run TO <MAIN>

S" myapp" SAVE
```

這種做法適合：

- 小型 command line tool。
- 不希望使用者環境中的 `spf4.ini` 影響 app。
- 想把啟動行為固定在一個明確 word。

---

## 4. Windows GUI app 骨架

GUI app 通常不希望進入 console `QUIT` 流程，而是設定 Windows subsystem 與 `MAINX`：

```forth
S" myapp.f" INCLUDED

0 TO SPF-INIT?
TRUE TO ?GUI
' NOOP TO <MAIN>
' run MAINX !

S" myapp.exe" SAVE
```

重點：

- `TRUE TO ?GUI` 讓 PE 儲存流程選 GUI subsystem。
- `<MAIN>` 設為 `NOOP`，避免 console entry 做太多事。
- `MAINX` 保存真正的 GUI app entry xt。

實際 GUI 程式還需要 Win32 message loop、window class、callback 等支援；這部分請回 [09-windows-platform.md](09-windows-platform.md) 追 `CALLBACK:` / `WNDPROC:` / WinAPI 呼叫機制。

---

## 5. 保留字典空間

若儲存後的 app 還需要在執行期載入檔案、建立新字或動態配置 dictionary，使用 `SAVE-WITH-RESERVE` 比單純 `SAVE` 更適合。

概念流程：

```forth
S" myapp.f" INCLUDED
' run TO <MAIN>

\ 視實際需求保留額外 dictionary 空間
1024 1024 * S" myapp" SAVE-WITH-RESERVE
```

目前 `src/spf.f` 中的 stack effect 是 `( u.target-dict-unused sd.filename-executable -- )`，也就是 reserve size 在前、檔名字串在後。若只是做固定功能 app，優先使用 `SAVE`，等真的需要 runtime dictionary growth 再切換。

---

## 6. 儲存後必測清單

每次產生 executable 後，至少做這幾個 smoke test：

| 測試 | 看什麼 |
|------|--------|
| 直接執行 | 是否啟動即 crash |
| stdout / stderr | console output 是否正常 |
| exit code | 成功 / 失敗是否符合預期 |
| current directory | 相對路徑是否仍能解析 |
| 外部 DLL / SO | FFI symbol 是否能找到 |
| command line | 若 `SPF-INIT?` 開啟，參數是否被正確處理 |

若 executable 產生成功但啟動即 crash，先回 [15-standalone-executable.md](15-standalone-executable.md) 看 runtime startup 與 relocation，再回 [12-debugging.md](12-debugging.md) 做分層排查。

---

## 7. 常見錯誤

| 症狀 | 常見原因 | 先查 |
|------|----------|------|
| `INCLUDED myapp.f` 找不到字或語法錯 | `INCLUDED` 少了 `S" ..."` | 改成 `S" myapp.f" INCLUDED` |
| 儲存成功但啟動後進入互動 prompt | `<MAIN>` 沒設定，或仍保留 `QUIT` 流程 | §2 / §3 |
| Windows GUI app 跳出 console | `?GUI` / `MAINX` 沒設定好 | §4 |
| POSIX link 失敗 | 缺 `gcc -m32` / multilib / GNU tools | [06-build-save.md](06-build-save.md) |
| FFI app 啟動才壞 | 外部函式、DLL/SO、callback ABI 或 pointer lifetime 問題 | [12-debugging.md](12-debugging.md) |

---

## 8. 讀完後回到哪裡？

- 想理解 `SAVE` / `XSAVE` / `TSAVE` 的內部機制，回 [15-standalone-executable.md](15-standalone-executable.md)。
- 想看 ELF / PE 寫出與建構流程，回 [06-build-save.md](06-build-save.md)。
- 想追 Windows PE / GUI / callback，讀 [09-windows-platform.md](09-windows-platform.md)。
- 想排查 saved executable crash，讀 [12-debugging.md](12-debugging.md)。
