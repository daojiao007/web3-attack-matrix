// SPDX-License-Identifier: MIT
  pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/Token.sol";

  contract TokenTest is Test {
      SimpleToken token;
      address alice = address(1);
      address bob = address(2);

      function setUp() public {
          token = new SimpleToken();
      }

      function test_Mint() public {
          token.mint(alice, 1000);
          assertEq(token.balanceOf(alice), 1000);
          assertEq(token.totalSupply(), 1000);
      }

      function test_Transfer() public {
          token.mint(alice, 1000);
          vm.prank(alice);
          token.transfer(bob, 300);
          assertEq(token.balanceOf(alice), 700);
          assertEq(token.balanceOf(bob), 300);
      }

      function test_RevertInsufficientBalance() public {
          token.mint(alice, 200);
          vm.prank(alice);
          vm.expectRevert("insufficient balance");
          token.transfer(bob, 300);
      }
  }
