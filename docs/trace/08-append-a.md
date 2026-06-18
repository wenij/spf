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

**逐步走查**：假設進入 `+` 時 `EAX = n2`（TOS），`EBP = 0x1000`，`[0x1000] = n1`（次項）：

| 步驟 | 指令 | 結果 | 對 SP-Forth 而言 |
|------|------|------|-------------------|
| 1 | `ADD EAX, [EBP]` | `EAX = n1 + n2` | TOS ← TOS + 次項 |
| 2 | `LEA EBP, 4 [EBP]` | `EBP = 0x1004` | data stack 彈一格（被加進去的次項已消耗） |
| 3 | `RET` | 控制權回 caller | — |

結束狀態：`EAX = n1+n2`、`EBP = 0x1004`。Stack effect：`( n1 n2 -- n3 )`。

SP-Forth 的關鍵不是 `ADD` 本身，而是：

- `EAX` 已經是 TOS，不必先 `MOV EAX, ...`
- `LEA EBP, 4 [EBP]` 只是在調整 stack pointer，不是做一般 pointer arithmetic 練習
- 整個 `+` **只用了 2 條指令**，連 `MOV` 都省了

#### 3.3.1 為什麼順序是 `ADD` 在 `LEA` 之前？

直覺寫法可能會想先 `pop` 再加：

```asm
MOV ECX, [EBP]      ; 備份次項
LEA EBP, 4 [EBP]    ; pop
ADD EAX, ECX        ; 相加
```

但 SP-Forth 知道**那個被 pop 掉的次項在 `ADD` 之後就沒人要了**。直接把 `ADD EAX, [EBP]` 接在 `LEA` 之前，省一次暫存器搬移，也少讀一次 `[EBP]`。這是 **branch-free peephole** 的精神：把「不可避免的副作用」壓到最少指令裡。

#### 3.3.2 flags 與後續指令

`ADD` 會同時改 `OF/SF/ZF/AF/PF/CF`。對 SP-Forth 來說：

- 如果 `+` 之後馬上接的是另一個 Forth word（compiler emit 的下一段組語），那 flags 被前一段覆寫是**正常**的，沒有「flags 被偷走」的問題。
- 如果 `+` 之後在同一段 `CODE` 內緊接著 `IF` / `?BR-OPT` 之類的條件跳，那 `+` 的 flags 是設計的一部分——你可以**故意**靠它省一條 `CMP`。

例如：

```asm
ADD EAX, [EBP]
LEA EBP, 4 [EBP]
JNZ SHORT @@1        ; 靠 ADD 的 ZF
@@1: RET
```

這個慣用法在 `OPT-RULES` 與 `?BR-OPT` 裡到處可見。

#### 3.3.3 一個可以自己跑的測試

```forth
CODE + ( n1 n2 -- n3 )
     ADD EAX, [EBP]
     LEA EBP, 4 [EBP]
     RET
END-CODE

: TEST-PLUS ( -- )
  100 23 + .   \ 應該印 123
  CR
;
```

如果印出 100 或 23，表示 `+` 的 TOS 邏輯有 bug（最常見：`LEA` 的位移用錯，pop 沒對齊）。

#### 3.3.4 與 C / 一般組語的差異總結

| 寫法 | 指令數 | 是否動 flags | 是否多一次暫存器搬移 |
|------|--------|--------------|----------------------|
| `MOV ECX,[ebp]; LEA ebp,[ebp+4]; ADD eax,ecx` | 3 | 是 | 是 |
| `ADD EAX, [EBP]; LEA EBP, 4 [EBP]` | 2 | 是 | 否 |
| `LEA EAX, [EAX+EBP]; LEA EBP, 4 [EBP]` | 2 | 否 | 否（用 `LEA`） |

第三種只有在「後面不能讓 flags 被改」時才用。SP-Forth 預設走第二種。

---

### 3.4 範例 3：`CELLS`

```forth
CODE CELLS
     LEA EAX, [EAX*4]
     RET
END-CODE
```

**逐步走查**：假設進入 `CELLS` 時 `EAX = 3`（cell 個數）：

| 步驟 | 指令 | 結果 | 對 SP-Forth 而言 |
|------|------|------|-------------------|
| 1 | `LEA EAX, [EAX*4]` | `EAX = 12` | 將 cell 個數轉成 byte 個數（3 cells × 4 bytes/cell = 12 bytes） |
| 2 | `RET` | — | 回 caller |

結束狀態：`EAX = 12`。對應 Forth 語意是 `( n -- n*4 )`（用 byte 數表示同一段距離）。

這裡是很適合初學者理解的 `LEA` 技巧：

- `LEA` 不一定只是「取位址」
- 它也常被拿來做 **不碰記憶體的整數運算**
- 結果只寫到目的暫存器，**不改任何旗標**

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
- 不會改 flags（如果後面要接條件跳或 optimizer 介入，這點很重要）

#### 3.4.1 為什麼用 `LEA` 而不用 `SHL`？

對照表：

| 寫法 | 指令長度 | 是否改 flags | 閱讀意圖 |
|------|----------|--------------|----------|
| `LEA EAX, [EAX*4]` | 3 bytes | 否 | 「乘以 cell size」 |
| `SHL EAX, 2` | 2~3 bytes | 是 | 一般左移 2 位 |
| `ADD EAX, EAX; ADD EAX, EAX` | 4 bytes | 是 | 兩次自我相加 |

