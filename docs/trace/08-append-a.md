# SP-Forth/4 原始碼追蹤 — 附錄 A：IA-32 組合語言技巧與 SP-Forth 內建組語

> 對應原始碼：`lib/ext/spf-asm.f`、`lib/asm/486asm.f`、`src/spf_defkern.f`、`src/spf_forthproc.f`、`src/compiler/spf_compile.f`、`src/tc_spf.F`、`src/posix/api.f`

> 本章目標：看懂 SP-Forth 原始碼中的 CODE 定義、C, 位元組組裝、以及 LEA 的位址運算技巧。
> 
> 閱讀定位：這一章是 **kernel 開發前的組語暖身**。如果你對 IA-32/x86 組語、`CODE ... END-CODE`、`C,` / `,` 這類寫法還不熟，建議先讀完本章，再進入 [01-kernel.md](01-kernel.md)。

---

## 1. 為什麼先補這章？

`src/*` 裡的核心原語、交叉編譯器與平台橋接大量使用 IA-32 組合語言。  
但 SP-Forth 的原始碼並不是單純把 Intel syntax 直接貼進檔案，而是混合了三層東西：

1. **一般 IA-32 組語觀念**：暫存器、記憶體定址、旗標、`CALL` / `RET`。
2. **SP-Forth 執行模型**：`EAX = TOS`、`EBP = 資料堆疊指標`、`ESP = 回返堆疊`、`EDI = USER/TLS`。
3. **SP-Forth 內建 assembler / metacompiler 寫法**：`CODE ... END-CODE`、`#` 立即數、`C,` / `,`、`RET,`、`A;`。

這章的目標不是把你訓練成 x86 assembler 專家，而是讓你在讀 SP-Forth 原始碼時，能分清楚：

- **哪裡是在寫執行期 machine code**
- **哪裡是在編譯期組裝 machine code**
- **哪裡是 SP-Forth 為了自己的 VM 模型做的特殊技巧**

---

## 2. 先用一般 IA-32 組語來看

### 2.1 先記住最常用的暫存器

| 暫存器 | 一般 IA-32 常見角色 | SP-Forth 裡最重要的角色 |
|--------|----------------------|--------------------------|
| `EAX` | 累加器 / 回傳值 | **TOS（資料堆疊頂端）** |
| `EBP` | 常被拿來當 frame pointer | **資料堆疊指標**，指向次堆疊項 |
| `ESP` | x86 stack pointer | **回返堆疊** |
| `EDI` | 字串 / 目的索引 | **USER / TLS 基底** |
| `EBX` `ECX` `EDX` `ESI` | 通用暫存器 | 依情境當暫存器、計數器、橋接用途 |

如果你只熟悉 C 編譯器輸出的組語，最容易卡住的點是：**SP-Forth 裡的 `EBP` 不是 C 式 frame pointer。**

#### 2.1a 一句話操作模型

讀任何 `CODE` 定義前，先把暫存器翻成這張心智圖：

```text
EAX   = 資料堆疊頂端（TOS）
[EBP] = 資料堆疊次項（second item）
ESP   = 回返堆疊 / x86 call stack
EDI   = USER / TLS 基底
```

所以看到一條指令時，先問：「它是在改 TOS、改次項、改回返堆疊，還是在切換 USER/TLS？」

---

### 2.2 指令先看「語意」，再看語法

先用一般 Intel 風格來看幾條最常見的指令：

```asm
mov eax, [ebp]      ; 從記憶體讀一個 cell 到 EAX
add eax, 4          ; EAX += 4
lea ebp, [ebp-4]    ; 算位址，但不解參考記憶體
push ebx            ; 把 EBX 推到 x86 stack
pop ebx             ; 從 x86 stack 取回 EBX
call target         ; 呼叫子程序
ret                 ; 返回
jmp target          ; 無條件跳轉
```

讀組語時，建議總是先問三件事：

1. **資料從哪裡來？**（register、memory、immediate）
2. **資料往哪裡去？**
3. **這條指令有沒有改旗標或堆疊？**

---

### 2.3 記憶體定址：SP-Forth 最常見的樣子

一般 Intel 寫法常見這些形式：

```asm
[ebp]          ; 取 EBP 指向的記憶體
[ebp+4]        ; 取 EBP+4
[eax+ebx]      ; 取 EAX+EBX
[eax*4]        ; 以 EAX*4 做位址計算
```

SP-Forth assembler 在 source 裡常長這樣：

```forth
[EBP]
4 [EAX]
[EDI] [EBX]
[EAX*4]
```

可把它理解成同一件事：

| SP-Forth 寫法 | 一般 Intel 想法 |
|--------------|------------------|
| `[EBP]` | `[ebp]` |
| `4 [EAX]` | `[eax+4]` |
| `-9 [EBX]` | `[ebx-9]` |
| `[EDI] [EBX]` | `[edi+ebx]` |
| `[EAX*4]` | `[eax*4]` |

#### 2.3a 定址語法的組合規則

SP-Forth assembler 的定址語法可以從小到大組合：

