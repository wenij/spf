# SP-Forth/4 原始碼追蹤 — 核心原語（Kernel Primitives）深入解析

> 對應原始碼：`spf_defkern.f`、`spf_forthproc.f`、`spf_forthproc_hl.f`、`spf_floatkern.f`
> 原始碼版權：Copyright [C] 1992-1999 A.Cherezov ac@forth.org

> 若你對 IA-32 組語、`CODE ... END-CODE`、`C,` / `,` 這類 SP-Forth assembler 寫法還不熟，建議先讀 [08-append-a.md](08-append-a.md) 再回來。

---

## 1. Forth 虛擬機器架構

### 1.1 什麼是 Forth 虛擬機器？

Forth 是一種堆疊導向（stack-oriented）的程式語言。在傳統 Forth 實作中，所有操作都圍繞著兩個堆疊進行：**資料堆疊**（Data Stack）與**回返堆疊**（Return Stack）。SP-Forth 採用了一種被稱為 **TOS 快取暫存器模型**（Top-Of-Stack cached in register）的直接執行緒式（direct-threaded code）架構，其核心思想是：**資料堆疊的頂端元素永遠快取在 x86 的 EAX 暫存器中**。

這種設計源自 1990 年代 Forth 社群對效能最佳化的深入研究。傳統的 Forth 實作將堆疊完全放在記憶體中，每次操作都需要記憶體存取。SP-Forth 的設計者 Alexander Cherezov 發現，透過將 TOS 快取在暫存器中，可以將大多數原語的指令數從 3~5 條減少到 1~3 條，顯著提升效能。

### 1.2 暫存器分配

原始碼 `spf_forthproc.f` 第 7~12 行明確記錄了暫存器的約定用途：

```forth
( Регистры для "процессора-интерпретатора"
  EAX       Top of Stack
  EBP       Data Stack
  [EBP]     Second item on Stack
  ESP       Return Stack
  EDI       Thread data pointer
)
```

| 暫存器 | 用途 | Forth 語意 | 詳細說明 |
|--------|------|-----------|---------|
| **EAX** | TOS（堆疊頂端） | 資料堆疊最上層元素 | 這是 SP-Forth 最關鍵的設計決策。所有從堆疊「取出」的操作（如 `+` 的第二個運算元）從 `[EBP]` 讀取，而「推入」的操作將結果放入 EAX |
| **EBP** | 資料堆疊指標 | 指向堆疊第二項 | EBP 永遠指向次堆疊項（second item on stack），而非堆疊頂端。這意味著 `[EBP]` 是次堆疊項，而 TOS 在 EAX 中 |
| **ESP** | 回返堆疊指標 | 標準 x86 堆疊指標 | 回返堆疊使用 x86 原生堆疊，這使得 C 語言呼叫慣例可以直接使用 `CALL`/`RET` |
| **EDI** | TLS 基底指標 | 執行緒本地儲存 | 每個 Forth 執行緒有獨立的 USER 變數空間，EDI 指向該空間的起始位址 |
| **EBX** | 暫存器 | 通用目的 | 在迴圈、CALLBACK 等場合使用 |
| **ECX** | 暫存器/計數器 | 字串操作/迴圈計數 | 在 `CMOVE`、`FILL` 等作為計數器 |
| **EDX** | 暫存器/乘除 | 乘法與除法的高位元組 | `IMUL`/`MUL`/`IDIV` 的隱含目的暫存器 |
| **ESI** | 來源索引 | 字串操作來源 | 在 `CMOVE`/`CMOVE>` 中作為來源指標 |

### 1.3 堆疊模型示意圖

```
資料堆疊（Data Stack）— 向低位址增長：

高位址 ─────────────────────────┐
                               │
          TOS-3  ◄── [EBP+8]  │
          TOS-2  ◄── [EBP+4]  │  ← EBP 指向此處
          TOS-1  ◄── [EBP]    │
                               │
         ┌────────────────────┐│
  EAX ── │  TOS   (堆疊頂端)  ││  ← TOS 永遠快取在 EAX
         └────────────────────┘│
低位址                         │
                               └── 向低位址增長

回返堆疊（Return Stack）— 使用 x86 原生堆疊（向低位址增長）：

高位址 ─────────────────────────┐
                               │
          返回位址  ◄── [ESP+4] │
          返回位址  ◄── ESP     │  ← ESP 指向棧頂
          迴圈界限              │
          迴圈索引              │
                               └── ESP 向低位址增長


FPU 堆疊 — 獨立的 80 位元暫存器堆疊：

  ST(0) ◄── 堆疊頂端（浮點 TOS）
  ST(1)
  ST(2)
  ...
  ST(7) ◄── 堆疊底部
```

### 1.4 為什麼 EBP 指向次堆疊項？

這是一個非常精密的設計選擇。考慮 `+` 操作的堆疊效果 `( n1 n2 -- n3 )`：

- 執行前：EAX = n2（TOS），[EBP] = n1（次項）
- 需要：n1 + n2 → EAX

如果 EBP 指向 TOS-1（次項），那麼：
```asm
ADD EAX, [EBP]    ; EAX = n2 + n1 = n3
LEA EBP, 4[EBP]  ; EBP += 4，彈出次項
RET
```

只需要 3 條指令！如果 EBP 指向 TOS，則需要額外的 `MOV` 指令。這個設計使得大多數雙項運算（需同時存取 TOS 和次項）都能在 2~3 條指令內完成。

---

## 2. 定義字核心原語（spf_defkern.f）深入解析

### 2.1 Forth 定義字的執行模型

在 SP-Forth 中，每個 Forth 定義（word）在記憶體中的結構如下圖所示。**CFA 不是直接儲存執行碼位址，而是一段 `CALL rel32` 指令；其引用的目標位址（rel32）才是 PFA 的起始**：

```
         ←── 低位址                                              高位址 ──→
┌────────┬──────────────┬───────┬────────────┬───────────────────────────┐
│ flags  │ 名稱 (可變長度) │ LFA(4) │ CALL rel32 │         PFA              │
│ (1 B)  │              │        │   (5 B)    │   （定義類型決定的資料）    │
└────────┴──────────────┴───────┴────────────┴───────────────────────────┘
 ↑                                              ↑
NFA（名稱欄位位址）                             此處 + 5 bytes = PFA 起始
```

**各欄位說明**：

| 欄位 | 大小 | 說明 |
|------|------|------|
| `flags` | 1 byte | 旗標位元組（IMMEDIATE、SMUDGE、VOC 等） |
| 名稱 | 可變 | 長度位元組（+7 隱藏位元）＋名稱字元 |
| `LFA` | 4 bytes | 鏈結欄位，指向前一個字的 NFA（構成詞彙表搜尋鏈） |
| `CFA` | 5 bytes | 一條 `CALL rel32` 指令；`rel32` 的值＝ PFA 的絕對位址 |
| `PFA` | 可變 | 參數欄位；儲存常數值、變數值、執行向量等，取決於定義類型 |

