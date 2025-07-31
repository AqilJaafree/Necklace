#[test_only]
module sui_eth_resolver::resolver_test {
    use sui::test_scenario;
    use sui::clock;
    use sui::coin;
    use sui::sui::SUI;
    use sui_eth_resolver::resolver;
    use sui_eth_resolver::escrow;
    use sui_eth_resolver::types;
    use std::string;

    #[test]
    fun test_resolver_deploy_with_deposit() {
        let admin = @0xABBA;
        let maker = @0x1234;
        let taker = @0x5678;
        
        let mut scenario_val = test_scenario::begin(admin);
        let scenario = &mut scenario_val;

        // Create resolver
        test_scenario::next_tx(scenario, taker);
        {
            let resolver_id = resolver::create_resolver(taker, test_scenario::ctx(scenario));
            assert!(sui::object::id_from_address(@0x0) != resolver_id, 0);
        };

        // Deploy source escrow with deposit
        test_scenario::next_tx(scenario, taker);
        {
            let resolver = test_scenario::take_shared<resolver::Resolver>(scenario);
            let deposit_coin = coin::mint_for_testing<SUI>(1000, test_scenario::ctx(scenario));
            let safety_coin = coin::mint_for_testing<SUI>(100, test_scenario::ctx(scenario));

            // Create immutables
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
                b"eth_order_hash",
            );

            // Deploy escrow with deposit
            let escrow_id = resolver::deploy_src_with_deposit<SUI>(
                &resolver,
                immutables,
                deposit_coin,
                safety_coin,
                test_scenario::ctx(scenario)
            );

            assert!(sui::object::id_from_address(@0x0) != escrow_id, 1);
            test_scenario::return_shared(resolver);
        };

        test_scenario::end(scenario_val);
    }

    #[test]
    fun test_separate_deposit_flow() {
        let admin = @0xABBA;
        let maker = @0x1234;
        let taker = @0x5678;
        
        let mut scenario_val = test_scenario::begin(admin);
        let scenario = &mut scenario_val;

        // Setup clock
        let mut clock = clock::create_for_testing(test_scenario::ctx(scenario));
        clock::set_for_testing(&mut clock, 1000000);

        // Create resolver
        test_scenario::next_tx(scenario, taker);
        {
            resolver::create_resolver(taker, test_scenario::ctx(scenario));
        };

        // Create escrow first
        test_scenario::next_tx(scenario, taker);
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
                b"eth_order_hash",
            );

            escrow::create<SUI>(immutables, test_scenario::ctx(scenario));
        };

        // Deposit through resolver
        test_scenario::next_tx(scenario, taker);
        {
            let resolver = test_scenario::take_shared<resolver::Resolver>(scenario);
            let mut escrow = test_scenario::take_shared<escrow::Escrow<SUI>>(scenario);
            let deposit_coin = coin::mint_for_testing<SUI>(1000, test_scenario::ctx(scenario));
            let safety_coin = coin::mint_for_testing<SUI>(100, test_scenario::ctx(scenario));

            resolver::deposit_to_escrow(
                &resolver,
                &mut escrow,
                deposit_coin,
                safety_coin,
                test_scenario::ctx(scenario)
            );

            test_scenario::return_shared(resolver);
            test_scenario::return_shared(escrow);
        };

        // Advance time and withdraw
        clock::increment_for_testing(&mut clock, 15000);

        test_scenario::next_tx(scenario, taker);
        {
            let resolver = test_scenario::take_shared<resolver::Resolver>(scenario);
            let mut escrow = test_scenario::take_shared<escrow::Escrow<SUI>>(scenario);
            let secret = b"secret123";

            let (withdrawn_coin, safety_coin) = resolver::withdraw<SUI>(
                &resolver,
                &mut escrow,
                secret,
                &clock,
                test_scenario::ctx(scenario)
            );

            assert!(coin::value(&withdrawn_coin) == 1000, 2);
            assert!(coin::value(&safety_coin) == 100, 3);

            coin::burn_for_testing(withdrawn_coin);
            coin::burn_for_testing(safety_coin);

            test_scenario::return_shared(resolver);
            test_scenario::return_shared(escrow);
        };

        clock::destroy_for_testing(clock);
        test_scenario::end(scenario_val);
    }
}