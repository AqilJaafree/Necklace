// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "forge-std/Script.sol";
import "../contracts/src/SuiResolver.sol";

contract Deploy is Script {
    function run() external {
        vm.startBroadcast();
        
        // Use proper checksummed addresses and correct types
        IEscrowFactory escrowFactory = IEscrowFactory(0x1111111111111111111111111111111111111111);
        IOrderMixin lop = IOrderMixin(0x111111125421cA6dc452d289314280a0f8842A65); // Fixed checksum
        address deployer = 0xd6499417BbC291304fc16f6849A1717D45569494;
        
        SuiResolver resolver = new SuiResolver(escrowFactory, lop, deployer);
        
        console.log("SuiResolver deployed to:", address(resolver));
        
        vm.stopBroadcast();
    }
}
