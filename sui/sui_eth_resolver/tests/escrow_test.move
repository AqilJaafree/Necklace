#[test_only]
module sui_eth_resolver::escrow_test {
    use sui::test_scenario;
    use sui::clock;
    use sui::coin;
    use sui::sui::SUI;
    use sui_eth_resolver::escrow;
    use sui_eth_resolver::types;
    use std::string;

    #[test]
    fun test_create_escrow_basic() {
        let admin = @0xABBA;
        let maker = @0x1234;  // Fixed: Use valid hex addresses
        let taker = @0x5678;  // Fixed: Use valid hex addresses
        
        let mut scenario_val = test_scenario::begin(admin);  // Fixed: Add 'mut'
        let scenario = &mut scenario_val;

        // Create test immutables
        test_scenario::next_tx(scenario, admin);
        {
            let time_locks = types::create_time_locks(10, 120, 121, 122, 10, 100, 101);
            let immutables = types::create_src_immutables(
                b"test_order",
                sui::hash::keccak256(&b"secret123"),
                maker,
                taker,
                string::utf8(b"0x2::sui::SUI"),
                1000,
                100,
                time_locks,
                b"eth_order",
            );

            // Test escrow creation
            let escrow_id = escrow::create<SUI>(immutables, test_scenario::ctx(scenario));
            assert!(sui::object::id_from_address(@0x0) != escrow_id, 0);
        };

        test_scenario::end(scenario_val);
    }

    #[test]
    fun test_deposit_and_withdraw() {
        let admin = @0xABBA;
        let maker = @0x1234;  // Fixed: Use valid hex addresses
        let taker = @0x5678;  // Fixed: Use valid hex addresses
        
        let mut scenario_val = test_scenario::begin(admin);  // Fixed: Add 'mut'
        let scenario = &mut scenario_val;

        // Setup
        let mut clock = clock::create_for_testing(test_scenario::ctx(scenario));  // Fixed: Add 'mut'
        clock::set_for_testing(&mut clock, 1000000);

        // Create escrow
        test_scenario::next_tx(scenario, admin);
        {
            let time_locks = types::create_time_locks(10, 120, 121, 122, 10, 100, 101);
            let immutables = types::create_src_immutables(
                b"test_order",
                sui::hash::keccak256(&b"secret123"),
                maker,
                taker,
                string::utf8(b"0x2::sui::SUI"),
                1000,
                100,
                time_locks,
                b"eth_order",
            );

            escrow::create<SUI>(immutables, test_scenario::ctx(scenario));
        };

        // Taker deposits
        test_scenario::next_tx(scenario, taker);
        {
            let mut escrow = test_scenario::take_shared<escrow::Escrow<SUI>>(scenario);  // Fixed: Add 'mut'
            let deposit_coin = coin::mint_for_testing<SUI>(1000, test_scenario::ctx(scenario));
            let safety_coin = coin::mint_for_testing<SUI>(100, test_scenario::ctx(scenario));
            
            escrow::deposit(&mut escrow, deposit_coin, safety_coin, test_scenario::ctx(scenario));
            test_scenario::return_shared(escrow);
        };

        // Advance time past withdrawal timelock
        clock::increment_for_testing(&mut clock, 15000); // 15 seconds

        // Taker withdraws with secret
        test_scenario::next_tx(scenario, taker);
        {
            let mut escrow = test_scenario::take_shared<escrow::Escrow<SUI>>(scenario);  // Fixed: Add 'mut'
            let secret = b"secret123";
            
            let (withdrawn_coin, safety_coin) = escrow::withdraw(
                &mut escrow,
                secret,
                &clock,
                test_scenario::ctx(scenario)
            );
            
            assert!(coin::value(&withdrawn_coin) == 1000, 0);
            assert!(coin::value(&safety_coin) == 100, 1);
            
            coin::burn_for_testing(withdrawn_coin);
            coin::burn_for_testing(safety_coin);
            test_scenario::return_shared(escrow);
        };

        clock::destroy_for_testing(clock);
        test_scenario::end(scenario_val);
    }
}