`LEA` 在這裡勝在：

1. **不動 flags**：後面若要接 `IF` 或 flags 相關的機器碼，flags 仍是乾淨的。
2. **語意更清楚**：「乘以 4」是位址計算，讀者一看就聯想到 cell size。
3. **單一指令**取代多條 shift/add。

#### 3.4.2 跨平台提醒

這個 `[EAX*4]` 把 cell size 寫死成 4。它是 IA-32-only 假設的痕跡之一：SP-Forth 在 IA-32 上沒有把 `CELL` 常數展開成 `*4`，而是直接 hardcode。要注意的是，若真要移植到 64-bit，**不能只把 scale 改成 8**——還得重新定義 cell 寬度與整個暫存器模型；x86-64 的指標運算通常會改用 `RAX`/`RBP` 等 64-bit 暫存器，而非沿用 IA-32 的 `EAX`/`EBP`。

#### 3.4.3 練習：自己推出 `2 CELLS` 的值

```text
2 CELLS  =>  EAX = 2*4 = 8
3 CELLS  =>  EAX = 3*4 = 12
0 CELLS  =>  EAX = 0
```

如果實際結果對不起來，幾乎可以肯定是 `CELL` 不是 4，或者 `[EAX*4]` 被打成 `[EAX*2]`。

#### 3.4.4 與 `CHAR+` / `CHARS` 的對照

| Forth word | 行為 | 對應指令（IA-32） |
|------------|------|-------------------|
| `CHARS`     | `n` 個 char 對應的 byte 數 | `EAX := EAX * 1`（SP-Forth 通常 **no-op**，因為 `1 * n = n`） |
| `CELL+`     | 把位址前進一個 cell（IA-32 上 = +4 bytes） | `LEA EAX, 4 [EAX]`（`spf_forthproc.f:388-390`） |
| `CELLS`     | `n` 個 cell 對應的 byte 數 | `LEA EAX, [EAX*4]` |
| `CHAR+`     | 把 byte 位址加 1 | `ADD EAX, # 1` 或 `INC EAX` |

可以看到 `CELLS` 是少數真正需要「乘 cell size」的 word；其他多半是常數加法或 no-op。

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

x86 執行 `CALL target` 時，會把「CALL 後面那個位址」推入 `ESP` 指向的回返堆疊。但要注意 `VALUE` 的真實佈局：value cell 在**第一個** CALL 之後、**第二個** CALL 之前（`tc_spf.F:374-377`）：

```text
VALUE 的執行體佈局：              進入 _TOVALUE-CODE 後：

xt+0:  CALL _CONSTANT-CODE  (5B)  ESP → return address（指向 xt+14）
xt+5:  value cell           (4B)        │
xt+9:  CALL _TOVALUE-CODE   (5B)        │  POP EBX 取得 xt+14
xt+14: 下一條指令          ◄────────────┘  LEA EBX,-9[EBX] → xt+5（value cell）
```

因此 `_TOVALUE-CODE` 一開始的 `POP EBX` 不是取一般資料堆疊，而是取出 `CALL _TOVALUE-CODE` 的 x86 return address（= xt+14）。`-9` 是從這個 return address 回退「5-byte CALL + 4-byte value cell」，剛好定位到前面的 value cell（xt+5）——它**回退到 value cell**，而不是讀取緊接在 CALL 後面的資料。

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

**逐步走查**：假設進入 `DUP` 時 `EAX = 0xAB`，`EBP = 0x1000`：

| 步驟 | 指令 | 結果 | 對 SP-Forth 而言 |
|------|------|------|-------------------|
| 1 | `LEA EBP, -4 [EBP]` | `EBP = 0x0FFC` | data stack 推入一格（位置 `0x0FFC` 現在「空著」） |
| 2 | `MOV [EBP], EAX` | `[0x0FFC] = 0xAB` | 把舊 TOS 寫到剛騰出的位置 |
| 3 | `RET` | 控制權回 caller | — |

結束狀態：`EAX = 0xAB`、`EBP = 0x0FFC`、`[0x0FFC] = 0xAB`。也就是 stack 變成 `( 0xAB -- 0xAB 0xAB )`，跟 Forth 的 `( x -- x x )` 對得起來。

**練習重點**：

- push 一格
- 把舊 TOS 寫回 memory
- 保留 `EAX`（不重新載入）
- 全部 **2 條指令** 就完成 `DUP`，這是 TOS-in-EAX 模型最大的回報

#### 6.1.1 對照：若用 C frame pointer 思維會讀錯成什麼？

| 讀法 | 結果 |
|------|------|
| 以為 `EBP` 是 C frame pointer | 會以為 `LEA EBP, -4 [EBP]` 是「準備 local variable」 |
| 以為 `[EBP]` 是 return address | 會以為 `MOV [EBP], EAX` 在覆蓋返回位址而驚慌 |
| 改用正確讀法 | 看到「data stack pointer 往下移一格，把 TOS 寫回去」 |

**記住**：在 SP-Forth，`EBP` 跟 return address **毫無關係**。`RET` 之前一定要先把 Forth 回返堆疊處理好，CPU 才看得到正確的 return target。

#### 6.1.2 一個可以自己跑的測試

```forth
CODE DUP ( x -- x x )
     LEA EBP, -4 [EBP]
     MOV [EBP], EAX
     RET
END-CODE

: TEST-DUP ( -- )
  42 DUP . .  \ 印 42 42
  CR
;
```

