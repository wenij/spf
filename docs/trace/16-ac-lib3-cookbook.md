# SP-Forth/4 原始碼追蹤 — `ac-lib3/` 使用索引與範例

> 定位：本章是 [16-ac-lib3.md](16-ac-lib3.md) 的配套使用索引。  
> 主章負責說明 `ac-lib3/` 在 repo 裡的角色；本章則回答「我想用某個 `ac-lib3/` 檔案，應該先看哪些 word、怎麼載入、有哪些前提」。

---

## 1. 使用前先確認的事

`ac-lib3/` 很像一個歷史應用函式庫集合，不像現代套件那樣每個檔案都有完整的套件描述。因此拿來用之前，最好先確認四件事：

| 檢查點 | 原因 |
|--------|------|
| `REQUIRE` 是否可用 | 多數檔案開頭會用 `REQUIRE ... ~ac/lib/...` 載入依賴 |
| `~ac/lib/...` 是否能解析 | SPF4 會透過 module / library path 尋找 `devel/~ac/lib/...` |
| 是否在 Windows/Win32 環境 | `win/`、`memory/`、`tools/` 大量直接呼叫 Windows DLL |
| 外部 DLL 是否存在 | regexp、bregexp、zlib 等 wrapper 需要對應 DLL |

最保守的讀法是：先看目標檔案開頭的 `REQUIRE` 列表，再決定載入順序。若環境已能解析 `~ac/lib/...`，通常直接載入目標檔案即可。

```forth
S" ac-lib3/STR2.F" INCLUDED
```

如果環境無法解析作者路徑，就要改用實體路徑手動載入依賴，或先調整 SPF 的 library path。

---

## 2. 語言延伸

### `LOCALS.F`

用途：提供 `{ ... -- ... }` locals 語法，讓資料流不用全靠 `SWAP` / `OVER` / `ROT` 維持。

常見情境：

- 數值或字串處理邏輯裡的堆疊搬移太多。
- 讀到 `registry2.f`、`STR2.F` 這類較新 `ac-lib3` 檔案中的 `{ ... }`。
- 想把舊 SPF 程式改寫成比較容易維護的形式。

範例：

```forth
: TEST { a b c d \ e f -- }
  a . b . c .
  b c + -> e
  e . f .
  ^ a @ .
;
```

重點：

- `a b c d` 來自資料堆疊。
- `\ e f` 是未初始化的局部暫存。
- `-> e` 寫入 local；`^ a` 取得 local 的地址。

### `TEMPS.F`

用途：較舊的一代暫存變數方案，使用 `| ... |`、`|| ... ||`、`(( ... ))` 等語法。

常見情境：

- 維護 `STR.F`、`REGISTRY.F` 或部分舊 `win/window/` 模組。
- 想理解 `ac-lib3` 從 `TEMPS.F` 風格遷移到 `LOCALS.F` 風格的軌跡。

範例風格：

```forth
| tmp count |
123 -> tmp
tmp .
```

```forth
(( a b c ))
```

提醒：新程式若沒有相容性壓力，通常先看 `LOCALS.F`；`TEMPS.F` 更適合讀舊碼。

### `REQUIRE.F`

用途：提供早期的 `REQUIRE` / `REQUIRED` 載入機制。SPF4 本體後來也有同名 word，概念相同：用代表 word 判斷 library 是否已載入，避免重複載入。

範例：

```forth
REQUIRE COMPARE-U ~ac/lib/string/compare-u.f
```

```forth
S" COMPARE-U" S" ~ac/lib/string/compare-u.f" REQUIRED
```

重點：

- `REQUIRE word path` 會先查 `word` 是否已存在。
- 若 `word` 不存在，才載入 `path`。
- `~ac/lib/...` 在此 repo 中主要對應 `devel/~ac/lib/...`；`ac-lib3/` 是整理後的副本。

---

## 3. 字串與文字處理

### `STR.F` / `STR2.F` / `STR3.F` / `str4.f`

用途：提供動態字串與模板字串，支援類似 `" ... {word} ..."` 的內插寫法。

選擇建議：

| 需求 | 優先看 |
|------|--------|
| 維護依賴 `TEMPS.F` 的舊程式 | `STR.F` |
| 一般模板字串 / 動態字串 | `STR2.F` |
| 需要 `%WORD`、`%I`、`%J` | `STR3.F` |
| 研究 heap 掃描、自訂 allocation | `str4.f` |

基本範例：

```forth
S" ac-lib3/STR2.F" INCLUDED

: text S" hello" ;
" before {text} after" STYPE
```

進階範例：

```forth
: TEST S" test" ;
" abc{TEST}123 5+5={5 5 +} Ok" STYPE CR
```

