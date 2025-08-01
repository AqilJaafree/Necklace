// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";

import {IOrderMixin} from "limit-order-protocol/contracts/interfaces/IOrderMixin.sol";
import {TakerTraits} from "limit-order-protocol/contracts/libraries/TakerTraitsLib.sol";

import {IEscrowFactory} from "../lib/cross-chain-swap/contracts/interfaces/IEscrowFactory.sol";
import {IBaseEscrow} from "../lib/cross-chain-swap/contracts/interfaces/IBaseEscrow.sol";
import {TimelocksLib, Timelocks} from "../lib/cross-chain-swap/contracts/libraries/TimelocksLib.sol";
import {IEscrow} from "../lib/cross-chain-swap/contracts/interfaces/IEscrow.sol";
import {ImmutablesLib} from "../lib/cross-chain-swap/contracts/libraries/ImmutablesLib.sol";

import "./Resolver.sol";
import "./SuiVerifier.sol";

/**
 * @title SuiResolver
 * @dev Extended resolver for Sui-Ethereum cross-chain atomic swaps
 * Combines 1inch LOP integration with Sui state verification
 * 
 * @custom:security-contact security@1inch.io
 */
contract SuiResolver is Resolver, SuiVerifier {
    using ImmutablesLib for IBaseEscrow.Immutables;
    using TimelocksLib for Timelocks;

    // Sui-specific events for cross-chain monitoring
    event SuiEscrowDeployed(
        bytes32 indexed orderHash,
        bytes32 indexed suiEscrowId,
        address indexed maker,
        address taker,
        uint256 amount
    );
    
    event SuiSecretUsed(
        bytes32 indexed orderHash,
        bytes32 indexed secret,
        address resolver
    );

    event CrossChainSwapCompleted(
        bytes32 indexed orderHash,
        address srcChain,
        address dstChain,
        uint256 srcAmount,
        uint256 dstAmount
    );

    // Errors
    error SuiProofVerificationFailed();
    error InvalidSuiEscrowParams();
    error SecretAlreadyRevealed();
    error SuiTransactionNotVerified();

    // Track revealed secrets to prevent double-spending
    mapping(bytes32 => bool) public revealedSecrets;
    
    // Track Sui escrow to Ethereum order mapping
    mapping(bytes32 => bytes32) public suiEscrowToOrder;
    mapping(bytes32 => bytes32) public orderToSuiEscrow;

    // Store factory and LOP references locally since parent's are private
    IEscrowFactory private immutable FACTORY;
    IOrderMixin private immutable LOP;
    
    constructor(
        IEscrowFactory factory,
        IOrderMixin lop,
        address initialOwner
    ) Resolver(factory, lop, initialOwner) {
        FACTORY = factory;
        LOP = lop;
    }

    /**
     * @dev Deploy source escrow with Sui proof verification
     * This is called when a Sui escrow has been created and we need to create
     * the corresponding Ethereum escrow with proof of Sui escrow existence
     */
    function deploySrcWithSuiProof(
        IBaseEscrow.Immutables calldata immutables,
        IOrderMixin.Order calldata order,
        SuiEscrowCreated calldata suiEscrow,
        SuiTransactionProof calldata suiProof,
        bytes32 r,
        bytes32 vs,
        uint256 amount,
        TakerTraits takerTraits,
        bytes calldata args
    ) external payable onlyOwner {
        // 1. Verify the Sui transaction containing the escrow creation
        if (!this.verifySuiTransaction(suiProof)) {
            revert SuiProofVerificationFailed();
        }

        // 2. Verify the Sui escrow event matches our order parameters
        _validateSuiEscrowParams(immutables, suiEscrow);

        // 3. Store the mapping between Sui escrow and Ethereum order
        bytes32 orderHash = _hashOrder(order);
        suiEscrowToOrder[suiEscrow.escrowId] = orderHash;
        orderToSuiEscrow[orderHash] = suiEscrow.escrowId;

        // 4. Deploy the Ethereum escrow using standard flow
        IBaseEscrow.Immutables memory immutablesMem = immutables;
        immutablesMem.timelocks = TimelocksLib.setDeployedAt(immutables.timelocks, block.timestamp);
        address computed = FACTORY.addressOfEscrowSrc(immutablesMem);

        (bool success,) = address(computed).call{value: immutablesMem.safetyDeposit}("");
        if (!success) revert IBaseEscrow.NativeTokenSendingFailure();

        // 5. Execute the 1inch LOP order
        takerTraits = TakerTraits.wrap(TakerTraits.unwrap(takerTraits) | uint256(1 << 251));
        bytes memory argsMem = abi.encodePacked(computed, args);
        LOP.fillOrderArgs(order, r, vs, amount, takerTraits, argsMem);

        // 6. Emit event for cross-chain monitoring
        emit SuiEscrowDeployed(
            orderHash,
            suiEscrow.escrowId,
            suiEscrow.maker,
            suiEscrow.taker,
            suiEscrow.amount
        );
    }

    /**
     * @dev Deploy destination escrow that will be unlocked by Sui secret reveal
     * This creates an Ethereum escrow that can only be unlocked when the secret
     * is revealed on the Sui side
     */
    function deployDstWithSuiCoordination(
        IBaseEscrow.Immutables calldata dstImmutables,
        bytes32 suiEscrowId,
        uint256 srcCancellationTimestamp
    ) external onlyOwner payable {
        // Ensure we have a valid Sui escrow mapping
        bytes32 orderHash = suiEscrowToOrder[suiEscrowId];
        require(orderHash != bytes32(0), "Unknown Sui escrow");

        // Deploy destination escrow
        FACTORY.createDstEscrow{value: msg.value}(dstImmutables, srcCancellationTimestamp);

        // Emit event - using simple approach to avoid type conversion issues
        emit SuiEscrowDeployed(
            orderHash,
            suiEscrowId,
            msg.sender, // Use msg.sender as placeholder for maker
            msg.sender, // Use msg.sender as placeholder for taker  
            dstImmutables.amount
        );
    }

    /**
     * @dev Withdraw using secret revealed on Sui
     * This function is called with proof that a secret was revealed on Sui,
     * allowing the corresponding Ethereum escrow to be unlocked
     */
    function withdrawWithSuiSecret(
        IEscrow escrow,
        IBaseEscrow.Immutables calldata immutables,
        SuiWithdrawal calldata suiWithdrawal,
        SuiTransactionProof calldata suiProof
    ) external {
        // 1. Verify the Sui withdrawal transaction
        if (!this.verifySuiTransaction(suiProof)) {
            revert SuiTransactionNotVerified();
        }

        // 2. Extract and verify the secret from Sui withdrawal
        bytes32 secret = this.verifySuiWithdrawal(suiWithdrawal, suiProof);
        
        // 3. Ensure secret hasn't been used before
        if (revealedSecrets[secret]) {
            revert SecretAlreadyRevealed();
        }
        revealedSecrets[secret] = true;

        // 4. Use the secret to withdraw from Ethereum escrow
        escrow.withdraw(secret, immutables);

        // 5. Emit event for monitoring
        bytes32 orderHash = suiEscrowToOrder[suiWithdrawal.escrowId];
        emit SuiSecretUsed(orderHash, secret, msg.sender);
    }

    /**
     * @dev Cancel cross-chain swap with Sui coordination
     * Handles cancellation when timeouts occur on either chain
     */
    function cancelWithSuiCoordination(
        IEscrow escrow,
        IBaseEscrow.Immutables calldata immutables,
        bytes32 suiEscrowId
    ) external {
        // Standard cancellation
        escrow.cancel(immutables);

        // Clean up cross-chain mappings
        bytes32 orderHash = suiEscrowToOrder[suiEscrowId];
        delete suiEscrowToOrder[suiEscrowId];
        delete orderToSuiEscrow[orderHash];
    }

    /**
     * @dev Emergency function to handle Sui network issues
     * Allows cancellation with additional verification requirements
     */
    function emergencyCancelWithSuiProof(
        IEscrow escrow,
        IBaseEscrow.Immutables calldata immutables,
        SuiTransactionProof calldata cancelProof
    ) external onlyOwner {
        // Verify Sui cancellation transaction
        require(this.verifySuiTransaction(cancelProof), "Invalid Sui cancel proof");
        
        // Execute cancellation
        escrow.cancel(immutables);
    }

    /**
     * @dev Batch process multiple Sui proofs for efficiency
     * Allows processing multiple cross-chain operations in one transaction
     */
    function batchProcessSuiProofs(
        SuiTransactionProof[] calldata proofs,
        bytes[] calldata actions
    ) external onlyOwner {
        require(proofs.length == actions.length, "Length mismatch");
        
        for (uint256 i = 0; i < proofs.length; i++) {
            // Verify each Sui transaction
            require(this.verifySuiTransaction(proofs[i]), "Proof verification failed");
            
            // Execute corresponding action
            (bool success,) = address(this).call(actions[i]);
            require(success, "Action execution failed");
        }
    }

    /**
     * @dev Internal function to validate Sui escrow parameters match Ethereum order
     */
    function _validateSuiEscrowParams(
        IBaseEscrow.Immutables calldata ethImmutables,
        SuiEscrowCreated calldata suiEscrow
    ) internal pure {
        // Verify order hash matches  
        require(ethImmutables.orderHash == suiEscrow.ethereumOrderHash, "Order hash mismatch");
        
        // Verify that the structs are properly formed
        require(suiEscrow.escrowId != bytes32(0), "Invalid escrow ID");
        require(suiEscrow.amount > 0, "Invalid amount");
        require(suiEscrow.hashLock != bytes32(0), "Invalid hash lock");
    }

    /**
     * @dev Internal function to hash 1inch order for tracking
     * Uses only the available struct members
     */
    function _hashOrder(IOrderMixin.Order calldata order) internal pure returns (bytes32) {
        return keccak256(abi.encode(
            order.salt,
            order.maker,
            order.receiver,
            order.makerAsset,
            order.takerAsset,
            order.makingAmount,
            order.takingAmount,
            order.makerTraits
        ));
    }

    /**
     * @dev Get Sui escrow ID for a given Ethereum order hash
     */
    function getSuiEscrowForOrder(bytes32 orderHash) external view returns (bytes32) {
        return orderToSuiEscrow[orderHash];
    }

    /**
     * @dev Get Ethereum order hash for a given Sui escrow ID
     */
    function getOrderForSuiEscrow(bytes32 suiEscrowId) external view returns (bytes32) {
        return suiEscrowToOrder[suiEscrowId];
    }

    /**
     * @dev Check if a secret has been revealed and used
     */
    function isSecretRevealed(bytes32 secret) external view returns (bool) {
        return revealedSecrets[secret];
    }
}