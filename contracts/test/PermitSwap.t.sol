// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/Token.sol";
import "../src/Pool.sol";
import "../src/PermitSwap.sol";

contract PermitSwapTest is Test {
    SimpleToken token;
    SimplePool pool;
    PermitSwap permitSwap;
    uint256 alicePk = 1;
    address alice;
    address bob = address(2);

    function setUp() public {
        alice = vm.addr(alicePk);  // 从私钥推导地址，保证跟 vm.sign 一致

        token = new SimpleToken();
        token.mint(alice, 1_000_000 ether);
        pool = new SimplePool(address(token));
        permitSwap = new PermitSwap(address(pool));

        vm.deal(alice, 100 ether);
        vm.prank(alice);
        token.approve(address(pool), type(uint256).max);
        vm.prank(alice);
        pool.addLiquidity{value: 100 ether}(200_000 ether);
    }

    function test_PermitSwapWorks() public {
        uint256 nonce = permitSwap.nonces(alice);
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 PERMIT_TYPEHASH = keccak256(
            "PermitSwap(address owner,uint256 ethAmount,uint256 minTokensOut,uint256 nonce,uint256 deadline)"
        );
        bytes32 structHash = keccak256(
            abi.encode(PERMIT_TYPEHASH, alice, 1 ether, uint256(0), nonce, deadline)
        );
        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", permitSwap.DOMAIN_SEPARATOR(), structHash)
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(alicePk, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.deal(address(permitSwap), 1 ether);
        vm.prank(bob);
        permitSwap.executeSwap(alice, 1 ether, 0, deadline, signature);

        assertEq(permitSwap.nonces(alice), 1);
    }

    function test_PermitSwapReplayReverts() public {
        uint256 nonce = permitSwap.nonces(alice);
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 PERMIT_TYPEHASH = keccak256(
            "PermitSwap(address owner,uint256 ethAmount,uint256 minTokensOut,uint256 nonce,uint256 deadline)"
        );
        bytes32 structHash = keccak256(
            abi.encode(PERMIT_TYPEHASH, alice, 1 ether, uint256(0), nonce, deadline)
        );
        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", permitSwap.DOMAIN_SEPARATOR(), structHash)
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(alicePk, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.deal(address(permitSwap), 2 ether);
        vm.prank(bob);
        permitSwap.executeSwap(alice, 1 ether, 0, deadline, signature);

        vm.prank(bob);
        vm.expectRevert("invalid signature");
        permitSwap.executeSwap(alice, 1 ether, 0, deadline, signature);
    }
}
