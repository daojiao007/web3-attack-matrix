// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./Pool.sol";

contract PermitSwap {
    SimplePool public pool;
    mapping(address => uint256) public nonces;

    // EIP-712 域名分隔符 —— 把 chainId + 合约地址 焊进签名
    bytes32 public immutable DOMAIN_SEPARATOR;
    bytes32 public constant PERMIT_TYPEHASH =
        keccak256("PermitSwap(address owner,uint256 ethAmount,uint256 minTokensOut,uint256 nonce,uint256 deadline)");

    event SwapExecuted(address indexed owner, uint256 ethIn, uint256 tokenOut);

    constructor(address _pool) {
        pool = SimplePool(_pool);
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256("PermitSwap"),
                keccak256("1"),
                block.chainid,        // ← 防跨链重放
                address(this)          // ← 防跨合约重放
            )
        );
    }

    // 任何人拿着 Alice 的签名来执行 swap
    function executeSwap(
        address owner,
        uint256 ethAmount,
        uint256 minTokensOut,
        uint256 deadline,
        bytes memory signature
    ) external returns (uint256) {
        require(block.timestamp <= deadline, "signature expired");  // ← 防延后重放
        uint256 nonce = nonces[owner];

        // 重建 signing hash（跟链下签名时一致）
        bytes32 structHash = keccak256(
            abi.encode(PERMIT_TYPEHASH, owner, ethAmount, minTokensOut, nonce, deadline)
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));

        // 从签名恢复签名者地址
        address signer = recoverSigner(digest, signature);
        require(signer == owner, "invalid signature");

        // nonce 自增，防重放
        nonces[owner]++;

        // 执行 Alice 的 swap（Alice 的 ETH 已经被测试 deal 好了）
        // 但钱是 Alice 的，需要 Alice 预先给这个合约 approve 或用 payable 方式
        // 简化：合约从 Alice 余额拉 ETH（测试里 deal + call from Alice 方式）
        pool.swapETHForToken{value: ethAmount}(minTokensOut);

        emit SwapExecuted(owner, ethAmount, minTokensOut);
        return nonce;
    }

    function recoverSigner(bytes32 digest, bytes memory signature) internal pure returns (address) {
        require(signature.length == 65, "invalid sig length");
        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := mload(add(signature, 32))
            s := mload(add(signature, 64))
            v := byte(0, mload(add(signature, 96)))
        }
        if (v < 27) v += 27;
        return ecrecover(digest, v, r, s);
    }

    receive() external payable {}
}
