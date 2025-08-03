// sui/sui_eth_resolver/sources/merkle_tree.move
module sui_eth_resolver::merkle_tree {
    use sui::hash;
    
    // Merkle tree structure for partial fills
    public struct MerkleTree has copy, drop, store {
        root: vector<u8>,
        leaves: vector<vector<u8>>,
        depth: u8,
    }
    
    // Create Merkle tree from secrets (for partial fills)
    public fun create_merkle_tree(secrets: vector<vector<u8>>): MerkleTree {
        let mut leaves = vector::empty<vector<u8>>();
        let mut i = 0;
        
        // Hash each secret to create leaves
        while (i < vector::length(&secrets)) {
            let secret = vector::borrow(&secrets, i);
            let leaf = hash::keccak256(secret);
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
                let parent = hash::keccak256(&combined);
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
                computed_hash = hash::keccak256(&combined);
            } else {
                // Right node
                let mut combined = *proof_element;
                vector::append(&mut combined, computed_hash);
                computed_hash = hash::keccak256(&combined);
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
    
    // Getters
    public fun get_root(tree: &MerkleTree): vector<u8> { tree.root }
    public fun get_leaves(tree: &MerkleTree): vector<vector<u8>> { tree.leaves }
    public fun get_depth(tree: &MerkleTree): u8 { tree.depth }
}