| 想表達 | SP-Forth 寫法 | Intel 想法 |
|--------|---------------|------------|
| base | `[EBP]` | `[ebp]` |
| base + disp | `8 [EBP]` | `[ebp+8]` |
| index * scale | `[EAX*4]` | `[eax*4]` |
| base + index | `[EDI] [EBX]` | `[edi+ebx]` |
| base + index + disp | `12 [EBP] [ECX]` | `[ebp+ecx+12]` |

實務上最常見的是 `[EBP]`、`4 [EBP]`、`[EAX*4]`。讀到複雜形式時，把它拆成「固定偏移 + base + index*scale」即可。

---

## 3. 再帶入 SP-Forth 的執行模型

### 3.1 最重要的前提：`EAX` 就是 TOS

SP-Forth 的 kernel 不是把資料堆疊完整放在記憶體頂端，而是採用：

- `EAX`：TOS
- `[EBP]`：次堆疊項
- `ESP`：回返堆疊

因此你看到：

```forth
ADD EAX, [EBP]
LEA EBP, 4 [EBP]
```

不要先想 C 的 local variable，要先翻成 Forth 的堆疊語意：

1. 用 `[EBP]` 取出次堆疊項
2. 和 `EAX`（TOS）運算
3. 再把 `EBP` 往上移一格，表示少了一個 stack item

---

### 3.2 範例 1：`DUP`

原始碼（`src/spf_forthproc.f`）：

```forth
CODE DUP ( x -- x x )
     LEA EBP, -4 [EBP]
     MOV [EBP], EAX
     RET
END-CODE
```

一般組語觀念可先這樣看：

```asm
lea ebp, [ebp-4]    ; 在 data stack 騰出一格
mov [ebp], eax      ; 把原本的 TOS 寫回去
ret
```

這裡最容易混淆的就是第一行：

```asm
lea ebp, [ebp-4]
```

它的**真正意思**是：

> 把「`EBP - 4` 這個位址值」算出來，再寫回 `EBP`

它**不是**：

- `mov ebp, [ebp-4]`：去讀取記憶體 `ebp-4` 位置的內容
- 也不是「把某個位址存進記憶體」

也就是說，`LEA` 在這裡做的是**位址運算**，不是記憶體讀取。  
若原本 `EBP = 0x1000`，那執行完：

```asm
lea ebp, [ebp-4]
```

之後會得到：

- 新的 `EBP = 0x0FFC`
- 記憶體內容完全還沒改

真正寫入記憶體的是下一行：

```asm
mov [ebp], eax
```

也就是說，這兩行合起來才是：

1. 先把 data stack pointer 往下移一格（騰出 1 個 cell）
2. 再把原本的 TOS 寫進這個新位置

可以把它想成下面這個流程：

```text
原本：
  EAX = x
  EBP = 0x1000

執行 lea ebp, [ebp-4] 後：
  EAX = x
  EBP = 0x0FFC
  （只是指標變了，還沒寫資料）

執行 mov [ebp], eax 後：
  [0x0FFC] = x
  EAX = x
```

對 SP-Forth 來說，因為一個 cell = 4 bytes，所以：

- `LEA EBP, -4 [EBP]` = **push 一格 data stack**
- `LEA EBP, 4 [EBP]` = **pop 一格 data stack**

再對照一組很容易混的寫法：

| 寫法 | 真正效果 |
|------|----------|
| `LEA EBP, -4 [EBP]` | `EBP := EBP - 4`，**不讀記憶體** |
| `MOV EBP, -4 [EBP]` | `EBP := memory[EBP-4]`，**會讀記憶體** |
| `SUB EBP, # 4` | 也能做到 `EBP := EBP - 4`，但會改旗標；`LEA` 則不會 |

最後這點很重要：在這類「調整堆疊指標」的場景，`LEA` 與 `SUB` 會得到相同的目的值，但 `LEA` 不改 flags。把它寫成 `LEA`，也更直接提醒讀者：這裡是在做**位址/偏移計算**，不是一般整數減法。

Forth 語意則是：

- 原本 `EAX = x`
- 執行後 `[EBP] = x`，`EAX` 仍是 `x`
- 所以 stack effect 變成 `( x -- x x )`

這是 SP-Forth 最典型的「**用位址移動代表堆疊操作**」。

---

### 3.3 範例 2：`+`

```forth
CODE + ( n1 n2 -- n3 )
     ADD EAX, [EBP]
     LEA EBP, 4 [EBP]
     RET
END-CODE
```

一般組語解讀：

```asm
add eax, [ebp]      ; eax = n2 + n1
lea ebp, [ebp+4]    ; data stack 彈一格
ret
```

SP-Forth 的關鍵不是 `ADD` 本身，而是：

- `EAX` 已經是 TOS，不必先 `MOV EAX, ...`
- `LEA EBP, 4 [EBP]` 只是在調整 stack pointer，不是做一般 pointer arithmetic 練習

---

### 3.4 範例 3：`CELLS`

```forth
CODE CELLS
     LEA EAX, [EAX*4]
     RET
END-CODE
```

這裡是很適合初學者理解的 `LEA` 技巧：