釋放規則：

- `STYPE` 會 `TYPE` 後釋放字串。
- 手動保留字串時，用 `STR@` 取得 `addr u`，用 `STRFREE` 釋放。
- `str4.f` 裡的 `FREESTR` 是 heap 掃描/清理工具，不是一般成對 free API。

### `string/CONV.F`

用途：base64、URL `%xx` 還原、KOI8-R / Windows-1251 轉換、把 token stream 轉成較容易解析的 blank-delimited 形式。

範例：

```forth
S" SGVsbG8=" debase64
```

```forth
S" a%20b%3Ac" CONVERT%
```

注意：`KOI>WIN` / `WIN>KOI` 會就地改寫 buffer，不是產生新字串。

### `string/get_params.f`

用途：解析 `name=value&x=y` 形式的 query string / form parameter。

範例：

```forth
S" error_code=10060&from=http://10.1.1.11/" GetParamsFromString
S" error_code" GetParam TYPE
```

常用 word：

- `GetParamsFromString`：解析整串參數。
- `GetParam`：取特定 key 的 value。
- `SetParam`：新增或覆蓋參數。
- `IsSet`：檢查 key 是否存在。
- `DumpParams`：輸出目前 parse 結果。

### `string/mime-decode.f`

用途：處理 MIME / mail header encoded-word，涵蓋 RFC 2045 / 2047 / 2231 常見格式。

範例：

```forth
S" =?windows-1251?B?...?=" MimeValueDecode
```

```forth
" Subject: =?koi8-r?Q?...?=" STR@ StripLwsp MimeValueDecode TYPE
```

重點：

- 支援 base64 與 quoted-printable 類型。
- `CHARSET-DECODERS` vocabulary 可掛 charset decoder。
- 原始註解特別偏俄文郵件情境，常見 charset 包含 `windows-1251`、`koi8-r`。

### `string/regexp.f`

用途：PCRE wrapper，提供 Perl 風格正規表示式。

範例：

```forth
S" PcReIsRULEZZ:)" S" ^P(.+)Z" PcreMatch .
```

```forth
S" one two three" S" (\S+)\s+(\S+)\s+(\S+)" PcreGetMatch
```

注意：

- 需要 `pcre.dll`。
- `PcreMatch` 回傳是否 match。
- `PcreGetMatch` 會把整體 match 與 capture groups 放回資料堆疊，最後回傳數量。
- 使用底層 compile/exec 流程時，要留意 `PcreFree` / `PcreEnd`。

### `string/bregexp/bregexp.f`

用途：另一套正規表示式 binding，依賴同目錄的 `BREGEXP.DLL`。

適合情境：

- 維護既有依賴 BRegexp 的舊工具。
- 想比較 PCRE 與 BRegexp 的 binding 風格。
- 需要使用同目錄附帶的歷史 DLL。

---

## 4. 除錯、工具與小型資料結構

### `debug/TRACE.F`

用途：載入後重新定義 `:`，讓之後定義的 word 在開頭自動插入 trace 輸出。輸出是否發生由 `DEBUG` 旗標控制。

範例：

```forth
S" ac-lib3/debug/TRACE.F" INCLUDED

DebugOn

: SQUARE  DUP * ;
: DEMO    3 SQUARE . ;

DEMO
```

重點：

- trace 注入發生在定義期。
- `TRACE.F` 載入前已存在的 word 不會被追蹤。
- `DebugOn` / `DebugOff` 只切換執行期輸出。

### `tools/load_lib.f`

用途：先用 `WINAPI:` 宣告 API，再用 `LoadInitLibrary` 一次載入 DLL 並解析 `WINAPLINK` 鏈上的函式地址。

範例：

```forth
S" ac-lib3/tools/load_lib.f" INCLUDED

WINAPI: MyPluginInit   MYPLUGIN.DLL
WINAPI: MyPluginRun    MYPLUGIN.DLL

S" myplugin.dll" LoadInitLibrary THROW DROP
```

若只想看錯誤碼：

```forth
S" extraapi.dll" LoadInitLibrary
SWAP DROP
?DUP IF ." LoadInitLibrary failed: " . CR THEN
```

### `tools/dump_winapi.f`

用途：走訪 `WINAPLINK`，列出目前所有 `WINAPI:` 宣告。

範例：

```forth
S" ac-lib3/tools/dump_winapi.f" INCLUDED
DUMP-WINAPI
```

搭配 `load_lib.f`：

```forth
S" ac-lib3/tools/load_lib.f"    INCLUDED
S" ac-lib3/tools/dump_winapi.f" INCLUDED

WINAPI: Sleep KERNEL32.DLL
S" kernel32.dll" LoadInitLibrary THROW DROP
DUMP-WINAPI
```

