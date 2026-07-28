// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/Token.sol";
import "../src/Pool.sol";

contract Deploy is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerKey);

        // 1. 部署 Token
        SimpleToken token = new SimpleToken();
        console.log("Token deployed at:", address(token));

        // 2. 部署 Pool
        SimplePool pool = new SimplePool(address(token));
        console.log("Pool deployed at:", address(pool));

        vm.stopBroadcast();
    }
}
