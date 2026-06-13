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
import "../test/mocks/MockUniswapRouter.sol";
import "../test/mocks/MockAavePool.sol";
import "../test/mocks/MockChainlinkFeed.sol";

/**
 * @title DeployLocal
 * @notice Deployment script for local testing with mock protocols
 * @dev Usage: forge script script/DeployLocal.s.sol:DeployLocal --fork-url http://localhost:8545 --broadcast
 */
contract DeployLocal is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envOr(
            "PRIVATE_KEY",
            uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80) // Anvil key #0
        );
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deploying Sigil Protocol LOCALLY");
        console.log("Deployer address:", deployer);
        console.log("---");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy mock protocols
        console.log("Deploying Mock Protocols...");
        MockUniswapRouter mockUniswap = new MockUniswapRouter();
        MockAavePool mockAave = new MockAavePool();
        MockChainlinkFeed ethFeed = new MockChainlinkFeed(8);
        ethFeed.setPrice(3500e8); // $3500

        console.log("  MockUniswapRouter:", address(mockUniswap));
        console.log("  MockAavePool:", address(mockAave));
        console.log("  MockChainlinkFeed:", address(ethFeed));

        // Deploy core contracts
        console.log("\nDeploying Core Contracts...");

        ERC8004Registry registry = new ERC8004Registry();
        console.log("  ERC8004Registry:", address(registry));

        address aiAgent = deployer;
        registry.registerAgent(
            aiAgent,
            registry.INTENT_DECOMPOSER(),
            "ipfs://test"
        );

        IntentDecomposer decomposer = new IntentDecomposer(
            aiAgent,
            address(registry),
            deployer
        );
        console.log("  IntentDecomposer:", address(decomposer));

        WatcherRegistry watcherRegistry = new WatcherRegistry(
            address(decomposer),
            deployer
        );
        console.log("  WatcherRegistry:", address(watcherRegistry));

        decomposer.setWatcherRegistry(address(watcherRegistry));

        IntentRouter router = new IntentRouter(deployer);
        console.log("  IntentRouter:", address(router));

        router.setIntentDecomposer(address(decomposer));
        decomposer.addAuthorizedRouter(address(router));

        TriggerExecutor executor = new TriggerExecutor(
            address(watcherRegistry),
            aiAgent,
            deployer
        );
        console.log("  TriggerExecutor:", address(executor));

        executor.setIntentDecomposer(address(decomposer));
        watcherRegistry.addAuthorizedExecutor(address(executor));

        // Deploy adapters with mock protocols
        console.log("\nDeploying Protocol Adapters...");
        UniswapV3Adapter uniswapAdapter = new UniswapV3Adapter(
            address(mockUniswap),
            deployer
        );
        console.log("  UniswapV3Adapter:", address(uniswapAdapter));

        AaveV3Adapter aaveAdapter = new AaveV3Adapter(
            address(mockAave),
            deployer
        );
        console.log("  AaveV3Adapter:", address(aaveAdapter));

        router.addProtocol("uniswap-v3", address(uniswapAdapter), Types.ProtocolCategory.DEX);
        router.addProtocol("aave-v3", address(aaveAdapter), Types.ProtocolCategory.LENDING);

        watcherRegistry.addPriceFeed("ETH/USD", address(ethFeed));

        vm.stopBroadcast();

        console.log("\n=== LOCAL DEPLOYMENT COMPLETE ===");
        console.log("All contracts deployed and configured!");
        console.log(unicode"Ready for local testing 🧪");
    }
}