- `LEA` 不一定只是「取位址」
- 它也常被拿來做 **不碰記憶體的整數運算**

一般組語裡你可能寫：

```asm
shl eax, 2
```

SP-Forth 這裡則用：

```asm
lea eax, [eax*4]
```

優點是：

- 語意直接表達「cell 大小 = 4 bytes」
- 不需要真的去讀某個記憶體位址

---

## 4. 整份 `src/*` 會反覆出現的組語技巧

### 4.1 `LEA` 不只是位址運算

在 SP-Forth 原始碼裡，`LEA` 很常用來：

1. **調整 data stack pointer**
2. **計算偏移**
3. **做乘法/縮放**

典型例子：

```forth
LEA EBP, -4 [EBP]   \ push 一格
LEA EBP, 4 [EBP]    \ pop 一格
LEA EAX, [EAX*4]    \ x * 4
LEA EBX, -9 [EBX]   \ 回退到嵌入資料的位置
```

在 SP-Forth，`LEA` 更常用來做「**位址 / 索引 / 堆疊偏移計算**」，而不是 C 風格的「取址」直覺。

可先記住幾個**硬事實**：

1. `LEA` 的來源操作數必須寫成 **memory-form** 的語法，也就是像 `[base + index*scale + displacement]` 這種形式。
2. 但 `LEA` **只取這個位址公式本身**，不會真的去讀取 `[]` 指向的記憶體。
3. `LEA` 的結果只會寫入目的暫存器，**不會改旗標**。
4. `scale` 只能是 `1 / 2 / 4 / 8`，所以它不是任意乘法器，而是很適合處理「元素大小固定」的索引計算。

換句話說，`LEA` 的 `[]` 比較像「**沿用 x86 位址公式的語法**」，不是 `MOV` 那種「真的去解參考」。

#### 4.1.1 為什麼 x86 會有 `LEA` 這種指令？

從 x86 ISA 的角度，`LEA` 的功能分工如下：

- x86 本來就內建了很強的有效位址公式：`base + index*scale + displacement`
- `LEA` 直接重用這套公式來計算結果
- 計算結果會寫入目的暫存器，**但不觸發記憶體存取**

公開可直接確認的重點是：`LEA` 重用 x86 的有效位址公式，並把計算結果寫入暫存器。這描述的是 ISA 層面的功能，不把它包裝成 Intel 官方公開宣告過的歷史設計理由。

因此：

- `lea ebp, [ebp-4]` = 計算 `ebp - 4`
- `lea eax, [ebx + ecx*4]` = 計算 `ebx + ecx*4`

它們都只是把「位址公式」當成整數/指標運算來用。

#### 4.1.2 `LEA`、`MOV`、`SUB` 的差別

| 寫法 | 會不會讀記憶體 | 會不會改 flags | 適合拿來表達什麼 |
|------|----------------|----------------|------------------|
| `LEA EBP, -4 [EBP]` | 不會 | 不會 | stack / pointer 偏移 |
| `MOV EBP, -4 [EBP]` | 會 | 不會 | 從記憶體載入資料 |
| `SUB EBP, # 4` | 不會 | 會 | 一般整數減法，或不在意 flags 的指標調整 |

對 SP-Forth 而言，`LEA EBP, -4 [EBP]` 的可讀重點其實是：

> 「data stack pointer 往下移 1 個 cell」

它不是在「取某個 local variable 的位址」，也不是在「讀取 `[EBP-4]` 的內容」。

#### 4.1.2a 打錯指令會發生什麼？

假設 `EBP = 0x1000`，而記憶體 `[0x0FFC] = 0xABCD`：

| 指令 | 執行後 `EBP` | 是否讀記憶體 | 結果 |
|------|--------------|--------------|------|
| `LEA EBP, -4 [EBP]` | `0x0FFC` | 否 | 正確：只是把 data stack pointer 往下移一格 |
| `MOV EBP, -4 [EBP]` | `0xABCD` | 是 | 錯誤：把 `[EBP-4]` 的內容當成新的指標 |
| `SUB EBP, # 4` | `0x0FFC` | 否 | 值對，但會改 flags |

所以看到 `LEA EBP, ±4 [EBP]` 時，不要翻成「取位址」，而要翻成「調整 SP-Forth data stack pointer」。

#### 4.1.3 和 ARM / AArch64 怎麼對照？

SP-Forth 這套原始碼是 IA-32，但拿 ARM / AArch64 對照很有助於理解設計取向。

最重要的差別是：

- 在 x86，`ADD` / `SUB` 會改 flags，所以很多時候會用 `LEA` 來做「不動 flags 的位址/索引運算」
- 在 AArch64，`ADD` / `SUB` **預設就不改 flags**，只有 `ADDS` / `SUBS` 才會改

所以在 ARM 世界裡，很多 `LEA` 承擔的工作，會直接由一般 `ADD` / `SUB` 完成。

