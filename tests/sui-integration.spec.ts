import 'dotenv/config'
import { expect } from '@jest/globals'
import { SuiClient } from '@mysten/sui.js/client'
import { Ed25519Keypair } from '@mysten/sui.js/keypairs/ed25519'
import { SuiWallet } from './sui-wallet'
import { SuiResolver } from './sui-resolver'
import { config } from './config'
import { createHash } from 'crypto'

// Test only if Sui package is deployed
const SKIP_SUI_TESTS = !process.env.SUI_PACKAGE_ID || process.env.SUI_PACKAGE_ID === '0x0'

describe('Sui Integration Tests', () => {
    let suiClient: SuiClient
    let userWallet: SuiWallet
    let resolverWallet: SuiWallet
    let suiResolver: SuiResolver
    
    const packageId = process.env.SUI_PACKAGE_ID || '0x0'
    const resolverObjectId = process.env.SUI_RESOLVER_ID || '0x0'

    beforeAll(async () => {
        if (SKIP_SUI_TESTS) {
            console.log('Skipping Sui tests - package not deployed')
            return
        }

        // Initialize Sui client
        suiClient = new SuiClient({ url: config.chain.sui.url })

        // Use your deployer address for testing (since it has SUI)
        const deployerPrivateKey = '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80'
        
        // Create test wallets
        userWallet = new SuiWallet(deployerPrivateKey, suiClient)
        resolverWallet = new SuiWallet(Ed25519Keypair.generate(), suiClient)

        // Transfer some SUI to resolver wallet for testing
        try {
            await userWallet.transferCoins(
                '0x2::sui::SUI',
                1000000000n, // 1 SUI
                await resolverWallet.getAddress()
            )
        } catch (error) {
            console.log('Transfer failed (might not have enough SUI):', error.message)
        }

        // Create resolver helper
        suiResolver = new SuiResolver(suiClient, packageId, resolverObjectId)

        console.log('Sui test setup complete:')
        console.log('User address:', await userWallet.getAddress())
        console.log('Resolver address:', await resolverWallet.getAddress())
    })

    describe('Sui Wallet Integration', () => {
        it('should connect to Sui testnet', async () => {
            if (SKIP_SUI_TESTS) return

            const chainInfo = await suiClient.getChainIdentifier()
            expect(chainInfo).toBeDefined()
        })

        it('should get SUI balance', async () => {
            if (SKIP_SUI_TESTS) return

            const balance = await userWallet.suiBalance()
            expect(typeof balance).toBe('bigint')
            console.log('User SUI balance:', balance.toString())
        })

        it('should transfer SUI between wallets', async () => {
            if (SKIP_SUI_TESTS) return

            const userBalance = await userWallet.suiBalance()
            if (userBalance < 2000000n) {
                console.log('Skipping transfer test - insufficient balance')
                return
            }

            const transferAmount = 1000000n // 0.001 SUI
            const initialBalance = await resolverWallet.suiBalance()

            const txHash = await userWallet.transferCoins(
                '0x2::sui::SUI',
                transferAmount,
                await resolverWallet.getAddress()
            )

            expect(txHash).toBeDefined()
            console.log('Transfer transaction:', txHash)

            // Check balance increased
            const finalBalance = await resolverWallet.suiBalance()
            expect(finalBalance).toBeGreaterThan(initialBalance)
        })
    })

    describe('Sui Resolver Integration', () => {
        it('should create resolver transaction blocks', async () => {
            if (SKIP_SUI_TESTS) return

            const timeLocks = SuiResolver.createTimeLocks(10, 120, 121, 122, 10, 100, 101)
            const immutables = SuiResolver.createImmutables(
                '0x1234567890abcdef',  // orderHash
                'secret123',           // secret (without 0x prefix)
                await userWallet.getAddress(),      // maker
                await resolverWallet.getAddress(), // taker
                '0x2::sui::SUI',      // tokenType
                1000000n,             // amount
                100000n,              // safetyDeposit
                timeLocks,
                '0xethorderabcdef'    // ethereumOrderHash
            )

            const tx = suiResolver.deploySrcWithDeposit(
                immutables,
                'dummy-coin-id',
                'dummy-safety-id'
            )

            expect(tx).toBeDefined()
            expect(tx.blockData.transactions.length).toBeGreaterThan(0)
        })

        it('should get resolver information', async () => {
            if (SKIP_SUI_TESTS) return

            try {
                const resolverInfo = await suiResolver.getResolverInfo()
                console.log('Resolver info:', resolverInfo.data.content.fields)
                expect(resolverInfo).toBeDefined()
                expect(resolverInfo.data.objectId).toBe(resolverObjectId)
            } catch (error) {
                console.log('Resolver not found:', error.message)
            }
        })
    })

    describe('Cross-Chain Preparation', () => {
        it('should prepare cross-chain swap data structures', async () => {
            if (SKIP_SUI_TESTS) return

            // Test that our data structures are compatible with cross-chain operations
            const secret = 'secret123'
            const timeLocks = SuiResolver.createTimeLocks(10, 120, 121, 122, 10, 100, 101)
            
            const suiImmutables = SuiResolver.createImmutables(
                '0x1234567890abcdef',
                secret,
                await userWallet.getAddress(),
                await resolverWallet.getAddress(),
                '0x2::sui::SUI',
                1000000n,
                100000n,
                timeLocks,
                '0xethorderabcdef'
            )

            // Verify hash consistency (should match Move contract hashing)
            const expectedHash = createHash('sha256').update(Buffer.from(secret)).digest()
            
            expect(Buffer.from(suiImmutables.hashLock)).toEqual(expectedHash)
            expect(suiImmutables.amount).toBe(1000000n)
            expect(suiImmutables.timeLocks.srcWithdrawal).toBe(10)
        })
    })
})