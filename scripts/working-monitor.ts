// scripts/working-monitor.ts
import { ethers } from 'ethers'
import { SuiClient } from '@mysten/sui.js/client'
import 'dotenv/config'

// Your deployed addresses
const SEPOLIA_RPC = process.env.SEPOLIA_RPC!
const SUI_RESOLVER = '0x9c58491817B883840737aF8E49C92eDcFF4bFf40'
const SUI_PACKAGE = '0x2649d770fdeda172fc3854cfbd8893ed87eae6a9cf5dd9aa72ecf6d93d824dff'

class WorkingMonitor {
    private ethProvider: ethers.JsonRpcProvider
    private suiClient: SuiClient
    private lastCheckedTx: string | null = null

    constructor() {
        this.ethProvider = new ethers.JsonRpcProvider(SEPOLIA_RPC)
        this.suiClient = new SuiClient({ url: 'https://fullnode.testnet.sui.io:443' })
    }

    async start() {
        console.log('🔍 Starting Working Cross-Chain Monitor...')
        console.log('📡 Ethereum Sepolia:', SUI_RESOLVER)
        console.log('🟦 Sui Testnet:', SUI_PACKAGE)
        
        // Monitor both chains
        await Promise.all([
            this.monitorEthereum(),
            this.monitorSuiTransactions()
        ])
    }

    private async monitorEthereum() {
        console.log('👁️ Watching Ethereum events...')
        
        const contract = new ethers.Contract(
            SUI_RESOLVER,
            [
                'event SuiEscrowDeployed(bytes32 indexed orderHash, bytes32 indexed suiEscrowId, address indexed maker, address taker, uint256 amount)',
                'event SuiSecretUsed(bytes32 indexed orderHash, bytes32 indexed secret, address resolver)',
            ],
            this.ethProvider
        )

        contract.on('SuiEscrowDeployed', (orderHash, suiEscrowId, maker, taker, amount) => {
            console.log('\n🚀 [ETHEREUM] Escrow Deployed:')
            console.log(`   Order: ${orderHash}`)
            console.log(`   Sui Escrow: ${suiEscrowId}`)
            console.log(`   Maker: ${maker}`)
            console.log(`   Amount: ${amount.toString()}`)
        })

        contract.on('SuiSecretUsed', (orderHash, secret, resolver) => {
            console.log('\n🔑 [ETHEREUM] Secret Used:')
            console.log(`   Order: ${orderHash}`)
            console.log(`   Secret: ${secret}`)
            console.log(`   Resolver: ${resolver}`)
        })

        const block = await this.ethProvider.getBlockNumber()
        console.log(`✅ Ethereum connected - Block: ${block}`)
    }

    private async monitorSuiTransactions() {
        console.log('👁️ Watching Sui transactions...')
        
        const poll = async () => {
            try {
                // Get recent transactions involving our package
                const txs = await this.suiClient.queryTransactionBlocks({
                    filter: {
                        MoveFunction: {
                            package: SUI_PACKAGE,
                            module: null,
                            function: null
                        }
                    },
                    limit: 5,
                    order: 'descending',
                    options: {
                        showEvents: true,
                        showEffects: true,
                        showInput: true
                    }
                })

                for (const tx of txs.data) {
                    // Skip if we've already processed this transaction
                    if (this.lastCheckedTx === tx.digest) {
                        break
                    }

                    if (tx.events && tx.events.length > 0) {
                        console.log(`\n📦 [SUI] Transaction: ${tx.digest.slice(0, 8)}...`)
                        
                        for (const event of tx.events) {
                            if (event.type.includes(SUI_PACKAGE)) {
                                this.handleSuiEvent(event)
                            }
                        }
                    }
                }

                // Update last checked transaction
                if (txs.data.length > 0) {
                    this.lastCheckedTx = txs.data[0].digest
                }

            } catch (error) {
                console.error('❌ Sui monitoring error:', error.message)
            }
            
            // Poll every 10 seconds
            setTimeout(poll, 10000)
        }

        // Check connection first
        const chainId = await this.suiClient.getChainIdentifier()
        console.log(`✅ Sui connected - Chain: ${chainId}`)
        
        // Look for your recent escrow transaction
        console.log('🔍 Looking for recent escrow transactions...')
        
        // Start polling
        poll()
    }

    private handleSuiEvent(event: any) {
        const eventType = event.type.split('::').pop()
        
        switch (eventType) {
            case 'EscrowCreated':
                console.log('🏗️ [SUI] Escrow Created:')
                if (event.parsedJson) {
                    const data = event.parsedJson
                    console.log(`   ID: ${data.escrow_id}`)
                    console.log(`   Maker: ${data.maker}`)
                    console.log(`   Amount: ${data.amount}`)
                    console.log(`   Hash Lock: ${Buffer.from(data.hash_lock).toString('hex').slice(0, 16)}...`)
                }
                break
                
            case 'Withdrawn':
                console.log('💰 [SUI] Withdrawal:')
                if (event.parsedJson) {
                    const data = event.parsedJson
                    console.log(`   ID: ${data.escrow_id}`)
                    console.log(`   Secret: ${Buffer.from(data.secret).toString('utf8')}`)
                    console.log(`   Amount: ${data.amount}`)
                }
                break
                
            case 'SrcEscrowDeployed':
                console.log('🚀 [SUI] Resolver Escrow:')
                if (event.parsedJson) {
                    console.log(`   ID: ${event.parsedJson.escrow_id}`)
                    console.log(`   ETH Order: ${Buffer.from(event.parsedJson.ethereum_order_hash).toString('utf8')}`)
                }
                break
                
            default:
                console.log(`📢 [SUI] ${eventType}:`)
                if (event.parsedJson) {
                    console.log('   Data:', event.parsedJson)
                }
        }
    }
}

// Run monitor
if (require.main === module) {
    const monitor = new WorkingMonitor()
    monitor.start().catch(console.error)
}

export { WorkingMonitor }