| x86 / x86-64 觀念 | AArch64 近似寫法 | 說明 |
|-------------------|------------------|------|
| `lea ebp, [ebp-4]` | `sub x0, x0, #4` | 都是在算「舊值減 4」；AArch64 不需要另外找一個不改 flags 的 `LEA` |
| `lea eax, [ebx + ecx*4]` | `add x0, x1, x2, lsl #2` | 都是在做 base + scaled index |
| `lea rax, [rip+symbol]` | `adr x0, symbol` / `adrp x0, symbol` + `add x0, x0, ...` | 都可用來產生 PC-relative 位址，但 ISA 編碼機制不同 |

上表第三列只能算**概念近似**，不是一對一對應：

- x86-64 的 RIP-relative `LEA` 是沿用 x86 的 effective-address 語法
- `ADR` / `ADRP` 則是 AArch64 直接提供的 PC-relative 位址生成指令

另外，本章以 IA-32 為主；如果你在 x86-64 讀到類似寫法，要再多注意一點：

- `lea ebp, [ebp-4]` 會寫入 32-bit `EBP`，並把結果 zero-extend 到 `RBP`
- 真正的 64-bit 指標運算通常會寫成 `lea rbp, [rbp-4]`

#### 4.1.4 這樣寫效能一定比較好嗎？

不一定。要把**架構語意**和**微架構效能**分開看：

- 架構層面上，`LEA` 的優點很明確：**不碰記憶體、不改 flags、可重用位址公式**
- 但在實際 CPU 上，`LEA` 是否比 `ADD` / `SUB` / `SHL` 更快，取決於**具體微架構**

對 `lea ebp, [ebp-4]` 這種**簡單形式**來說，許多現代 x86 CPU 都能相當有效率地執行；把它當成一般的 stack/pointer update 來理解即可。  
但對較複雜的形式，例如：

- `base + index*scale + displacement`
- 或同時混合多個來源與縮放

某些 CPU 世代可能會比簡單 `ADD` 或拆成兩步的寫法更不划算。

因此文件裡最安全的原則是：

1. 把 `LEA` 當成**語意很清楚的位址/索引工具**
2. 不要把它寫成「一定比 `ADD` / `SUB` 快」
3. 如果真的要談 cycle / throughput，必須綁定特定 CPU 型號或微架構

#### 4.1.5 還有哪些相似的指令設計？

`LEA` 背後的設計想法，其實是把「常見的小運算模式」直接做成單一指令。類似例子包括：

| 指令 / 設計 | 常見用途 | 和 `LEA` 相似在哪裡 |
|-------------|----------|----------------------|
| AArch64 `ADD x0, x1, x2, LSL #2` | base + scaled index | 把「加法 + 位移/縮放」合成一條指令 |
| AArch64 `ADR` / `ADRP` | 產生 PC-relative 位址 | 把「取當前程式位置附近的位址」做成明確操作 |
| x86 `MOVZX` / `MOVSX` | 載入後立即做零擴展/符號擴展 | 把常見資料轉換與載入合在一起 |
| x86 `IMUL reg, reg, imm` | 乘上固定常數 | 把「乘法 + 常數」做成直接可用的形式 |

這些設計的共同理念不是「一定比較快」，而是：

- 讓常見模式更容易表達
- 減少中間暫存器或額外指令
- 讓組語程式更貼近資料/位址的實際形狀

所以讀 SP-Forth 的 `LEA` 時，最好的心智模型不是「這是奇怪的取址指令」，而是：

> x86 把位址公式當成一等公民；`LEA` 只是把這個公式借來做不碰記憶體的計算。

---

### 4.2 無分支布林：`XOR` + `SUB` + `SBB`

`=` 的核心技巧在 `src/spf_forthproc.f`：

```forth
XOR EAX, [EBP]
SUB EAX, # 1
SBB EAX, EAX
LEA EBP, 4 [EBP]
RET
```

這是經典的 **branchless boolean**：

1. `XOR` 後若相等，結果為 `0`
2. `SUB 1` 後若原本為 `0`，則結果變 `-1` 並帶出借位
3. `SBB EAX, EAX` 把借位旗標轉成 `0` 或 `-1`

也就是說，它不是靠 `JE` / `JNE` 跳轉，而是直接把旗標「壓成」Forth 需要的真值格式。

#### 4.2a `=` 的逐步真值表

| 步驟 | 指令 | 若 x1 = x2 | 若 x1 ≠ x2 | 重點 |
|------|------|------------|------------|------|
| 1 | `XOR EAX, [EBP]` | `EAX = 0` | `EAX ≠ 0` | 相等才會變 0 |
| 2 | `SUB EAX, # 1` | `EAX = -1`, `CF=1` | 通常 `CF=0` | 借位旗標記錄原值是否為 0 |
| 3 | `SBB EAX, EAX` | `EAX = -1` | `EAX = 0` | 把 CF 轉成 Forth truth value |
| 4 | `LEA EBP, 4 [EBP]` | pop 次項 | pop 次項 | 清理被比較的第二個參數 |

Forth 的 true 是 `-1`（所有位元為 1），所以 `SBB EAX, EAX` 正好能把 CPU 的 CF 轉成 Forth 布林值。

---

