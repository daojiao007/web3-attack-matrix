#!/usr/bin/env python3
"""对账脚本：验证链上 swap 金额是否符合 x*y=k 公式"""
import subprocess, sys, json

RPC = "http://localhost:8545"

def cast(*args):
    result = subprocess.run(["cast"] + list(args), capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(f"cast failed: {' '.join(args)}\n{result.stderr}")
    return result.stdout.strip()

def main(tx: str, pool: str):
    print(f"===== 对账: {tx} =====")

    # 1. 从 Swapped event 提取 ethIn 和 tokenOut
    receipt = cast("receipt", "--rpc-url", RPC, tx, "--json")
    receipt = json.loads(receipt)

    log_data = None
    for log in receipt["logs"]:
        topic = log["topics"][0]
        if topic == "0x3a9a9f34f5831e9c8ecb66ab3aa308b2ff31eaca434615f6c9cadc656a9af71c":
            log_data = log["data"]
            break

    if not log_data:
        print("FAIL: Swapped event not found")
        sys.exit(1)

    eth_in = int(log_data[2:66], 16)
    token_out = int(log_data[66:130], 16)

    print(f"\nchain event:")
    print(f"  ethIn:    {eth_in / 1e18:.4f} ETH")
    print(f"  tokenOut: {token_out / 1e18:.4f} Token")

    # 2. 查 swap 之前的 reserves
    block_hex = receipt["blockNumber"]
    block_num = int(block_hex, 0)
    prev_block = block_num - 1

    eth_before_raw = cast("call", "--rpc-url", RPC, "--block", str(prev_block), pool, "ethReserve()(uint256)")
    eth_before = int(eth_before_raw.split()[0])
    token_before_raw = cast("call", "--rpc-url", RPC, "--block", str(prev_block), pool, "tokenReserve()(uint256)")
    token_before = int(token_before_raw.split()[0])

    print(f"\nreserves before swap (block {prev_block}):")
    print(f"  ethReserve:   {eth_before / 1e18:.4f} ETH")
    print(f"  tokenReserve: {token_before / 1e18:.4f} Token")

    # 3. x*y=k 公式推算预期 tokenOut
    FEE = 3
    DENOM = 1000
    eth_after_fee = (eth_in * (DENOM - FEE)) // DENOM
    k = eth_before * token_before
    new_token = k // (eth_before + eth_after_fee)
    expected = token_before - new_token

    print(f"\nexpected (x*y=k):")
    print(f"  tokenOut: {expected / 1e18:.4f} Token")

    # 4. 对账
    diff = abs(token_out - expected)
    print(f"\n===== RESULT =====")
    if diff <= 10:
        print(f"PASS: diff {diff} wei ({diff / expected * 100:.6f}%) — within 10 wei")
    else:
        print(f"FAIL: diff {diff} wei ({diff / expected * 100:.6f}%) — exceeds tolerance!")

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("用法: python3 scripts/reconcile.py <txHash> <pool地址>")
        sys.exit(1)
    main(sys.argv[1], sys.argv[2])
