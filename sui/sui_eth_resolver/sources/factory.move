module sui_eth_resolver::factory {
    use sui::event;
    use sui_eth_resolver::types::SrcImmutables;
    use sui_eth_resolver::escrow;

    // Error constants
    const E_UNAUTHORIZED: u64 = 0;

    // Factory struct
    public struct EscrowFactory has key {
        id: sui::object::UID,
        owner: address,
        rescue_delay_src: u64,
        rescue_delay_dst: u64,
    }

    // Events
    public struct SrcEscrowCreated has copy, drop {
        factory_id: sui::object::ID,
        escrow_id: sui::object::ID,
        immutables: SrcImmutables,
        creator: address,
    }

    public struct DstEscrowCreated has copy, drop {
        factory_id: sui::object::ID,
        escrow_id: sui::object::ID,
        immutables: SrcImmutables,
        creator: address,
        src_cancellation_timestamp: u64,
    }

    // Initialize factory
    fun init(ctx: &mut sui::tx_context::TxContext) {
        let factory = EscrowFactory {
            id: sui::object::new(ctx),
            owner: sui::tx_context::sender(ctx),
            rescue_delay_src: 1800,
            rescue_delay_dst: 1800,
        };
        sui::transfer::share_object(factory);
    }

    // Create factory with specific parameters
    public fun create_factory(
        owner: address,
        rescue_delay_src: u64,
        rescue_delay_dst: u64,
        ctx: &mut sui::tx_context::TxContext
    ): sui::object::ID {
        let factory = EscrowFactory {
            id: sui::object::new(ctx),
            owner,
            rescue_delay_src,
            rescue_delay_dst,
        };
        let factory_id = sui::object::id(&factory);
        sui::transfer::share_object(factory);
        factory_id
    }

    // Create source escrow
    public fun create_src_escrow<T>(
        factory: &EscrowFactory,
        immutables: SrcImmutables,
        ctx: &mut sui::tx_context::TxContext
    ): sui::object::ID {
        let escrow_id = escrow::create<T>(immutables, ctx);

        // Emit creation event
        event::emit(SrcEscrowCreated {
            factory_id: sui::object::id(factory),
            escrow_id,
            immutables,
            creator: sui::tx_context::sender(ctx),
        });

        escrow_id
    }

    // Create destination escrow
    public fun create_dst_escrow<T>(
        factory: &EscrowFactory,
        immutables: SrcImmutables,
        src_cancellation_timestamp: u64,
        ctx: &mut sui::tx_context::TxContext
    ): sui::object::ID {
        let escrow_id = escrow::create<T>(immutables, ctx);

        // Emit creation event
        event::emit(DstEscrowCreated {
            factory_id: sui::object::id(factory),
            escrow_id,
            immutables,
            creator: sui::tx_context::sender(ctx),
            src_cancellation_timestamp,
        });

        escrow_id
    }

    // Utility functions
    public fun get_owner(factory: &EscrowFactory): address {
        factory.owner
    }

    public fun get_rescue_delays(factory: &EscrowFactory): (u64, u64) {
        (factory.rescue_delay_src, factory.rescue_delay_dst)
    }

    public fun transfer_ownership(
        factory: &mut EscrowFactory,
        new_owner: address,
        ctx: &mut sui::tx_context::TxContext
    ) {
        assert!(sui::tx_context::sender(ctx) == factory.owner, E_UNAUTHORIZED);
        factory.owner = new_owner;
    }
}