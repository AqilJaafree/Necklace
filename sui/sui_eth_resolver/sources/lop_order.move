// sui/sui_eth_resolver/sources/lop_order.move
module sui_eth_resolver::lop_order {
    use std::string::String;
    use sui::event;

    // ===========================================
    // BASIC LOP ORDER STRUCTURES
    // ===========================================

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

    // ===========================================
    // MERKLE TREE STRUCTURES (for partial fills)
    // ===========================================

    // Merkle tree structure for partial fills
    public struct MerkleTree has copy, drop, store {
        root: vector<u8>,
        leaves: vector<vector<u8>>,
        depth: u8,
    }

    // Enhanced LOP Order with Merkle tree support
    public struct PartialFillLOPOrder has copy, drop, store {
        // Base order fields
        salt: vector<u8>,
        maker: address,
        receiver: address,
        maker_asset: String,
        taker_asset: String,
        making_amount: u64,
        taking_amount: u64,
        maker_traits: vector<u8>,
        
        // Partial fill fields
        merkle_root: vector<u8>,        // Merkle root for partial fills
        fill_percentage: u64,           // Current fill percentage (0-10000 for basis points)
        secret_index: u64,              // Index of secret being used
        allow_partial_fills: bool,      // Whether partial fills are allowed
        total_secrets: u64,             // Total number of secrets in tree
    }

    // ===========================================
    // CROSS-CHAIN MAPPING
    // ===========================================

    // Cross-chain mapping
    public struct CrossChainMapping has copy, drop, store {
        ethereum_order_hash: vector<u8>,
        sui_escrow_id: sui::object::ID,
        maker: address,
        validated: bool,
    }

    // ===========================================
    // EVENTS
    // ===========================================

    public struct LOPOrderRegistered has copy, drop {
        order_hash: vector<u8>,
        maker: address,
        making_amount: u64,
        taking_amount: u64,
        maker_asset: String,
        taker_asset: String,
    }

    public struct PartialFillOrderRegistered has copy, drop {
        order_hash: vector<u8>,
        maker: address,
        making_amount: u64,
        taking_amount: u64,
        merkle_root: vector<u8>,
        total_secrets: u64,
        allow_partial_fills: bool,
    }

    public struct CrossChainMappingCreated has copy, drop {
        ethereum_order_hash: vector<u8>,
        sui_escrow_id: sui::object::ID,
        maker: address,
    }

    public struct PartialFillExecuted has copy, drop {
        order_hash: vector<u8>,
        secret_index: u64,
        fill_percentage: u64,
        fill_amount: u64,
        executor: address,
    }

    // ===========================================
    // ERROR CONSTANTS
    // ===========================================

    const E_INVALID_ORDER_HASH: u64 = 100;
    const E_INVALID_MERKLE_PROOF: u64 = 101;
    const E_PARTIAL_FILLS_NOT_ALLOWED: u64 = 102;
    const E_INVALID_FILL_PERCENTAGE: u64 = 103;
    const E_SECRET_INDEX_OUT_OF_BOUNDS: u64 = 104;
    const E_EMPTY_SECRETS_LIST: u64 = 105;

    // ===========================================
    // MERKLE TREE FUNCTIONS
    // ===========================================

    // Create Merkle tree from secrets (for partial fills)
    public fun create_merkle_tree(secrets: vector<vector<u8>>): MerkleTree {
        assert!(vector::length(&secrets) > 0, E_EMPTY_SECRETS_LIST);
        
        let mut leaves = vector::empty<vector<u8>>();
        let mut i = 0;
        
        // Hash each secret to create leaves
        while (i < vector::length(&secrets)) {
            let secret = vector::borrow(&secrets, i);
            let leaf = sui::hash::keccak256(secret);
            vector::push_back(&mut leaves, leaf);
            i = i + 1;
        };
        
        let root = compute_merkle_root(&leaves);
        
        MerkleTree {
            root,
            leaves,
            depth: calculate_depth(vector::length(&secrets)),
        }
    }

    // Compute Merkle root
    fun compute_merkle_root(leaves: &vector<vector<u8>>): vector<u8> {
        let mut current_level = *leaves;
        
        while (vector::length(&current_level) > 1) {
            let mut next_level = vector::empty<vector<u8>>();
            let mut i = 0;
            
            while (i < vector::length(&current_level)) {
                let left = vector::borrow(&current_level, i);
                let right = if (i + 1 < vector::length(&current_level)) {
                    vector::borrow(&current_level, i + 1)
                } else {
                    left // Duplicate last element if odd number
                };
                
                let mut combined = *left;
                vector::append(&mut combined, *right);
                let parent = sui::hash::keccak256(&combined);
                vector::push_back(&mut next_level, parent);
                
                i = i + 2;
            };
            
            current_level = next_level;
        };
        
        *vector::borrow(&current_level, 0)
    }