執行 `TEST-DUP` 應該印出 `42 42`。如果印出別的（例如 42 然後 0），表示 `DUP` 的 EBP / EAX 邏輯有 bug，幾乎可以確定不是你寫的使用者程式錯了。

---

### 6.2 範例 B：兩數相加

```forth
CODE + ( n1 n2 -- n3 )
     ADD EAX, [EBP]
     LEA EBP, 4 [EBP]
     RET
END-CODE
```

**逐步走查**：假設進入 `+` 時 `EAX = n2`（TOS），`EBP = 0x1000`，`[0x1000] = n1`（次項）：

| 步驟 | 指令 | 結果 | 對 SP-Forth 而言 |
|------|------|------|-------------------|
| 1 | `ADD EAX, [EBP]` | `EAX = n1 + n2` | TOS := 次項 + TOS，**不重複讀** TOS |
| 2 | `LEA EBP, 4 [EBP]` | `EBP = 0x1004` | data stack 彈出一格（被加進去的次項已消耗） |
| 3 | `RET` | 控制權回 caller | — |

結束狀態：`EAX = n1+n2`、`EBP = 0x1004`。Stack effect：`( n1 n2 -- n3 )`。

要練習的重點：

- `EAX` 已是 TOS，不必先 `MOV EAX, ...`
- `[EBP]` 是次項，**`ADD` 一次就夠**（不必先 pop 再 add）
- `LEA EBP, 4 [EBP]` 代表 pop 一格，但**沒有刪除記憶體**——被 pop 的格子其實還在，只是 `EBP` 不再指它
- 整個 `+` 只用 **2 條指令**，連 `MOV` 都省了

#### 6.2.1 為什麼不用先 `POP` 再 `ADD`？

C / 一般組語寫法可能是：

```asm
mov ecx, [ebp]      ; 先把次項備份到 ECX
lea ebp, [ebp+4]    ; pop
add eax, ecx        ; 真的相加
```

但 SP-Forth 知道 `EAX` 馬上就會被新值覆蓋，所以**那個「被 pop 掉的次項」在 `ADD` 完成後就沒人要了**。直接把 `ADD EAX, [EBP]` 接在 `LEA EBP, 4 [EBP]` 之前，少一次暫存器搬移，也少讀一次 `EBP`。

#### 6.2.2 對照：符號/溢位/旗標

- `ADD` 會改 OF/SF/ZF/AF/PF/CF。如果後續會 `IF ... THEN`，這些旗標是設計語意的一部分。
- 若要在 `+` 之後**保留** flags（例如馬上接一段用 flags 的組合語言），就不行；這時需要先把 flags 存在某個地方，或者改用 `LEA` 改寫。
- 對 Forth 來說，`+` 之後通常接的是另一個 Forth word（會再 emit 自己的組語），所以旗標被前一段覆寫是常態，不是問題。

#### 6.2.3 邊界與進位

`ADD EAX, [EBP]` 在 IA-32 是 32-bit 整數加法，不分有號無號。Forth 規格允許 `-` 與 `+` 在 cell 範圍內 wrap around（`ADDRESS-UNIT-BITS` 與 `MAX-N`/`MAX-U` 由實作決定），SP-Forth 的 `+` 不做額外檢查。

---

### 6.3 範例 C：把 cell 大小內化成位址運算

```forth
CODE CELLS
     LEA EAX, [EAX*4]
     RET
END-CODE
```

**逐步走查**：假設進入 `CELLS` 時 `EAX = 3`（cell 個數）：

| 步驟 | 指令 | 結果 | 對 SP-Forth 而言 |
|------|------|------|-------------------|
| 1 | `LEA EAX, [EAX*4]` | `EAX = 12` | 將 cell 個數轉成 byte 個數（3 cells × 4 bytes/cell = 12 bytes） |
| 2 | `RET` | — | 回 caller |

結束狀態：`EAX = 12`。對應 Forth 語意是 `( n -- n*4 )`（用 byte 數表示同一段距離）。

這個例子很適合拿來理解：

- `LEA` 常被當成 integer arithmetic
- SP-Forth 的 cell 在 IA-32 上是 4 bytes
- `[EAX*4]` 的 `4` 來自 cell 大小；如果換到 64-bit SP-Forth，這個常數會變 `8`

#### 6.3.1 為什麼用 `LEA` 而不用 `SHL`？

對照表：

| 寫法 | 指令長度 | 是否改 flags | 閱讀意圖 |
|------|----------|--------------|----------|
| `LEA EAX, [EAX*4]` | 3 bytes | 否 | 「乘以 cell size」 |
| `SHL EAX, 2` | 2~3 bytes | 是 | 一般左移 2 位 |
| `ADD EAX, EAX; ADD EAX, EAX` | 4 bytes | 是 | 兩次自我相加 |

`LEA` 在這裡勝在：

1. **不動 flags**：後面若要接 `IF` / 旗標相關指令，flags 仍是乾淨的。
2. **語意更清楚**：「乘以 4」是位址計算，讀者一看就聯想到 cell size。
3. **單一指令**取代多條 shift/add。

#### 6.3.2 跨平台提醒

