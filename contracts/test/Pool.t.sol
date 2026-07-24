// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "forge-std/console.sol";
import "forge-std/Test.sol";
import "../src/Token.sol";
import "../src/Pool.sol";

contract PoolTest is Test {
    SimpleToken token;
    SimplePool pool;
    address alice = address(1);
    uint256 constant INITIAL_ETH = 100 ether;
    uint256 constant INITIAL_TOKEN = 200_000 ether;

    function setUp() public {
        // 1. 部署 Token
        token = new SimpleToken();
        token.mint(alice, 1_000_000 ether);

        // 2. 部署 Pool（绑定这个 Token）
        pool = new SimplePool(address(token));

        // 3. Alice 授权 Pool 花她的 Token
        vm.prank(alice);
        token.approve(address(pool), type(uint256).max);

        // 4. Alice 添加初始流动性：100 ETH + 200,000 Token
        vm.deal(alice, INITIAL_ETH);
        vm.prank(alice);
        pool.addLiquidity{value: INITIAL_ETH}(INITIAL_TOKEN);
    }

    // ===== 功能测试 =====

    function test_AddLiquidity() public view {
        assertEq(pool.ethReserve(), INITIAL_ETH, "ETH reserve mismatch");
        assertEq(pool.tokenReserve(), INITIAL_TOKEN, "Token reserve mismatch");
    }

    function test_SwapETHForToken() public {
        address bob = address(2);
        vm.deal(bob, 1 ether);

        // Bob 用 1 ETH 换 Token
        uint256 bobBefore = token.balanceOf(bob);
        vm.prank(bob);
        uint256 tokenOut = pool.swapETHForToken{value: 1 ether}(0);
        uint256 bobAfter = token.balanceOf(bob);

        // Bob 收到了 Token
        assertGt(bobAfter, bobBefore, "Bob should receive tokens");
        assertEq(tokenOut, bobAfter - bobBefore, "return value must match");

        // 池子 reserves 更新了
        assertEq(pool.ethReserve(), INITIAL_ETH + 1 ether, "ETH reserve");
        assertEq(pool.tokenReserve(), INITIAL_TOKEN - tokenOut, "Token reserve");
    }

    // ===== x*y=k 恒定性验证 =====

    function test_ConstantProductInvariant() public {
        uint256 kBefore = pool.ethReserve() * pool.tokenReserve();

        address bob = address(2);
        vm.deal(bob, 1 ether);
        vm.prank(bob);
        pool.swapETHForToken{value: 1 ether}(0);

        uint256 kAfter = pool.ethReserve() * pool.tokenReserve();

        // swap 后 k 不应减少（手续费留在池子里，k 会略微增大）
        assertGe(kAfter, kBefore, "x*y=k invariant violated");
    }

    // ===== 滑点保护 =====

    function test_RevertSlippage() public {
        address bob = address(2);
        vm.deal(bob, 1 ether);

        // 要求收到 1,000,000 Token —— 但 1 ETH 远换不到这么多
        vm.prank(bob);
        vm.expectRevert("slippage exceeded");
        pool.swapETHForToken{value: 1 ether}(1_000_000 ether);
    }

    // ===== 比例检查 =====

    function test_RevertWrongRatio() public {
        address bob = address(2);
        vm.deal(bob, 1 ether);
        token.mint(bob, 1000 ether);

        vm.prank(bob);
        token.approve(address(pool), type(uint256).max);

        // 池子比例是 100:200000 = 1:2000
        // Bob 提供 1 ETH : 1000 Token → 比例不对
        vm.prank(bob);
        vm.expectRevert("ratio mismatch");
        pool.addLiquidity{value: 1 ether}(1000 ether);
    }

    // ===== 事件测试 =====

    function test_EmitSwapEvent() public {
        address bob = address(2);
        vm.deal(bob, 1 ether);

        vm.prank(bob);
        vm.expectEmit(true, true, false, false); // checkData=false，不比对具体数值
        emit SimplePool.Swapped(bob, 1 ether, 0);
        pool.swapETHForToken{value: 1 ether}(0);
    }
    function testFuzz_Swap(uint256 amount) public {
      // 限制范围：1 wei ~ 池子 ETH 储备的 1/10
      amount = bound(amount, 21001, pool.ethReserve() / 10);

      address bob = address(2);
      vm.deal(bob, amount);
      vm.prank(bob);
      uint256 tokenOut = pool.swapETHForToken{value: amount}(0);

      // 验证：换到的 Token > 0
      assertGt(tokenOut, 0, "should receive tokens");
    }
    function getSpotPrice() public view returns (uint256) {
        return pool.tokenReserve() * 1e18 / pool.ethReserve() ;
    }

    function test_SpotPriceManipulated() public {
        // 攻击前价格
        uint256 priceBefore = getSpotPrice();
        console.log("Price before:", priceBefore);

        // 闪电贷借 90 ETH，全部砸进池子
        address attacker = address(999);
        vm.deal(attacker, 90 ether);
        vm.prank(attacker);
        pool.swapETHForToken{value: 90 ether}(0);

        // 攻击后价格
        uint256 priceAfter = getSpotPrice();
        console.log("Price after:", priceAfter);

        // 价格应该暴跌
        assertLt(priceAfter, priceBefore);
    }
    //闪电贷攻击
    function testFuzz_LargeSwapChangesPrice(uint256 amount) public {
        amount = bound(amount,0.05 ether,pool.ethReserve() / 2);
        uint256 last_price = getSpotPrice();
        address bob = address(2);
        vm.deal(bob,amount);
        vm.prank(bob);
        pool.swapETHForToken{value: amount }(0);
        uint256 new_price = getSpotPrice();
        console.log("Price after:", new_price);
        assertGt(last_price ,new_price,"swap change price fail");
    }

    //三明治攻击，
    function test_FrontrunSandwich() public {
      address bob = address(2);
    //   address alice = address(3);

      // 给 Bob 一些 ETH + Token（他需要两样）
      vm.deal(bob, 50 ether);
      token.mint(bob, 100_000 ether);
      vm.prank(bob);
      //先授权给池子，供后续换回eth,好操作swapTokenForETH函数
      token.approve(address(pool), type(uint256).max);

      // Bob 抢跑：ETH → Token
      vm.startPrank(bob);
      uint256 before = bob.balance;
      uint256 tokenGot = pool.swapETHForToken{value: 12 ether}(0);
      vm.stopPrank();
      // Alice 被夹：ETH → Token（价格已被 Bob 拉高）
      vm.deal(alice, 10 ether);
      vm.prank(alice);
      pool.swapETHForToken{value: 10 ether}(0);

      // Bob 出场：Token → ETH
      vm.prank(bob);
      pool.swapTokenForETH(0, tokenGot);
      uint256 afterEth = bob.balance;
      assertGt(afterEth,before,"Fron trun Sandwich Fail");
  }

}
