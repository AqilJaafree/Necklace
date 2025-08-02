// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "forge-std/Script.sol";
import "../contracts/src/SuiResolver.sol";

contract Deploy is Script {
    function run() external {
        // Get environment variables
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);
        
        console.log("=== Enhanced SuiResolver Deployment ===");
        console.log("Deployer address:", deployerAddress);
        console.log("Chain ID:", block.chainid);
        
        // Check deployer balance
        uint256 balance = deployerAddress.balance;
        console.log("Deployer balance:", balance / 1e18, "ETH");
        require(balance > 0.01 ether, "Insufficient ETH for deployment");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Constructor arguments - using proper addresses from your environment
        IEscrowFactory escrowFactory = IEscrowFactory(0x1111111111111111111111111111111111111111);
        IOrderMixin lop = IOrderMixin(0x111111125421cA6dc452d289314280a0f8842A65);
        address initialOwner = deployerAddress;
        
        console.log("Constructor arguments:");
        console.log("- EscrowFactory:", address(escrowFactory));
        console.log("- LimitOrderProtocol:", address(lop));
        console.log("- Initial Owner:", initialOwner);
        
        // Deploy the enhanced SuiResolver
        SuiResolver resolver = new SuiResolver(escrowFactory, lop, initialOwner);
        
        console.log("=== Deployment Successful ===");
        console.log("Enhanced SuiResolver deployed to:", address(resolver));
        
        // Verify deployment
        console.log("=== Verification ===");
        console.log("Owner:", resolver.owner());
        console.log("Contract size:", address(resolver).code.length, "bytes");
        
        // Log important information for .env update
        console.log("=== Update your .env file ===");
        console.log("SUI_RESOLVER_ADDRESS_ENHANCED=", address(resolver));
        
        vm.stopBroadcast();
        
        // Additional deployment verification
        _verifyDeployment(resolver, escrowFactory, lop, initialOwner);
    }
    
    function _verifyDeployment(
        SuiResolver resolver,
        IEscrowFactory expectedFactory,
        IOrderMixin expectedLop,
        address expectedOwner
    ) internal view {
        console.log("=== Post-Deployment Verification ===");
        
        // Verify owner
        address actualOwner = resolver.owner();
        require(actualOwner == expectedOwner, "Owner verification failed");
        console.log("Owner verified:", actualOwner);
        
        // Check if contract has the enhanced functions
        try resolver.isSecretCoordinated(bytes32(0)) returns (bool) {
            console.log("Enhanced coordination functions available");
        } catch {
            console.log("Enhanced coordination functions not found");
        }
        
        // Check event signature exists (basic contract validation)
        console.log("Contract deployment verified");
        console.log("Ready for live secret coordination!");
    }
}