這個 `[EAX*4]` 把 cell size 寫死成 4。它是 IA-32-only 假設的痕跡之一：SP-Forth 在 IA-32 上沒有把 `CELL` 常數展開成 `*4`，而是直接 hardcode。要注意的是，若真要移植到 64-bit，**不能只把 scale 改成 8**——還得重新定義 cell 寬度與整個暫存器模型；x86-64 的指標運算通常會改用 `RAX`/`RBP` 等 64-bit 暫存器，而非沿用 IA-32 的 `EAX`/`EBP`。

#### 6.3.3 練習：自己推出 `2 CELLS` 的值

```text
2 CELLS  =>  EAX = 2*4 = 8
3 CELLS  =>  EAX = 3*4 = 12
0 CELLS  =>  EAX = 0
```

如果實際結果對不起來，幾乎可以肯定是 `CELL` 不是 4，或者 `[EAX*4]` 被打成 `[EAX*2]`。

---

### 6.4 範例 D：無分支比較

```forth
XOR EAX, [EBP]
SUB EAX, # 1
SBB EAX, EAX
LEA EBP, 4 [EBP]
RET
```

這是 `=` 的本體，會把 `( x1 x2 -- flag )`，其中 `flag` 是 `-1`（相等）或 `0`（不相等）。

**逐步走查**：假設進入時 `EAX = x1`，`EBP = 0x1000`，`[0x1000] = x2`：

| 步驟 | 指令 | 若 x1 = x2 | 若 x1 ≠ x2 | 重點 |
|------|------|------------|------------|------|
| 1 | `XOR EAX, [EBP]` | `EAX = 0` | `EAX = x1 XOR x2 ≠ 0` | 把兩個值的差轉成「是否為 0」 |
| 2 | `SUB EAX, # 1` | `EAX = -1`（0xFFFFFFFF），`CF = 1`（借位） | `EAX` 視差值而變，`CF = 0` | 借位旗標記住「原本是否為 0」 |
| 3 | `SBB EAX, EAX` | `EAX = -1`（CF 為 1，`EAX - EAX - 1`） | `EAX = 0`（CF 為 0，`EAX - EAX - 0`） | 把 CF 轉成 Forth 真值 |
| 4 | `LEA EBP, 4 [EBP]` | `EBP += 4` | `EBP += 4` | pop 次項 |
| 5 | `RET` | — | — | — |

練習的重點：

- CPU flags 也是資料流的一部分
- `SBB reg, reg` 是經典「把 CF 變成 0 / -1」技巧
- **完全沒有跳轉**——這也是為什麼 SP-Forth 的 `=` 沒有 branch misprediction 成本

#### 6.4.1 為什麼 Forth 用 `-1` 當 true？

Forth 的布林慣例是「所有 bit 為 1」才是 true。這條慣例的歷史原因之一是「-1 的 bitwise NOT 是 0」與「對任何 cell 來說，NOT 0 就是 -1」這兩個事實剛好對得起來。

`SBB EAX, EAX` 巧合地同時滿足：

- 兩種情況結果都是 `0` 或 `-1`（不會有其他值）
- 結果**所有 bit**都一致（全 0 或全 1），符合 Forth truth 慣例

如果換成 `JNE label; MOV EAX, -1; label: MOV EAX, 0`，結果雖然一樣，但：

1. 多了一條分支。
2. branch predictor 失準時會痛。
3. 多了一個 forward reference / label，後續 optimizer 還得多一個最佳化規則。

#### 6.4.2 為什麼 `SUB 1` 用在 `XOR` 之後？

`XOR EAX, EAX`（自己 XOR 自己）會把 flags 清成「結果為 0」。但**這裡的 XOR 是 `EAX` 與 `[EBP]`**，結果不一定是 0。`SUB EAX, # 1` 是把「`XOR` 結果是不是 0」轉成「借位旗標 CF」：

- 若 XOR = 0，SUB 0-1 = -1，CF = 1（借位）
- 若 XOR ≠ 0，SUB (XOR) - 1，CF = 0（除非 XOR 正好是 0，這個 case 上面處理過）

CF 才是我們要的「相等旗標」。`SBB` 把 CF 翻成 Forth 布林。

#### 6.4.3 對照：用 `CMP` + 條件賦值怎麼寫？

```asm
cmp eax, [ebp]
mov eax, 0
jne done
mov eax, -1
done:
lea ebp, 4 [ebp]
ret
```

功能一樣，但分支明確。SP-Forth 的寫法則把這四條壓成四條**線性**指令，沒有任何 branch，optimizer 也更好處理。

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

這是 Windows callback / Linux signal handler 風格的橋接器，把外部 C 函式的呼叫 frame 翻譯成 SP-Forth 可以執行的環境。

**逐步走查**：

| 步驟 | 指令 | 為什麼 |
|------|------|--------|
| 1 | `MOV EAX, ESP` | 把目前 x86 stack pointer 存到 `EAX`。稍後 Forth 離開時要還原。 |
| 2 | `SUB ESP, # 3968` | 在 x86 stack 開 3968 bytes 的「工作區」，給 Forth 模擬使用。 |
| 3 | `A;` | 強迫 assembler 完成 `SUB` 的 emit。 |
| 4 | `HERE 4 - ' ST-RES 9 + EXECUTE` | 倒回到剛 emit 的 `3968` 欄位，呼叫 Forth 字 `ST-RES 9 +` 把它修成「回填位置」。 |
| 5 | `PUSH EBP` | 把目前的 `EBP`（其實是 data stack pointer）保護到 x86 stack 頂端。 |
| 6 | ... | 中段可能是建立新的 `EBP`、`EDI`（USER base）、初始化 local 變數的程式碼。 |
| 7 | `CALL EBX` | 呼叫真正的 Forth 主體（由 callback 流程決定）。 |
| 8 | ... | 收尾、把回返值整理到 `EAX`。 |
| 9 | `XCHG EAX, [ESP]` | EBP 已由先前的 `MOV EBP, 4 [EAX]` 還原（`posix/api.f:71`）；此處把 `EAX`（Forth 回返值）與 `[ESP]`（堆疊頂端的返回位址）對調，使回返值留在 EAX、返回位址回到堆疊頂端，接著 `RET` 只負責彈出返回位址到 EIP。`RET` 不會 pop 任何東西到 EBP。 |
| 10 | `RET` | x86 跳回 callback 的 caller；`EAX` 是回返值。 |

