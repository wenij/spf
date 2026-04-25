# SP-Forth/4 原始碼追蹤 — 附錄 A：IA-32 組合語言技巧與 SP-Forth 內建組語

> 對應原始碼：`lib/ext/spf-asm.f`、`lib/asm/486asm.f`、`src/spf_defkern.f`、`src/spf_forthproc.f`、`src/compiler/spf_compile.f`、`src/tc_spf.F`、`src/posix/api.f`

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
| 原始 byte | `0E8 C,` | emit `0xE8` |
| 原始 cell | `,` | emit one cell / rel32 / literal |

其中 **`#` 表示 immediate value**，這點是讀 source 時最常遇到、也最值得先記住的 SP-Forth assembler 習慣。

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

---

### 5.4 `C,` 與 `,`：什麼時候用？

#### `C,`
適合輸出單一 opcode byte：

```forth
0E8 C,   \ CALL rel32
0B8 C,   \ MOV EAX, imm32
0xC3 C,  \ RET
```

#### `,`
適合輸出 cell / rel32 / literal：

```forth
DP @ CELL+ - ,
```

這種組合在 `src/compiler/spf_compile.f` 和 `src/tc_spf.F` 非常常見。

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