**名稱欄位存取子**（均以 CFA 為參考原點往前回推）：

| 運算 | 定義 | 意義 |
|------|------|------|
| `NAME>C` | `EAX = NFA - 5` | 取 CFA 位址 |
| `NAME>F` | `EAX = NFA - 1` | 取 flags 位址 |
| `NAME>L` | `EAX = NFA + len + 1` | 取 LFA 位址 |
| `NAME>` | `EAX = [NFA - 5]` | 取 **xt**（即 CFA 中的指標值，亦即 PFA） |

**執行流程**：當 Forth 引擎執行一個 word 時，`CALL CFA` 會執行 `CALL [CFA]` —— 但事實上這條 `CALL` 指令是內嵌在字典中的（由 `SHEADER1` 的 `HERE 0 ,` 預留空間、`HERE SWAP !` 回填位址），它並不直接儲存目標位址，而是作為一個「橋樑」，讓 `NAME>` (`MOV EAX, -5[EAX]`) 能以一條指令取得 xt。

不同定義類型在 PFA 中儲存不同資料：
- `CONSTANT`：PFA = 常數值（4 bytes）
- `VARIABLE`：PFA = 變數儲存格（4 bytes）
- `VALUE`：PFA = 值（4 bytes）＋ `_TOVALUE-CODE`（供 `TO` 修改）

### 2.2 各定義字執行碼的詳細分析

#### 2.2.1 CREATE — `_CREATE-CODE`

```asm
CODE _CREATE-CODE
     LEA  EBP, -4 [EBP]    ; 將 EAX 推入資料堆疊（建立新的堆疊項）
     MOV  [EBP], EAX        ; [EBP] = 舊的 TOS
     POP EAX                ; 從回返堆疊取出 PFA 位址 → 新的 TOS
     RET
END-CODE
```

**行為**：`CREATE` 定義的字在執行時，會將其**參數欄位位址**（PFA）推上資料堆疊。

**Forth 語意**：`( -- addr )`

**堆疊變化**（逐步追蹤）：
```
執行前：                        執行後：
  ESP → 返回位址                  ESP → （已彈出返回位址）
  EAX = x（不關心的值）            EAX = PFA位址
  [EBP] = y（次項）               [EBP] = x（原來的 TOS 變成次項）
```

**為什麼要用 `POP EAX` 而不是 `MOV EAX, [ESP]` + `ADD ESP, 4`？**

因為在 SP-Forth 的執行緒式碼中，每個 CODE 定義的末尾都有 `RET` 指令。當 Forth 引擎呼叫一個字時，`CALL CFA` 會將返回位址推入 ESP，然後 CFA 中的 `JMP _CREATE-CODE` 跳到執行碼。此時 ESP 指向「下一個要被執行的指令位址」（即 PFA 位址，因為 SP-Forth 將 PFA 位址放在 CFA 後面，而呼叫慣例使用 CALL+RET 模式傳遞 PFA）。

#### 2.2.2 CONSTANT — `_CONSTANT-CODE`

```asm
CODE _CONSTANT-CODE
     LEA  EBP, -4 [EBP]    ; 堆疊往深推一層
     MOV  [EBP], EAX        ; 舊 TOS → 次項
     POP EAX                ; 從回返堆疊取出 PFA 位址
     MOV EAX, [EAX]         ; 從 PFA 讀取常數值 → 新的 TOS
     RET
END-CODE
```

**與 CREATE 的差異**：多了一條 `MOV EAX, [EAX]`。CONSTANT 定義的字不回傳 PFA 位址本身，而是回傳**儲存在 PFA 中的值**。

**Forth 語意**：`( -- x )`，其中 x 是定義時給定的值。

**堆疊追蹤**：
```
假設 CONSTANT FOO 定義為 42：

定義體結構：
  CFA: JMP _CONSTANT-CODE
  PFA: 42  ← 4 位元組的整數值

執行 FOO 時：
  1. CALL CFA → JMP _CONSTANT-CODE
  2. ESP 指向 PFA 位址
  3. LEA EBP, -4[EBP]; MOV [EBP], EAX  → 推入舊 TOS
  4. POP EAX → EAX = PFA 位址
  5. MOV EAX, [EAX] → EAX = 42
  6. RET → 繼續執行下一個字
```

#### 2.2.3 USER — `_USER-CODE`

```asm
CODE _USER-CODE
     LEA  EBP, -4 [EBP]    ; 堆疊往深推一層
     MOV  [EBP], EAX        ; 舊 TOS → 次項
     POP EAX                ; PFA 位址 → EAX
     MOV EAX, [EAX]         ; 讀取 USER 變數的偏移量
     LEA EAX, [EDI] [EAX]   ; EDI + 偏移量 = USER 變數的絕對位址
     RET
END-CODE
```

**行為**：USER 變數的 PFA 中儲存的是**相對於 TLS 基底（EDI）的偏移量**。執行時，將 EDI 加上偏移量計算出絕對位址。

**為什麼要用 USER 變數？**

在多執行緒環境中，每個執行緒需要自己的「全域」變數副本。傳統做法是使用作業系統的 TLS API（如 `pthread_getspecific`/`TlsGetValue`），但每次存取都需要函數呼叫，開銷很大。SP-Forth 將 TLS 基底指標放在 EDI 中，使得 USER 變數的存取只需要一條 `LEA` 指令：

```asm
LEA EAX, [EDI][EAX]  ; 一條指令完成 USER 變數定位！
```

這比呼叫 `pthread_getspecific()` 快大約 10~50 倍。

**執行緒切換**：當執行緒切換時，只需更新 EDI 暫存器即可：

```asm
; 進入 Forth 執行緒
MOV EDI, [TLS_block_address]   ; 設定 EDI 為新執行緒的 TLS 基底
; ... 執行 Forth 程式碼 ...
; 離開 Forth 執行緒
; EDI 不需要恢復，因為 C 呼叫約定中 EDI 是被呼叫者儲存的
```

#### 2.2.4 VECT — `_VECT-CODE`

```asm
CODE _VECT-CODE
     POP EBX               ; 從回返堆疊取出 PFA 位址
     JMP [EBX]             ; 從 PFA 讀取執行向量並跳躍
END-CODE
```

**行為**：VECT（向量/延遲字）是一種可以重新導向的字。PFA 中儲存的是另一個字的 **XT（執行令牌，execution token）**。執行時直接跳到該 XT 指向的程式碼。

**Forth 中的 VECT 類似於其他語言的函數指標或虛函數**。例如：

```forth
VECT TYPE     \ 定義一個向量，初始指向 NOOP
' TYPE1 ' TYPE TC-VECT!   \ 將 TYPE 重新導向到 TYPE1
```