### `tools/jmp.f` / `tools/map.f`

`jmp.f` 提供低階 hot patch：

```forth
' NEW-WORD ' OLD-WORD JMP
```

它會在 `OLD-WORD` 入口寫入 near JMP，讓呼叫改跳到 `NEW-WORD`。這是直接改機器碼的工具，適合研究或 instrumentation，不適合一般業務程式隨手使用。

`map.f` 則用 `JMP` 攔截 `COMPILE,` / `LIT,`，載入後會開始輸出編譯 reference map。

```forth
S" ac-lib3/tools/map.f" INCLUDED
: DEMO  1 2 + . ;
```

提醒：`map.f` 會改全域 compiler 行為。除錯完通常開乾淨 session，比在同一 session 裡繼續開發穩。

### `list/STR_LIST.F`

用途：單向鏈結串列，節點 value 常用 xcount 字串指標。

可跑的最小範例：

```forth
VARIABLE my-list

: >XCOUNT ( addr u -- xaddr )
  DUP CELL+ ALLOCATE THROW
  >R
  DUP R@ !
  R@ CELL+ SWAP MOVE
  R>
;

S" hello" >XCOUNT my-list AddNode
S" world" >XCOUNT my-list AddNode
S" hello" my-list inList .
```

注意：`AddNode` 收的是 value 指標，不是直接收 `addr u`。實際應用可參考 `mbox/text_mbox_parsing.f` 的 `COPYBUFC`。

### `transl/vocab.f` / `transl/BNF.F`

`vocab.f` 提供 vocabulary / public API 的區塊語法：

```forth
InVoc{ MyModule
  Public{
    : hello ... ;
  }Public
}PrevVoc
```

`BNF.F` 提供小型 parser scaffolding：

```forth
CHAR ( Match
GetQuoted
CHAR ) Match
```

這兩個檔案更像範例與語法工具，適合研究 SPF 如何把 parser / vocabulary 操作包成小 DSL。

### `ruvim/MASK.F`

用途：wildcard / glob 類比對，支援 `*`、`?` 與跳脫字元。

範例：

```forth
S" report.txt" S" *.txt" WildCMP-U
```

```forth
S" mail-01.log" S" mail-??.log" WildCMP-U
```

### `res_ctrl.f`

用途：thread-aware resource table，偏 Eserv2 風格，常用來學 file handle / resource tracking。

範例：

```forth
INIT-RTABLE
DUMP-RES
```

適合用來研究，不建議未讀懂前直接搬進一般專案。

### `memory/heap_enum.f` / `heap_enum2.f` / `less_mem.f`

用途：

- `heap_enum.f` / `heap_enum2.f`：列舉 process heap。
- `less_mem.f`：透過 Windows API 要求縮小 process working set。

範例：

```forth
MEM
```

```forth
ReduceMem
```

---

## 5. Windows 系統整合

### `win/registry2.f` / `win/REGISTRY.F`

用途：Windows registry 操作。`REGISTRY.F` 是舊版 `TEMPS.F` 風格；`registry2.f` 是較新的 `LOCALS.F` 風格。

範例：

```forth
S" ac-lib3/win/registry2.f" INCLUDED

S" ProxyServer" S" SOFTWARE\\Example" StrValue
```

列舉 subkeys：

```forth
: TYPECR ( addr u -- ) TYPE CR ;

S" SOFTWARE\\Example" HKEY_LOCAL_MACHINE RG_OpenKey THROW
['] TYPECR SWAP RG_ForEachKey
```

注意：

- `StrValue` / `NumValue` / `BinValue` 會透過 `EK` 決定 root key。
- `registry2.f` 預設 `EK` 是 `HKEY_LOCAL_MACHINE`。
- 若要查 `HKEY_CURRENT_USER` 等其它 hive，要先改 `EK`。

### `win/ini.f`

用途：INI 檔操作，並提供 `File.Section[Key]` 風格的便利語法。

範例：

```forth
S" key" S" section" S" file.ini" IniFile@
```

```forth
S" g:\\WINXP\\win.ini.Mail[CMCDLLNAME32]" IniS@
```

### `win/file/`

用途：Win32 檔案列舉、遞迴掃描、file time、share-delete、C runtime stream wrapper。

範例：

```forth
S" *.txt" ['] TYPE FIND-FILES
```

```forth
S" c:\\logs\\*.log" ['] TYPE FIND-FILES-R
```

### `win/process/`

用途：啟動外部 process、等待 process、列舉、kill、pipe、child I/O。

範例：

```forth
S" notepad.exe" StartApp
```

```forth
S" ping 127.0.0.1" StartAppWait
```

