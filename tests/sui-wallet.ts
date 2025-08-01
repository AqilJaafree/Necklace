import { Ed25519Keypair } from '@mysten/sui.js/keypairs/ed25519';
import { SuiClient } from '@mysten/sui.js/client';
import { TransactionBlock } from '@mysten/sui.js/transactions';

export class SuiWallet {
    private keypair: Ed25519Keypair;
    public address: string;

    constructor(
        privateKeyOrKeypair: string | Ed25519Keypair,
        private client: SuiClient
    ) {
        if (typeof privateKeyOrKeypair === 'string') {
            // Convert Ethereum-style private key to Sui keypair
            const privateKeyBytes = Buffer.from(privateKeyOrKeypair.replace('0x', ''), 'hex');
            this.keypair = Ed25519Keypair.fromSecretKey(privateKeyBytes.slice(0, 32));
        } else {
            this.keypair = privateKeyOrKeypair;
        }
        
        this.address = this.keypair.getPublicKey().toSuiAddress();
    }

    // Mirror wallet.ts patterns
    async getAddress(): Promise<string> {
        return this.address;
    }

    // Get coin balance (mirror tokenBalance from wallet.ts)
    async coinBalance(coinType: string): Promise<bigint> {
        try {
            const balance = await this.client.getBalance({
                owner: this.address,
                coinType,
            });
            return BigInt(balance.totalBalance);
        } catch (error) {
            console.warn(`Failed to get balance for ${coinType}:`, error);
            return 0n;
        }
    }

    // Get SUI balance specifically
    async suiBalance(): Promise<bigint> {
        return this.coinBalance('0x2::sui::SUI');
    }

    // Sign and execute transaction (mirror send from wallet.ts)
    async send(tx: TransactionBlock): Promise<{
        txHash: string;
        blockTimestamp: bigint;
        blockHash: string;
    }> {
        // Set gas budget
        tx.setGasBudget(10_000_000); // 0.01 SUI

        // Sign and execute
        const result = await this.client.signAndExecuteTransactionBlock({
            signer: this.keypair,
            transactionBlock: tx,
            options: {
                showEffects: true,
                showEvents: true,
                showObjectChanges: true,
            },
        });

        if (result.effects?.status?.status !== 'success') {
            throw new Error(`Transaction failed: ${result.effects?.status?.error}`);
        }

        return {
            txHash: result.digest,
            blockTimestamp: BigInt(result.timestampMs || Date.now()),
            blockHash: result.digest, // Sui doesn't have separate block hash
        };
    }

    // Request SUI from faucet (for testnet)
    async requestSuiFromFaucet(): Promise<void> {
        try {
            // Note: This would use the Sui faucet API in a real implementation
            console.log(`Requesting SUI from faucet for ${this.address}`);
            // In practice, you'd call the faucet API here
        } catch (error) {
            console.warn('Failed to request SUI from faucet:', error);
        }
    }

    // Get gas coins for transaction fees
    async getGasCoins(amount: bigint = 1000000000n): Promise<string[]> {
        const coins = await this.client.getCoins({
            owner: this.address,
            coinType: '0x2::sui::SUI',
        });

        return coins.data
            .filter(coin => BigInt(coin.balance) >= amount)
            .map(coin => coin.coinObjectId)
            .slice(0, 10); // Limit to 10 coins
    }

    // Split coins for testing (mirror donor funding pattern)
    async splitCoins(coinType: string, amounts: bigint[]): Promise<string[]> {
        if (amounts.length === 0) return [];

        const tx = new TransactionBlock();
        
        // Get coins to split
        const coins = await this.client.getCoins({
            owner: this.address,
            coinType,
        });

        if (coins.data.length === 0) {
            throw new Error(`No coins of type ${coinType} found`);
        }

        const coinToSplit = coins.data[0];
        
        // Split the coin
        const splitCoins = tx.splitCoins(
            tx.object(coinToSplit.coinObjectId),
            amounts.map(amount => tx.pure(amount.toString()))
        );

        // Execute transaction
        const result = await this.send(tx);
        
        // Extract created coin IDs from object changes
        const createdCoins: string[] = [];
        if (result && 'objectChanges' in result) {
            // This would need to be implemented based on actual Sui response structure
            // For now, return empty array
        }

        return createdCoins;
    }

    // Transfer coins to another address
    async transferCoins(
        coinType: string,
        amount: bigint,
        recipient: string
    ): Promise<string> {
        const tx = new TransactionBlock();

        // Get coins
        const coins = await this.client.getCoins({
            owner: this.address,
            coinType,
        });

        if (coins.data.length === 0) {
            throw new Error(`No coins of type ${coinType} found`);
        }

        // Use the first coin that has enough balance
        const suitableCoin = coins.data.find(coin => BigInt(coin.balance) >= amount);
        if (!suitableCoin) {
            throw new Error(`Insufficient balance for transfer`);
        }

        // Split and transfer
        const [transferCoin] = tx.splitCoins(
            tx.object(suitableCoin.coinObjectId),
            [tx.pure(amount.toString())]
        );

        tx.transferObjects([transferCoin], tx.pure(recipient));

        const result = await this.send(tx);
        return result.txHash;
    }
}