這使得 SP-Forth 可以在執行期動態改變字的行為，而不用修改所有呼叫點。

#### 2.2.5 TO + VALUE — `_TOVALUE-CODE`

```asm
CODE _TOVALUE-CODE
     POP EBX               ; CALL _TOVALUE-CODE 之後的返回位址
     LEA EBX, -9 [EBX]     ; 回退 9 bytes，落到 value cell
     MOV [EBX], EAX         ; 寫入新值
     MOV EAX, [EBP]         ; 恢復 TOS
     LEA EBP, 4 [EBP]      ; 彈出堆疊
     RET
END-CODE
```

**行為**：`TO` 用於修改 VALUE 定義的目前值。`_TOVALUE-CODE` 的關鍵不是「沿著名稱欄位回推」，而是利用 CALL/RET 慣例，從返回位址回推到 VALUE 內嵌的 value cell。

更精確地說，`_TOVALUE-CODE` 是利用 **CALL/RET 傳遞內嵌資料位址** 的慣例來找回 VALUE 的儲存格，而不是從名稱欄位或旗標欄位回推。

**VALUE 執行體佈局**（從該字的執行碼起點開始）：
```
+0  ~ +4   CALL _CONSTANT-CODE   ← 執行 VALUE 時讀取值
+5  ~ +8   value cell            ← 真正儲存目前值的位置
+9  ~ +13  CALL _TOVALUE-CODE    ← 執行 TO name 時走這條路徑
```

當 `_TOVALUE-CODE` 執行時：
1. `POP EBX` 取到的是 **第二個 CALL 的返回位址**，也就是 `+14`
2. `LEA EBX, -9 [EBX]` 將位址回退 9 位元組
3. 回退後恰好落在 `value cell`（`+5`）

因此 `-9` 的意義是：**從 `_TOVALUE-CODE` 呼叫後的位置，回退一個 `CALL rel32`（5 bytes）再回退一個 value cell（4 bytes）**。

#### 2.2.6 SLITERAL — `_SLITERAL-CODE`

```asm
CODE _SLITERAL-CODE
      LEA   EBP, -8 [EBP]      ; 堆疊推入兩項
      MOV   4 [EBP], EAX        ; 舊 TOS → 新的次次項
      POP   EBX                  ; 從回返堆疊取得字串位址
      MOVZX EAX, BYTE [EBX]      ; 讀取計數位元組（字串長度）
      LEA   EBX, 1 [EBX]         ; 跳過計數位元組
      MOV   [EBP], EBX           ; 字串起始位址 → 新的次項
      LEA   EBX, [EBX] [EAX]    ; 計算字串結尾
      LEA   EBX, 1 [EBX]         ; 跳過最後的對齊填充位元組
      JMP   EBX                  ; 跳到字串後的下一個指令
END-CODE
```

**行為**：這是 `S"` 和 `SLITERAL` 的執行期碼。它從資料流中讀取一個計數字串（以長度位元組開頭，以 `0` 位元組結尾的對齊填充），並將其位址和長度推上資料堆疊。

**堆疊效果**：`( -- c-addr u )`

**資料流格式**：
```
┌────────────┬──────────────────┬───┐
│ 計數位元組  │   字串資料        │ 0 │
│ (1 byte)   │  (u bytes)       │   │
└────────────┴──────────────────┴───┘
```

**為什麼要 `JMP EBX` 而不是 `RET`？**

因為字串資料直接內嵌在程式碼流中（threaded code），所以執行完畢後需要跳過字串資料繼續執行下一個指令。如果用 `RET`，會導致 ESP 指向字串資料中間，產生錯誤。這是 Forth 執行緒式碼中常見的「內嵌資料」技術。

---

## 3. Forth 程序核心（spf_forthproc.f）深入解析

此檔案包含 SP-Forth 的所有基本操作原語，共約 1500 行，幾乎全部以 `CODE ... END-CODE` 撰寫（即內聯 x86 組合語言）。

### 3.1 堆疊操作原語的指令級分析

#### 3.1.1 DUP — 堆疊複製

```asm
CODE DUP ( x -- x x ) \ 94
     LEA EBP, -4 [EBP]    ; EBP -= 4（堆疊向下增長）
     MOV [EBP], EAX        ; 將 EAX 存入新的次項位置
     RET
END-CODE
```

**指令分析**：
- `LEA EBP, -4[EBP]`：1 微操作，1 時脈週期（Pentium Pro+），0 記憶體存取
- `MOV [EBP], EAX`：1 微操作，1 時脈週期，1 次記憶體寫入
- `RET`：1 微操作

**總計**：3 條指令，2 次記憶體存取（1 寫入 + 可能的快取命中）

**與傳統堆疊模型比較**：
```
傳統模型（TOS 在記憶體中）：
  PUSH [ESP]     ; 1 次讀取 + 1 次寫入
  或
  MOV EAX, [ESP]
  SUB ESP, 4
  MOV [ESP], EAX    ; 4 條指令，3 次記憶體存取

SP-Forth 模型（TOS 在 EAX 中）：
  LEA EBP, -4[EBP]  ; 1 條指令
  MOV [EBP], EAX    ; 1 條指令
  RET                ; 1 條指令
  總計：3 條指令，1 次記憶體寫入
```

**Forth 語意**：`( x -- x x )` 複製堆疊頂端元素。這是 Forth 中最常用的操作之一，在直譯器和編譯器中頻繁使用。

#### 3.1.2 DROP — 堆疊丟棄

```asm
CODE DROP ( x -- ) \ 94
     MOV EAX, [EBP]        ; 次項 → 新 TOS
     LEA EBP, 4 [EBP]     ; EBP += 4（堆疊彈出）
     RET
END-CODE
```

**行為**：丟棄堆疊頂端元素。原來的次項 `[EBP]` 成為新的 TOS。

#### 3.1.3 SWAP — 堆疊交換

```asm
CODE SWAP ( x1 x2 -- x2 x1 ) \ 94
      MOV   EDX, [EBP]    ; EDX = x1（次項）
      MOV   [EBP], EAX    ; [EBP] = x2（新次項 = 舊 TOS）
      MOV   EAX, EDX      ; EAX = x1（新 TOS = 舊次項）
      RET
END-CODE
```

**注意**：原始碼第 122 行有一個被註解掉的替代方案 `XCHG EAX, [EBP]`。為什麼不使用 `XCHG`？

因為 `XCHG` 指令在 x86 中，當第二個運算元是記憶體時，會隱含 `LOCK` 前綴，導致匯流排鎖定，影響多處理器效能。使用 `MOV` 序列避免了這個問題。

#### 3.1.4 ROT — 三項旋轉