### 4.3 `CALL` / `POP` 取嵌入資料

`_TOVALUE-CODE` 是 SP-Forth 很有代表性的技巧：

```forth
CODE _TOVALUE-CODE
     POP EBX
     LEA EBX, -9 [EBX]
     MOV [EBX], EAX
     MOV EAX, [EBP]
     LEA EBP, 4 [EBP]
     RET
END-CODE
```

這段的重點不是 `MOV`，而是：

- `POP EBX` 先拿到 `CALL _TOVALUE-CODE` 的返回位址
- `LEA EBX, -9 [EBX]` 再倒退回「call 指令 + embedded value cell」的位置

這種寫法在一般組語世界也常見，可視為一種 **position-dependent embedded data trick**。  
在 SP-Forth 裡，它很適合拿來實作 `TO VALUE` 這種需要直接回寫內嵌欄位的語意。

#### 4.3a `CALL` 後面為什麼可以接資料？

x86 執行 `CALL target` 時，會把「CALL 後面那個位址」推入 `ESP` 指向的回返堆疊：

```text
執行 CALL 前：                  進入 _TOVALUE-CODE 後：

程式碼：                        ESP → return address
CALL _TOVALUE-CODE                    │
<embedded value cell>  ◄──────────────┘
下一條指令
```

因此 `_TOVALUE-CODE` 一開始的 `POP EBX` 不是取一般資料堆疊，而是取出 x86 return address。這個 return address 剛好指向嵌入資料附近，所以再用 `LEA EBX, -9 [EBX]` 回推到要改寫的 cell。

讀到 `POP` 但前面沒有明顯 `PUSH` 時，要先懷疑：這是不是在取 `CALL` 推入的 return address？

---

### 4.4 手工輸出 opcode：`C,` / `,`

不是所有機器碼都透過 `CODE ... END-CODE` 直接寫。  
在 compiler / cross-compiler 裡，也常看到這種 metacompiler 風格：

```forth
0E8 C,              \ CALL opcode
DP @ CELL+ - ,
```

這代表：

- `C,`：直接輸出 1 byte
- `,`：直接輸出 1 cell

例如 `TC-CALL,`：

```forth
: TC-CALL, ( addr -- )
  ?SET
  SetOP
  0E8 C,              \ CALL rel32 opcode
  DP @ CELL+ - ,
  DP @ TO LAST-HERE
;
```

這不是在「執行 CALL」，而是在**編譯期把 CALL 指令編進 target image**。

這也是讀 SP-Forth 原始碼時最重要的分界之一：

- `CODE ... END-CODE`：定義執行期原語
- `C,` / `,` / `RET,`：在編譯期組裝目標機器碼

---

### 4.5 `A;`：暫時結束上一條組語，切回 Forth 做組裝期工作

`lib/asm/486asm.f` 對 `A;` 的說明是：

```forth
: A; ( FINISH THE ASSEMBLY OF THE PREVIOUS INSTRUCTION )
        0 DO-OPCODE ;
```

在 `src/posix/api.f` 可看到：

```forth
CODE _WNDPROC-CODE
     MOV  EAX, ESP
     SUB  ESP, # 3968
A;   HERE 4 - ' ST-RES 9 + EXECUTE
     ...
END-CODE
```

這裡的理解方式是：

1. 前一條 assembler instruction 先完成輸出
2. 暫時回到 Forth 層，執行 `HERE 4 - ' ST-RES 9 + EXECUTE`
3. 再繼續後面的組語輸出

也就是說，`A;` 不是 CPU 指令，而是 **assembler / metaprogramming 的切換點**。  
它很適合拿來做「一邊寫 machine code，一邊修補剛輸出的 bytes」這種工作。

#### 4.5a `A;` 的實際用途：修補剛輸出的位元組

在 `_WNDPROC-CODE` 裡：

```forth
SUB  ESP, # 3968
A;   HERE 4 - ' ST-RES 9 + EXECUTE
```

可以這樣讀：

1. `SUB ESP, # 3968` 先輸出一條含有立即數的指令。
2. `A;` 讓 assembler 完成這條指令的編碼。
3. `HERE 4 -` 回到剛輸出的 4-byte immediate 欄位。
4. `' ST-RES 9 + EXECUTE` 用 Forth 計算/修補這個欄位。

所以 `A;` 不是「換行」或「註解」，而是讓你在兩條機器碼指令之間暫時回到 Forth 世界，做位址計算、patch、或其他組裝期工作。

---

## 5. SP-Forth 內建組語怎麼寫？

### 5.1 `CODE ... END-CODE`

最基本形式：

```forth
CODE WORD-NAME ( stack-effect )
     ... x86 instructions ...
     RET
END-CODE
```

這會建立一個 Forth 字詞，其執行碼欄位就是你在中間輸出的 machine code。

更精確地說，`CODE WORD-NAME ... END-CODE` 會經過這些步驟：

1. 建立標準 Forth header，名稱是 `WORD-NAME`。
2. 進入 assembler vocabulary / assembler state。
3. 中間每條 assembler 指令直接輸出 machine code 到字典。
4. `END-CODE` 完成最後一條指令、檢查未解決的 forward reference、對齊並揭露新字。

