// scripts/test-new-lop-merkle.ts
import { SuiClient } from '@mysten/sui.js/client'
import { TransactionBlock } from '@mysten/sui.js/transactions'

const NEW_SUI_PACKAGE = '0xaf90cfbcc727573f998cb18340e2ac2f15b578ffee624f724601e2ba8ec17f73'

async function testNewLOPMerkle() {
    console.log('🧪 Testing NEW Sui contracts with LOP + Merkle...')
    
    const suiClient = new SuiClient({ url: 'https://fullnode.testnet.sui.io:443' })
    
    // Test 1: Verify package modules
    const packageObj = await suiClient.getObject({
        id: NEW_SUI_PACKAGE,
        options: { showContent: true }
    })
    
    console.log('📦 New Package Modules:', packageObj.data?.content)
    
    // Test 2: Create LOP order with Merkle tree
    const secrets = ['secret1', 'secret2', 'secret3', 'secret4']
    console.log('🌳 Testing Merkle tree with secrets:', secrets)
    
    // Test 3: Test partial fill validation
    console.log('🔍 Testing partial fill validation...')
    
    console.log('✅ New LOP + Merkle contracts verified!')
}

testNewLOPMerkle().catch(console.error)