```asm
CODE ROT ( x1 x2 x3 -- x2 x3 x1 ) \ 94
      MOV  EDX, [EBP]     ; EDX = x1
      MOV  [EBP], EAX     ; [EBP] = x3（新次項 = 舊 TOS）
      MOV  EAX, 4 [EBP]   ; EAX = x2（新 TOS = 原第三項）
      MOV  4 [EBP], EDX   ; [EBP+4] = x1（新第三項 = 原第一項）
      RET
END-CODE
```

**Forth 語意**：將第三個堆疊項旋轉到頂端。這在迴圈和條件結構中非常有用。

**替代語法**：`UNROT`（或 `-ROT`）是反向旋轉：`( x1 x2 x3 -- x3 x1 x2 )`，這是 2025 年 Forth 標準提案中加入的。

#### 3.1.5 PICK — 堆疊索引存取

```asm
CODE PICK ( xu ... x1 x0 u -- xu ... x1 x0 xu ) \ 94 CORE EXT
        MOV     EAX, [EBP] [EAX*4]
     RET
END-CODE
```

**這條指令只有一條有效指令**（不計 `RET`）！`[EBP][EAX*4]` 是 x86 的 SIB 定址模式，直接從堆疊中按照索引取出元素。注意這裡的索引是以 0 為基礎的：`0 PICK` 等於 `DUP`。

### 3.2 比較原語的精巧實作

SP-Forth 的比較原語使用了 x86 標誌旗標的巧妙組合，避免了條件跳躍指令（分支預測失敗的代價）。

#### 3.2.1 `=` — 等於比較

```asm
CODE = ( x1 x2 -- flag ) \ 94
      XOR  EAX, [EBP]     ; EAX = x1 XOR x2
      SUB  EAX, # 1       ; 若相等則 EAX = -1，否則 EAX >= 0
      SBB  EAX, EAX       ; 若相等則 EAX = -1，否則 EAX = 0
      LEA  EBP, 4 [EBP]   ; 彈出次項
      RET
END-CODE
```

**這是一個非常巧妙的無分支（branchless）實作**。逐步分析：

1. `XOR EAX, [EBP]`：若 x1 == x2，則結果為 0
2. `SUB EAX, #1`：若 x1 == x2（XOR 結果為 0），則結果為 -1（0xFFFFFFFF），借位旗標 CF=1；否則結果為非負值（`>= 0`），CF=0
3. `SBB EAX, EAX`：EAX = EAX - EAX - CF。由於 `EAX - EAX = 0`，所以結果其實就是 `-CF`：若 CF=1（相等）則結果為 -1；若 CF=0（不等）則結果為 0

**結果**：x1 == x2 時回傳 -1（TRUE），否則回傳 0（FALSE）。這符合 Forth 標準中真值為全位元 1（-1）的規定。

#### 3.2.2 `0=` — 零值比較

```asm
CODE 0= ( x -- flag ) \ 94
      SUB   EAX, # 1      ; 若 x == 0，則 -1 減 0 產生借位 CF=1
      SBB   EAX, EAX      ; EAX = 0 - 0 - CF = -CF
      RET
END-CODE
```

又是無分支實作！只有 2 條有效指令。

#### 3.2.3 `U<` — 無號小於比較

```asm
CODE U< ( u1 u2 -- flag ) \ 94
      CMP  [EBP], EAX     ; 比較 u1 和 u2（無號）
      SBB  EAX, EAX       ; 若 u1 < u2（借位），EAX = -1；否則 EAX = 0
      LEA  EBP, 4 [EBP]
      RET
END-CODE
```

**巧妙之處**：`CMP` 指令在 u1 < u2 時設定借位旗標 CF=1，`SBB EAX, EAX` 利用此旗標直接產生 0 或 -1。

#### 3.2.4 `WITHIN` — 範圍檢查

```asm
CODE WITHIN ( n1 low high -- f1 )
      MOV  EDX, 4 [EBP]   ; EDX = n1
      SUB  EAX, [EBP]     ; EAX = high - low
      SUB  EDX, [EBP]     ; EDX = n1 - low
      SUB  EDX, EAX       ; EDX = (n1 - low) - (high - low) = n1 - high
                           ; 借位判斷：若 n1 >= low 且 n1 < high
      SBB  EAX, EAX       ; 結果為 -1 或 0
      LEA  EBP, 8 [EBP]   ; 彈出兩項
      RET
END-CODE
```

**這是目前已知最快速的 `WITHIN` 實作**，只需 5 條指令且無分支。

### 3.3 MAX/MIN 的 P6 條件搬移最佳化

```asm
CODE MAX ( n1 n2 -- n3 ) \ 94
ARCH-P6 [IF]
      MOV     EDX, [EBP]    ; EDX = n1
      CMP     EDX, EAX      ; 比較 n1 和 n2
      CMOVG   EAX, EDX      ; 若 n1 > n2，EAX = n1
[ELSE]
      CMP     EAX, [EBP]    ; 比較 n2 和 n1
      JL # ' DROP           ; 若 n2 < n1，跳到 DROP（EAX = n1）
[THEN]
      LEA EBP, 4 [EBP]     ; 彈出次項
      RET
END-CODE
```

當 `ARCH-P6` 為 TRUE（Pentium Pro 及以後的處理器）時，使用 `CMOV` 條件搬移指令，完全消除分支預測失敗的風險。舊的處理器路徑使用條件跳躍到 `DROP` 的程式碼（程式碼共享最佳化）。

### 3.4 記憶體存取原語的深入分析

#### 3.4.1 `@` — 讀取儲存格

```asm
CODE @ ( a-addr -- x ) \ 94
      MOV EAX, [EAX]    ; 直接從位址讀取 32 位元值
     RET
END-CODE
```

**這是整個 SP-Forth 中最簡短的原語之一**——只有 1 條有效指令加 1 條 `RET`。因為 TOS 就是位址，直接用 `[EAX]` 間接定址即可。

#### 3.4.2 `!` — 寫入儲存格

```asm
CODE ! ( x a-addr -- ) \ 94
      MOV EDX, [EBP]     ; EDX = x（次項 = 值）
      MOV [EAX], EDX     ; *a-addr = x
      MOV EAX, 4 [EBP]   ; EAX = 新 TOS（第三項）
      LEA EBP, 8 [EBP]   ; 彈出兩項
      RET
END-CODE
```

注意 `!` 需要彈出兩項（值和位址），所以需要從堆疊中取回第三項作為新的 TOS。

#### 3.4.3 `+!` — 原子加法

```asm
CODE +! ( n|u a-addr -- ) \ 94
      MOV EDX, [EBP]   ; EDX = n
      ADD [EAX], EDX   ; *a-addr += n（x86 LOCK 隱含，但單處理器無影響）
      MOV EAX, 4 [EBP] ; 新 TOS
      LEA EBP, 8 [EBP] ; 彈出兩項
      RET
END-CODE
```

