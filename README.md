# mini-dex-qa — Web3 安全测试作品集

> 一个最小化 DEX（AMM 恒定乘积池）+ **5 类链上攻击的完整攻防验证**。
> 全部合约与测试手写完成，18 个测试全 PASS。
>
> **开发环境**：Foundry (Solidity ^0.8.20) | **测试框架**：forge test + fuzzing + invariant

---

## 项目结构

```
contracts/
├── src/
│   ├── Token.sol          # ERC20 代币（mint/transfer/approve/transferFrom）
│   ├── BadToken.sol       # 恶意 Token（transfer/transferFrom 返回 false，不 revert）
│   ├── Pool.sol           # AMM 恒定乘积池（ETH ↔ Token swap，0.3% 手续费）
│   ├── Vault.sol          # 有漏洞的存钱罐（演示重入攻击）
│   ├── Attack.sol         # 重入攻击合约
│   └── PermitSwap.sol     # EIP-712 链下签名授权 swap（防重放）
├── test/
│   ├── Token.t.sol        # ERC20 功能测试
│   ├── BadToken.t.sol     # 假充值漏洞验证
│   ├── Pool.t.sol         # Pool 功能 + Fuzzing + 三明治攻击 + 价格操纵
│   ├── Pool.invariant.t.sol  # x×y=k 不变式测试（128,000 次随机操作）
│   ├── Attack.t.sol       # 重入攻击验证
│   └── PermitSwap.t.sol   # 签名重放防护验证
```

---

## 快速启动

```bash
# 安装 Foundry
curl -L https://foundry.paradigm.xyz | bash && foundryup

# 运行全部测试
cd contracts && forge test -vvv

# 运行指定测试
forge test --match-test test_Reentrancy -vvv
forge test --match-test test_FrontrunSandwich -vvv
forge test --match-test test_PermitSwapReplayReverts -vvv

# 运行 Invariant Test（随机操作序列）
forge test --match-test invariant_XTimesYNeverDecreases -vvv
```

---

## 测试覆盖

| 模块 | 测试数 | 类型 | 状态 |
|------|:--:|------|:--:|
| Token.sol | 3 | 功能 + 回滚 | ✅ |
| Pool.sol | 10 | 功能 + Fuzz(256 runs) + 三明治 + 价格操纵 | ✅ |
| Pool 不变式 | 1 | Invariant (128,000 calls) | ✅ |
| Vault + Attack | 2 | 重入攻击 + 资金回收 | ✅ |
| PermitSwap | 2 | EIP-712 签名 + 重放防护 | ✅ |
| BadToken | 2 | 假充值（返回值未检查） | ✅ |
| **合计** | **20** | — | **全部 PASS** |

---

## 5 类链上攻防

### 1. 重入攻击 (Reentrancy Attack)

**原理**：合约在更新状态之前进行外部调用（ETH 转账），攻击者利用 receive() 回调在状态更新前重复进入提款函数。

```
攻击链：deposit → withdraw → receive() 检测 Vault 余额 → 再次 withdraw → 循环直到 Vault 被掏空
```

**模拟方式**：
- `Vault.sol`：`withdraw()` 先 `.call{value}` 再 `balances = 0`（漏洞版本）
- `Attack.sol`：`receive()` 中判断 Vault 余额并循环调用 `withdraw()`
- 单次 deposit 5 ETH，反复提取同一余额，最终掏空 Vault（含其他用户存款）

**防护方案**：先清零余额再转账，或使用 OpenZeppelin `ReentrancyGuard`

| 文件 | 说明 |
|------|------|
| `src/Vault.sol` | 漏洞合约 |
| `src/Attack.sol` | 攻击合约 |
| `test/Attack.t.sol` | 攻击验证 |

---

### 2. 闪电贷价格操纵 (Flash Loan Price Manipulation)

**原理**：闪电贷无抵押借巨资 → 一次性砸入 AMM 池子 → 现货价格被瞬间扭曲 → 攻击者利用被操纵的价格在其他协议套利。

```
借 900 ETH → 砸进 100 ETH 池子 → 现货价从 2,000 跌至 554 Token/ETH（暴跌 72%）
```

**模拟方式**：通过 Fuzz 测试随机生成 256 个 swap 金额，验证"金额越大，价格扭曲越严重"。

**防护方案**：使用 TWAP（时间加权平均价格）替代现货价格作为关键决策依据

| 文件 | 说明 |
|------|------|
| `test/Pool.t.sol` | `testFuzz_LargeSwapChangesPrice` + `test_SpotPriceManipulated` |

---

### 3. 三明治攻击 (Sandwich Attack)

