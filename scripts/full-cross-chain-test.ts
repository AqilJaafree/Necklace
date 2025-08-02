import { ethers } from 'ethers'
import { SuiClient } from '@mysten/sui.js/client'
import { Ed25519Keypair } from '@mysten/sui.js/keypairs/ed25519'
import { TransactionBlock } from '@mysten/sui.js/transactions'
import 'dotenv/config'

const ENHANCED_RESOLVER = '0xb6A8B60d6973bd110c637357121BF191657295de'
const SUI_PACKAGE = '0x2649d770fdeda172fc3854cfbd8893ed87eae6a9cf5dd9aa72ecf6d93d824dff'
const SUI_FACTORY_ID = '0x4a67a605d45460e06e1e3cacfc4ddc58eeb0cf9d67e9134ae35e5e46b7308ba0'

class FullCrossChainTest {
    private suiClient: SuiClient
    private ethProvider: ethers.JsonRpcProvider
    private ethWallet: ethers.Wallet
    private suiKeypair: Ed25519Keypair
    private enhancedResolver: ethers.Contract

    constructor() {
        // Initialize Sui
        this.suiClient = new SuiClient({ url: 'https://fullnode.testnet.sui.io:443' })
        
        // Initialize Ethereum
        this.ethProvider = new ethers.JsonRpcProvider(process.env.SEPOLIA_RPC!)
        this.ethWallet = new ethers.Wallet(process.env.PRIVATE_KEY!, this.ethProvider)
        
        // FIXED: Better Sui keypair initialization
        this.suiKeypair = this.createSuiKeypair()
        
        // Initialize enhanced resolver
        this.enhancedResolver = new ethers.Contract(
            ENHANCED_RESOLVER,
            [
                'function coordinateSecretFromSui(bytes32,bytes32,bytes32) external',
                'function getCoordinatedSecret(bytes32) external view returns (bytes32,bool,uint256,address,string)',
                'function isSecretCoordinated(bytes32) external view returns (bool)',
                'event LiveSecretCoordinated(bytes32 indexed,bytes32 indexed,bytes32 indexed,address,uint256)'
            ],
            this.ethWallet
        )
    }

    // FIXED: Better keypair creation method
    private createSuiKeypair(): Ed25519Keypair {
        try {
            const privateKeyHex = process.env.PRIVATE_KEY!.replace('0x', '')
            
            // Method 1: Try direct conversion (most common)
            let privateKeyBytes = Buffer.from(privateKeyHex, 'hex')
            
            // Ensure exactly 32 bytes for Ed25519
            if (privateKeyBytes.length > 32) {
                privateKeyBytes = privateKeyBytes.slice(0, 32)
            } else if (privateKeyBytes.length < 32) {
                const padded = Buffer.alloc(32)
                privateKeyBytes.copy(padded, 32 - privateKeyBytes.length)
                privateKeyBytes = padded
            }
            
            return Ed25519Keypair.fromSecretKey(privateKeyBytes)
            
        } catch (error) {
            console.error('❌ Keypair creation failed:', error.message)
            throw new Error('Could not create Sui keypair from private key')
        }
    }

    async runFullCrossChainTest() {
        console.log('🚀 Running Full Cross-Chain Integration Test')
        console.log('👤 Sui Address:', this.suiKeypair.getPublicKey().toSuiAddress())
        console.log('👤 Eth Address:', this.ethWallet.address)
        console.log('🌉 Enhanced Resolver:', ENHANCED_RESOLVER)
        
        // STEP 0: Verify we have SUI balance
        console.log('\n💰 Step 0: Verifying SUI Balance...')
        await this.verifySuiBalance()
        
        try {
            // Step 1: Create Sui atomic swap
            console.log('\n🟦 Step 1: Creating Sui Atomic Swap...')
            const suiResult = await this.createSuiAtomicSwap()
            
            // Step 2: Complete Sui swap to reveal secret
            console.log('\n🔑 Step 2: Completing Sui Swap to Reveal Secret...')
            const revealedSecret = await this.completeSuiSwap(suiResult.escrowId, suiResult.secret)
            
            // Step 3: Coordinate secret to Ethereum
            console.log('\n📡 Step 3: Coordinating Secret to Ethereum...')
            const ethResult = await this.coordinateSecretToEthereum(
                suiResult.escrowId,
                revealedSecret,
                suiResult.orderHash
            )
            
            // Step 4: Verify cross-chain coordination
            console.log('\n🔍 Step 4: Verifying Cross-Chain Coordination...')
            await this.verifyCrossChainCoordination(suiResult.escrowId, revealedSecret)
            
            console.log('\n🎉 FULL CROSS-CHAIN TEST SUCCESSFUL!')
            console.log('🌍 Live secret coordination between Sui and Ethereum CONFIRMED!')
            
            return {
                suiEscrowId: suiResult.escrowId,
                ethereumCoordination: ethResult.txHash,
                secret: revealedSecret,
                status: 'CROSS_CHAIN_SUCCESS'
            }
            
        } catch (error) {
            console.error('❌ Full cross-chain test failed:', error.message)
            throw error
        }
    }

