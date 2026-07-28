#!/bin/bash
# 对账脚本：验证一笔 swap 的链上数据是否符合 x*y=k 公式
# 用法: ./scripts/reconcile.sh <txHash> <pool地址>

RPC=${RPC_URL:-http://localhost:8545}
TX=$1
POOL=$2

if [ -z "$TX" ] || [ -z "$POOL" ]; then
    echo "用法: ./scripts/reconcile.sh <txHash> <pool地址>"
    exit 1
fi

echo "===== 对账: $TX ====="

# 1. 从 tx receipt 提取 Swapped event 的 data
LOG_DATA=$(cast receipt --rpc-url $RPC $TX --json 2>/dev/null | python3 -c "
import json, sys
try:
    r = json.load(sys.stdin)
    for log in r['logs']:
        if log['topics'][0] == '0x3a9a9f34f5831e9c8ecb66ab3aa308b2ff31eaca434615f6c9cadc656a9af71c':
            print(log['data'])
            break
except: pass
")

if [ -z "$LOG_DATA" ]; then
    echo "FAIL: Swapped event not found in tx $TX"
    exit 1
fi

# data 前 32 字节 = ethIn, 后 32 字节 = tokenOut
ETH_IN=$((16#${LOG_DATA:2:64}))
TOKEN_OUT=$((16#${LOG_DATA:66:64}))

echo ""
echo "chain event (from tx receipt):"
printf "  ethIn:    %.4f ETH\n" "$(echo "scale=4; $ETH_IN / 10^18" | bc)"
printf "  tokenOut: %.4f Token\n" "$(echo "scale=4; $TOKEN_OUT / 10^18" | bc)"

# 2. 查 swap 前一个区块的 reserves
BLOCK_HEX=$(cast receipt --rpc-url $RPC $TX --json 2>/dev/null | python3 -c "import json,sys; print(json.load(sys.stdin)['blockNumber'])")
BLOCK_DEC=$((BLOCK_HEX))
PREV_BLOCK=$((BLOCK_DEC - 1))

ETH_RES_BEFORE=$(cast call --rpc-url $RPC --block $PREV_BLOCK $POOL "ethReserve()(uint256)" 2>/dev/null)
TOKEN_RES_BEFORE=$(cast call --rpc-url $RPC --block $PREV_BLOCK $POOL "tokenReserve()(uint256)" 2>/dev/null)

echo ""
echo "reserves before swap (block $PREV_BLOCK):"
printf "  ethReserve:   %.4f ETH\n" "$(echo "scale=4; $ETH_RES_BEFORE / 10^18" | bc)"
printf "  tokenReserve: %.4f Token\n" "$(echo "scale=4; $TOKEN_RES_BEFORE / 10^18" | bc)"

# 3. 用 x*y=k 公式计算预期值
EXPECTED_RAW=$(python3 -c "
eth_in = $ETH_IN
eth_res = $ETH_RES_BEFORE
token_res = $TOKEN_RES_BEFORE
fee = 3
denom = 1000
eth_after_fee = (eth_in * (denom - fee)) // denom
k = eth_res * token_res
new_token = k // (eth_res + eth_after_fee)
token_out = token_res - new_token
print(token_out)
")

echo ""
printf "expected (x*y=k formula): %.4f Token\n" "$(echo "scale=4; $EXPECTED_RAW / 10^18" | bc)"

# 4. 对账
DIFF=$((TOKEN_OUT - EXPECTED_RAW))
DIFF=${DIFF#-}  # 取绝对值

echo ""
echo "===== RESULT ====="
if [ "$DIFF" -le 10 ]; then
    echo "PASS: diff $DIFF wei — within 10 wei tolerance"
else
    echo "FAIL: diff $DIFF wei — exceeds 10 wei. Investigate!"
fi
