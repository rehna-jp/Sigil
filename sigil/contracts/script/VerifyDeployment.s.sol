// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/IntentDecomposer.sol";
import "../src/WatcherRegistry.sol";
import "../src/IntentRouter.sol";
import "../src/TriggerExecutor.sol";

/**
 * @title VerifyDeployment
 * @notice Script to verify Sigil Protocol deployment configuration
 * @dev Usage: forge script script/VerifyDeployment.s.sol:VerifyDeployment --rpc-url $ARBITRUM_SEPOLIA_RPC
 */
contract VerifyDeployment is Script {
    function run() external view {
        // Read deployment addresses from JSON
        string memory json = vm.readFile("./deployments/arbitrum-sepolia.json");

        address registryAddr = vm.parseJsonAddress(json, ".registry");
        address decomposerAddr = vm.parseJsonAddress(json, ".decomposer");
        address watcherRegistryAddr = vm.parseJsonAddress(json, ".watcherRegistry");
        address routerAddr = vm.parseJsonAddress(json, ".router");
        address executorAddr = vm.parseJsonAddress(json, ".executor");
        address uniswapAdapterAddr = vm.parseJsonAddress(json, ".uniswapAdapter");
        address aaveAdapterAddr = vm.parseJsonAddress(json, ".aaveAdapter");

        console.log("=== VERIFYING SIGIL DEPLOYMENT ===\n");

        // Verify IntentDecomposer
        console.log("1. Verifying IntentDecomposer...");
        IntentDecomposer decomposer = IntentDecomposer(decomposerAddr);
        address watcherReg = address(decomposer.watcherRegistry());
        bool routerAuthorized = decomposer.isAuthorizedRouter(routerAddr);

        console.log("   WatcherRegistry set:", watcherReg == watcherRegistryAddr ? "✓" : "✗");
        console.log("   IntentRouter authorized:", routerAuthorized ? "✓" : "✗");

        // Verify WatcherRegistry
        console.log("\n2. Verifying WatcherRegistry...");
        WatcherRegistry registry = WatcherRegistry(watcherRegistryAddr);
        address intentDecomp = address(registry.intentDecomposer());
        bool executorAuthorized = registry.isAuthorizedExecutor(executorAddr);

        console.log("   IntentDecomposer set:", intentDecomp == decomposerAddr ? "✓" : "✗");
        console.log("   TriggerExecutor authorized:", executorAuthorized ? "✓" : "✗");

        // Verify IntentRouter
        console.log("\n3. Verifying IntentRouter...");
        IntentRouter router = IntentRouter(payable(routerAddr));
        address routerDecomposer = address(router.intentDecomposer());
        bool uniswapApproved = router.approvedProtocols(uniswapAdapterAddr);
        bool aaveApproved = router.approvedProtocols(aaveAdapterAddr);

        console.log("   IntentDecomposer set:", routerDecomposer == decomposerAddr ? "✓" : "✗");
        console.log("   UniswapV3Adapter approved:", uniswapApproved ? "✓" : "✗");
        console.log("   AaveV3Adapter approved:", aaveApproved ? "✓" : "✗");

        // Verify TriggerExecutor
        console.log("\n4. Verifying TriggerExecutor...");
        TriggerExecutor executor = TriggerExecutor(executorAddr);
        address executorRegistry = address(executor.watcherRegistry());
        address executorDecomposer = address(executor.intentDecomposer());

        console.log("   WatcherRegistry set:", executorRegistry == watcherRegistryAddr ? "✓" : "✗");
        console.log("   IntentDecomposer set:", executorDecomposer == decomposerAddr ? "✓" : "✗");

        // Final status
        console.log("\n=== VERIFICATION COMPLETE ===");
        bool allChecks =
            watcherReg == watcherRegistryAddr &&
            routerAuthorized &&
            intentDecomp == decomposerAddr &&
            executorAuthorized &&
            routerDecomposer == decomposerAddr &&
            uniswapApproved &&
            aaveApproved &&
            executorRegistry == watcherRegistryAddr &&
            executorDecomposer == decomposerAddr;

        if (allChecks) {
            console.log("\n✅ All verifications passed!");
            console.log("🔗 Sigil Protocol is correctly configured!");
        } else {
            console.log("\n❌ Some verifications failed!");
            console.log("Please check the configuration above.");
        }
    }
}
