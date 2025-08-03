// sui/sui_eth_resolver/tests/lop_order_test.move
#[test_only]
module sui_eth_resolver::lop_order_test {
    use sui::test_scenario;
    use sui_eth_resolver::lop_order;
    use std::string;

    #[test]
    fun test_create_lop_order() {
        let admin = @0xABBA;
        let maker = @0x1234;
        let receiver = @0x5678;
        
        let mut scenario_val = test_scenario::begin(admin);
        let scenario = &mut scenario_val;

        test_scenario::next_tx(scenario, admin);
        {
            // Create test LOP order
            let salt = vector[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32];
            let maker_traits = vector[0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
            
            let lop_order = lop_order::create_lop_order(
                salt,
                maker,
                receiver,
                string::utf8(b"0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238"), // USDC
                string::utf8(b"0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14"), // WETH
                100000000, // 100 USDC (6 decimals)
                25000000000000000, // 0.025 ETH
                maker_traits,
            );

            // Verify order creation
            assert!(lop_order::get_order_maker(&lop_order) == maker, 0);
            assert!(lop_order::get_making_amount(&lop_order) == 100000000, 1);
            assert!(lop_order::get_taking_amount(&lop_order) == 25000000000000000, 2);
        };

        test_scenario::end(scenario_val);
    }

    #[test]
    fun test_order_hash_computation() {
        let admin = @0xABBA;
        let maker = @0x1234;
        let receiver = @0x5678;
        
        let mut scenario_val = test_scenario::begin(admin);
        let scenario = &mut scenario_val;

        test_scenario::next_tx(scenario, admin);
        {
            // Create test LOP order
            let salt = vector[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32];
            let maker_traits = vector[0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
            
            let lop_order = lop_order::create_lop_order(
                salt,
                maker,
                receiver,
                string::utf8(b"0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238"),
                string::utf8(b"0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14"),
                100000000,
                25000000000000000,
                maker_traits,
            );

            // Compute hash
            let computed_hash = lop_order::compute_order_hash(&lop_order);
            
            // Hash should be 32 bytes
            assert!(std::vector::length(&computed_hash) == 32, 3);
            
            // Create order hash data
            let signature_r = vector[1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1];
            let signature_s = vector[2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2];
            
            let order_hash_data = lop_order::create_lop_order_hash(
                computed_hash,
                signature_r,
                signature_s,
                27, // v value
            );

            // Validate order
            let is_valid = lop_order::validate_lop_order_basic(&lop_order, &order_hash_data);
            assert!(is_valid, 4);
        };

        test_scenario::end(scenario_val);
    }

    #[test]
    fun test_cross_chain_mapping() {
        let admin = @0xABBA;
        let maker = @0x1234;
        
        let mut scenario_val = test_scenario::begin(admin);
        let scenario = &mut scenario_val;

        test_scenario::next_tx(scenario, admin);
        {
            // Create test data
            let ethereum_order_hash = vector[0xab, 0xcd, 0xef, 0x12, 0x34, 0x56, 0x78, 0x90, 0xab, 0xcd, 0xef, 0x12, 0x34, 0x56, 0x78, 0x90, 0xab, 0xcd, 0xef, 0x12, 0x34, 0x56, 0x78, 0x90, 0xab, 0xcd, 0xef, 0x12, 0x34, 0x56, 0x78, 0x90];
            let sui_escrow_id = sui::object::id_from_address(@0x999);

            // Create mapping
            let mapping = lop_order::create_cross_chain_mapping(
                ethereum_order_hash,
                sui_escrow_id,
                maker
            );

            // Verify mapping
            assert!(lop_order::get_mapping_maker(&mapping) == maker, 5);
            assert!(lop_order::get_mapping_sui_escrow(&mapping) == sui_escrow_id, 6);
            assert!(lop_order::is_mapping_validated(&mapping), 7);
            
            let retrieved_hash = lop_order::get_mapping_ethereum_hash(&mapping);
            assert!(retrieved_hash == ethereum_order_hash, 8);
        };

        test_scenario::end(scenario_val);
    }

    #[test]
    fun test_lop_order_registration() {
        let admin = @0xABBA;
        let maker = @0x1234;
        let receiver = @0x5678;
        
        let mut scenario_val = test_scenario::begin(admin);
        let scenario = &mut scenario_val;

        test_scenario::next_tx(scenario, admin);
        {
            // Create and register LOP order
            let salt = vector[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32];
            let maker_traits = vector[0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
            
            let lop_order = lop_order::create_lop_order(
                salt,
                maker,
                receiver,
                string::utf8(b"0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238"),
                string::utf8(b"0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14"),
                100000000,
                25000000000000000,
                maker_traits,
            );

            let computed_hash = lop_order::compute_order_hash(&lop_order);
            let signature_r = vector[1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1];
            let signature_s = vector[2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2];
            
            let order_hash_data = lop_order::create_lop_order_hash(
                computed_hash,
                signature_r,
                signature_s,
                27,
            );

            // Register order
            let registered_hash = lop_order::register_lop_order(
                lop_order,
                order_hash_data,
                test_scenario::ctx(scenario)
            );

            // Verify registration
            assert!(registered_hash == computed_hash, 9);
        };

        test_scenario::end(scenario_val);
    }
}