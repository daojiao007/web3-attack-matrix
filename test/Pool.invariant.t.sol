pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/Token.sol";
import "../src/Pool.sol";


contract PoolInvariantTest is Test {
    SimpleToken token;
    SimplePool pool;
    address alice = address(1);
    uint256 constant INITIAL_ETH = 100 ether;
    uint256 constant INITIAL_TOKEN = 200_000 ether;
    uint256  initialK ;
    function setUp() public {
        // 部署 Token + Pool + 添加初始流动性（跟你之前一样）
        token =new SimpleToken();
        token.mint(alice,1_000_000 ether);


        // 2. 部署 Pool（绑定这个 Token）
        pool = new SimplePool(address(token));

        
 

        // 3. Alice 授权 Pool 花她的 Token
        vm.prank(alice);
        token.approve(address(pool),type(uint256).max);

        // 4. Alice 添加初始流动性：100 ETH + 200,000 Token
        vm.deal(alice,INITIAL_ETH);
        vm.prank(alice);
        pool.addLiquidity{value:INITIAL_ETH}(INITIAL_TOKEN);
        initialK = pool.ethReserve() * pool.tokenReserve();
        
    }

    // Forge 自动随机调用这两个函数，组合成随机序列  Invariant Test不能带testFuzz_
    function Swap(uint256 amount) public {
        amount = bound(amount, 21001, pool.ethReserve() / 10);
        // ... 调 pool.swapETHForToken
        address bob = address(2);
        vm.deal(bob,amount);
        vm.prank(bob);
        uint256 outToken = pool.swapETHForToken{value:amount}(0);
        invariant_XTimesYNeverDecreases();
        assertGt(outToken,0, "should receive token");

    }

    function addLiquidity(uint256 tokenAmount) public {
        // ... 调 pool.addLiquidity
        uint256 ethAmount = bound(tokenAmount, 21001, pool.ethReserve() / 10);
        address bob = address(2);
        vm.deal(bob,ethAmount);
        vm.startPrank(bob);
        token.approve(address(pool), type(uint256).max);
        uint256 tokenAdd = (ethAmount * pool.tokenReserve()) / pool.ethReserve();
        token.mint(bob, tokenAdd);
        
        uint256 last_ethReserve = pool.ethReserve();
        uint256 last_tokenReserve = pool.tokenReserve();
        pool.addLiquidity{value:ethAmount}(tokenAdd);
        vm.stopPrank();
        assertGt(pool.ethReserve() , last_ethReserve ,"Failed to add ETH liquidity");
        assertGt(pool.tokenReserve() , last_tokenReserve ,"Failed to add token liquidity");
        invariant_XTimesYNeverDecreases();


    }

    // 每次随机序列执行完后，Forge 检查这个不变式
    function invariant_XTimesYNeverDecreases() public view {
        uint256 k = pool.ethReserve() * pool.tokenReserve();
        assertGe(k, initialK, "violated");
    }
}