這個例子比前面難很多，因為它一次混了：

- x86 stack / register 保存
- SP-Forth 資料堆疊重建
- `A;` 切回 Forth 做組裝期修補
- callback 回傳值整理

建議讀法：

1. 先只看 `MOV/SUB/PUSH/CALL/POP/XCHG`
2. 再看它怎麼把 C callback frame 轉成 Forth 可執行環境
3. 最後才看 `A;` 那一行的 metaprogramming 意味

#### 6.5.1 為什麼要 `A;`？

`SUB ESP, # 3968` 這條指令要 emit 的 `3968` 是 4-byte immediate，assembler 必須先知道 Forth 字面常數的值才能 emit。等到 Forth 真的跑完 `:` 定義，那個 4-byte 欄位就已經躺在 dictionary 裡了。

`A; HERE 4 - ' ST-RES 9 + EXECUTE` 則是：

- `A;` 收尾前一條組語。
- `HERE 4 -` 拿到剛 emit 出去的 `3968` 欄位位址。
- `' ST-RES 9 +` 計算回填目標位址（`ST-RES` 是某個常駐 Forth word，它的位址加 9 指向某個固定偏移）。
- `EXECUTE` 跑那個 Forth 字，**在編譯期**把欄位修好。

#### 6.5.2 為什麼 callback 還要保護 `EBP`？

在 callback 內部，SP-Forth 要建立自己的 data stack（在 Windows 上就是這 3968 bytes 的保留區）。`EBP` 會被改成指向這塊新區域的某個位置。callback 結束時必須把**外層**的 `EBP` 還原，否則外部 C 程式看到 `EBP` 突然指到奇怪的位址會 crash。

`PUSH EBP` 在進入時保護外層 EBP；離開時由 `MOV EBP, 4 [EAX]` 還原 EBP。`XCHG EAX, [ESP]; RET` 只是 wrapper 的返回位址/回傳值整理序列（把回傳值放進 EAX、返回位址放回堆疊頂端再 `RET`），它**不**負責還原 EBP。

#### 6.5.3 練習：把它壓成 pseudo-Forth

```text
callback_frame:
  保留舊 ESP        \ MOV EAX, ESP
  開 3968 bytes    \ SUB ESP, 3968
  記住「還原位置」 \ A; ... ST-RES ...
  保護舊 EBP       \ PUSH EBP
  建立新 data stack \ 設定 EBP / EDI
  跑 Forth 主體    \ CALL EBX
  取回 Forth TOS   \ 從 stack 讀到 EAX
  還原舊 EBP       \ XCHG EAX, [ESP]
  返回 C caller    \ RET
```

這 9 個步驟就是 `_WNDPROC-CODE` 之類橋接器的本質。

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

**逐步走查**：這個字在**編譯期**被呼叫，參數 `addr` 是要被呼叫的 Forth word 的 CFA（Code Field Address）：

| 步驟 | 程式碼 | 發生在什麼時候 | 作用 |
|------|--------|----------------|------|
| 1 | `?SET` | 編譯期 | 清掉過時的 OP / JP 緩衝區 |
| 2 | `SetOP` | 編譯期 | 記錄「下一條機器碼的 DP 起點」 |
| 3 | `0E8 C,` | 編譯期 | 把 `CALL rel32` 的 opcode `0xE8` 寫進 dictionary |
| 4 | `DP @ CELL+ - ,` | 編譯期 | emit opcode 後 `DP @` 是 rel32 欄位起點；`CELL+` 前進到下一條指令位址（CALL 起點 + 5），以此為基準算 `addr` 的 rel32，emit 為 4-byte literal |
| 5 | `DP @ TO LAST-HERE` | 編譯期 | 把這條 machine instruction 的結束位址記起來，給 optimizer 用 |

#### 6.6.1 一個具體數字

假設 `TC-CALL,` 被呼叫時（注意區分「CALL 起點」與「emit opcode 後的 DP」）：

- `addr = 0x00403000`（某個 Forth word 的 CFA）
- CALL opcode（`0xE8`）位於 `0x00401010`
- emit 完 `0xE8` 後，`DP = 0x00401011`（rel32 欄位的起點）
- rel32 的計算基準是 `DP @ CELL+ = 0x00401011 + 4 = 0x00401015`（也就是 CALL 起點 + 5 = 下一條指令位址）

emit 出來的 4-byte displacement 就是：

```text
0x00403000 - 0x00401015 = 0x00001FEB
```

寫進 dictionary 後，target 執行到這條 CALL 時，CPU 算 `IP_next + rel32 = 0x00401015 + 0x00001FEB = 0x00403000`，正好跳到 `addr`。

