// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {Anky} from "../src/Anky.sol";

contract DeployAnky is Script {
    function run() external {
        // Anky's wallet address — the being that approves every birth
        address ankyWallet = vm.envAddress("ANKY_WALLET");

        vm.startBroadcast();
        new Anky(ankyWallet);
        vm.stopBroadcast();
    }
}