    // Verify Merkle proof
    public fun verify_merkle_proof(
        leaf: vector<u8>,
        proof: vector<vector<u8>>,
        root: vector<u8>,
        index: u64
    ): bool {
        let mut computed_hash = leaf;
        let mut i = 0;
        let mut current_index = index;
        
        while (i < vector::length(&proof)) {
            let proof_element = vector::borrow(&proof, i);
            
            if (current_index % 2 == 0) {
                // Left node
                let mut combined = computed_hash;
                vector::append(&mut combined, *proof_element);
                computed_hash = sui::hash::keccak256(&combined);
            } else {
                // Right node
                let mut combined = *proof_element;
                vector::append(&mut combined, computed_hash);
                computed_hash = sui::hash::keccak256(&combined);
            };
            
            current_index = current_index / 2;
            i = i + 1;
        };
        
        computed_hash == root
    }

    fun calculate_depth(num_leaves: u64): u8 {
        let mut depth = 0;
        let mut leaves = num_leaves;
        while (leaves > 1) {
            leaves = (leaves + 1) / 2;
            depth = depth + 1;
        };
        depth
    }

    // ===========================================
    // CONSTRUCTOR FUNCTIONS
    // ===========================================

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

    // Create order with Merkle tree support for partial fills
    public fun create_partial_fill_order(
        base_order: LOPOrder,
        secrets: vector<vector<u8>>,
        allow_partial_fills: bool
    ): PartialFillLOPOrder {
        let merkle_tree = create_merkle_tree(secrets);
        
        PartialFillLOPOrder {
            // Copy base order fields
            salt: base_order.salt,
            maker: base_order.maker,
            receiver: base_order.receiver,
            maker_asset: base_order.maker_asset,
            taker_asset: base_order.taker_asset,
            making_amount: base_order.making_amount,
            taking_amount: base_order.taking_amount,
            maker_traits: base_order.maker_traits,
            
            // Partial fill fields
            merkle_root: get_merkle_root(&merkle_tree),
            fill_percentage: 0,
            secret_index: 0,
            allow_partial_fills,
            total_secrets: vector::length(&secrets),
        }
    }

    // ===========================================
    // VALIDATION FUNCTIONS
    // ===========================================

    public fun validate_lop_order_basic(
        lop_order: &LOPOrder,
        order_hash_data: &LOPOrderHash,
    ): bool {
        // Basic validation - compute hash and check format
        let computed_hash = compute_order_hash(lop_order);
        
        // Check if computed hash matches provided hash
        computed_hash == order_hash_data.order_hash
    }