所以 `CODE` 不是單純的「組語區塊標記」；它是會建立一個可被 Forth 呼叫的 native word。

最小例子：

```forth
CODE NOP-LIKE ( x -- x )
     RET
END-CODE
```

---

### 5.2 SP-Forth assembler 常用寫法對照

| 類型 | SP-Forth 寫法 | 一般 Intel 觀念 |
|------|---------------|-----------------|
| 暫存器搬移 | `MOV EAX, [EBP]` | `mov eax, [ebp]` |
| 立即數 | `SUB ESP, # 3968` | `sub esp, 3968` |
| 記憶體位移 | `4 [EAX]` | `[eax+4]` |
| 負偏移 | `-9 [EBX]` | `[ebx-9]` |
| 雙基底感 | `[EDI] [EBX]` | `[edi+ebx]` |
| 縮放索引 | `[EAX*4]` | `[eax*4]` |
| 明確 byte 大小 | `BYTE [EAX]` | byte ptr `[eax]` |
| 明確 word 大小 | `WORD [EAX]` | word ptr `[eax]` |
| 明確 dword 大小 | `DWORD [EAX]` | dword ptr `[eax]` |
| 短跳躍 | `JNZ SHORT @@1` | 8-bit relative branch |
| 原始 byte | `0E8 C,` | emit `0xE8` |
| 原始 word | `TRUE W,` | emit 16-bit word |
| 原始 cell | `,` | emit one cell / rel32 / literal |

其中 **`#` 表示 immediate value**，這點是讀 source 時最常遇到、也最值得先記住的 SP-Forth assembler 習慣。

### 5.2a 大小修飾詞：`BYTE` / `WORD` / `DWORD`

有些 x86 指令只看運算元語法無法判斷要讀寫幾個 byte，這時 SP-Forth assembler 會用大小修飾詞：

```forth
MOVZX EAX, BYTE [EAX]   \ 讀 1 byte，零擴展到 EAX
MOVZX EAX, WORD [EAX]   \ 讀 2 bytes，零擴展到 EAX
MOV WORD [EAX], DX      \ 寫 2 bytes
MOV DWORD [EAX], # 0    \ 寫 4 bytes 的 0
```

常見規則：

| 修飾詞 | 大小 | 常見用途 |
|--------|------|----------|
| `BYTE` | 8-bit | `C@`、字元、低位 byte |
| `WORD` | 16-bit | `W@` / `W!`、x86 16-bit 欄位 |
| `DWORD` | 32-bit | cell、位址、一般 IA-32 整數 |

#### 5.2a1 為什麼需要大小修飾詞？

裸記憶體操作數有時太模糊：

```forth
MOV [EAX], # 0       \ 不清楚要寫 1、2 還是 4 bytes
MOV BYTE [EAX], # 0  \ 寫 1 byte
MOV WORD [EAX], # 0  \ 寫 2 bytes
MOV DWORD [EAX], # 0 \ 寫 4 bytes
```

只要看到「目的地或來源是裸記憶體位址」，就先想：assembler 是否能推斷大小？如果不能，就加 `BYTE` / `WORD` / `DWORD`。

### 5.2b `MOVZX` / `MOVSX`：讀小型資料時的擴展

讀取 byte/word 到 32-bit 暫存器時，不能只看低位元。SP-Forth 常用：

```forth
MOVZX EAX, BYTE [EAX]   \ zero-extend：高位補 0
MOVSX EAX, AL           \ sign-extend：依符號位擴展
```

`MOVZX` 適合字元與無號欄位，例如 `C@`；`MOVSX` 適合要保留符號語意的小整數。

### 5.2c `SHORT` 與區域標籤 `@@1:`

source 裡常見：

```forth
JL SHORT @@1
  MOV EAX, EDX
@@1:
```

- `@@1:` 定義區域標籤。
- `@@1` 引用這個標籤。
- `SHORT` 要求使用 8-bit signed displacement，目標必須在大約 ±128 bytes 內。

這能產生較短的跳躍指令；若距離太遠，就不能使用 `SHORT`。

完整例子：

```forth
CODE ?DUP ( x -- 0 | x x )
     TEST EAX, EAX
     JZ SHORT @@1
     LEA EBP, -4 [EBP]
     MOV [EBP], EAX
@@1: RET
END-CODE
```

這裡 `JZ SHORT @@1` 是 forward reference；assembler 先記住要回填的位置，等看到 `@@1:` 再計算短跳距離。

### 5.2d `REPZ` / `REPNZ` 字串指令前綴

SP-Forth 的字串與記憶體搬移原語會看到 x86 string instruction：

```forth
REP MOVS DWORD      \ 依 ECX 次數搬移 dword
REPZ SCAS BYTE      \ 掃描 byte，ZF 條件成立時持續
```

讀法：

| 寫法 | 意義 |
|------|------|
| `REP` | 重複執行 ECX 次 |
| `REPZ` / `REPE` | ZF=1 時重複 |
| `REPNZ` / `REPNE` | ZF=0 時重複 |

