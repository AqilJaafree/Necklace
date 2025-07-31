module sui_eth_resolver::escrow {
    use sui::balance::{Self, Balance};
    use sui::event;
    use sui::sui::SUI;
    use sui_eth_resolver::types::{Self, SrcImmutables};

    // Error constants
    const E_ESCROW_COMPLETED: u64 = 0;
    const E_UNAUTHORIZED: u64 = 1;
    const E_INVALID_SECRET: u64 = 2;
    const E_TIME_LOCK_NOT_EXPIRED: u64 = 3;

    // Escrow struct
    public struct Escrow<phantom T> has key {
        id: sui::object::UID,
        immutables: SrcImmutables,
        deposited_amount: Balance<T>,
        safety_deposit: Balance<SUI>,
        is_completed: bool,
    }

    // Events
    public struct EscrowCreated has copy, drop {
        escrow_id: sui::object::ID,
        maker: address,
        taker: address,
        amount: u64,
        hash_lock: vector<u8>,
        ethereum_order_hash: vector<u8>,
    }

    public struct Deposited has copy, drop {
        escrow_id: sui::object::ID,
        depositor: address,
        amount: u64,
        safety_deposit: u64,
    }

    public struct Withdrawn has copy, drop {
        escrow_id: sui::object::ID,
        secret: vector<u8>,
        to: address,
        amount: u64,
    }

    public struct Cancelled has copy, drop {
        escrow_id: sui::object::ID,
        to: address,
        amount: u64,
    }

    // Create escrow
    public fun create<T>(
        immutables: SrcImmutables,
        ctx: &mut sui::tx_context::TxContext
    ): sui::object::ID {
        let escrow = Escrow<T> {
            id: sui::object::new(ctx),
            immutables,
            deposited_amount: balance::zero<T>(),
            safety_deposit: balance::zero<SUI>(),
            is_completed: false,
        };

        let escrow_id = sui::object::id(&escrow);
        
        // Emit creation event using getter functions
        event::emit(EscrowCreated {
            escrow_id,
            maker: types::get_maker(&escrow.immutables),
            taker: types::get_taker(&escrow.immutables),
            amount: types::get_amount(&escrow.immutables),
            hash_lock: types::get_hash_lock(&escrow.immutables),
            ethereum_order_hash: types::get_ethereum_order_hash(&escrow.immutables),
        });

        sui::transfer::share_object(escrow);
        escrow_id
    }

    // Deposit
    public fun deposit<T>(
        escrow: &mut Escrow<T>,
        coin: sui::coin::Coin<T>,
        safety_deposit: sui::coin::Coin<SUI>,
        ctx: &mut sui::tx_context::TxContext
    ) {
        assert!(!escrow.is_completed, E_ESCROW_COMPLETED);
        assert!(sui::tx_context::sender(ctx) == types::get_taker(&escrow.immutables), E_UNAUTHORIZED);

        let amount = sui::coin::value(&coin);
        let safety_amount = sui::coin::value(&safety_deposit);

        balance::join(&mut escrow.deposited_amount, sui::coin::into_balance(coin));
        balance::join(&mut escrow.safety_deposit, sui::coin::into_balance(safety_deposit));

        event::emit(Deposited {
            escrow_id: sui::object::id(escrow),
            depositor: sui::tx_context::sender(ctx),
            amount,
            safety_deposit: safety_amount,
        });
    }

    // Withdraw with secret
    public fun withdraw<T>(
        escrow: &mut Escrow<T>,
        secret: vector<u8>,
        clock: &sui::clock::Clock,
        ctx: &mut sui::tx_context::TxContext
    ): (sui::coin::Coin<T>, sui::coin::Coin<SUI>) {
        assert!(!escrow.is_completed, E_ESCROW_COMPLETED);
        
        // Verify hashlock
        let hash = sui::hash::keccak256(&secret);
        assert!(hash == types::get_hash_lock(&escrow.immutables), E_INVALID_SECRET);

        // Check timelock
        let current_time = sui::clock::timestamp_ms(clock) / 1000;
        let time_locks = types::get_time_locks(&escrow.immutables);
        
        // Private withdrawal for taker
        if (sui::tx_context::sender(ctx) == types::get_taker(&escrow.immutables)) {
            assert!(current_time >= types::get_src_withdrawal(&time_locks), E_TIME_LOCK_NOT_EXPIRED);
        };

        escrow.is_completed = true;

        // Emit withdrawal event with secret
        event::emit(Withdrawn {
            escrow_id: sui::object::id(escrow),
            secret,
            to: types::get_maker(&escrow.immutables),
            amount: balance::value(&escrow.deposited_amount),
        });

        let withdrawn_coin = sui::coin::from_balance(balance::withdraw_all(&mut escrow.deposited_amount), ctx);
        let safety_coin = sui::coin::from_balance(balance::withdraw_all(&mut escrow.safety_deposit), ctx);

        (withdrawn_coin, safety_coin)
    }

    // Cancel after timeout
    public fun cancel<T>(
        escrow: &mut Escrow<T>,
        clock: &sui::clock::Clock,
        ctx: &mut sui::tx_context::TxContext
    ): (sui::coin::Coin<T>, sui::coin::Coin<SUI>) {
        assert!(!escrow.is_completed, E_ESCROW_COMPLETED);

        let current_time = sui::clock::timestamp_ms(clock) / 1000;
        let time_locks = types::get_time_locks(&escrow.immutables);

        // Check cancellation timelock
        if (sui::tx_context::sender(ctx) == types::get_taker(&escrow.immutables)) {
            assert!(current_time >= types::get_src_cancellation(&time_locks), E_TIME_LOCK_NOT_EXPIRED);
        } else {
            // Public cancellation
            assert!(current_time >= types::get_src_public_cancellation(&time_locks), E_TIME_LOCK_NOT_EXPIRED);
        };

        escrow.is_completed = true;

        event::emit(Cancelled {
            escrow_id: sui::object::id(escrow),
            to: types::get_maker(&escrow.immutables),
            amount: balance::value(&escrow.deposited_amount),
        });

        let refunded_coin = sui::coin::from_balance(balance::withdraw_all(&mut escrow.deposited_amount), ctx);
        let safety_coin = sui::coin::from_balance(balance::withdraw_all(&mut escrow.safety_deposit), ctx);

        (refunded_coin, safety_coin)
    }
}