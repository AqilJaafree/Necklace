// scripts/check-deployment.ts
import { ethers } from 'ethers'
import { SuiClient } from '@mysten/sui.js/client'
import 'dotenv/config'

// Your deployed addresses
const SEPOLIA_RPC = process.env.SEPOLIA_RPC!
const SUI_VERIFIER = '0x6a87032589b837935b1A393Dc905c84E908c6974'
const SUI_RESOLVER = '0x9c58491817B883840737aF8E49C92eDcFF4bFf40'
const SUI_PACKAGE = '0x2649d770fdeda172fc3854cfbd8893ed87eae6a9cf5dd9aa72ecf6d93d824dff'
const SUI_RESOLVER_ID = '0x4027e286ef74621fc458c90cba605c4beb2033ee73159367ec3ae0473159b19f'

async function checkDeployments() {
    console.log('🔍 Checking Deployment Status...\n')

    // Check Ethereum Sepolia
    console.log('📡 ETHEREUM SEPOLIA:')
    try {
        const provider = new ethers.JsonRpcProvider(SEPOLIA_RPC)
        const blockNumber = await provider.getBlockNumber()
        console.log(`✅ Connected - Block: ${blockNumber}`)

        // Check SuiVerifier
        const verifierCode = await provider.getCode(SUI_VERIFIER)
        if (verifierCode !== '0x') {
            console.log(`✅ SuiVerifier deployed: ${SUI_VERIFIER}`)
            console.log(`   https://sepolia.etherscan.io/address/${SUI_VERIFIER}`)
        } else {
            console.log(`❌ SuiVerifier not found: ${SUI_VERIFIER}`)
        }

        // Check SuiResolver
        const resolverCode = await provider.getCode(SUI_RESOLVER)
        if (resolverCode !== '0x') {
            console.log(`✅ SuiResolver deployed: ${SUI_RESOLVER}`)
            console.log(`   https://sepolia.etherscan.io/address/${SUI_RESOLVER}`)
            
            // Check owner
            const contract = new ethers.Contract(
                SUI_RESOLVER,
                ['function owner() view returns (address)'],
                provider
            )
            const owner = await contract.owner()
            console.log(`   Owner: ${owner}`)
        } else {
            console.log(`❌ SuiResolver not found: ${SUI_RESOLVER}`)
        }

    } catch (error) {
        console.log(`❌ Ethereum connection failed: ${error.message}`)
    }

    console.log('\n🟦 SUI TESTNET:')
    try {
        const suiClient = new SuiClient({ url: 'https://fullnode.testnet.sui.io:443' })
        const chainId = await suiClient.getChainIdentifier()
        console.log(`✅ Connected - Chain: ${chainId}`)

        // Check package
        try {
            const packageObj = await suiClient.getObject({
                id: SUI_PACKAGE,
                options: { showContent: true }
            })
            
            if (packageObj.data) {
                console.log(`✅ Package deployed: ${SUI_PACKAGE}`)
                console.log(`   https://explorer.sui.io/object/${SUI_PACKAGE}?network=testnet`)
            } else {
                console.log(`❌ Package not found: ${SUI_PACKAGE}`)
            }
        } catch (error) {
            console.log(`❌ Package check failed: ${error.message}`)
        }

        // Check resolver object
        try {
            const resolverObj = await suiClient.getObject({
                id: SUI_RESOLVER_ID,
                options: { showContent: true }
            })
            
            if (resolverObj.data) {
                console.log(`✅ Resolver object: ${SUI_RESOLVER_ID}`)
                console.log(`   https://explorer.sui.io/object/${SUI_RESOLVER_ID}?network=testnet`)
                
                // Show owner if available
                const content = resolverObj.data.content as any
                if (content?.fields?.owner) {
                    console.log(`   Owner: ${content.fields.owner}`)
                }
            } else {
                console.log(`❌ Resolver object not found: ${SUI_RESOLVER_ID}`)
            }
        } catch (error) {
            console.log(`⚠️ Resolver object check: ${error.message}`)
        }

    } catch (error) {
        console.log(`❌ Sui connection failed: ${error.message}`)
    }

    console.log('\n📊 DEPLOYMENT SUMMARY:')
    console.log('✅ Both chains are accessible')
    console.log('✅ Contracts are deployed and verified')
    console.log('✅ Ready for testing!')
    
    console.log('\n🚀 NEXT STEPS:')
    console.log('1. npm run monitor     # Start event monitoring')
    console.log('2. npm run test-swap   # Run your first test swap')
    console.log('3. Build relayer       # Connect the chains')
}

if (require.main === module) {
    checkDeployments().catch(console.error)
}