`ADD [EAX], EDX` 是一條讀取-修改-寫入指令，在多處理器環境中可能需要 `LOCK` 前綴以保證原子性，但 SP-Forth 目前未添加 `LOCK`。

### 3.5 算術原語的深入分析

#### 3.5.1 `*` — 乘法

```asm
CODE * ( n1|u1 n2|u2 -- n3|u3 ) \ 94
      IMUL DWORD [EBP]   ; EAX = EAX * [EBP]（帶號 32 位元乘法）
      LEA EBP, 4 [EBP]   ; 彈出次項
      RET
END-CODE
```

`IMUL` 是 x86 的帶號乘法指令，其單運算元形式將結果截斷為 32 位元存入 EAX。這對於 Forth 的 `*` 操作已經足夠，因為 Forth 標準只要求 32 位元的低位部分結果。

**雙精確度乘法**由 `M*` 和 `UM*` 提供：

```asm
CODE M* ( n1 n2 -- d ) \ 94
      IMUL DWORD [EBP]   ; EDX:EAX = n1 * n2（64 位元結果）
      MOV  [EBP], EAX    ; 低 32 位元 → 堆疊次項
      MOV  EAX, EDX      ; 高 32 位元 → TOS
      RET
END-CODE
```

#### 3.5.2 `2/` — 算術右移

```asm
CODE 2/ ( x1 -- x2 ) \ 94
      D1 C, F8 C,  \   SAR EAX, # 1
      RET
END-CODE
```

**注意這裡的編碼方式**：`D1 C, F8 C,` 直接輸出 x86 機器碼位元組 `0xD1 0xF8`，這是 `SAR EAX, 1` 的編碼。這是因為 SP-Forth 的組譯器可能不支援某些指令的助記符，所以直接輸出機器碼。

`SAR`（算術右移）保留符號位，與 `SHR`（邏輯右移）不同。例如 `-4 2/` 會得到 `-2`（正確），而 `-4 U2/` 會得到 `2147483646`（大正數）。

### 3.6 迴圈原語的深入分析

#### 3.6.1 `C-DO` — DO 迴圈核心

```asm
CODE C-DO
   LEA EBP, 8 [EBP]     ; 彈出兩項（界限和索引）
   MOV  EBX, EAX         ; EBX = 索引（TOS）
   ADD  EAX, # 80000000  ; EAX = 索引 + 0x80000000（調整為無號比較）
   SUB  EAX, -8 [EBP]    ; EAX = (索引 + 0x80000000) - (界限 + 0x80000000)
   MOV  EDX, EAX         ; EDX = 迴圈計數器
   MOV  EAX, -4 [EBP]    ; EAX = 繼續執行的返回值
   MOV  EDX, EDX          ; NOP（最佳化器的佔位符）
   RET                    ; 返回到迴圈體開始
END-CODE
```

**為什麼要加 `0x80000000`？**

這是為了將帶號整數的比較轉換為無號整數的比較。Forth 的 `DO` 迴圈允許界限和索引的任意組合（如 `3 10 DO ... LOOP` 或 `10 3 DO ... -1 +LOOP`）。將界限和索引都加上 `0x80000000` 後，帶號比較就變成無號比較，使得溢位檢測可以用一個簡單的 `JNO`（不溢位則跳躍）指令來實現。

**迴圈範例**：
```forth
10 0 DO I . LOOP
```
編譯後的迴圈體：
```asm
; DO 部分（C-DO + PUSH 界限/索引）
; ... 迴圈體 ...
; LOOP 部分：
   INC DWORD [ESP]        ; 索引++
   INC DWORD 4[ESP]       ; 界限計數器++
   JNO loop_start          ; 若無溢位則繼續
   LEA ESP, 0xC[ESP]      ; 清理迴圈參數
```

#### 3.6.2 `C-?DO` — 條件 DO 迴圈

```asm
CODE C-?DO
      CMP  EAX, -8 [EBP]   ; 比較索引與界限
      JNZ  SHORT @@1         ; 若不相等則進入迴圈
      MOV  EAX, -4 [EBP]    ; 若相等則跳過迴圈
      JMP  EBX               ; EBX 是迴圈後的指令位址
@@1:  PUSH EBX               ; 保存迴圈後的位址
      ; ... 同 C-DO ...
END-CODE
```

`?DO` 在界限等於索引時不進入迴圈，直接跳到 `LOOP` 之後的程式碼。

### 3.7 LOCALS（區域變數）原語

SP-Forth 的 LOCALS 實作使用回返堆疊來儲存區域變數的值，避免在資料堆疊上混雜區域變數和臨時值。

#### 3.7.1 `N>R` / `NR>` — 區域變數存取

```asm
CODE N>R ( D: x1..xn n -- R: x1..xn n )
      LEA  EBP, -4 [EBP]    ; 推入 n 到資料堆疊
      MOV  [EBP], EAX
      LEA EAX, 4 [EAX*4]   ; EAX = (n+1) * 4 = 需要的位元組數
      POP  EDX               ; EDX = 返回位址
      MOV  ESI, EAX         ; ESI = 位元組計數器
@@1:
      PUSH -4 [EBP] [ESI]   ; 從資料堆疊複製到回返堆疊
      SUB  ESI, # 4
      JNZ  SHORT @@1
      ADD  EBP, EAX         ; 調整資料堆疊指標
      MOV  EAX, [EBP]
      LEA  EBP, 4 [EBP]
      JMP  EDX
END-CODE
```

### 3.8 特殊原語

#### 3.8.1 `(ENTER)` — 回呼函數進入點

```asm
CODE (ENTER) ( {4*params ret_addr} -- 4*params R: ret_addr ebp )
      POP  EBX              ; 保存 Forth 返回位址
      POP  ESI              ; 保存 C 回呼返回位址
      MOV  EAX, EBP         ; EAX = 舊的 EBP（將推入資料堆疊）
      MOV  EBP, ESP         ; EBP = ESP（建立新的 Forth 堆疊框架）

      XOR  EDX, EDX         ; 清零
      MOV  ECX, # 32        ; 32 個儲存格
@@1: PUSH EDX                ; 分配 32 * 4 = 128 位元組的堆疊空間
      DEC  ECX
      JNZ  @@1

      PUSH ESI              ; C 返回位址
      PUSH EAX              ; 舊的 EBP
      MOV EAX, [EBP]        ; 載入第一個參數到 TOS
      LEA EBP, 4 [EBP]      ; 調整 EBP
      JMP  EBX              ; 跳到 Forth 字的程式碼
END-CODE
```

**(ENTER)** 是 C 語言回呼函數的進入點，它做了以下幾件事：

