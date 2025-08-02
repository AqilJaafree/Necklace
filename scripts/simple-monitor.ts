// scripts/simple-monitor.ts
import { ethers } from 'ethers'
import { SuiClient } from '@mysten/sui.js/client'
import type { EventId } from '@mysten/sui.js/client'
import 'dotenv/config'

// Your deployed addresses
const SEPOLIA_RPC = process.env.SEPOLIA_RPC!
const SUI_VERIFIER = '0x6a87032589b837935b1A393Dc905c84E908c6974'
const SUI_RESOLVER = '0x9c58491817B883840737aF8E49C92eDcFF4bFf40'
const SUI_PACKAGE = '0x2649d770fdeda172fc3854cfbd8893ed87eae6a9cf5dd9aa72ecf6d93d824dff'

class SimpleMonitor {
    private ethProvider: ethers.JsonRpcProvider
    private suiClient: SuiClient

    constructor() {
        this.ethProvider = new ethers.JsonRpcProvider(SEPOLIA_RPC)
        this.suiClient = new SuiClient({ url: 'https://fullnode.testnet.sui.io:443' })
    }

    async start() {
        console.log('🔍 Starting Cross-Chain Monitor...')
        console.log('📡 Ethereum Sepolia:', SUI_RESOLVER)
        console.log('🟦 Sui Testnet:', SUI_PACKAGE)
        
        // Monitor both chains
        await Promise.all([
            this.monitorEthereum(),
            this.monitorSui()
        ])
    }

    private async monitorEthereum() {
        console.log('👁️ Watching Ethereum events...')
        
        // Simple contract instance
        const contract = new ethers.Contract(
            SUI_RESOLVER,
            [
                'event SuiEscrowDeployed(bytes32 indexed orderHash, bytes32 indexed suiEscrowId, address indexed maker, address taker, uint256 amount)',
                'event SuiSecretUsed(bytes32 indexed orderHash, bytes32 indexed secret, address resolver)',
                'event CrossChainSwapCompleted(bytes32 indexed orderHash, address srcChain, address dstChain, uint256 srcAmount, uint256 dstAmount)'
            ],
            this.ethProvider
        )

        // Listen for escrow deployments
        contract.on('SuiEscrowDeployed', (orderHash, suiEscrowId, maker, taker, amount) => {
            console.log('🚀 [ETHEREUM] Escrow Deployed:')
            console.log(`   Order: ${orderHash}`)
            console.log(`   Sui Escrow: ${suiEscrowId}`)
            console.log(`   Maker: ${maker}`)
            console.log(`   Amount: ${amount.toString()}`)
        })

        // Listen for secret usage
        contract.on('SuiSecretUsed', (orderHash, secret, resolver) => {
            console.log('🔑 [ETHEREUM] Secret Used:')
            console.log(`   Order: ${orderHash}`)
            console.log(`   Secret: ${secret}`)
            console.log(`   Resolver: ${resolver}`)
        })

        // Check current block
        const block = await this.ethProvider.getBlockNumber()
        console.log(`✅ Ethereum connected - Block: ${block}`)
    }

    private async monitorSui() {
        console.log('👁️ Watching Sui events...')
        
        let cursor: EventId | null = null
        
        const poll = async () => {
            try {
                // Query events from our package - simplified query
                const events = await this.suiClient.queryEvents({
                    query: {
                        Package: SUI_PACKAGE
                    },
                    limit: 10
                })

                if (events.data.length > 0) {
                    console.log(`📢 Found ${events.data.length} events`)
                    for (const event of events.data) {
                        this.handleSuiEvent(event)
                    }
                }
            } catch (error) {
                console.error('❌ Sui polling error:', error.message)
            }
            
            // Poll every 10 seconds
            setTimeout(poll, 10000)
        }

        // Check connection
        const chainId = await this.suiClient.getChainIdentifier()
        console.log(`✅ Sui connected - Chain: ${chainId}`)
        
        // Start polling
        poll()
    }

    private handleSuiEvent(event: any) {
        const type = event.type.split('::').pop()
        
        switch (type) {
            case 'EscrowCreated':
                console.log('🏗️ [SUI] Escrow Created:')
                console.log(`   ID: ${event.parsedJson?.escrow_id}`)
                console.log(`   Maker: ${event.parsedJson?.maker}`)
                console.log(`   Amount: ${event.parsedJson?.amount}`)
                break
                
            case 'Withdrawn':
                console.log('💰 [SUI] Withdrawal:')
                console.log(`   ID: ${event.parsedJson?.escrow_id}`)
                console.log(`   Secret: ${event.parsedJson?.secret}`)
                console.log(`   Amount: ${event.parsedJson?.amount}`)
                break
                
            case 'SrcEscrowDeployed':
                console.log('🚀 [SUI] Resolver Escrow:')
                console.log(`   ID: ${event.parsedJson?.escrow_id}`)
                console.log(`   ETH Order: ${event.parsedJson?.ethereum_order_hash}`)
                break
                
            default:
                console.log(`📢 [SUI] ${type}:`, event.parsedJson)
        }
    }
}

// Run monitor
if (require.main === module) {
    const monitor = new SimpleMonitor()
    monitor.start().catch(console.error)
}

export { SimpleMonitor }