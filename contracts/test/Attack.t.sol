// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "forge-std/console.sol"; 
import "forge-std/Test.sol";
import "../src/Vault.sol";
import "../src/Attack.sol";



contract AttackTest is Test {
    Vault vault;
    Attack attack;
    address alice = address(1);
    address bob = address(2);





    function setUp() public {
        //部署vault合约
        vault = new Vault();
        attack = new Attack(address(vault));
        

    }

    function test_attack() public {
        // Alice 存 10 ETH 做诱饵
        vm.deal(alice, 10 ether);
        vm.prank(alice);
        vault.deposit{value: 10 ether}();

        // 给 Attack 合约转 5 ETH 作为启动资金
        vm.deal(address(attack), 5 ether);

        // Attack 先存 5 ETH 到 Vault，然后攻击
        attack.depositToVault{value: 5 ether}();
        attack.attack();

        uint256 amount = vault.getBalance();
        console.log("Vault remaining:", amount);
        require(amount == 0, "attack failed");
    }

    function test_collect() public {
        vm.deal(alice, 20 ether);
        vm.prank(alice);
        vault.deposit{value: 20 ether}();

        vm.deal(address(attack), 5 ether);
        // uint256 bobBefore = bob.balance;

        attack.depositToVault{value: 5 ether}();
        attack.attack();
        attack.collect();

        require(address(attack).balance == 0, "collect failed: attack still has ETH");
        // 攻击完 Vault 应该被掏空了
        require(vault.getBalance() == 0, "vault not drained");
    }
    receive() external payable {} 
}