1. 保存 Forth 的 EBP 和返回位址
2. 將 ESP 作為新的 Forth 資料堆疊基底
3. 在 Forth 堆疊上分配 128 位元組的工作空間
4. 將 C 回呼的返回位址和舊的 EBP 推入 Forth 資料堆疊
5. 跳到 Forth 字的程式碼開始執行

這種設計使得 Forth 字可以作為 Windows 訊息處理器或 C 語言回呼函數。

#### 3.8.2 `TRAP-CODE` — CATCH 例外恢復

```asm
CODE TRAP-CODE ( D: j*x u R: i*x i -- i*x u )
      POP  EDX           ; 恢復返回位址
      POP  ESI            ; ESI = n（要恢復的項數）
      OR   ESI, ESI      ; n == 0？
      JZ   @@2            ; 若是，跳過恢復
      LEA  ESI, [ESI*4]  ; ESI = n * 4（位元組數）
      MOV  ECX, ESI
@@1: MOV  EBX, -4 [ESI] [ESP]   ; 從回返堆疊複製到資料堆疊
      MOV  -4 [ESI] [EBP], EBX
      SUB  ESI, # 4
      JNZ  SHORT @@1
      ADD  ESP, ECX       ; 調整回返堆疊
@@2: JMP  EDX
END-CODE
```

這是 `CATCH`/`THROW` 的核心恢復碼。當 `THROW` 被呼叫時，它恢復資料堆疊和回返堆疊到 `CATCH` 設定的檢查點，然後將例外碼推上資料堆疊。

---

## 4. 浮點運算核心（spf_floatkern.f）深入解析

### 4.1 x87 FPU 與 Forth 浮點堆疊的介面

SP-Forth 使用 x87 FPU 的 80 位元擴充精度格式進行所有浮點運算。FPU 暫存器 ST(0)~ST(7) 構成獨立的浮點堆疊，與資料堆疊（EBP/EAX）分離。

**堆疊互動模型**：

```
資料堆疊 ←→ FPU 堆疊 的轉換：
  S>F  ：( S: n -- ; F: -- r )    整數 → 浮點
  F>S  ：( F: r -- ; S: -- n )    浮點 → 整數（四捨五入）
  D>F  ：( S: d -- ; F: -- r )    雙精確度整數 → 浮點
  F>D  ：( F: r -- ; S: -- d )    浮點 → 雙精確度整數
```

### 4.2 浮點比較的實作細節

#### F0= — 測試浮點零值

```asm
CODE F0=
      LEA EBP, -4 [EBP]    ; 推入結果空間
      MOV [EBP], EAX        ; 保存舊 TOS
      XOR EBX, EBX          ; EBX = 0（預設結果為 FALSE）
      FTST                  ; 測試 ST(0) 是否為零
      FFREE ST              ; 釋放 ST(0)
      FINCSTP               ; 調整 FPU 堆疊指標
      FSTSW EAX             ; 將 FPU 狀態字存入 EAX
      SAHF                  ; 將 AH 載入 x86 標誌暫存器
      JNZ SHORT @@1         ; 若非零則跳轉
      MOV EBX, # -1         ; 若為零，EBX = -1（TRUE）
@@1:   MOV EAX, EBX          ; 結果 → EAX
      RET
END-CODE
```

**步驟解析**：
1. `FTST`：比較 ST(0) 與 0.0，設定 FPU 狀態字中的 C0、C2、C3 條件碼
2. `FFREE ST + FINCSTP`：等效於 `FSTP ST(0)`，但不移動數值（避免精度問題）
3. `FSTSW EAX`：將 FPU 狀態字的低 16 位元載入 AX
4. `SAHF`：將 AH 載入 x86 的標誌暫存器，使得 FPU 比較結果可以用 x86 條件跳躍指令來判斷
5. `JNZ`：若 ST(0) 不為零，跳轉保持 EBX=0

**為什麼要用 `FFREE + FINCSTP` 而不是 `FSTP ST(0)`？**

因為在某些 x87 實作中，`FSTP` 可能會對數值進行不必要的捨入，而 `FFREE + FINCSTP` 只是標記暫存器為空，避免任何精度損失。

### 4.3 FEXP — 指數函數的精巧實作

```asm
CODE FEXP
      FLDL2E                ; ST(0) = log₂(e), ST(1) = x
      FMULP ST(1), ST(0)   ; ST(0) = x * log₂(e)
      LEA EBP, -4 [EBP]     ; 設定截斷捨入模式
      MOV [EBP], EAX
      FSTCW  DWORD -4 [EBP] ; 保存目前 FPU 控制字
      MOV EAX, -4 [EBP]
      AND AH, # 0F3          ; 清除捨入模式位元
      OR  AH, # 0C           ; 設定截斷模式（RC=11）
      MOV -8 [EBP], EAX
      FLDCW DWORD -8 [EBP]  ; 載入新控制字
      FLD ST(0)              ; ST(0) = n, ST(1) = x*log₂(e) 的整數部分
      FRNDINT                ; ST(0) = n（整數部分）
      FXCH ST(1)             ; ST(0) = f, ST(1) = n（小數部分）
      FSUB ST(0), ST(1)      ; ST(0) = f = x*log₂(e) - n
      F2XM1                  ; ST(0) = 2^f - 1
      FLD1                   ; ST(0) = 1, ST(1) = 2^f - 1
      FADDP ST(1), ST(0)    ; ST(0) = 2^f
      FSCALE                  ; ST(0) = 2^f * 2^n = 2^(f+n) = e^x
      FXCH ST(1)             ; 清理
      FCOMP ST(1)
      FLDCW DWORD -4 [EBP]  ; 恢復原來的 FPU 控制字
      MOV EAX, [EBP]
      LEA EBP, 4 [EBP]
      RET
END-CODE
```

**演算法分析**：

`e^x = 2^(x * log₂(e))`

但是 x87 FPU 的 `F2XM1` 指令只接受 -1 ≤ ST(0) ≤ 1 的輸入，所以需要將指數分解為整數部分和小數部分：

1. 計算 `t = x * log₂(e)`
2. 分解 `t = n + f`，其中 n 是整數部分，f 是小數部分
3. 計算 `2^f - 1`（使用 `F2XM1`）
4. 計算 `2^f = (2^f - 1) + 1`
5. 計算 `e^x = 2^f * 2^n`（使用 `FSCALE`）

**為什麼要切換捨入模式？**

因為 `FRNDINT` 需要「截斷」模式（向零捨入），以確保整數部分正確。FPU 預設的捨入模式是「最近偶數」，這會導致 `FRNDINT(0.5) = 0`（而不是 1），使指數函數計算出錯。

### 4.4 浮點常值編碼

#### `_FLIT-CODE8` — 8 位元組浮點常值

```asm
CODE _FLIT-CODE8
      POP  EBX             ; 從資料流取得浮點數位址
      FLD  QWORD [EBX]     ; 載入 64 位元 IEEE 754 double
      ADD  EBX, # 8        ; 跳過 8 位元組資料
      JMP  EBX              ; 跳到下一個指令
END-CODE
```

