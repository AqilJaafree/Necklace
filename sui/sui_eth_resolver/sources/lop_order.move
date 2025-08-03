// sui/sui_eth_resolver/sources/lop_order.move
module sui_eth_resolver::lop_order {
    use std::string::String;
    use sui::event;

    // Basic 1inch LOP Order structure for Sui
    public struct LOPOrder has copy, drop, store {
        salt: vector<u8>,           // 32 bytes
        maker: address,             // Ethereum address converted to Sui
        receiver: address,          // Ethereum address converted to Sui  
        maker_asset: String,        // Token address as string
        taker_asset: String,        // Token address as string
        making_amount: u64,         // Amount maker is providing
        taking_amount: u64,         // Amount maker wants to receive
        maker_traits: vector<u8>,   // 32 bytes of traits
    }

    // LOP Order validation data
    public struct LOPOrderHash has copy, drop, store {
        order_hash: vector<u8>,     // 32 bytes computed hash
        signature_r: vector<u8>,    // 32 bytes
        signature_s: vector<u8>,    // 32 bytes  
        v: u8,                      // Recovery byte
    }

    // Cross-chain mapping
    public struct CrossChainMapping has copy, drop, store {
        ethereum_order_hash: vector<u8>,
        sui_escrow_id: sui::object::ID,
        maker: address,
        validated: bool,
    }

    // Events
    public struct LOPOrderRegistered has copy, drop {
        order_hash: vector<u8>,
        maker: address,
        making_amount: u64,
        taking_amount: u64,
        maker_asset: String,
        taker_asset: String,
    }

    public struct CrossChainMappingCreated has copy, drop {
        ethereum_order_hash: vector<u8>,
        sui_escrow_id: sui::object::ID,
        maker: address,
    }

    // Error constants
    const E_INVALID_ORDER_HASH: u64 = 100;

    // Constructor functions
    public fun create_lop_order(
        salt: vector<u8>,
        maker: address,
        receiver: address,
        maker_asset: String,
        taker_asset: String,
        making_amount: u64,
        taking_amount: u64,
        maker_traits: vector<u8>,
    ): LOPOrder {
        LOPOrder {
            salt,
            maker,
            receiver,
            maker_asset,
            taker_asset,
            making_amount,
            taking_amount,
            maker_traits,
        }
    }

    public fun create_lop_order_hash(
        order_hash: vector<u8>,
        signature_r: vector<u8>,
        signature_s: vector<u8>,
        v: u8,
    ): LOPOrderHash {
        LOPOrderHash {
            order_hash,
            signature_r,
            signature_s,
            v,
        }
    }

    // Validation functions
    public fun validate_lop_order_basic(
        lop_order: &LOPOrder,
        order_hash_data: &LOPOrderHash,
    ): bool {
        // Basic validation - compute hash and check format
        let computed_hash = compute_order_hash(lop_order);
        
        // Check if computed hash matches provided hash
        computed_hash == order_hash_data.order_hash
    }

    public fun compute_order_hash(order: &LOPOrder): vector<u8> {
        // Simplified hash computation for testing
        // In production, this would exactly match Ethereum's hash computation
        let mut data = vector::empty<u8>();
        
        // Concatenate order fields
        vector::append(&mut data, order.salt);
        vector::append(&mut data, sui::bcs::to_bytes(&order.maker));
        vector::append(&mut data, sui::bcs::to_bytes(&order.receiver));
        vector::append(&mut data, sui::bcs::to_bytes(&order.making_amount));
        vector::append(&mut data, sui::bcs::to_bytes(&order.taking_amount));
        
        // Return keccak256 hash
        sui::hash::keccak256(&data)
    }

    // Cross-chain integration
    public fun create_cross_chain_mapping(
        ethereum_order_hash: vector<u8>,
        sui_escrow_id: sui::object::ID,
        maker: address,
    ): CrossChainMapping {
        CrossChainMapping {
            ethereum_order_hash,
            sui_escrow_id,
            maker,
            validated: true,
        }
    }

    public fun register_lop_order(
        lop_order: LOPOrder,
        order_hash_data: LOPOrderHash,
        _ctx: &mut sui::tx_context::TxContext
    ): vector<u8> {
        // Validate order
        assert!(validate_lop_order_basic(&lop_order, &order_hash_data), E_INVALID_ORDER_HASH);
        
        // Emit registration event
        event::emit(LOPOrderRegistered {
            order_hash: order_hash_data.order_hash,
            maker: lop_order.maker,
            making_amount: lop_order.making_amount,
            taking_amount: lop_order.taking_amount,
            maker_asset: lop_order.maker_asset,
            taker_asset: lop_order.taker_asset,
        });

        order_hash_data.order_hash
    }

    public fun link_to_escrow(
        ethereum_order_hash: vector<u8>,
        sui_escrow_id: sui::object::ID,
        maker: address,
        _ctx: &mut sui::tx_context::TxContext
    ): CrossChainMapping {
        let mapping = create_cross_chain_mapping(
            ethereum_order_hash,
            sui_escrow_id,
            maker
        );

        // Emit mapping event
        event::emit(CrossChainMappingCreated {
            ethereum_order_hash,
            sui_escrow_id,
            maker,
        });

        mapping
    }

    // Getter functions
    public fun get_order_maker(order: &LOPOrder): address { order.maker }
    public fun get_order_receiver(order: &LOPOrder): address { order.receiver }
    public fun get_making_amount(order: &LOPOrder): u64 { order.making_amount }
    public fun get_taking_amount(order: &LOPOrder): u64 { order.taking_amount }
    public fun get_maker_asset(order: &LOPOrder): String { order.maker_asset }
    public fun get_taker_asset(order: &LOPOrder): String { order.taker_asset }
    public fun get_order_hash(hash_data: &LOPOrderHash): vector<u8> { hash_data.order_hash }
    
    // Mapping getters
    public fun get_mapping_ethereum_hash(mapping: &CrossChainMapping): vector<u8> { 
        mapping.ethereum_order_hash 
    }
    public fun get_mapping_sui_escrow(mapping: &CrossChainMapping): sui::object::ID { 
        mapping.sui_escrow_id 
    }
    public fun get_mapping_maker(mapping: &CrossChainMapping): address { 
        mapping.maker 
    }
    public fun is_mapping_validated(mapping: &CrossChainMapping): bool { 
        mapping.validated 
    }
}