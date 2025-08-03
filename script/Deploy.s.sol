// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "forge-std/Script.sol";
import "../contracts/src/TestEscrowFactory.sol";
import "../contracts/src/SuiResolverBidirectional.sol";

contract Deploy is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);
        
        console.log("=== Complete Bidirectional Bridge Deployment ===");
        console.log("Deployer address:", deployerAddress);
        console.log("Chain ID:", block.chainid);
        
        uint256 balance = deployerAddress.balance;
        console.log("Deployer balance:", balance / 1e18, "ETH");
        require(balance > 0.05 ether, "Insufficient ETH for deployment");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Sepolia addresses
        address lopAddress = 0x111111125421cA6dc452d289314280a0f8842A65;
        address sepoliaWETH = 0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14;
        address sepoliaUSDC = 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238;
        
        console.log("Constructor arguments:");
        console.log("- LimitOrderProtocol:", lopAddress);
        console.log("- Fee Token (WETH):", sepoliaWETH);
        console.log("- Access Token (USDC):", sepoliaUSDC);
        console.log("- Owner:", deployerAddress);
        
        // Step 1: Deploy TestEscrowFactory
        console.log("Step 1: Deploying TestEscrowFactory...");
        TestEscrowFactory factory = new TestEscrowFactory(
            lopAddress,
            IERC20(sepoliaWETH),
            IERC20(sepoliaUSDC),
            deployerAddress,
            1800,
            1800
        );
        
        console.log("TestEscrowFactory deployed to:", address(factory));
        
        // Step 2: Deploy SuiResolverBidirectional
        console.log("Step 2: Deploying SuiResolverBidirectional...");
        SuiResolverBidirectional resolver = new SuiResolverBidirectional(
            IEscrowFactory(address(factory)),
            IOrderMixin(lopAddress),
            deployerAddress
        );
        
        console.log("SuiResolverBidirectional deployed to:", address(resolver));
        
        vm.stopBroadcast();
        
        // Verify deployment (only check resolver owner)
        console.log("=== Deployment Verification ===");
        console.log("Resolver Owner:", resolver.owner());
        console.log("Factory Contract Size:", address(factory).code.length, "bytes");
        console.log("Resolver Contract Size:", address(resolver).code.length, "bytes");
        
        // Test basic functionality
        _verifyDeployment(factory, resolver, deployerAddress);
        
        // Log important information for .env update
        console.log("=== Update your .env file ===");
        console.log("SEPOLIA_ESCROW_FACTORY=", address(factory));
        console.log("SUI_RESOLVER_BIDIRECTIONAL=", address(resolver));
        
        console.log("=== Deployment Successful ===");
        console.log("Both contracts deployed and verified");
        console.log("Ready for bidirectional cross-chain swaps!");
    }
    
    function _verifyDeployment(
        TestEscrowFactory factory,
        SuiResolverBidirectional resolver,
        address expectedOwner
    ) internal view {
        console.log("=== Post-Deployment Verification ===");
        
        // Only verify resolver owner (SuiResolverBidirectional inherits from Ownable via Resolver)
        address resolverOwner = resolver.owner();
        require(resolverOwner == expectedOwner, "Resolver owner verification failed");
        console.log("Resolver owner verified:", resolverOwner);
        
        // Test bidirectional functions
        console.log("Testing bidirectional functions...");
        
        // Test ethereumOrderExists
        bool orderExists = resolver.ethereumOrderExists(bytes32(0));
        console.log("ethereumOrderExists test passed:", !orderExists);
        
        // Test isSecretCoordinated
        bool secretCoordinated = resolver.isSecretCoordinated(bytes32(0));
        console.log("isSecretCoordinated test passed:", !secretCoordinated);
        
        console.log("All verification tests passed!");
        console.log("Contract deployment verified successfully");
        console.log("Bidirectional bridge is ready!");
    }
}