#### 6.6.2 為什麼 `DP @ CELL+ - ,` 不是 `DP @ - ,`？

CALL 的 rel32 計算基準是 **「CALL 指令結束、下一條指令的位址」**（CALL 起點 + 5），不是「CALL 的起始位址」，也不是「rel32 欄位起點」：

```forth
[ CALL起點   ] 0xE8     \ CALL opcode，1 byte
[ CALL起點+1 ] rel32    \ 4 byte；emit opcode 後 DP @ 指向這裡
[ CALL起點+5 ] ← 下一條指令；這才是 rel32 的基準（= DP @ CELL+）
```

所以是 `DP @ CELL+ - ,`：emit opcode 後 `DP @` 是 rel32 欄位起點，`CELL+` 再前進 4 bytes 到下一條指令位址，最後 `addr - 下一條指令位址` 才是正確的 rel32。

#### 6.6.3 為什麼要 `LAST-HERE`？

`LAST-HERE` 是「上一條 machine instruction 的結束位址」。`OPT_CLOSE` / `RESOLVE_OPT` 之後的優化器會用這個值判斷哪些 OP / JP 插槽還在目前最佳化邊界內，避免誤刪。

把 `DP @ TO LAST-HERE` 放在每條 emit 結尾，等於是告訴 optimizer：「這條 CALL 的邊界在這裡，後續的優化不要跨過它。」

#### 6.6.4 對照：`C,` / `,` 在這裡不是「執行」

| 寫法 | 跑在 | 會做什麼 |
|------|------|----------|
| `0E8 C,` | 編譯期 | 寫出 1 byte `0xE8` |
| `,` | 編譯期 | 寫出 1 cell |
| `EXECUTE` | 執行期 | 真的呼叫某個 Forth word |

`C,` / `,` 是 byte emitter；`EXECUTE` 是控制流。讀到 `C,` / `,` 時，**它們不會在這一刻跳到任何地方**；它們只是在擴充 image。

#### 6.6.5 練習：寫一個最簡單的 `TC-JMP,`

```forth
: TC-JMP, ( addr -- )
  ?SET  SetOP
  0xE9 C,           \ JMP rel32 opcode
  DP @ CELL+ - ,
  DP @ TO LAST-HERE
;
```

跟 `TC-CALL,` 的差別只有 opcode（`0xE8` → `0xE9`）和「CALL 會 push return address / JMP 不會」。如果這段拼對了，你可以用 `TC-JMP,` 在 compile-time 產生一個長跳 JMP，並用 `RESOLVE_OPT` 在後續把 `0xE9` 縮成短跳 `0xEB`（見 [07-optimizer.md](07-optimizer.md) §6.2.5）。

---

## 7. 初學者最常卡住的地方

### 7.1 不要把 `EBP` 當 C frame pointer

在這套 codebase 裡，`EBP` 幾乎都應先翻譯成：

> data stack pointer，且 `[EBP]` 是次堆疊項

#### 7.1.1 對照表

| 你以為的 C 語意 | 真正的 SP-Forth 語意 |
|------------------|----------------------|
| `EBP` 是函式的 frame pointer | `EBP` 是 data stack pointer |
| `[EBP-4]` 是 local variable | `[EBP-4]` 還是堆疊，只是位置在 `EBP` 下方一格 |
| `push %rbp; mov %rsp,%rbp` 的固定 prologue | 沒有 prologue；`EBP` 從開機就由 VM 自己維持 |
| `[EBP+8]` 才是呼叫者的參數 | `[EBP]` 永遠是「上一個被推上去的值」 |

#### 7.1.2 用 `DUP` 當例子

`DUP` 的 kernel primitive 真的就是這兩條：

```asm
LEA EBP, -4 [EBP]      ; data stack 往下移一格
MOV [EBP], EAX         ; 把 TOS 寫到新的 TOS 位置
```

如果硬把它當 C frame 看，就會卡在：

- 為什麼 `LEA EBP, -4[EBP]` 是「宣告一個 local」而不是「調整 sp」？
- 為什麼「函式入口」沒有 `push ebp; mov ebp, esp`？

把 `EBP` 翻成「data stack pointer」之後，兩條指令的語意馬上變成：

1. 把 stack pointer 往下移 1 cell，騰出一格空間。
2. 把目前 TOS 寫進這格新空間。完成後，stack 變成「原本 TOS、原本 TOS」。

#### 7.1.3 反例：什麼時候 `EBP` **不是** data stack pointer

少數情況下 `EBP` 暫時不是 data stack pointer，例如 `_WNDPROC-CODE`：

```forth
CODE _WNDPROC-CODE
     MOV  EAX, ESP        \ 暫時把 ESP 的位置交給 EAX
     SUB  ESP, # 3968
A;   HERE 4 - ' ST-RES 9 + EXECUTE
     ...
     RET
END-CODE
```

這裡 `MOV EAX, ESP` 是在保護 x86 stack 的當前位置，準備在 Windows callback 結束時用 `ST-RES` 還原。所以讀到 `EAX` / `EBP` 的時候還是要看「這段是在做什麼事」，不要無條件套用 TOS / data stack pointer 規則。

#### 7.1.4 簡單的閱讀清單

讀到任何 `EBP` 時，依序問自己：

