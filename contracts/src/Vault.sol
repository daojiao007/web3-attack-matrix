// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;



contract Vault {

    mapping(address => uint256) public balances;

    function  deposit() external payable {
        balances[msg.sender] += msg.value ;
    }

    function withdraw() external {
        uint256 amount =balances[msg.sender];
        (bool success, ) = (msg.sender).call{value:amount}("");
        require(success,"eth is not transfer success");
        balances[msg.sender] = 0;
        // payable(msg.sender).transfer(amount);
    }   

    function getBalance() view external returns (uint256 balance) {
        return balances[msg.sender];
    }

}