    // Validate partial fill with Merkle proof
    public fun validate_partial_fill(
        order: &PartialFillLOPOrder,
        secret: vector<u8>,
        merkle_proof: vector<vector<u8>>,
        secret_index: u64,
        fill_percentage: u64
    ): bool {
        // Check if partial fills are allowed
        assert!(order.allow_partial_fills, E_PARTIAL_FILLS_NOT_ALLOWED);
        
        // Check fill percentage is valid (0-10000 basis points = 0-100%)
        assert!(fill_percentage <= 10000, E_INVALID_FILL_PERCENTAGE);
        
        // Check secret index is valid
        assert!(secret_index < order.total_secrets, E_SECRET_INDEX_OUT_OF_BOUNDS);
        
        // Verify secret is in Merkle tree
        let secret_hash = sui::hash::keccak256(&secret);
        
        verify_merkle_proof(
            secret_hash,
            merkle_proof,
            order.merkle_root,
            secret_index
        )
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

    public fun compute_partial_fill_order_hash(order: &PartialFillLOPOrder): vector<u8> {
        let mut data = vector::empty<u8>();
        
        // Include all relevant fields for partial fill orders
        vector::append(&mut data, order.salt);
        vector::append(&mut data, sui::bcs::to_bytes(&order.maker));
        vector::append(&mut data, sui::bcs::to_bytes(&order.receiver));
        vector::append(&mut data, sui::bcs::to_bytes(&order.making_amount));
        vector::append(&mut data, sui::bcs::to_bytes(&order.taking_amount));
        vector::append(&mut data, order.merkle_root);
        vector::append(&mut data, sui::bcs::to_bytes(&order.total_secrets));
        
        sui::hash::keccak256(&data)
    }

    // ===========================================
    // CROSS-CHAIN INTEGRATION
    // ===========================================

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

    // Register partial fill order
    public fun register_partial_fill_order(
        partial_order: PartialFillLOPOrder,
        _ctx: &mut sui::tx_context::TxContext
    ): vector<u8> {
        let order_hash = compute_partial_fill_order_hash(&partial_order);
        
        // Emit registration event
        event::emit(PartialFillOrderRegistered {
            order_hash,
            maker: partial_order.maker,
            making_amount: partial_order.making_amount,
            taking_amount: partial_order.taking_amount,
            merkle_root: partial_order.merkle_root,
            total_secrets: partial_order.total_secrets,
            allow_partial_fills: partial_order.allow_partial_fills,
        });

        order_hash
    }

    // Execute partial fill
    public fun execute_partial_fill(
        order: &mut PartialFillLOPOrder,
        secret: vector<u8>,
        merkle_proof: vector<vector<u8>>,
        secret_index: u64,
        fill_percentage: u64,
        ctx: &mut sui::tx_context::TxContext
    ): u64 {
        // Validate the partial fill
        assert!(
            validate_partial_fill(order, secret, merkle_proof, secret_index, fill_percentage),
            E_INVALID_MERKLE_PROOF
        );
        
        // Update order state
        order.fill_percentage = order.fill_percentage + fill_percentage;
        order.secret_index = secret_index;
        
        // Calculate actual fill amount
        let fill_amount = (order.making_amount * fill_percentage) / 10000;
        
        // Emit event
        event::emit(PartialFillExecuted {
            order_hash: compute_partial_fill_order_hash(order),
            secret_index,
            fill_percentage,
            fill_amount,
            executor: sui::tx_context::sender(ctx),
        });
        
        fill_amount
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

    // ===========================================
    // GETTER FUNCTIONS - Basic LOP Order
    // ===========================================
    
    public fun get_order_maker(order: &LOPOrder): address { order.maker }
    public fun get_order_receiver(order: &LOPOrder): address { order.receiver }
    public fun get_making_amount(order: &LOPOrder): u64 { order.making_amount }
    public fun get_taking_amount(order: &LOPOrder): u64 { order.taking_amount }
    public fun get_maker_asset(order: &LOPOrder): String { order.maker_asset }
    public fun get_taker_asset(order: &LOPOrder): String { order.taker_asset }
    public fun get_order_hash(hash_data: &LOPOrderHash): vector<u8> { hash_data.order_hash }
    
    // ===========================================
    // GETTER FUNCTIONS - Merkle Tree
    // ===========================================
    
    public fun get_merkle_root(tree: &MerkleTree): vector<u8> { tree.root }
    public fun get_merkle_leaves(tree: &MerkleTree): vector<vector<u8>> { tree.leaves }
    public fun get_merkle_depth(tree: &MerkleTree): u8 { tree.depth }

    // ===========================================
    // GETTER FUNCTIONS - Partial Fill Order
    // ===========================================
    
    public fun get_partial_order_maker(order: &PartialFillLOPOrder): address { order.maker }
    public fun get_partial_order_receiver(order: &PartialFillLOPOrder): address { order.receiver }
    public fun get_partial_making_amount(order: &PartialFillLOPOrder): u64 { order.making_amount }
    public fun get_partial_taking_amount(order: &PartialFillLOPOrder): u64 { order.taking_amount }
    public fun get_partial_maker_asset(order: &PartialFillLOPOrder): String { order.maker_asset }
    public fun get_partial_taker_asset(order: &PartialFillLOPOrder): String { order.taker_asset }
    public fun get_partial_merkle_root(order: &PartialFillLOPOrder): vector<u8> { order.merkle_root }
    public fun get_partial_fill_percentage(order: &PartialFillLOPOrder): u64 { order.fill_percentage }
    public fun get_partial_secret_index(order: &PartialFillLOPOrder): u64 { order.secret_index }
    public fun get_partial_allow_partial_fills(order: &PartialFillLOPOrder): bool { order.allow_partial_fills }
    public fun get_partial_total_secrets(order: &PartialFillLOPOrder): u64 { order.total_secrets }
    
    // ===========================================
    // GETTER FUNCTIONS - Cross-Chain Mapping
    // ===========================================
    
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

    // ===========================================
    // UTILITY FUNCTIONS
    // ===========================================

    // Check if order is fully filled
    public fun is_order_fully_filled(order: &PartialFillLOPOrder): bool {
        order.fill_percentage >= 10000 // 100% in basis points
    }

    // Calculate remaining amount to fill
    public fun get_remaining_amount(order: &PartialFillLOPOrder): u64 {
        let filled_amount = (order.making_amount * order.fill_percentage) / 10000;
        order.making_amount - filled_amount
    }

    // Get next secret index for partial fills
    public fun get_next_secret_index(order: &PartialFillLOPOrder): u64 {
        if (order.secret_index + 1 < order.total_secrets) {
            order.secret_index + 1
        } else {
            order.total_secrets - 1 // Use last secret if at end
        }
    }
}