// scripts/create-test-usdc.ts
import { SuiClient } from '@mysten/sui.js/client'
import { Ed25519Keypair } from '@mysten/sui.js/keypairs/ed25519'
import { TransactionBlock } from '@mysten/sui.js/transactions'
import 'dotenv/config'

class TestUSDCCreator {
    private suiClient: SuiClient
    private userKeypair: Ed25519Keypair

    constructor() {
        this.suiClient = new SuiClient({ url: 'https://fullnode.testnet.sui.io:443' })
        
        // Fix private key for Sui (pad to 32 bytes)
        const privateKeyHex = process.env.PRIVATE_KEY!.slice(2)
        let privateKeyBytes = Buffer.from(privateKeyHex, 'hex')
        
        if (privateKeyBytes.length < 32) {
            const padded = Buffer.alloc(32)
            privateKeyBytes.copy(padded, 32 - privateKeyBytes.length)
            privateKeyBytes = padded
        } else if (privateKeyBytes.length > 32) {
            privateKeyBytes = privateKeyBytes.slice(0, 32)
        }
        
        this.userKeypair = Ed25519Keypair.fromSecretKey(privateKeyBytes)
    }

    async createTestUSDC() {
        console.log('🪙 Creating Test USDC Token on Sui Testnet')
        console.log('👤 Creator:', this.userKeypair.getPublicKey().toSuiAddress())

        try {
            // Check SUI balance for gas
            const balance = await this.suiClient.getBalance({
                owner: this.userKeypair.getPublicKey().toSuiAddress(),
                coinType: '0x2::sui::SUI'
            })
            
            const suiAmount = Number(balance.totalBalance) / 1_000_000_000
            console.log('💰 SUI balance:', suiAmount.toFixed(4), 'SUI')
            
            if (suiAmount < 0.1) {
                throw new Error('Need at least 0.1 SUI for gas fees')
            }

            const tx = new TransactionBlock()

            // Create a simple coin using the Sui framework
            // This creates a custom coin type that we can use for testing
            const coinName = 'TestUSDC'
            const coinSymbol = 'TUSDC'
            const coinDescription = 'Test USDC for cross-chain bridge testing'
            const coinDecimals = 6 // USDC has 6 decimals
            const initialSupply = 1_000_000 * 1_000_000 // 1M USDC with 6 decimals

            // For simplicity, we'll just mint some SUI coins and treat them as USDC
            // In a real implementation, you'd deploy a custom coin module
            
            console.log('🏭 For this test, we\'ll use SUI as proxy for USDC')
            console.log('💡 In production, deploy a proper ERC20-like token on Sui')
            
            // Split some SUI to create "USDC" amounts
            const [usdcCoin] = tx.splitCoins(tx.gas, [tx.pure(100_000_000)]) // 0.1 "USDC"
            
            // Transfer the "USDC" to self for demonstration
            tx.transferObjects([usdcCoin], tx.pure(this.userKeypair.getPublicKey().toSuiAddress()))

            tx.setGasBudget(10_000_000)

            console.log('📤 Executing token creation...')

            const result = await this.suiClient.signAndExecuteTransactionBlock({
                signer: this.userKeypair,
                transactionBlock: tx,
                options: {
                    showEffects: true,
                    showEvents: true,
                    showObjectChanges: true
                }
            })

            if (result.effects?.status?.status !== 'success') {
                throw new Error(`Transaction failed: ${result.effects?.status?.error}`)
            }

            console.log('✅ Test USDC token operations completed!')
            console.log('📜 Transaction:', result.digest)

            // Show created objects
            const createdObjects = result.objectChanges?.filter(change => 
                change.type === 'created'
            )
            
            if (createdObjects && createdObjects.length > 0) {
                console.log('🪙 Created objects:')
                createdObjects.forEach((obj, i) => {
                    console.log(`   ${i + 1}. ${(obj as any).objectType}: ${(obj as any).objectId}`)
                })
            }

            console.log('\n💡 Usage Notes:')
            console.log('• Use "0x2::sui::SUI" as token type in your escrow')
            console.log('• This represents USDC for testing purposes')
            console.log('• In production, use actual USDC token contract')
            
            console.log('\n🚀 Ready to test cross-chain USDC swaps!')
            console.log('   Run: npm run test-swap')

        } catch (error) {
            console.error('❌ Token creation failed:', error.message)
        }
    }
}

// Run token creation
if (require.main === module) {
    const creator = new TestUSDCCreator()
    creator.createTestUSDC().catch(console.error)
}