**原理**：攻击者在 Mempool 中看到受害者的待处理交易 → 抢先执行同向交易拉高价格 → 受害者以更差价格成交 → 攻击者反向交易出场获利。

```
Bob 抢跑(ETH→Token) → Alice 被夹(ETH→Token，价格已涨) → Bob 出场(Token→ETH，高位抛售)
```

**模拟方式**：在 Pool 测试中手动控制交易顺序，对比 Bob 攻击前后 ETH 余额。

**防护方案**：用户设置 `minTokensOut` 滑点保护；协议使用 commit-reveal 机制隐藏订单

| 文件 | 说明 |
|------|------|
| `test/Pool.t.sol` | `test_FrontrunSandwich` |
| `src/Pool.sol` | `swapETHForToken` + `swapTokenForETH`（双向 swap 支持三明治） |

---

### 4. 签名重放攻击 (Signature Replay Attack)

**原理**：同一份链下签名在多个链或多次被重复使用。无防护时，攻击者拿到签名即可无限次执行授权操作。

**模拟方式**：
- `PermitSwap.sol` 实现 EIP-712 标准签名验证
- 测试中 Alice 链下签名授权 swap → Bob 拿签名上链执行
- 同一签名第二次使用 → nonce 已自增 → `ecrecover` 恢复的签名者不匹配 → revert

**三重防护**：

| 字段 | 防护维度 |
|------|---------|
| `chainId` | 跨链重放（Mainnet 签名在 Polygon 无效） |
| `nonce` | 同链重放（每个签名仅可使用一次） |
| `deadline` | 延后重放（过期签名自动失效） |

| 文件 | 说明 |
|------|------|
| `src/PermitSwap.sol` | EIP-712 签名验证合约 |
| `test/PermitSwap.t.sol` | 签名执行 + 重放 revert 验证 |

---

### 5. 精度漏洞 / 假充值 (Precision & Fake Deposit)

**原理**：部分 ERC20（如 USDT）不遵循标准，`transferFrom` 返回 void 或不返回 bool；部分 Token 转账失败静默返回 false 而不 revert。合约未检查返回值 → 记录虚假入账。

**模拟方式**：`BadToken.transfer/transferFrom` 永远返回 `false` 但不 revert → Pool 的 `addLiquidity` 未检查返回值 → `tokenReserve` 凭空增加 5000 Token → Pool 实际余额为 0。攻击者以零成本获得了流动性份额。

**测试验证**：
- `test_FakeDepositInflatesReserve`：验证 tokenReserve 增加但 Pool 实际 Token 余额为 0
- `test_FixedPoolRevertsOnBadToken`：确认漏洞存在（当前 addLiquidity 不 revert）

**防护方案**：在 Pool 合约中对 `transferFrom` 调用加上 `require(xxx, "transfer failed")`，或使用 OpenZeppelin `SafeERC20` 库

| 文件 | 说明 |
|------|------|
| `src/BadToken.sol` | 返回 false 的恶意 Token |
| `test/BadToken.t.sol` | 假充值漏洞验证 |

---

## Fuzzing 与 Invariant Test

### Fuzzing（随机输入空间探索）

Forge 自动生成 256 个随机 swap 金额，在 `[21001 wei, 10 ETH]` 范围内逐一执行，确保：
- 所有合法金额均能成功 swap
- 极小金额不会导致 `ethAfterFee = 0`（整数除法精度 bug 已发现并修复）
- 大额 swap 不破坏合约状态

### Invariant Test（合约级不变式验证）

128,000 次随机操作序列（swap + addLiquidity），验证 x×y=k 恒定乘积法则：

```
无论任何操作序列，ethReserve × tokenReserve 永不低于初始值
```

Forge 在 128,000 次操作中未发现 invariant 违规。

---

## 技术栈

| 层级 | 技术 |
|------|------|
| 智能合约 | Solidity ^0.8.20 |
| 测试框架 | Foundry (forge test) |
| 测试类型 | Unit / Fuzz / Invariant |
| 作弊码 | vm.deal / vm.prank / vm.sign / vm.expectRevert |
| 签名标准 | EIP-712 (Typed Structured Data) |

---

## 运行要求

- Foundry >= v1.0.0
- Solidity ^0.8.20
- macOS / Linux

---

## 作者

Jim — 7 年功能测试经验，正在从手工测试转型 Web3 测试开发。
本项目的每个合约与测试均为独立手写完成（非 AI 代写）。

---

> **面试能讲的**：5 类攻击的原理、模拟方式、防护方案、Fuzzing vs Invariant Test 的区别、为什么 x×y=k 不变式是最重要的 DeFi 安全测试之一。
