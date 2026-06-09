// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/IntentDecomposer.sol";
import "../src/WatcherRegistry.sol";
import "../src/IntentRouter.sol";
import "../src/TriggerExecutor.sol";
import "../src/adapters/UniswapV3Adapter.sol";
import "../src/adapters/AaveV3Adapter.sol";
import "../src/interfaces/IERC8004.sol";

/**
 * @title DeploySigil
 * @notice Deployment script for Sigil Protocol on Arbitrum Sepolia
 * @dev Usage: forge script script/DeploySigil.s.sol:DeploySigil --rpc-url $ARBITRUM_SEPOLIA_RPC --broadcast --verify
 */
contract DeploySigil is Script {
    // Arbitrum Sepolia addresses
    address constant UNISWAP_V3_ROUTER = 0x101F443B4d1b059569D643917553c771E1b9663E; // Arbitrum Sepolia SwapRouter
    address constant AAVE_V3_POOL = 0x6Cad12b3618A6E8638E19049E7fF94802904c1Ed; // Arbitrum Sepolia Pool

    // Price feeds (Arbitrum Sepolia Chainlink)
    address constant ETH_USD_FEED = 0xd30e2101a97dcbAeBCBC04F14C3f624E67A35165;
    address constant USDC_USD_FEED = 0x0153002d20B96532C639313c2d54c3dA09109309;

    // Deployed contracts
    ERC8004Registry public registry;
    IntentDecomposer public decomposer;
    WatcherRegistry public watcherRegistry;
    IntentRouter public router;
    TriggerExecutor public executor;
    UniswapV3Adapter public uniswapAdapter;
    AaveV3Adapter public aaveAdapter;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deploying Sigil Protocol to Arbitrum Sepolia");
        console.log("Deployer address:", deployer);
        console.log("---");

        vm.startBroadcast(deployerPrivateKey);

        // Step 1: Deploy ERC8004 Agent Registry
        console.log("1. Deploying ERC8004Registry...");
        registry = new ERC8004Registry();
        console.log("   Registry deployed at:", address(registry));

        // Step 2: Register AI Agent
        console.log("2. Registering AI Agent...");
        address aiAgent = deployer; // For now, deployer acts as AI agent
        registry.registerAgent(
            aiAgent,
            registry.INTENT_DECOMPOSER(),
            "ipfs://QmSigilAIAgentMetadata" // Update with actual IPFS hash
        );
        console.log("   AI Agent registered:", aiAgent);

        // Step 3: Deploy IntentDecomposer
        console.log("3. Deploying IntentDecomposer...");
        decomposer = new IntentDecomposer(
            aiAgent,
            address(registry),
            deployer
        );
        console.log("   IntentDecomposer deployed at:", address(decomposer));

        // Step 4: Deploy WatcherRegistry
        console.log("4. Deploying WatcherRegistry...");
        watcherRegistry = new WatcherRegistry(
            address(decomposer),
            deployer
        );
        console.log("   WatcherRegistry deployed at:", address(watcherRegistry));

        // Step 5: Set WatcherRegistry in IntentDecomposer
        console.log("5. Configuring IntentDecomposer...");
        decomposer.setWatcherRegistry(address(watcherRegistry));
        console.log("   WatcherRegistry set in IntentDecomposer");

        // Step 6: Deploy IntentRouter
        console.log("6. Deploying IntentRouter...");
        router = new IntentRouter(deployer);
        console.log("   IntentRouter deployed at:", address(router));

        // Step 7: Configure IntentRouter
        console.log("7. Configuring IntentRouter...");
        router.setIntentDecomposer(address(decomposer));
        decomposer.addAuthorizedRouter(address(router));
        console.log("   IntentRouter configured");

        // Step 8: Deploy TriggerExecutor
        console.log("8. Deploying TriggerExecutor...");
        executor = new TriggerExecutor(
            address(watcherRegistry),
            aiAgent,
            deployer
        );
        console.log("   TriggerExecutor deployed at:", address(executor));

        // Step 9: Configure TriggerExecutor
        console.log("9. Configuring TriggerExecutor...");
        executor.setIntentDecomposer(address(decomposer));
        watcherRegistry.addAuthorizedExecutor(address(executor));
        console.log("   TriggerExecutor configured");

        // Step 10: Deploy Protocol Adapters
        console.log("10. Deploying Protocol Adapters...");

        // Uniswap V3 Adapter
        uniswapAdapter = new UniswapV3Adapter(
            UNISWAP_V3_ROUTER,
            deployer
        );
        console.log("    UniswapV3Adapter deployed at:", address(uniswapAdapter));

        // Aave V3 Adapter
        aaveAdapter = new AaveV3Adapter(
            AAVE_V3_POOL,
            deployer
        );
        console.log("    AaveV3Adapter deployed at:", address(aaveAdapter));

        // Step 11: Register Adapters in IntentRouter
        console.log("11. Registering Protocol Adapters...");
        router.addProtocol(
            "uniswap-v3",
            address(uniswapAdapter),
            Types.ProtocolCategory.DEX
        );
        router.addProtocol(
            "aave-v3",
            address(aaveAdapter),
            Types.ProtocolCategory.LENDING
        );
        console.log("    Adapters registered in IntentRouter");

        // Step 12: Add Price Feeds to WatcherRegistry
        console.log("12. Adding Price Feeds...");
        watcherRegistry.addPriceFeed("ETH/USD", ETH_USD_FEED);
        watcherRegistry.addPriceFeed("USDC/USD", USDC_USD_FEED);
        console.log("    Price feeds added");

        vm.stopBroadcast();

        // Print deployment summary
        console.log("\n=== DEPLOYMENT COMPLETE ===");
        console.log("Network: Arbitrum Sepolia");
        console.log("Deployer:", deployer);
        console.log("AI Agent:", aiAgent);
        console.log("---");
        console.log("Core Contracts:");
        console.log("  ERC8004Registry:", address(registry));
        console.log("  IntentDecomposer:", address(decomposer));
        console.log("  WatcherRegistry:", address(watcherRegistry));
        console.log("  IntentRouter:", address(router));
        console.log("  TriggerExecutor:", address(executor));
        console.log("---");
        console.log("Protocol Adapters:");
        console.log("  UniswapV3Adapter:", address(uniswapAdapter));
        console.log("  AaveV3Adapter:", address(aaveAdapter));
        console.log("---");
        console.log("Price Feeds:");
        console.log("  ETH/USD:", ETH_USD_FEED);
        console.log("  USDC/USD:", USDC_USD_FEED);
        console.log("\n🎉 Sigil Protocol successfully deployed!");
        console.log("🔗 The Persistent Intent Loop is LIVE!");

        // Save deployment addresses to file
        _saveDeploymentAddresses();
    }

    function _saveDeploymentAddresses() internal {
        string memory json = "deployments";

        vm.serializeAddress(json, "registry", address(registry));
        vm.serializeAddress(json, "decomposer", address(decomposer));
        vm.serializeAddress(json, "watcherRegistry", address(watcherRegistry));
        vm.serializeAddress(json, "router", address(router));
        vm.serializeAddress(json, "executor", address(executor));
        vm.serializeAddress(json, "uniswapAdapter", address(uniswapAdapter));
        string memory finalJson = vm.serializeAddress(json, "aaveAdapter", address(aaveAdapter));

        vm.writeJson(finalJson, "./deployments/arbitrum-sepolia.json");
        console.log("\nDeployment addresses saved to: deployments/arbitrum-sepolia.json");
    }
}