    // NEW: Verify SUI balance before starting
    private async verifySuiBalance() {
        const address = this.suiKeypair.getPublicKey().toSuiAddress()
        
        try {
            const balance = await this.suiClient.getBalance({
                owner: address,
                coinType: '0x2::sui::SUI'
            })
            
            const suiAmount = Number(balance.totalBalance) / 1_000_000_000
            console.log('💰 SUI Balance:', suiAmount.toFixed(6), 'SUI')
            
            if (suiAmount < 0.05) {
                throw new Error(`Insufficient SUI balance: ${suiAmount} SUI (need at least 0.05 SUI)`)
            }
            
            // Also check if we have usable coins
            const coins = await this.suiClient.getCoins({
                owner: address,
                coinType: '0x2::sui::SUI'
            })
            
            console.log('🪙 Available coins:', coins.data.length)
            
            if (coins.data.length === 0) {
                throw new Error('No SUI coins available for gas')
            }
            
            console.log('✅ Sufficient SUI for cross-chain test')
            
        } catch (error) {
            console.error('❌ SUI balance check failed:', error.message)
            throw error
        }
    }

    private async createSuiAtomicSwap() {
        const secret = 'cross_chain_test_' + Date.now()
        const secretHash = new Uint8Array(
            Buffer.from(ethers.keccak256(Buffer.from(secret)).slice(2), 'hex')
        )
        
        console.log('🔐 Creating Sui swap with secret:', secret)
        
        const tx = new TransactionBlock()

        // Create TimeLocks
        const timeLocks = tx.moveCall({
            target: `${SUI_PACKAGE}::types::create_time_locks`,
            arguments: [
                tx.pure(15, 'u64'),   // src_withdrawal - 15 seconds
                tx.pure(60, 'u64'),   // src_public_withdrawal
                tx.pure(120, 'u64'),  // src_cancellation
                tx.pure(180, 'u64'),  // src_public_cancellation
                tx.pure(15, 'u64'),   // dst_withdrawal
                tx.pure(60, 'u64'),   // dst_public_withdrawal
                tx.pure(120, 'u64')   // dst_cancellation
            ]
        })

        // Create cross-chain order hash
        const crossChainOrderHash = 'cross_chain_order_' + Date.now()
        
        // Create SrcImmutables
        const immutables = tx.moveCall({
            target: `${SUI_PACKAGE}::types::create_src_immutables`,
            arguments: [
                tx.pure(Array.from(Buffer.from(crossChainOrderHash, 'utf8'))),
                tx.pure(Array.from(secretHash)),
                tx.pure(this.suiKeypair.getPublicKey().toSuiAddress()), // maker
                tx.pure(this.suiKeypair.getPublicKey().toSuiAddress()), // taker
                tx.pure('0x2::sui::SUI'),
                tx.pure(20_000_000, 'u64'), // amount (0.02 SUI)
                tx.pure(5_000_000, 'u64'),  // safety_deposit (0.005 SUI)
                timeLocks,
                tx.pure(Array.from(Buffer.from(this.ethWallet.address, 'utf8'))) // ethereum_address
            ]
        })

        // Create escrow using factory
        tx.moveCall({
            target: `${SUI_PACKAGE}::factory::create_src_escrow`,
            arguments: [
                tx.object(SUI_FACTORY_ID),
                immutables
            ],
            typeArguments: ['0x2::sui::SUI']
        })

        tx.setGasBudget(50_000_000) // Increased gas budget

        const result = await this.suiClient.signAndExecuteTransactionBlock({
            signer: this.suiKeypair,
            transactionBlock: tx,
            options: {
                showEffects: true,
                showEvents: true,
                showObjectChanges: true
            }
        })

        if (result.effects?.status?.status !== 'success') {
            throw new Error(`Sui escrow creation failed: ${result.effects?.status?.error}`)
        }

        console.log('✅ Sui escrow created!')
        console.log('📜 Sui TX:', result.digest)
        
        // Extract escrow ID
        let escrowId: string | null = null
        
        if (result.events) {
            result.events.forEach((event) => {
                const eventType = event.type.split('::').pop()
                if (event.parsedJson) {
                    const eventData = event.parsedJson as any
                    if ((eventType === 'EscrowCreated' || eventType === 'SrcEscrowCreated') && eventData.escrow_id) {
                        escrowId = eventData.escrow_id
                    }
                }
            })
        }

        if (!escrowId) {
            const createdObjects = result.objectChanges?.filter(change => 
                change.type === 'created'
            )
            if (createdObjects && createdObjects.length > 0) {
                escrowId = (createdObjects[0] as any).objectId
            }
        }

        if (!escrowId) {
            throw new Error('Could not find escrow ID')
        }

        return {
            escrowId,
            txHash: result.digest,
            secret,
            orderHash: crossChainOrderHash
        }
    }