1. 這段是在 SP-Forth 的 data stack 邏輯裡，還是在保護某個 x86 / OS 結構？
2. `[EBP]` 是「次堆疊項」嗎？
3. 這條指令是要調整 stack 位置（`LEA`）還是真的讀寫資料（`MOV`）？

#### 7.1.5 常見誤讀示意

```text
以為：                                事實：
┌──────────┐                          ┌──────────┐
│ return   │ ← EBP+4                  │ 舊 TOS   │ ← EBP   (= 次堆疊項)
├──────────┤                          ├──────────┤
│ locals   │ ← EBP                    │  TOS     │ ← EAX
├──────────┤                          ├──────────┤
│ args     │ ← EBP-8                  │  (尚未寫入) │ ← EBP-4 (空)
```

左邊是 C 函式的 frame；右邊是 SP-Forth 的 data stack 形狀。差異在「`EBP` 指向哪一格」與「下一格是不是 caller 的區域」。

---

### 7.2 不要把 `CODE` 和 metacompiler byte emission 混成一類

兩者的「產出物」長得很像，都是 x86 bytes，但發生時間完全不同：

| 寫法 | 發生時間 | 產出 | 看到的程式碼 |
|------|----------|------|---------------|
| `CODE ... END-CODE` | target 載入後執行某字時 | 一塊會被 CPU 跑到的 machine code | 直接的組語指令 |
| `C,` / `,` / `W,` / `RET,` | 編譯期 | target image 裡的 bytes | Forth 程式碼呼叫 emit 字 |

#### 7.2.1 `CODE ... END-CODE` 是 runtime primitive

`CODE` 區塊定義的是一個 Forth word，執行這個 word 時，CPU 就會跑你寫進去的機器碼。

```forth
CODE NOP-LIKE ( x -- x )
     RET
END-CODE
```

執行 `NOP-LIKE` 時，CPU 拿到一條 `RET`，馬上把控制權交回去。`NOP-LIKE` 的執行碼欄位（CFA）就是這一條 `0xC3`。

#### 7.2.2 `C,` / `,` 是 compile-time byte emission

`C,` 把一個 byte 寫到 DP；`,` 把一個 cell 寫到 DP。它們**不會自己執行任何機器碼**——只是在擴充正在被編譯的那塊 target image。

```forth
: TC-CALL, ( addr -- )
  ?SET
  SetOP
  0E8 C,              \ 寫出 CALL opcode（執行時才會被 CPU 解讀）
  DP @ CELL+ - ,
  DP @ TO LAST-HERE
;
```

這段程式碼執行時（編譯期），它把：

- `0xE8`（CALL rel32 的 opcode）
- 一個 4-byte 的相對位移

寫進 target dictionary。target 執行到這個位置時，CPU 才看到一條 `CALL`。

#### 7.2.3 混用的陷阱

| 情境 | 你以為 | 實際 |
|------|--------|------|
| 在 `CODE` 區塊裡看到 `RET` | 編譯期寫出 `0xC3` | runtime 立即返回上一層 |
| 在 `:` 定義裡看到 `0xC3 C,` | runtime 執行 `0xC3` | compile-time 寫一個 byte 進 image |
| 兩者都有名字 `RET` | 同一個 word | 不同 word；compile-time 版本叫 `RET,`（多一個逗號） |

#### 7.2.4 快速判斷法

讀到一段組語時，問自己：

1. 這段是被 `CODE` 還是 `:` 包起來？
2. 如果是 `CODE`，那這段是**這個 word 被呼叫時**才會跑。
3. 如果是 `:` 或在 high-level 編譯輔助字裡，那 `C,` / `,` / `W,` 是把 bytes 寫進 image，不是執行。

---

### 7.3 看到 `LEA` 先想「位址/縮放/stack 調整」

在 SP-Forth 裡，`LEA` 常常比 `MOV` 還更關鍵，因為它隱含了：

- push/pop
- index scaling
- embedded data 回退

#### 7.3.1 LEA 不碰記憶體，但會算位址

```asm
LEA EBP, -4 [EBP]      ; EBP -= 4（data stack 推入一格）
LEA EBP,  4 [EBP]      ; EBP += 4（data stack 取出一格）
LEA EAX, [EBX + ECX*4] ; EAX = EBX + ECX*4（純計算）
```

第一條不是「取某個 local 的位址」，而是「把 data stack pointer 往下移一格」。

#### 7.3.2 三種常見用途對照

| 用途 | 形式 | 例子 |
|------|------|------|
| stack push | `LEA EBP, -N [EBP]` | `LEA EBP, -4 [EBP]` = 把 data stack 推入一格 cell |
| stack pop | `LEA EBP, +N [EBP]` | `LEA EBP, 4 [EBP]` = 把 data stack 取出一格 cell |
| scaled index | `LEA EAX, [base + idx*scale + disp]` | `LEA EAX, [EBX + ECX*4]` = 算陣列元素的位址 |

#### 7.3.3 embedded data 回退：`_TOVALUE-CODE`

```forth
CODE _TOVALUE-CODE
     POP EBX                 \ 取回 x86 return address
     LEA EBX, -9 [EBX]       \ 把 return address 倒推到「嵌入 value cell」位置
     MOV [EBX], EAX          \ 把新值寫入該 cell
     ...
     RET
END-CODE
```

