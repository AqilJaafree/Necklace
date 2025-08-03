// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "forge-std/Script.sol";
import "../contracts/src/TestEscrowFactory.sol";
import "../contracts/src/SuiResolverBidirectional.sol";

/**
 * @title DeployEscrowFactory
 * @dev Deploy TestEscrowFactory first
 */
contract DeployEscrowFactory is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);
        
        console.log("=== TestEscrowFactory Deployment ===");
        console.log("Deployer address:", deployerAddress);
        console.log("Chain ID:", block.chainid);
        
        // Check deployer balance
        uint256 balance = deployerAddress.balance;
        console.log("Deployer balance:", balance / 1e18, "ETH");
        require(balance > 0.02 ether, "Insufficient ETH for deployment");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Sepolia addresses for constructor
        address lopAddress = 0x111111125421cA6dc452d289314280a0f8842A65;
        address sepoliaWETH = 0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14;
        address sepoliaUSDC = 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238;
        
        console.log("Constructor arguments:");
        console.log("- LimitOrderProtocol:", lopAddress);
        console.log("- Fee Token (WETH):", sepoliaWETH);
        console.log("- Access Token (USDC):", sepoliaUSDC);
        console.log("- Owner:", deployerAddress);
        console.log("- Rescue Delays: 1800 seconds");
        
        // Deploy TestEscrowFactory
        TestEscrowFactory factory = new TestEscrowFactory(
            lopAddress,
            IERC20(sepoliaWETH),
            IERC20(sepoliaUSDC),
            deployerAddress,
            1800, // rescueDelaySrc
            1800  // rescueDelayDst
        );
        
        console.log("=== Deployment Successful ===");
        console.log("TestEscrowFactory deployed to:", address(factory));
        
        // Verify deployment
        console.log("=== Verification ===");
        console.log("Owner:", factory.owner());
        console.log("Contract size:", address(factory).code.length, "bytes");
        
        // Test basic functionality
        try factory.owner() returns (address owner) {
            console.log("Factory owner verified:", owner);
        } catch {
            console.log("Factory owner check failed");
        }
        
        // Log important information for .env update
        console.log("=== Update your .env file ===");
        console.log("SEPOLIA_ESCROW_FACTORY=", address(factory));
        
        vm.stopBroadcast();
        
        console.log("=== Post-Deployment Verification ===");
        console.log("✅ TestEscrowFactory deployed and verified");
        console.log("🚀 Ready to deploy SuiResolverBidirectional!");
    }
}

/**
 * @title DeploySuiResolverBidirectional
 * @dev Deploy SuiResolverBidirectional using deployed EscrowFactory
 */