這些指令通常會同時使用 `ESI`、`EDI`、`ECX`，所以讀到它們時要先找這三個暫存器如何被設定。

等價的手寫迴圈概念：

```forth
MOV ECX, # 100     \ 重複 100 次
MOV ESI, source    \ 來源
MOV EDI, dest      \ 目的
CLD                \ 確保 ESI/EDI 往高位址前進
REP MOVS DWORD     \ 搬 100 個 dword
```

`REP` 不會自己知道要搬多少；`ECX` 才是計數器。方向則由 DF flag 決定，所以常見程式會先 `CLD`。

### 5.2e `FS:` segment override

少數程式碼會出現：

```forth
MOV EAX, FS: [EAX]
```

`FS:` 是 x86 segment override。它不是一般記憶體定址，而是透過特定 segment base 存取資料；在作業系統或 TLS 相關程式碼中很常見。SP-Forth 原始碼中可在 `FS@` / `FS!` 看到 `FS: [EAX]` 形式；讀到這類寫法時，通常要聯想到 thread-local storage 或平台相關執行環境。

在 SP-Forth 裡可先用這個策略讀：

| 看到 | 先想到 |
|------|--------|
| `MOV EAX, FS: [EAX]` | 讀取 OS/thread-local 區域中的資料 |
| `MOV FS: [EAX], EBX` | 寫入 OS/thread-local 區域 |
| `TlsIndex!` / `TlsIndex@` | SP-Forth 自己用 `EDI` 保存 USER/TLS base，和 `FS:` 是不同層級的機制 |

---

### 5.3 `RET` 與 `RET,` 不一樣

這一對很容易混：

#### 在 `CODE ... END-CODE` 裡

```forth
RET
```

意思是：直接輸出 runtime primitive 裡的 `RET` 指令。

#### 在 compiler / cross-compiler 裡

```forth
: RET, ( -> )
  ?SET SetOP 0xC3 C, OPT OPT_CLOSE
;
```

意思是：**在編譯期**把 `RET opcode` 編進 target image。

所以：

- `RET`：你正在寫 assembler primitive
- `RET,`：你正在寫「會產生 assembler bytes 的 Forth 字」

對照表：

| 寫法 | 出現位置 | 發生時間 | 意義 |
|------|----------|----------|------|
| `RET` | `CODE ... END-CODE` | 該 word 執行時 | CPU 返回上一層呼叫者 |
| `RET,` | `: ... ;` 編譯器輔助字 | 編譯期間 | 把 `0xC3` 寫進 target image |

---

### 5.4 `C,`、`W,` 與 `,`：什麼時候用？

#### `C,`
適合輸出單一 opcode byte：

```forth
0E8 C,   \ CALL rel32
0B8 C,   \ MOV EAX, imm32
0xC3 C,  \ RET
```

#### `W,`
適合輸出 16-bit word：

```forth
TRUE W, TRUE W,   \ 常見於手工輸出 32-bit -1 時拆成兩個 word
```

#### `,`
適合輸出 cell / rel32 / literal：

```forth
DP @ CELL+ - ,
```

這種組合在 `src/compiler/spf_compile.f` 和 `src/tc_spf.F` 非常常見。

| 字 | 輸出大小 | 常見用途 |
|----|----------|----------|
| `C,` | 1 byte | opcode、ModR/M byte、短立即數 |
| `W,` | 2 bytes | 16-bit 立即數或拆分輸出 |
| `,` | 1 cell（IA-32 上 4 bytes） | rel32、位址、cell literal |

### 5.5 `SetOP` / `?SET` / `DP @`：compiler 裡的組碼基礎設施

讀 [03-cross-compiler.md](03-cross-compiler.md) 或 [07-optimizer.md](07-optimizer.md) 時，會看到：

```forth
?SET
SetOP
0E8 C,
DP @ CELL+ - ,
DP @ TO LAST-HERE
```

這些不是 CPU 指令，而是編譯器/最佳化器基礎設施：

| 字 | 用途 |
|----|------|
| `DP @` | 目前字典指標 / 下一個要輸出的位址 |
| `SetOP` | 告訴 optimizer「這裡開始是一條新機器碼指令」 |
| `?SET` | 檢查 / 修正 optimizer 追蹤的狀態 |
| `LAST-HERE` | 記錄最近機器碼邊界，供後續最佳化/回填使用 |

因此 `TC-CALL,` 裡的 `0E8 C,` 不是「立刻 CALL」，而是把 CALL opcode 寫進 target image；`DP @ CELL+ - ,` 則寫入 rel32 displacement。

逐步追蹤一條 `CALL` 的輸出：

| 步驟 | 程式碼 | 作用 |
|------|--------|------|
| 1 | `?SET` | 檢查 optimizer 狀態 |
| 2 | `SetOP` | 標記新 machine instruction 起點 |
| 3 | `0E8 C,` | 寫出 `CALL rel32` opcode |
| 4 | `DP @ CELL+ - ,` | 計算並寫出 4-byte relative displacement |
| 5 | `DP @ TO LAST-HERE` | 記錄這條指令結束位址 |

