#!/bin/bash
# Deploy Sui bridge contracts to Sepolia testnet

set -e  # Exit on any error

echo "🚀 Deploying Sui Bridge Contracts to Sepolia"

# Load environment variables
if [ -f .env ]; then
    source .env
else
    echo "❌ .env file not found"
    exit 1
fi

# Check required variables
if [ -z "$SEPOLIA_RPC" ]; then
    echo "❌ SEPOLIA_RPC not set in .env"
    exit 1
fi

if [ -z "$PRIVATE_KEY" ]; then
    echo "❌ PRIVATE_KEY not set in .env"
    exit 1
fi

# Check balance
echo "💰 Checking Sepolia ETH balance..."
DEPLOYER=$(cast wallet address --private-key $PRIVATE_KEY)
BALANCE=$(cast balance $DEPLOYER --rpc-url $SEPOLIA_RPC)
echo "Deployer: $DEPLOYER"
echo "Balance: $(cast to-unit $BALANCE ether) ETH"

# Convert to ETH for comparison
BALANCE_ETH=$(cast to-unit $BALANCE ether | cut -d'.' -f1)
if [ "$BALANCE_ETH" = "0" ]; then
    echo "❌ Insufficient Sepolia ETH! Get some from: https://sepoliafaucet.com/"
    echo "Your address: $DEPLOYER"
    exit 1
fi

echo "✅ Balance sufficient for deployment"

# Deploy SuiVerifier
echo "🔍 Deploying SuiVerifier..."
echo "Using RPC: $SEPOLIA_RPC"

SUI_VERIFIER_OUTPUT=$(forge create --rpc-url $SEPOLIA_RPC --private-key $PRIVATE_KEY \
    contracts/src/SuiVerifier.sol:SuiVerifier \
    --json 2>/dev/null)

SUI_VERIFIER=$(echo $SUI_VERIFIER_OUTPUT | grep -o '"deployedTo":"[^"]*"' | cut -d'"' -f4)

if [ -z "$SUI_VERIFIER" ] || [ "$SUI_VERIFIER" = "null" ]; then
    echo "❌ SuiVerifier deployment failed"
    echo "Output: $SUI_VERIFIER_OUTPUT"
    exit 1
fi

echo "✅ SuiVerifier deployed at: $SUI_VERIFIER"

# Contract addresses for Sepolia (using known addresses)
ESCROW_FACTORY="0x1111111111111111111111111111111111111111"  # Placeholder - would need real factory
LOP_ADDRESS="0x111111125421ca6dc452d289314280a0f8842a65"      # Real 1inch LOP on Sepolia

# Deploy SuiResolver
echo "🌉 Deploying SuiResolver..."
SUI_RESOLVER_OUTPUT=$(forge create --rpc-url $SEPOLIA_RPC --private-key $PRIVATE_KEY \
    contracts/src/SuiResolver.sol:SuiResolver \
    --constructor-args $ESCROW_FACTORY $LOP_ADDRESS $DEPLOYER \
    --json 2>/dev/null)

SUI_RESOLVER=$(echo $SUI_RESOLVER_OUTPUT | grep -o '"deployedTo":"[^"]*"' | cut -d'"' -f4)

if [ -z "$SUI_RESOLVER" ] || [ "$SUI_RESOLVER" = "null" ]; then
    echo "❌ SuiResolver deployment failed"
    echo "Output: $SUI_RESOLVER_OUTPUT"
    exit 1
fi

echo "✅ SuiResolver deployed at: $SUI_RESOLVER"

# Save deployment addresses
echo "💾 Saving deployment addresses..."
cat >> .env << EOL

# Sui Bridge Contract Addresses - Sepolia Testnet ($(date))
SUI_VERIFIER_ADDRESS=$SUI_VERIFIER
SUI_RESOLVER_ADDRESS=$SUI_RESOLVER
SEPOLIA_DEPLOYER_ADDRESS=$DEPLOYER
EOL

echo ""
echo "🎉 Deployment Complete!"
echo "📝 Contract addresses added to .env"
echo ""
echo "📊 Contract Summary:"
echo "SuiVerifier:  $SUI_VERIFIER"
echo "SuiResolver:  $SUI_RESOLVER"
echo ""
echo "🔗 View on Etherscan:"
echo "SuiVerifier:  https://sepolia.etherscan.io/address/$SUI_VERIFIER"
echo "SuiResolver:  https://sepolia.etherscan.io/address/$SUI_RESOLVER"
echo ""
echo "🚀 Ready for Phase 2: Event Monitoring!"