#### `_FLIT-CODE10` — 10 位元組浮點常值

```asm
CODE _FLIT-CODE10
      POP  EBX             ; 從資料流取得浮點數位址
      FLD  TBYTE [EBX]     ; 載入 80 位元 IEEE 754 extended
      ADD  EBX, # 0A       ; 跳過 10 位元組資料
      JMP  EBX              ; 跳到下一個指令
END-CODE
```

**為什麼有兩種格式？**

x87 FPU 內部使用 80 位元擴充精度格式，但記憶體中可以儲存為 64 位元 double 或 80 位元 extended。`_FLIT-CODE8` 用於 `2.E`、`10.E` 等精確值（使用 64 位元儲存），而 `_FLIT-CODE10` 用於一般浮點常值（保留完整 80 位元精度）。

### 4.5 FPU 控制字操作

SP-Forth 提供了完整的 FPU 控制字操作：

| 字 | 行為 | 用途 |
|----|------|------|
| `SETFPUCW` | `( u -- )` 設定 FPU 控制字 | 改變捨入模式、精度等 |
| `GETFPUCW` | `( -- u )` 取得 FPU 控制字 | 查詢目前 FPU 設定 |
| `TRUNC-MODE` | 設定截斷捨入模式 | 用於 `F>D` 等需要截斷的操作 |
| `ROUND-MODE` | 設定最近偶數捨入模式 | FPU 預設模式 |
| `UP-MODE` | 設定正無限大捨入模式 | 特殊用途 |
| `LOW-MODE` | 設定負無限大捨入模式 | 特殊用途 |

**FPU 控制字的位元佈局**：

```
位元 11-10: RC（捨入控制）
  00 = 最近偶數（ROUND-MODE）
  01 = 負無限大（LOW-MODE）
  10 = 正無限大（UP-MODE）
  11 = 截斷（TRUNC-MODE）
位元 9-8: PC（精度控制）
  00 = 單精度
  01 = 保留
  10 = 雙精度
  11 = 擴充精度（預設）
位元 0-5: 例外遮罩
```

---

## 5. 高階 Forth 程序（spf_forthproc_hl.f）深入解析

### 5.1 HASH — FNV-1 雜湊函數

```forth
: HASH ( addr u u1 -- u2 )
   2166136261 2SWAP OVER + SWAP
   ?DO 16777619 * I C@ XOR LOOP
   SWAP ?DUP IF UMOD THEN
;
```

**FNV-1 演算法**：

- 初始值：2166136261（FNV offset basis，32 位元版本）
- 乘數常數：16777619（FNV prime，32 位元版本）
- 流程：對每個位元組執行 `hash = (hash * FNV_prime) XOR byte`
- 最後若指定了模數 `u1`，則執行 `UMOD` 取餘數

**用途**：此雜湊函數用於字詞搜尋（word lookup），在詞彙表的雜湊鍊中快速定位字詞。

### 5.2 換行模式

```forth
HEX
CREATE LT 0A0D , \ line terminator（CRLF）
CREATE LTL 2 ,   \ line terminator length（2 位元組）

: DOS-LINES ( -- ) 0A0D LT ! 2 LTL ! ;
: UNIX-LINES ( -- ) 0A0A LT ! 1 LTL ! ;

: EOLN ( -- a u ) LT LTL @ ;
```

SP-Forth 支援兩種換行模式：
- **DOS 模式**：CRLF（0x0D 0x0A），2 位元組
- **UNIX 模式**：LF（0x0A），1 位元組

`LT` 和 `LTL` 使用 `CREATE` 建立可修改的記憶體區域，而不是 `CONSTANT`，這使得換行模式可以在執行期動態切換。

`NATIVE-LINES` 根據 `UNIX-ENVIRONMENT` 自動選擇正確的換行模式。

### 5.3 `MOVE` — 智慧記憶體搬移

```forth
: MOVE ( addr1 addr2 u -- ) \ 94
  >R 2DUP SWAP R@ + U<  \ 檢查目標是否在來源的低位址
  IF 2DUP U<              \ 來源比目標低位址？
     IF R> CMOVE> ELSE R> CMOVE THEN
  ELSE R> CMOVE THEN
;
```

**為什麼需要「智慧」搬移？**

當來源區域和目標區域重疊時（例如將陣列中的元素向低位址平移），順向複製（CMOVE）會破壞尚未搬移的資料。`MOVE` 透過比較位址來決定使用順向（CMOVE）或反向（CMOVE>）複製，確保重疊區域的正確性。

### 5.4 NUMBER 轉換相關

```forth
: >NUMBER ( ud1 c-addr1 u1 -- ud2 c-addr2 u2 ) \ 94
  BEGIN
    DUP
  WHILE
    >R DUP >R
    C@ BASE @ DIGIT 0=     \ 嘗試將字元轉為數字
    IF R> R> EXIT THEN     \ 失敗：回傳
    SWAP BASE @ UM* DROP   \ ud_low * base
    ROT BASE @ UM* D+      \ (n*ud_high*base) + carry
    R> CHAR+ R> 1-         \ 前進到下一字元
  REPEAT
;
```

**演算法**：對每個字元：
1. 使用 `DIGIT` 將字元轉換為數值
2. 將目前的雙精確度結果乘以基數
3. 加上新的數值
4. 繼續直到所有字元處理完畢或遇到非法字元

`DIGIT` 原語支援 2~36 進位，處理 0-9、A-Z（或 a-z）的轉換。

---

## 6. 架構特點深入分析

### 6.1 TOS 快取模型的效能影響

以一個簡單的 Forth 片段 `OVER +` 為例：

**傳統堆疊模型（TOS 在記憶體中）**：
```asm
; OVER
MOV EAX, [ESP+4]    ; 讀取次項
PUSH EAX            ; 推入副本
; +
POP ECX             ; 彈出 TOS
POP EAX             ; 彈出次項
ADD EAX, ECX        ; 加法
PUSH EAX            ; 推入結果
; 總計：5 條指令，5 次記憶體存取
```

**SP-Forth TOS 快取模型**：
```asm
; OVER
LEA EBP, -4[EBP]    ; 堆疊向深推一層
MOV [EBP], EAX      ; 存入原 TOS
MOV EAX, 4[EBP]     ; 讀取新的次項（原第三項）→ 新 TOS
; +
ADD EAX, [EBP]      ; TOS + 次項
LEA EBP, 4[EBP]     ; 彈出次項
; 總計：5 條指令，3 次記憶體存取
```

指令數相同，但記憶體存取減少了 40%，這在快取未命中時的效能差異更加顯著。

### 6.2 回返堆疊與 Forth 迴圈模型

