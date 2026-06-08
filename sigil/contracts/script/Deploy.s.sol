// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {IntentDecomposer} from "../src/IntentDecomposer.sol";
import {WatcherRegistry} from "../src/WatcherRegistry.sol";
import {TriggerExecutor} from "../src/TriggerExecutor.sol";
import {IntentRouter} from "../src/IntentRouter.sol";
import {MockPriceFeed} from "../src/mocks/MockPriceFeed.sol";

contract Deploy is Script {
    // Chainlink ETH/USD on Arbitrum Sepolia
    address constant CHAINLINK_ETH_USD_ARB_SEPOLIA = 0xd30e2101a97dcbAeBCBC04F14C3f624E67A35165;

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        console.log("==========================================");
        console.log("Deploying Sigil Protocol");
        console.log("Deployer:", deployer);
        console.log("Chain ID:", block.chainid);
        console.log("==========================================");

        vm.startBroadcast(deployerKey);

        // 1. MockPriceFeed — ETH at $3,800 (use for testnet demos)
        MockPriceFeed mockFeed = new MockPriceFeed(
            380000000000, // $3,800 with 8 decimals
            8,
            "ETH / USD (Sigil Mock)",
            deployer
        );

        // 2. IntentDecomposer
        IntentDecomposer decomposer = new IntentDecomposer(deployer);

        // 3. WatcherRegistry
        WatcherRegistry registry = new WatcherRegistry(deployer);

        // 4. TriggerExecutor
        TriggerExecutor executor = new TriggerExecutor(address(registry), deployer);

        // 5. IntentRouter
        IntentRouter router = new IntentRouter(address(decomposer), deployer);

        // ── Configure permissions ────────────────────────────────
        decomposer.setIntentRouter(address(router));
        decomposer.setWatcherRegistry(address(registry));
        registry.authorizeExecutor(address(executor));
        registry.setIntentDecomposer(address(decomposer));
        // NOTE: call decomposer.setAIAgent(AI_WALLET) after deploying backend

        vm.stopBroadcast();

        console.log("==========================================");
        console.log("DEPLOYMENT COMPLETE");
        console.log("==========================================");
        console.log("MockPriceFeed    :", address(mockFeed));
        console.log("IntentDecomposer :", address(decomposer));
        console.log("WatcherRegistry  :", address(registry));
        console.log("TriggerExecutor  :", address(executor));
        console.log("IntentRouter     :", address(router));
        console.log("");
        console.log("Demo tip: dropPrice(340000000000) to fire price watcher");
    }
}