    private async completeSuiSwap(escrowId: string, secret: string): Promise<string> {
        console.log('💰 Depositing and completing Sui swap...')
        
        // Deposit tokens
        await this.depositToEscrow(escrowId)
        
        // Wait for timelock
        console.log('⏳ Waiting 20 seconds for timelock...')
        await new Promise(resolve => setTimeout(resolve, 20000))
        
        // Withdraw with secret (this reveals the secret)
        const tx = new TransactionBlock()

        const secretBytes = Array.from(Buffer.from(secret, 'utf8'))

        const [withdrawnCoin, safetyCoin] = tx.moveCall({
            target: `${SUI_PACKAGE}::escrow::withdraw`,
            arguments: [
                tx.object(escrowId),
                tx.pure(secretBytes),
                tx.object('0x6'), // clock
            ],
            typeArguments: ['0x2::sui::SUI']
        })

        tx.transferObjects([withdrawnCoin, safetyCoin], tx.pure(this.suiKeypair.getPublicKey().toSuiAddress()))
        tx.setGasBudget(30_000_000)

        const result = await this.suiClient.signAndExecuteTransactionBlock({
            signer: this.suiKeypair,
            transactionBlock: tx,
            options: {
                showEffects: true,
                showEvents: true
            }
        })

        if (result.effects?.status?.status === 'success') {
            console.log('✅ Sui secret revealed!')
            console.log('🔐 Secret:', secret)
            return secret
        } else {
            throw new Error('Sui withdrawal failed')
        }
    }

    private async depositToEscrow(escrowId: string) {
        const tx = new TransactionBlock()

        const [depositCoin] = tx.splitCoins(tx.gas, [tx.pure(20_000_000)])
        const [safetyDepositCoin] = tx.splitCoins(tx.gas, [tx.pure(5_000_000)])

        tx.moveCall({
            target: `${SUI_PACKAGE}::escrow::deposit`,
            arguments: [
                tx.object(escrowId),
                depositCoin,
                safetyDepositCoin
            ],
            typeArguments: ['0x2::sui::SUI']
        })

        tx.setGasBudget(30_000_000)

        const result = await this.suiClient.signAndExecuteTransactionBlock({
            signer: this.suiKeypair,
            transactionBlock: tx,
            options: { showEffects: true }
        })

        if (result.effects?.status?.status !== 'success') {
            throw new Error('Deposit failed')
        }
    }

    private async coordinateSecretToEthereum(suiEscrowId: string, secret: string, orderHash: string) {
        console.log('🌉 Coordinating secret from Sui to Ethereum...')
        
        const secretBytes32 = ethers.keccak256(Buffer.from(secret))
        const orderHashBytes32 = ethers.keccak256(Buffer.from(orderHash, 'utf8'))
        
        console.log('📋 Coordination data:')
        console.log('   Sui Escrow:', suiEscrowId)
        console.log('   Secret (string):', secret)
        console.log('   Secret (bytes32):', secretBytes32)
        console.log('   Order Hash:', orderHashBytes32)
        
        const tx = await this.enhancedResolver.coordinateSecretFromSui(
            suiEscrowId,
            secretBytes32,
            orderHashBytes32,
            { gasLimit: 300000 }
        )
        
        console.log('✅ Coordination transaction sent!')
        console.log('📜 Eth TX:', tx.hash)
        
        const receipt = await tx.wait()
        console.log('✅ Secret coordinated to Ethereum!')
        console.log('📊 Block:', receipt.blockNumber)
        console.log('⛽ Gas used:', receipt.gasUsed.toString())
        
        return { txHash: tx.hash, blockNumber: receipt.blockNumber }
    }

    private async verifyCrossChainCoordination(suiEscrowId: string, secret: string) {
        console.log('🔍 Verifying cross-chain coordination...')
        
        const secretBytes32 = ethers.keccak256(Buffer.from(secret))
        
        // Check if secret is coordinated
        const isCoordinated = await this.enhancedResolver.isSecretCoordinated(secretBytes32)
        console.log('✅ Secret coordinated on Ethereum:', isCoordinated)
        
        // Get coordination details
        const [coordSecret, available, timestamp, coordinator, status] = 
            await this.enhancedResolver.getCoordinatedSecret(suiEscrowId)
        
        console.log('📊 Coordination Details:')
        console.log('   Secret available:', available)
        console.log('   Coordinator:', coordinator)
        console.log('   Status:', status)
        console.log('   Timestamp:', new Date(Number(timestamp) * 1000).toISOString())
        
        if (isCoordinated && available) {
            console.log('🎉 CROSS-CHAIN COORDINATION VERIFIED!')
            console.log('🌍 Secret is now available on both Sui and Ethereum!')
        } else {
            throw new Error('Cross-chain coordination verification failed')
        }
    }
}

// Run the full test
if (require.main === module) {
    const test = new FullCrossChainTest()
    test.runFullCrossChainTest().catch(console.error)
}

export { FullCrossChainTest }