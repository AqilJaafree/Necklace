// sui/sources/usdc_token.move
module sui_usdc::usdc_coin {
    use sui::coin::{Self, Coin, TreasuryCap};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};

    public struct USDC has drop {}

    fun init(witness: USDC, ctx: &mut TxContext) {
        let (treasury, metadata) = coin::create_currency(
            witness,
            6, // USDC has 6 decimals
            b"USDC",
            b"USD Coin",
            b"Cross-chain USDC on Sui",
            option::none(),
            ctx
        );
        
        transfer::public_freeze_object(metadata);
        transfer::public_transfer(treasury, tx_context::sender(ctx));
    }

    public fun mint(
        treasury: &mut TreasuryCap<USDC>,
        amount: u64,
        recipient: address,
        ctx: &mut TxContext
    ) {
        coin::mint_and_transfer(treasury, amount, recipient, ctx);
    }

    public fun burn(treasury: &mut TreasuryCap<USDC>, coin: Coin<USDC>) {
        coin::burn(treasury, coin);
    }
}