注意：`StartApp` / `StartAppWait` 回傳 CreateProcess 結果；這組 wrapper 很貼近 Win32 API，錯誤處理要看原檔的堆疊效果。

### `win/service/`

用途：Windows service skeleton 與 service control helper。

範例：

```forth
S" MyService" StartService
```

```forth
S" MyService" DeleteService
```

注意：`SERVICE.F` 裡的 `StartService` 是呼叫 `StartServiceCtrlDispatcherA`、讓目前 process 進入 service main loop；它不是「啟動已安裝服務」的控制 API。完整安裝/控制流程要一起看 `CreateService`、`DeleteService` 與 `service_struct.f`。

### `win/com/`

用途：COM / OLE / BSTR / Unicode 基礎封裝，也包含 COM server framework 與大量 automation samples。

範例：

```forth
S" ac-lib3/win/com/COM.F" INCLUDED

ComInit THROW
```

```forth
S" Scripting.FileSystemObject" ProgID>CLSID THROW
```

```forth
ComExit
```

建議讀法：

- 想呼叫 COM / ActiveX：先看 `COM.F`。
- 想看 automation 實例：看 `win/com/samples/`。
- 想研究 SPF 實作 COM server：看 `com_server.f` / `com_server2.f`。

### `win/window/`

用途：Win32 GUI、dialog、listbox、tray icon、popup menu、window enumeration。

這一組 API 參數通常偏長，建議搭配 `WINCONST.F`、`WINDOW.F`、`DIALOG.F` 和 `samples/` 一起看。

範例方向：

```forth
... Window
```

```forth
... DialogModal
```

### `win/winsock/`

用途：Winsock wrapper，涵蓋 raw socket、line-based socket I/O、UDP、DNS、IP helper。

raw socket 範例：

```forth
S" ac-lib3/win/winsock/SOCKETS.F" INCLUDED

SocketsStartup THROW
CreateSocket THROW
```

`PSOCKET.F` 範例：

```forth
S" ac-lib3/STR2.F" INCLUDED
S" ac-lib3/win/winsock/PSOCKET.F" INCLUDED

SocketsStartup THROW
" www.example.com" 80 fsockopen DUP >R
" GET / HTTP/1.0{CRLF}{CRLF}" R@ fputs
R@ fgets STYPE
R> fclose
```

注意：

- `fsockopen` 的 server 參數是 `STR2.F` 的字串物件，所以用 `" www.example.com"`，不是 `S" www.example.com"`。
- `fgets` 回傳字串物件；若直接輸出，可用 `STYPE`。
- `ws2/` 子目錄是 `WS2_32.DLL` 版本，非 `ws2/` 則多為舊 `WSOCK32.DLL` 版本。

### `win/access/`

用途：帳號、SID、ACL、privilege、LSA logon、群組列舉。

範例：

```forth
whoami TYPE
```

```forth
S" user" S" password" LoginUser
```

注意：`LoginUser` 會呼叫 `LogonUserA` / `ImpersonateLoggedOnUser`，實際可用性取決於 Windows 權限與 logon type。

### `win/odbc/`

用途：ODBC / SQL 封裝，包含基本查詢、DSN / driver connect、資料來源列舉與 XML 輸出。

範例：

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

用途：封裝 `zlib.dll`，提供 zlib deflate、gzip 輸出與 CRC32。

範例：

```forth
S" hello" zlib_compress
```

```forth
S" hello" CRC32 .
```

```forth
S" hello" gzip
```

注意：

- `zlib_compress` / `zlib_uncompress` 使用 zlib 格式。
- `gzip` / `gzip_write` 輸出 gzip 格式。
- 需要 `zlib.dll`。

---

## 6. 建議查找順序

若你已知道需求，可以直接按問題找：

| 需求 | 先看 |
|------|------|
| 降低堆疊搬移 | `LOCALS.F`、`TEMPS.F` |
| 產生文字模板 | `STR2.F`、`STR3.F` |
| 解析 query string | `string/get_params.f` |
| 解碼 mail header | `string/mime-decode.f` |
| 正規表示式 | `string/regexp.f` |
| registry / INI | `win/registry2.f`、`win/ini.f` |
| process / service | `win/process/`、`win/service/` |
| socket / DNS | `win/winsock/` |
| COM automation | `win/com/`、`win/com/samples/` |
| 插樁 / 除錯 | `debug/TRACE.F`、`tools/map.f` |

本章的目的不是取代原始檔註解，而是讓你知道第一個入口在哪裡。真正要接進專案時，仍應回到對應 `.f` 檔開頭，確認 `REQUIRE` 依賴、堆疊效果與外部 DLL 前提。