SP-Forth 的 DO...LOOP 迴圈使用回返堆疊儲存三個值：

```
回返堆疊（由 ESP 指向）：

  ESP+12  ← 迴圈界限（limit）
  ESP+8   ← 迴圈索引（index，已偏移 0x80000000）
  ESP+4   ← 迴圈後的返回位址（由 DO 的 inline PUSH 放入）
  ESP+0   ← 目前字的返回位址
```

C-DO 將索引加上 `0x80000000` 的偏移量，使得帶號比較可以用無號溢位（`JNO`）來檢測迴圈結束。這是一個非常聰明的最佳化技巧：

```
帶號迴圈：10 0 DO ... LOOP
  索引偏移：0 + 0x80000000 = 0x80000000
  界限偏移：10 + 0x80000000 = 0x8000000A
  每次迭代後 INC [ESP] 使索引+1
  當索引遞增到界限時，INC 不會產生溢位，JNO 繼續迴圈
  當索引超過界限時（0x8000000A → 0x8000000B），JNO 仍然不會跳
  但當索引從 0x7FFFFFFF 遞增到 0x80000000 時會溢位，JNO 跳出迴圈
```

**LOOP 的編譯輸出**：
```asm
INC DWORD [ESP]        ; 索引++
INC DWORD 4[ESP]      ; 界限計數器++
JNO loop_start          ; 若無溢位（未完成迴圈），繼續
LEA ESP, 0xC[ESP]      ; 清理迴圈參數（3 個值）
```

### 6.3 執行緒安全與 TLS 實作

SP-Forth 的多執行緒模型依賴 EDI 暫存器作為 TLS 基底：

```
每個執行緒的記憶體佈局：

  +0    TlsIndex（TLS 索引）
  +4    USER 變數 0（例如 HLD）
  +8    USER 變數 1（例如 BASE）
  ...   更多 USER 變數
  +N    堆疊空間
```

`TlsIndex!` 和 `TlsIndex@` 原語直接操作 EDI：

```asm
CODE TlsIndex! ( x -- )
     MOV EDI, EAX        ; 設定 TLS 基底指標
     MOV EAX, [EBP]       ; 恢復 TOS
     LEA EBP, 4 [EBP]     ; 彈出堆疊
     RET
END-CODE
```

當切換執行緒時，只需要一條 `MOV EDI, new_thread_data` 指令即可切換所有 USER 變數的基底。這比呼叫 `pthread_getspecific()` 或 `TlsGetValue()` 快得多。

**與 POSIX 信號處理的連接**：`TlsIndex!` 的核心操作 `MOV EDI, EAX` 與 POSIX 信號處理中的 `CONTEXT_EDI + @ TlsIndex!`（詳見 [04-posix-platform.md §12.2](04-posix-platform.md#122-errsignal信號處理器)）形成對稱——後者在信號發生時從 `ucontext_t` 恢復 EDI，確保 THROW 能正確存取目前執行緒的 USER 變數。兩個方向使用同一個 EDI 暫存器作為 TLS 基底，保證了 SP-Forth 例外機制與多執行緒模型的一致性。

### 6.4 FPU 狀態保存與恢復

在 `F>D`（浮點轉雙精確度整數）的高階包裝中：

```forth
: F>D  ( F: r -- ;  S: -- d ) \ 94 FLOATING
        GETFPUCW >R         ; 保存目前 FPU 控制字
        TRUNC-MODE           ; 切換到截斷模式
        F>D                  ; 執行轉換
        R> SETFPUCW          ; 恢復原來的控制字
;
```

這確保了 `F>D` 使用截斷捨入（向零捨入），符合 Forth 標準的要求，而不影響程式其他部分的捨入模式。

### 6.5 `ASCIIZ>` — C 字串長度計算

```asm
CODE ASCIIZ> ( c-addr -- c-addr u )
        LEA  EBP, -4 [EBP]   ; 堆疊推入空間
        MOV  EDX, EAX          ; EDX = 起始位址
@@1:   MOV  CL, [EAX]        ; 讀取一個位元組
        LEA  EAX, 1 [EAX]     ; EAX++
        OR   CL, CL            ; 測試是否為零
        JNZ  SHORT @@1        ; 非零則繼續
        LEA  EAX, -1 [EAX]   ; 回退到零位元組的前一位
        SUB  EAX, EDX         ; EAX = 長度
        MOV  [EBP], EDX       ; 堆疊次項 = 起始位址
        RET
END-CODE
```

**行為**：計算 ASCIIZ（null-terminated）字串的長度，回傳位址和長度（`( c-addr -- c-addr u )`），這是 C 語言 `strlen()` 的 Forth 等價物。

---

## 7. 比較運算子的無分支（branchless）技術

SP-Forth 大量使用 `SBB`（帶借位減法）指令來實作無分支的布林運算，這是 x86 組合語言中的經典技巧：

**原理**：`SBB reg, reg` 在借位旗標 CF=0 時結果為 0，在 CF=1 時結果為 -1。

| 運算 | 實作 | 回傳值 |
|------|------|--------|
| 等於（`=`） | `XOR EAX,[EBP]; SUB EAX,#1; SBB EAX,EAX` | 0 或 -1 |
| 不等於（`<>`） | `XOR EAX,[EBP]; NEG EAX; SBB EAX,EAX` | 0 或 -1 |
| 無號小於（`U<`） | `CMP [EBP],EAX; SBB EAX,EAX` | 0 或 -1 |
| 零值等於（`0=`） | `SUB EAX,#1; SBB EAX,EAX` | 0 或 -1 |
| 非零（`0<>`） | `NEG EAX; SBB EAX,EAX` | 0 或 -1 |

**這種技術的優勢**：完全避免了分支預測失敗的風險。在現代 x86 處理器中，分支預測失敗的代價是 15~20 個時脈週期，而無分支實作的代價是固定的 2~4 個時脈週期。

**Forth 的真值慣例**：Forth 標準規定真值為 `-1`（所有位元為 1，即 `0xFFFFFFFF`），假值為 `0`。這使得布林運算可以直接使用位元運算（AND、OR、XOR）而不需要額外的正規化步驟。

---

## 8. 原始碼對照速查表

| 原始碼檔案 | 行數 | 主要內容 |
|-----------|------|---------|
| `spf_defkern.f` | 138 | 定義字執行碼（CREATE, CONSTANT, USER, VECT, VALUE 等） |
| `spf_forthproc.f` | 1502 | 核心程序原語（堆疊、算術、記憶體、比較、字串、迴圈等） |
| `spf_forthproc_hl.f` | 97 | 高階 Forth 字（FALSE, TRUE, MOVE, HASH, 換行模式等） |
| `spf_floatkern.f` | 688 | 浮點運算原語（x87 FPU 操作、三角函數、比較、轉換等） |
