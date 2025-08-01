import { TransactionBlock } from '@mysten/sui.js/transactions';
import { SuiClient } from '@mysten/sui.js/client';
import { createHash } from 'crypto';

// Type definitions (mirror Sui Move structs)
export interface SuiTimeLocks {
    srcWithdrawal: number;
    srcPublicWithdrawal: number;
    srcCancellation: number;
    srcPublicCancellation: number;
    dstWithdrawal: number;
    dstPublicWithdrawal: number;
    dstCancellation: number;
}

export interface SuiImmutables {
    orderHash: Uint8Array;
    hashLock: Uint8Array;
    maker: string;
    taker: string;
    tokenType: string;
    amount: bigint;
    safetyDeposit: bigint;
    timeLocks: SuiTimeLocks;
    ethereumOrderHash: Uint8Array;
}

export class SuiResolver {
    constructor(
        private client: SuiClient,
        private packageId: string,
        private resolverObjectId: string
    ) {}

    // Mirror deploySrc from EVM resolver.ts
    deploySrcWithDeposit(
        immutables: SuiImmutables,
        depositCoinId: string,
        safetyDepositCoinId: string,
        coinType: string = '0x2::sui::SUI'
    ): TransactionBlock {
        const tx = new TransactionBlock();

        // Create immutables object
        const timeLocksArg = tx.pure([
            immutables.timeLocks.srcWithdrawal,
            immutables.timeLocks.srcPublicWithdrawal,
            immutables.timeLocks.srcCancellation,
            immutables.timeLocks.srcPublicCancellation,
            immutables.timeLocks.dstWithdrawal,
            immutables.timeLocks.dstPublicWithdrawal,
            immutables.timeLocks.dstCancellation,
        ]);

        const immutablesArg = tx.pure([
            Array.from(immutables.orderHash),
            Array.from(immutables.hashLock),
            immutables.maker,
            immutables.taker,
            immutables.tokenType,
            immutables.amount.toString(),
            immutables.safetyDeposit.toString(),
            // timeLocks will be created in Move
            Array.from(immutables.ethereumOrderHash),
        ]);

        // Call the resolver function
        tx.moveCall({
            target: `${this.packageId}::resolver::deploy_src_with_deposit`,
            arguments: [
                tx.object(this.resolverObjectId),
                immutablesArg,
                tx.object(depositCoinId),
                tx.object(safetyDepositCoinId),
            ],
            typeArguments: [coinType],
        });

        return tx;
    }

    // Mirror deployDst from EVM resolver.ts
    deployDstWithDeposit(
        immutables: SuiImmutables,
        srcCancellationTimestamp: number,
        depositCoinId: string,
        safetyDepositCoinId: string,
        coinType: string = '0x2::sui::SUI'
    ): TransactionBlock {
        const tx = new TransactionBlock();

        const immutablesArg = tx.pure([
            Array.from(immutables.orderHash),
            Array.from(immutables.hashLock),
            immutables.maker,
            immutables.taker,
            immutables.tokenType,
            immutables.amount.toString(),
            immutables.safetyDeposit.toString(),
            // timeLocks
            Array.from(immutables.ethereumOrderHash),
        ]);

        tx.moveCall({
            target: `${this.packageId}::resolver::deploy_dst_with_deposit`,
            arguments: [
                tx.object(this.resolverObjectId),
                immutablesArg,
                tx.pure(srcCancellationTimestamp),
                tx.object(depositCoinId),
                tx.object(safetyDepositCoinId),
            ],
            typeArguments: [coinType],
        });

        return tx;
    }

    // Deposit to existing escrow
    depositToEscrow(
        escrowId: string,
        depositCoinId: string,
        safetyDepositCoinId: string,
        coinType: string = '0x2::sui::SUI'
    ): TransactionBlock {
        const tx = new TransactionBlock();

        tx.moveCall({
            target: `${this.packageId}::resolver::deposit_to_escrow`,
            arguments: [
                tx.object(this.resolverObjectId),
                tx.object(escrowId),
                tx.object(depositCoinId),
                tx.object(safetyDepositCoinId),
            ],
            typeArguments: [coinType],
        });

        return tx;
    }

    // Mirror withdraw from EVM resolver.ts
    withdraw(
        escrowId: string,
        secret: string,
        clockId: string,
        coinType: string = '0x2::sui::SUI'
    ): TransactionBlock {
        const tx = new TransactionBlock();

        // Convert secret to bytes
        const secretBytes = Array.from(Buffer.from(secret.replace('0x', ''), 'hex'));

        tx.moveCall({
            target: `${this.packageId}::resolver::withdraw`,
            arguments: [
                tx.object(this.resolverObjectId),
                tx.object(escrowId),
                tx.pure(secretBytes),
                tx.object(clockId),
            ],
            typeArguments: [coinType],
        });

        return tx;
    }

    // Mirror cancel from EVM resolver.ts
    cancel(
        escrowId: string,
        clockId: string,
        coinType: string = '0x2::sui::SUI'
    ): TransactionBlock {
        const tx = new TransactionBlock();

        tx.moveCall({
            target: `${this.packageId}::resolver::cancel`,
            arguments: [
                tx.object(this.resolverObjectId),
                tx.object(escrowId),
                tx.object(clockId),
            ],
            typeArguments: [coinType],
        });

        return tx;
    }

    // Utility functions
    async getResolverInfo(): Promise<any> {
        return this.client.getObject({
            id: this.resolverObjectId,
            options: { showContent: true },
        });
    }

    // Create time locks helper
    static createTimeLocks(
        srcWithdrawal: number,
        srcPublicWithdrawal: number,
        srcCancellation: number,
        srcPublicCancellation: number,
        dstWithdrawal: number,
        dstPublicWithdrawal: number,
        dstCancellation: number
    ): SuiTimeLocks {
        return {
            srcWithdrawal,
            srcPublicWithdrawal,
            srcCancellation,
            srcPublicCancellation,
            dstWithdrawal,
            dstPublicWithdrawal,
            dstCancellation,
        };
    }

    // Create immutables helper
    static createImmutables(
        orderHash: string,
        secret: string,
        maker: string,
        taker: string,
        tokenType: string,
        amount: bigint,
        safetyDeposit: bigint,
        timeLocks: SuiTimeLocks,
        ethereumOrderHash: string
    ): SuiImmutables {
        // Hash the secret using SHA-256 (same as Move contract)
        const hashLock = createHash('sha256').update(Buffer.from(secret.replace('0x', ''), 'hex')).digest();

        return {
            orderHash: Buffer.from(orderHash.replace('0x', ''), 'hex'),
            hashLock: new Uint8Array(hashLock),
            maker,
            taker,
            tokenType,
            amount,
            safetyDeposit,
            timeLocks,
            ethereumOrderHash: Buffer.from(ethereumOrderHash.replace('0x', ''), 'hex'),
        };
    }
}