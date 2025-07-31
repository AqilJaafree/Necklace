module sui_eth_resolver::resolver {
    use sui::event;
    use sui::sui::SUI;
    use sui_eth_resolver::types::{Self, SrcImmutables};
    use sui_eth_resolver::escrow::{Self, Escrow};

    // Error constants
    const E_UNAUTHORIZED: u64 = 0;

    // Resolver struct
    public struct Resolver has key {
        id: sui::object::UID,
        owner: address,
    }

    // Events for cross-chain monitoring
    public struct SrcEscrowDeployed has copy, drop {
        resolver_id: sui::object::ID,
        escrow_id: sui::object::ID,
        immutables: SrcImmutables,
        deployer: address,
        ethereum_order_hash: vector<u8>,
    }

    public struct DstEscrowDeployed has copy, drop {
        resolver_id: sui::object::ID,
        escrow_id: sui::object::ID,
        immutables: SrcImmutables,
        deployer: address,
        src_cancellation_timestamp: u64,
    }

    public struct EscrowWithdrawn has copy, drop {
        resolver_id: sui::object::ID,
        escrow_id: sui::object::ID,
        secret: vector<u8>,
        executor: address,
        amount: u64,
    }

    public struct EscrowCancelled has copy, drop {
        resolver_id: sui::object::ID,
        escrow_id: sui::object::ID,
        executor: address,
        amount: u64,
    }

    // Initialize resolver
    fun init(ctx: &mut sui::tx_context::TxContext) {
        let resolver = Resolver {
            id: sui::object::new(ctx),
            owner: sui::tx_context::sender(ctx),
        };
        sui::transfer::share_object(resolver);
    }

    // Create resolver with specific owner
    public fun create_resolver(owner: address, ctx: &mut sui::tx_context::TxContext): sui::object::ID {
        let resolver = Resolver {
            id: sui::object::new(ctx),
            owner,
        };
        let resolver_id = sui::object::id(&resolver);
        sui::transfer::share_object(resolver);
        resolver_id
    }

    // Deploy source escrow and deposit in one transaction
    public fun deploy_src_with_deposit<T>(
        resolver: &Resolver,
        immutables: SrcImmutables,
        deposit_coin: sui::coin::Coin<T>,
        safety_deposit: sui::coin::Coin<SUI>,
        ctx: &mut sui::tx_context::TxContext
    ): sui::object::ID {
        // Only resolver owner can deploy escrows
        assert!(sui::tx_context::sender(ctx) == resolver.owner, E_UNAUTHORIZED);

        // Create escrow
        let escrow_id = escrow::create<T>(immutables, ctx);

        // Emit deployment event for cross-chain monitoring
        event::emit(SrcEscrowDeployed {
            resolver_id: sui::object::id(resolver),
            escrow_id,
            immutables,
            deployer: sui::tx_context::sender(ctx),
            ethereum_order_hash: types::get_ethereum_order_hash(&immutables),
        });

        // Note: In a complete implementation, we would need to deposit the coins
        // to the escrow in the same transaction. For now, we transfer coins to resolver owner
        // as a placeholder. In practice, this would be handled differently.
        sui::transfer::public_transfer(deposit_coin, resolver.owner);
        sui::transfer::public_transfer(safety_deposit, resolver.owner);

        escrow_id
    }

    // Deploy destination escrow and deposit
    public fun deploy_dst_with_deposit<T>(
        resolver: &Resolver,
        immutables: SrcImmutables,
        src_cancellation_timestamp: u64,
        deposit_coin: sui::coin::Coin<T>,
        safety_deposit: sui::coin::Coin<SUI>,
        ctx: &mut sui::tx_context::TxContext
    ): sui::object::ID {
        // Only resolver owner can deploy escrows
        assert!(sui::tx_context::sender(ctx) == resolver.owner, E_UNAUTHORIZED);

        // Create destination escrow
        let escrow_id = escrow::create<T>(immutables, ctx);

        // Emit deployment event for cross-chain monitoring
        event::emit(DstEscrowDeployed {
            resolver_id: sui::object::id(resolver),
            escrow_id,
            immutables,
            deployer: sui::tx_context::sender(ctx),
            src_cancellation_timestamp,
        });

        // Transfer coins to resolver owner (placeholder for actual deposit)
        sui::transfer::public_transfer(deposit_coin, resolver.owner);
        sui::transfer::public_transfer(safety_deposit, resolver.owner);

        escrow_id
    }

    // Deposit funds to escrow (separate function for flexibility)
    public fun deposit_to_escrow<T>(
        resolver: &Resolver,
        escrow: &mut Escrow<T>,
        deposit_coin: sui::coin::Coin<T>,
        safety_deposit: sui::coin::Coin<SUI>,
        ctx: &mut sui::tx_context::TxContext
    ) {
        // Only resolver owner can deposit
        assert!(sui::tx_context::sender(ctx) == resolver.owner, E_UNAUTHORIZED);

        // Deposit to escrow
        escrow::deposit(escrow, deposit_coin, safety_deposit, ctx);
    }

    // Withdraw from escrow with secret
    public fun withdraw<T>(
        resolver: &Resolver,
        escrow: &mut Escrow<T>,
        secret: vector<u8>,
        clock: &sui::clock::Clock,
        ctx: &mut sui::tx_context::TxContext
    ): (sui::coin::Coin<T>, sui::coin::Coin<SUI>) {
        // Anyone can call withdraw if they have the correct secret
        let (withdrawn_coin, safety_coin) = escrow::withdraw(
            escrow,
            secret,
            clock,
            ctx
        );

        let amount = sui::coin::value(&withdrawn_coin);

        // Emit withdrawal event for cross-chain monitoring
        event::emit(EscrowWithdrawn {
            resolver_id: sui::object::id(resolver),
            escrow_id: sui::object::id(escrow),
            secret,
            executor: sui::tx_context::sender(ctx),
            amount,
        });

        (withdrawn_coin, safety_coin)
    }

    // Cancel escrow after timeout
    public fun cancel<T>(
        resolver: &Resolver,
        escrow: &mut Escrow<T>,
        clock: &sui::clock::Clock,
        ctx: &mut sui::tx_context::TxContext
    ): (sui::coin::Coin<T>, sui::coin::Coin<SUI>) {
        let (refunded_coin, safety_coin) = escrow::cancel(
            escrow,
            clock,
            ctx
        );

        let amount = sui::coin::value(&refunded_coin);

        // Emit cancellation event for cross-chain monitoring
        event::emit(EscrowCancelled {
            resolver_id: sui::object::id(resolver),
            escrow_id: sui::object::id(escrow),
            executor: sui::tx_context::sender(ctx),
            amount,
        });

        (refunded_coin, safety_coin)
    }

    // Utility functions
    public fun get_owner(resolver: &Resolver): address {
        resolver.owner
    }

    public fun transfer_ownership(
        resolver: &mut Resolver,
        new_owner: address,
        ctx: &mut sui::tx_context::TxContext
    ) {
        assert!(sui::tx_context::sender(ctx) == resolver.owner, E_UNAUTHORIZED);
        resolver.owner = new_owner;
    }

    public fun get_resolver_id(resolver: &Resolver): sui::object::ID {
        sui::object::id(resolver)
    }
}