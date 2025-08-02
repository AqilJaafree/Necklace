import { ethers } from 'ethers'
import 'dotenv/config'

const ENHANCED_RESOLVER = '0xb6A8B60d6973bd110c637357121BF191657295de'

async function testEnhancedResolver() {
    console.log('🧪 Testing Enhanced SuiResolver with Live Coordination...')
    
    const provider = new ethers.JsonRpcProvider(process.env.SEPOLIA_RPC!)
    const wallet = new ethers.Wallet(process.env.PRIVATE_KEY!, provider)
    
    // Create contract instance
    const resolver = new ethers.Contract(
        ENHANCED_RESOLVER,
        [
            'function coordinateSecretFromSui(bytes32,bytes32,bytes32) external',
            'function getCoordinatedSecret(bytes32) external view returns (bytes32,bool,uint256,address,string)',
            'function isSecretCoordinated(bytes32) external view returns (bool)',
            'function owner() external view returns (address)',
            'event LiveSecretCoordinated(bytes32 indexed,bytes32 indexed,bytes32 indexed,address,uint256)'
        ],
        wallet
    )
    
    console.log('📋 Contract Info:')
    console.log('   Address:', ENHANCED_RESOLVER)
    console.log('   Owner:', await resolver.owner())
    
    // Test secret coordination
    const testSuiEscrowId = '0x' + '1'.repeat(64) // Test escrow ID
    const testSecret = '0x' + '2'.repeat(64)      // Test secret
    const testEthOrder = '0x' + '3'.repeat(64)    // Test order hash
    
    console.log('🔑 Testing Secret Coordination...')
    console.log('   Sui Escrow ID:', testSuiEscrowId)
    console.log('   Secret:', testSecret)
    console.log('   Ethereum Order:', testEthOrder)
    
    try {
        // Test coordination (this would normally be called by the monitor)
        const tx = await resolver.coordinateSecretFromSui(
            testSuiEscrowId,
            testSecret, 
            testEthOrder,
            { gasLimit: 200000 }
        )
        
        console.log('✅ Coordination transaction sent!')
        console.log('   TX Hash:', tx.hash)
        
        const receipt = await tx.wait()
        console.log('✅ Coordination confirmed!')
        console.log('   Block:', receipt.blockNumber)
        
        // Check if secret is coordinated
        const isCoordinated = await resolver.isSecretCoordinated(testSecret)
        console.log('🔍 Secret coordinated:', isCoordinated)
        
        // Get coordination details
        const [secret, available, timestamp, coordinator, status] = 
            await resolver.getCoordinatedSecret(testSuiEscrowId)
        
        console.log('📊 Coordination Details:')
        console.log('   Secret:', secret)
        console.log('   Available:', available)
        console.log('   Timestamp:', new Date(Number(timestamp) * 1000).toISOString())
        console.log('   Coordinator:', coordinator)
        console.log('   Status:', status)
        
        console.log('🎉 LIVE SECRET COORDINATION WORKING!')
        
    } catch (error) {
        console.error('❌ Test failed:', error.message)
    }
}

testEnhancedResolver().catch(console.error)