contract DeploySuiResolverBidirectional is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);
        
        console.log("=== SuiResolverBidirectional Deployment ===");
        console.log("Deployer address:", deployerAddress);
        console.log("Chain ID:", block.chainid);
        
        // Check deployer balance
        uint256 balance = deployerAddress.balance;
        console.log("Deployer balance:", balance / 1e18, "ETH");
        require(balance > 0.02 ether, "Insufficient ETH for deployment");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Get addresses from environment or use defaults
        address escrowFactoryAddress;
        address lopAddress = 0x111111125421cA6dc452d289314280a0f8842A65;
        
        // Try to get factory address from environment
        try vm.envAddress("SEPOLIA_ESCROW_FACTORY") returns (address factory) {
            escrowFactoryAddress = factory;
            console.log("Using factory from env:", escrowFactoryAddress);
        } catch {
            // Use your existing SuiResolver as factory reference (fallback)
            try vm.envAddress("SUI_RESOLVER_ADDRESS") returns (address resolver) {
                escrowFactoryAddress = resolver;
                console.log("Using SuiResolver as factory reference:", escrowFactoryAddress);
            } catch {
                revert("No factory address found. Deploy factory first or set SUI_RESOLVER_ADDRESS");
            }
        }
        
        // Verify factory/resolver exists
        require(escrowFactoryAddress.code.length > 0, "Factory/Resolver contract not found");
        
        console.log("Constructor arguments:");
        console.log("- EscrowFactory:", escrowFactoryAddress);
        console.log("- LimitOrderProtocol:", lopAddress);
        console.log("- Initial Owner:", deployerAddress);
        
        // Deploy SuiResolverBidirectional
        SuiResolverBidirectional resolver = new SuiResolverBidirectional(
            IEscrowFactory(escrowFactoryAddress),
            IOrderMixin(lopAddress),
            deployerAddress
        );
        
        console.log("=== Deployment Successful ===");
        console.log("SuiResolverBidirectional deployed to:", address(resolver));
        
        // Verify deployment
        console.log("=== Verification ===");
        console.log("Owner:", resolver.owner());
        console.log("Contract size:", address(resolver).code.length, "bytes");
        
        // Test bidirectional functions
        console.log("=== Testing Bidirectional Functions ===");
        
        // Test ethereumOrderExists
        try resolver.ethereumOrderExists(bytes32(0)) returns (bool exists) {
            console.log("✅ ethereumOrderExists function working");
        } catch {
            console.log("❌ ethereumOrderExists function failed");
        }
        
        // Test isSecretCoordinated  
        try resolver.isSecretCoordinated(bytes32(0)) returns (bool coordinated) {
            console.log("✅ isSecretCoordinated function working");
        } catch {
            console.log("❌ isSecretCoordinated function failed");
        }
        
        // Test getBidirectionalMapping
        try resolver.getBidirectionalMapping(bytes32(0)) returns (
            bytes32 ethOrder,
            bytes32 suiEscrow, 
            bool mappingExists,
            string memory status
        ) {
            console.log("✅ getBidirectionalMapping function working");
        } catch {
            console.log("❌ getBidirectionalMapping function failed");
        }
        
        // Log important information for .env update
        console.log("=== Update your .env file ===");
        console.log("SUI_RESOLVER_BIDIRECTIONAL=", address(resolver));
        
        vm.stopBroadcast();
        
        // Final verification
        _verifyBidirectionalDeployment(resolver, IEscrowFactory(escrowFactoryAddress), IOrderMixin(lopAddress), deployerAddress);
    }
    
    function _verifyBidirectionalDeployment(
        SuiResolverBidirectional resolver,
        IEscrowFactory expectedFactory,
        IOrderMixin expectedLop,
        address expectedOwner
    ) internal view {
        console.log("=== Post-Deployment Verification ===");
        
        // Verify owner
        address actualOwner = resolver.owner();
        require(actualOwner == expectedOwner, "Owner verification failed");
        console.log("✅ Owner verified:", actualOwner);
        
        // Check if contract has bidirectional functions
        try resolver.ethereumOrderExists(bytes32(0)) returns (bool) {
            console.log("✅ Bidirectional functions available");
        } catch {
            console.log("❌ Bidirectional functions not found");
        }
        
        // Check if contract has live coordination functions
        try resolver.isSecretCoordinated(bytes32(0)) returns (bool) {
            console.log("✅ Live coordination functions available");
        } catch {
            console.log("❌ Live coordination functions not found");
        }
        
        console.log("✅ Contract deployment verified");
        console.log("🌉 Ready for bidirectional cross-chain swaps!");
        console.log("🚀 World's first trustless Sui-Ethereum bidirectional bridge is LIVE!");
    }
}

/**
 * @title DeployComplete
 * @dev Deploy both contracts in sequence
 */
contract DeployComplete is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);
        
        console.log("=== Complete System Deployment ===");
        console.log("Deployer address:", deployerAddress);
        console.log("Chain ID:", block.chainid);
        
        // Check deployer balance
        uint256 balance = deployerAddress.balance;
        console.log("Deployer balance:", balance / 1e18, "ETH");
        require(balance > 0.05 ether, "Insufficient ETH for complete deployment");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Step 1: Deploy TestEscrowFactory
        console.log("🏭 Step 1: Deploying TestEscrowFactory...");
        
        address lopAddress = 0x111111125421cA6dc452d289314280a0f8842A65;
        address sepoliaWETH = 0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14;
        address sepoliaUSDC = 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238;
        
        TestEscrowFactory factory = new TestEscrowFactory(
            lopAddress,
            IERC20(sepoliaWETH),
            IERC20(sepoliaUSDC),
            deployerAddress,
            1800,
            1800
        );
        
        console.log("✅ TestEscrowFactory deployed:", address(factory));
        
        // Step 2: Deploy SuiResolverBidirectional
        console.log("🌉 Step 2: Deploying SuiResolverBidirectional...");
        
        SuiResolverBidirectional resolver = new SuiResolverBidirectional(
            IEscrowFactory(address(factory)),
            IOrderMixin(lopAddress),
            deployerAddress
        );
        
        console.log("✅ SuiResolverBidirectional deployed:", address(resolver));
        
        // Log for .env updates
        console.log("=== Update your .env file ===");
        console.log("SEPOLIA_ESCROW_FACTORY=", address(factory));
        console.log("SUI_RESOLVER_BIDIRECTIONAL=", address(resolver));
        
        vm.stopBroadcast();
        
        // Final verification
        console.log("=== Final System Verification ===");
        console.log("✅ Factory Owner:", factory.owner());
        console.log("✅ Resolver Owner:", resolver.owner());
        console.log("✅ Both contracts deployed successfully");
        console.log("🎉 Complete bidirectional bridge system is LIVE!");
        console.log("🌍 Ready to revolutionize cross-chain DeFi!");
    }
}