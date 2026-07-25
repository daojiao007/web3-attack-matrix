# web3-attack-matrix — Web3 安全攻防测试矩阵

> AMM 恒定乘积池 + **5 类链上攻击的完整攻防验证**。
> 全部合约与测试手写完成，**20 个测试全 PASS**。
>
> **技术栈**：Solidity ^0.8.20 + Foundry (forge test / fuzzing / invariant) + Docker

---

## 项目结构

```
web3-attack-matrix/
├── src/                     # 6 个合约
│   ├── Token.sol            # ERC20 代币（mint/transfer/approve/transferFrom）
│   ├── BadToken.sol         # 恶意 Token（transfer 返回 false，不 revert）
│   ├── Pool.sol             # AMM 恒定乘积池（ETH ↔ Token swap，0.3% 手续费）
│   ├── Vault.sol            # 漏洞存钱罐（重入攻击靶子）
│   ├── Attack.sol           # 重入攻击合约
│   └── PermitSwap.sol       # EIP-712 链下签名授权（防重放）
├── test/                    # 6 个测试文件
│   ├── Token.t.sol          # ERC20 功能测试（3 PASS）
│   ├── BadToken.t.sol       # 假充值漏洞验证（2 PASS）
│   ├── Pool.t.sol           # Pool 功能 + Fuzz + 三明治 + 价格操纵（10 PASS）
│   ├── Pool.invariant.t.sol # x×y=k 不变式（128,000 calls, 1 PASS）
│   ├── Attack.t.sol         # 重入攻击验证（2 PASS）
│   └── PermitSwap.t.sol     # 签名重放防护（2 PASS）
├── lib/forge-std/           # Foundry 依赖
├── Dockerfile               # Docker 镜像（Foundry 环境）
├── docker-compose.yml       # 一键启动测试
├── foundry.toml             # Foundry 配置
└── remappings.txt           # 依赖重映射
```

---

## 快速启动

### 方式 1：Docker（推荐，无需安装 Foundry）

```bash
git clone https://github.com/daojiao007/web3-attack-matrix.git
cd web3-attack-matrix
docker compose up
```

### 方式 2：本地 Foundry

```bash
# 安装 Foundry
curl -L https://foundry.paradigm.xyz | bash && foundryup

# 运行全部测试
cd web3-attack-matrix && forge test -vvv

# 运行指定测试
forge test --match-test test_FrontrunSandwich -vvv
forge test --match-test test_Reentrancy -vvv
forge test --match-test test_PermitSwapReplayReverts -vvv

# 运行 Invariant Test（128,000 次随机操作序列）
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

## CI/CD + Gas 回归门禁

每次 `git push` 或 `PR` 自动触发 GitHub Actions 流水线：

```yaml
.github/workflows/test.yml:
  ├── Step 1: checkout + 拉取 forge-std 子模块
  ├── Step 2: 安装 Foundry 工具链
  ├── Step 3: forge test -vvv（20 个测试，失败则阻断）
  ├── Step 4: forge snapshot --check（生成 Gas 快照）
  └── Step 5: forge snapshot --diff（PR 时对比 main 分支 Gas 差异）
```

### Gas 回归阻断逻辑（已配置，默认注释）

PR 提交时，如果**任意函数的 Gas 消耗比 main 分支增加超过 5%** → CI 标红 → 禁止合并。

```
解析 forge snapshot --diff 输出
  → 匹配每个函数的 Gas 变化百分比
  → 超过 5% → exit 1（阻断）
```

> 取消注释 `.github/workflows/test.yml` 中 `Block gas regression > 5%` 段落即可启用。

---

## 技术栈

| 层级 | 技术 |
|------|------|
| 智能合约 | Solidity ^0.8.20 |
| 测试框架 | Foundry (forge test) |
| 测试类型 | Unit / Fuzz / Invariant |
| 容器化 | Docker + docker-compose |
| CI/CD | GitHub Actions（测试 + Gas 回归门禁） |
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