// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// 模仿 USDT 等不遵循 ERC20 标准的 Token：
// transfer/transferFrom 返回 false 但不 revert，转账实际未执行
contract BadToken {
    string public name = "BadToken";
    string public symbol = "BAD";
    uint8 public decimals = 18;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    uint256 public totalSupply;

    event Transfer(address indexed from, address indexed to, uint256 amount);
    event Approval(address indexed owner, address indexed spender, uint256 amount);

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
        emit Transfer(address(0), to, amount);
    }

    // BUG: 始终返回 false，但不会 revert
    function transfer(address, uint256) external pure returns (bool) {
        return false;
    }

    // BUG: 同样返回 false，不做任何操作
    function transferFrom(address, address, uint256) external pure returns (bool) {
        return false;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }
}