---

## 6. 由淺入深的多個範例

### 6.1 範例 A：複製 TOS

```forth
CODE DUP ( x -- x x )
     LEA EBP, -4 [EBP]
     MOV [EBP], EAX
     RET
END-CODE
```

你應該練習看到它就能翻譯成：

- push 一格
- 把舊 TOS 寫回 memory
- 保留 `EAX`

---

### 6.2 範例 B：兩數相加

```forth
CODE + ( n1 n2 -- n3 )
     ADD EAX, [EBP]
     LEA EBP, 4 [EBP]
     RET
END-CODE
```

要練習的重點：

- `EAX` 已是 TOS
- `[EBP]` 是次項
- `LEA EBP, 4 [EBP]` 代表 pop 一格

---

### 6.3 範例 C：把 cell 大小內化成位址運算

```forth
CODE CELLS
     LEA EAX, [EAX*4]
     RET
END-CODE
```

這個例子很適合拿來理解：

- `LEA` 常被當成 integer arithmetic
- SP-Forth 的 cell 在 IA-32 上是 4 bytes

---

### 6.4 範例 D：無分支比較

```forth
XOR EAX, [EBP]
SUB EAX, # 1
SBB EAX, EAX
LEA EBP, 4 [EBP]
RET
```

這裡練習的是：

- CPU flags 也是資料流的一部分
- `SBB reg, reg` 可以把 `CF` 壓成 `0` 或 `-1`

---

### 6.5 範例 E：回呼橋接器

```forth
MOV  EAX, ESP
SUB  ESP, # 3968
A;   HERE 4 - ' ST-RES 9 + EXECUTE
PUSH EBP
...
CALL EBX
...
XCHG EAX, [ESP]
RET
```

這個例子比前面難很多，因為它一次混了：

- x86 stack / register 保存
- SP-Forth 資料堆疊重建
- `A;` 切回 Forth 做組裝期修補
- callback 返回值整理

建議讀法：

1. 先只看 `MOV/SUB/PUSH/CALL/POP/XCHG`
2. 再看它怎麼把 C callback frame 轉成 Forth 可執行環境
3. 最後才看 `A;` 那一行的 metaprogramming 意味

---

### 6.6 範例 F：在 compiler 裡手工組 CALL

```forth
: TC-CALL, ( addr -- )
  ?SET
  SetOP
  0E8 C,
  DP @ CELL+ - ,
  DP @ TO LAST-HERE
;
```

這裡最容易誤解的地方是：這段不是 runtime primitive。  
它是在**產生 target machine code**，所以：

- `0E8 C,` 是寫出 opcode
- `,` 是寫出 rel32
- `LAST-HERE` 是讓後續最佳化器/回填邏輯知道目前 machine code 邊界

---

## 7. 初學者最常卡住的地方

### 7.1 不要把 `EBP` 當 C frame pointer

在這套 codebase 裡，`EBP` 幾乎都應先翻譯成：

> data stack pointer，且 `[EBP]` 是次堆疊項

---

### 7.2 不要把 `CODE` 和 metacompiler byte emission 混成一類

- `CODE ... END-CODE`：定義執行期原語
- `C,` / `,` / `RET,` / `TC-CALL,`：在編譯期組 machine code

---

### 7.3 看到 `LEA` 先想「位址/縮放/stack 調整」

在 SP-Forth 裡，`LEA` 常常比 `MOV` 還更關鍵，因為它隱含了：

- push/pop
- index scaling
- embedded data 回退

---

### 7.4 看到 `A;` 時，要切換成「assembler 不是純文字，而是可編程工具」的心智模型

這是 SP-Forth 很值得學的地方：

- 組語不是被動語法
- 它可以和 Forth 的 metaprogramming 混在一起
- 你可以一邊輸出 bytes，一邊運算、修補、植入資料

---

## 8. 讀完這章之後，下一步怎麼讀？

如果你現在已經能看懂：

1. `DUP` 為什麼只要兩條指令
2. `+` 為什麼只動 `EAX` 與 `[EBP]`
3. `=` 為什麼可以不用跳轉
4. `TC-CALL,` 為什麼不是 runtime code
5. `A;` 為什麼代表 assembler / Forth 混合組裝

那就可以進入：

- [01-kernel.md](01-kernel.md)：正式看 kernel primitives
- [03-cross-compiler.md](03-cross-compiler.md)：看 metacompiler 如何組出 target machine code
- [07-optimizer.md](07-optimizer.md)：看最佳化器怎麼改寫這些 machine code 片段

---

## 9. 一句話總結

讀 SP-Forth 的組語，最關鍵的不是背指令表，而是同時抓住三件事：

1. **一般 IA-32 指令在做什麼**
2. **SP-Forth VM 把哪些語意綁到 `EAX/EBP/ESP/EDI`**
3. **目前這段 code 是 runtime primitive，還是 compile-time machine-code emission**

抓住這三層，整份 `src/*` 的 assembler 片段就會從「難讀的 opcode 咒語」變成「有規律的 VM 實作」。 
