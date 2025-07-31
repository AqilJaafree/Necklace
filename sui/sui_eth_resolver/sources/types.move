module sui_eth_resolver::types {
    use std::string::String;

    public struct TimeLocks has copy, drop, store {
        src_withdrawal: u64,
        src_public_withdrawal: u64,
        src_cancellation: u64,
        src_public_cancellation: u64,
        dst_withdrawal: u64,
        dst_public_withdrawal: u64,
        dst_cancellation: u64,
    }

    public struct SrcImmutables has copy, drop, store {
        order_hash: vector<u8>,
        hash_lock: vector<u8>,
        maker: address,
        taker: address,
        token_type: String,
        amount: u64,
        safety_deposit: u64,
        time_locks: TimeLocks,
        ethereum_order_hash: vector<u8>,
    }

    #[allow(unused_field)]
    public struct DstImmutables has copy, drop, store {
        order_hash: vector<u8>,
        hash_lock: vector<u8>,
        maker: address,
        taker: address,
        token_type: String,
        amount: u64,
        safety_deposit: u64,
        time_locks: TimeLocks,
        deployed_at: u64,
    }

    // Constructor functions
    public fun create_time_locks(
        src_withdrawal: u64,
        src_public_withdrawal: u64,
        src_cancellation: u64,
        src_public_cancellation: u64,
        dst_withdrawal: u64,
        dst_public_withdrawal: u64,
        dst_cancellation: u64,
    ): TimeLocks {
        TimeLocks {
            src_withdrawal,
            src_public_withdrawal,
            src_cancellation,
            src_public_cancellation,
            dst_withdrawal,
            dst_public_withdrawal,
            dst_cancellation,
        }
    }

    public fun create_src_immutables(
        order_hash: vector<u8>,
        hash_lock: vector<u8>,
        maker: address,
        taker: address,
        token_type: String,
        amount: u64,
        safety_deposit: u64,
        time_locks: TimeLocks,
        ethereum_order_hash: vector<u8>,
    ): SrcImmutables {
        SrcImmutables {
            order_hash,
            hash_lock,
            maker,
            taker,
            token_type,
            amount,
            safety_deposit,
            time_locks,
            ethereum_order_hash,
        }
    }

    // Getter functions for TimeLocks
    public fun get_src_withdrawal(time_locks: &TimeLocks): u64 { time_locks.src_withdrawal }
    public fun get_src_public_withdrawal(time_locks: &TimeLocks): u64 { time_locks.src_public_withdrawal }
    public fun get_src_cancellation(time_locks: &TimeLocks): u64 { time_locks.src_cancellation }
    public fun get_src_public_cancellation(time_locks: &TimeLocks): u64 { time_locks.src_public_cancellation }
    public fun get_dst_withdrawal(time_locks: &TimeLocks): u64 { time_locks.dst_withdrawal }
    public fun get_dst_public_withdrawal(time_locks: &TimeLocks): u64 { time_locks.dst_public_withdrawal }
    public fun get_dst_cancellation(time_locks: &TimeLocks): u64 { time_locks.dst_cancellation }
    
    // Getter functions for SrcImmutables
    public fun get_order_hash(immutables: &SrcImmutables): vector<u8> { immutables.order_hash }
    public fun get_hash_lock(immutables: &SrcImmutables): vector<u8> { immutables.hash_lock }
    public fun get_maker(immutables: &SrcImmutables): address { immutables.maker }
    public fun get_taker(immutables: &SrcImmutables): address { immutables.taker }
    public fun get_token_type(immutables: &SrcImmutables): String { immutables.token_type }
    public fun get_amount(immutables: &SrcImmutables): u64 { immutables.amount }
    public fun get_safety_deposit(immutables: &SrcImmutables): u64 { immutables.safety_deposit }
    public fun get_time_locks(immutables: &SrcImmutables): TimeLocks { immutables.time_locks }
    public fun get_ethereum_order_hash(immutables: &SrcImmutables): vector<u8> { immutables.ethereum_order_hash }
}