這條 `LEA EBX, -9 [EBX]` 是用 `LEA` 從 return address 倒推回嵌在 code stream 裡的 value 欄位。`9` 不是魔術數字：它是「5-byte `CALL _TOVALUE-CODE` ＋ 4-byte value cell」的總長度——從 `CALL _TOVALUE-CODE` 之後的 return address 回退 9 bytes，剛好落在 value cell（見 §4.3a 的佈局圖）。

#### 7.3.4 怎麼快速判斷 `LEA` 在做什麼

| 看到 | 第一個猜測 |
|------|------------|
| `LEA EBP, ±N [EBP]` | 推/取 data stack |
| `LEA ESP, ±N [ESP]` | 推/取 x86 return stack |
| `LEA reg, [base + idx*scale + disp]` | 算陣列元素位址，或 `MOV` 結果的替代 |
| `LEA reg, [reg - 常數]` | 從 return address 回推 embedded data |

#### 7.3.5 跟 `MOV` / `SUB` 的差別

| 想做的事 | 寫法 | 為什麼常被誤用 |
|----------|------|----------------|
| data stack 推入一格 | `LEA EBP, -4 [EBP]` | 看起來像「取位址」，其實是「移動 SP」 |
| 真的讀 `[EBP-4]` 內容 | `MOV reg, -4 [EBP]` | 會觸發記憶體讀取，語意完全不同 |
| 純加法但不想動 flags | `LEA EAX, 4 [EAX]` | 與 `ADD EAX, #4` 等價，但不會改 flags |

#### 7.3.6 為什麼 SP-Forth 偏愛 `LEA`？

- 不改 flags，下一段邏輯不會被前一段影響。
- 不用先 `MOV` 到另一個暫存器再運算。
- 對 `EBP` 的 push/pop 來說，**只有 `LEA` 才能表達「我要的不是值，是 stack 位置」**。

---

### 7.4 看到 `A;` 時，要切換成「assembler 不是純文字，而是可編程工具」的心智模型

這是 SP-Forth 很值得學的地方：

- 組語不是被動語法
- 它可以和 Forth 的 metaprogramming 混在一起
- 你可以一邊輸出 bytes，一邊運算、修補、植入資料

#### 7.4.1 `A;` 是什麼

`lib/asm/486asm.f` 對 `A;` 的定義是：

```forth
: A; ( FINISH THE ASSEMBLY OF THE PREVIOUS INSTRUCTION )
        0 DO-OPCODE ;
```

它本身**不是** x86 指令。它告訴 assembler：「把前一條 assembler 指令收尾，確定 bytes 都已經寫出來了。」

#### 7.4.2 為什麼需要 `A;`？

在 SP-Forth assembler 裡：

- `MOV EAX, # 5` 這種 immediate 形式，需要等 Forth 算出 immediate 才能寫出完整 bytes。
- Assembler 會延後真正 emit，直到它能確定所有 operand 都齊全。

如果中間想「先回到 Forth 算點東西，再繼續寫組語」，就需要 `A;` 強迫 assembler 把前一條指令收尾，然後切換到 Forth 模式。

#### 7.4.3 實例：`_WNDPROC-CODE` 的 stack reservation

```forth
CODE _WNDPROC-CODE
     MOV  EAX, ESP        \ 保留目前的 ESP
     SUB  ESP, # 3968
A;   HERE 4 - ' ST-RES 9 + EXECUTE
     ...
     RET
END-CODE
```

逐行解讀：

1. `MOV EAX, ESP`：把目前 ESP 存到 `EAX`。
2. `SUB ESP, # 3968`：保留 3968 bytes 給 Windows callback 用。`A;` 之前 assembler 還沒把這條 SUB 收尾。
3. `A;`：完成 SUB 的 emit，bytes 都在 dictionary 裡了。
4. `HERE 4 -`：回到剛剛 emit 出去的 immediate 欄位（4 byte 的 `3968`）。
5. `' ST-RES 9 + EXECUTE`：呼叫一個 Forth word，把 `ST-RES` 的位址加 9（這條指令之後的位移），用 Forth 邏輯把這個欄位補成「回填位置」。

#### 7.4.4 心智模型切換

讀到 `A;` 時，要把腦袋切換成「**我正在寫一個可以呼叫 Forth 的組語組裝器**」：

```text
平常讀組語：                    讀到 A; 時：
  指令 → 指令 → 指令               指令 → 指令 → [回到 Forth]
                                       ↑                  ↓
                                       └── A; 把前一條收尾 ──┘
                                                  ↓
                                       Forth 計算、修補、emit
                                                  ↓
                                       [切回 assembler] → 指令
```

也就是說，`A;` 讓你在兩條 machine code 指令之間插入「任意 Forth 程式」，而不是只能單純接續下一條組語。

#### 7.4.5 常見的 `A;` 用法

| 用法 | 模式 |
|------|------|
| 回填剛 emit 的欄位 | `A; HERE N - ' something EXECUTE` |
| 在 code stream 裡塞 runtime 計算的常數 | `A; HERE ... ,` |
| 把 branch target 留給 Forth 算 | `A; HERE ... !` |
| 切換到其他 wordlist / state | `A; ['] ... EXECUTE` |

#### 7.4.6 為什麼這對讀 SP-Forth 很重要

SP-Forth 不是「先寫好組語字串再 emit」，而是「**邊組邊算**」。`A;` 是這個模型最重要的開關。看到 `A;` 時，要準備好「接下來是 Forth 邏輯，後面才再回到 assembler」，這樣讀 metacompiler 與 cross-compiler 章節才不會卡住。

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
