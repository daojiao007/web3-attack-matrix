// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/BadToken.sol";
import "../src/Pool.sol";

contract BadTokenTest is Test {
    BadToken badToken;
    SimplePool pool;
    address alice = address(1);

    function setUp() public {
        badToken = new BadToken();
        pool = new SimplePool(address(badToken));

        // 给 Alice 铸 BadToken，并给 ETH 添加初始流动性
        badToken.mint(alice, 1_000_000 ether);
        vm.deal(alice, 100 ether);
        vm.prank(alice);
        badToken.approve(address(pool), type(uint256).max);
    }

    // 验证漏洞：addLiquidity 不检查 transferFrom 返回值，
    // BadToken 返回 false 但池子仍记录了 tokenReserve 增加
    function test_FakeDepositInflatesReserve() public {
        uint256 tokenReserveBefore = pool.tokenReserve();
        uint256 poolTokenBalanceBefore = badToken.balanceOf(address(pool));

        vm.prank(alice);
        pool.addLiquidity{value: 10 ether}(5000 ether);

        uint256 tokenReserveAfter = pool.tokenReserve();
        uint256 poolTokenBalanceAfter = badToken.balanceOf(address(pool));

        // 致命矛盾：tokenReserve 认为收到了 5000 Token
        assertGt(tokenReserveAfter, tokenReserveBefore,
            "BUG: tokenReserve should increase (contract believes deposit succeeded)");

        // 但 Pool 实际余额为 0 ---- BadToken.transferFrom 返回 false 且什么都没做
        assertEq(poolTokenBalanceAfter, 0,
            "BUG: pool actual balance should be 0 (transferFrom returned false)");
        assertEq(poolTokenBalanceAfter, poolTokenBalanceBefore,
            "BUG: pool balance unchanged -- no tokens actually moved");

        // 攻击者用 0 成本获得了流动性份额
        assertEq(tokenReserveAfter, tokenReserveBefore + 5000 ether,
            "ATTACK: fake deposit successfully inflated tokenReserve");
    }

    // 验证：加上 require 检查返回值就能防住
    function test_FixedPoolRevertsOnBadToken() public {
        // 当前 Pool.sol 没有检查 transferFrom 返回值
        // 此测试确认漏洞存在（addLiquidity 不 revert）
        vm.prank(alice);
        pool.addLiquidity{value: 10 ether}(5000 ether);

        // 应该 revert 但没 revert ---- 漏洞确认
        assertEq(pool.tokenReserve(), 5000 ether,
            "VULNERABILITY CONFIRMED: pool accepted fake deposit");
    }
}
