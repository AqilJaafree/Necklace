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
 * @title Enhanced SuiResolver - WITH LIVE SECRET COORDINATION
 * @dev Extended resolver for Sui-Ethereum cross-chain atomic swaps
 * Combines 1inch LOP integration with Sui state verification and REAL-TIME cross-chain secret coordination
 * 
 * KEY ENHANCEMENT: Live secret coordination between Sui and Ethereum chains
 * 
 * @custom:security-contact security@1inch.io
 */
contract SuiResolver is Resolver, SuiVerifier {
    using ImmutablesLib for IBaseEscrow.Immutables;
    using TimelocksLib for Timelocks;

    // ===========================================
    // ENHANCED EVENTS FOR LIVE COORDINATION
    // ===========================================
    
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

    // 🔥 NEW: Live coordination events
    event LiveSecretCoordinated(
        bytes32 indexed suiEscrowId,
        bytes32 indexed ethereumOrderHash,
        bytes32 indexed secret,
        address coordinator,
        uint256 timestamp
    );

    event CrossChainMappingRegistered(
        bytes32 indexed suiEscrowId,
        bytes32 indexed ethereumOrderHash,
        address registrar
    );

    event SecretRevealedFromSui(
        bytes32 indexed suiEscrowId,
        bytes32 indexed secret,
        uint256 timestamp,
        string status
    );

    event LiveCoordinationStatus(
        bytes32 indexed identifier,
        string status,
        uint256 timestamp
    );

    // ===========================================
    // ENHANCED ERRORS
    // ===========================================
    
    error SuiProofVerificationFailed();
    error InvalidSuiEscrowParams();
    error SecretAlreadyRevealed();
    error SuiTransactionNotVerified();
    error InvalidSecretFormat();
    error CoordinationFailed();
    error UnauthorizedCoordination();
    error SecretNotAvailable();
    error CrossChainMappingExists();
    error InvalidCoordinationData();

    // ===========================================
    // 🔥 ENHANCED STORAGE FOR LIVE COORDINATION
    // ===========================================
    
    // Live secret coordination storage
    mapping(bytes32 => bytes32) public liveSecrets; // suiEscrowId => secret
    mapping(bytes32 => bool) public secretCoordinated; // secret => coordinated
    mapping(bytes32 => uint256) public secretTimestamp; // secret => reveal timestamp
    mapping(bytes32 => address) public secretCoordinator; // secret => coordinator address
    mapping(bytes32 => string) public coordinationStatus; // escrowId => status
    
    // Enhanced cross-chain coordination mappings
    mapping(bytes32 => bytes32) public suiEscrowToOrder; // suiEscrowId => ethereumOrderHash
    mapping(bytes32 => bytes32) public orderToSuiEscrow; // ethereumOrderHash => suiEscrowId
    mapping(bytes32 => bool) public crossChainMappingExists; // orderHash => exists
    
    // Track revealed secrets to prevent double-spending
    mapping(bytes32 => bool) public revealedSecrets;
    
    // Coordination queue for batch processing
    mapping(bytes32 => bool) public pendingCoordination; // secret => pending

    // Store factory and LOP references locally since parent's are private
    IEscrowFactory private immutable FACTORY;
    IOrderMixin private immutable LOP;
    
    // Coordination settings
    uint256 public constant COORDINATION_TIMEOUT = 3600; // 1 hour
    uint256 public constant MAX_COORDINATION_ATTEMPTS = 3;
    mapping(bytes32 => uint256) public coordinationAttempts; // secret => attempts

    constructor(
        IEscrowFactory factory,
        IOrderMixin lop,
        address initialOwner
    ) Resolver(factory, lop, initialOwner) {
        FACTORY = factory;
        LOP = lop;
    }

    // ===========================================
    // 🔥 CORE LIVE COORDINATION FUNCTIONS
    // ===========================================

    /**
     * @dev 🔥 MAIN FUNCTION: Coordinate secret from Sui to Ethereum
     * This is called when a secret is revealed on Sui and needs to be made available on Ethereum
     */
    function coordinateSecretFromSui(
        bytes32 suiEscrowId,
        bytes32 revealedSecret,
        bytes32 ethereumOrderHash
    ) external {
        // Validation
        require(revealedSecret != bytes32(0), "Invalid secret");
        require(suiEscrowId != bytes32(0), "Invalid escrow ID");
        require(!secretCoordinated[revealedSecret], "Secret already coordinated");
        
        // Store the secret for cross-chain use
        liveSecrets[suiEscrowId] = revealedSecret;
        secretCoordinated[revealedSecret] = true;
        secretTimestamp[revealedSecret] = block.timestamp;
        secretCoordinator[revealedSecret] = msg.sender;
        coordinationStatus[suiEscrowId] = "SECRET_COORDINATED";
        
        // Update cross-chain mappings if not exists
        if (suiEscrowToOrder[suiEscrowId] == bytes32(0)) {
            suiEscrowToOrder[suiEscrowId] = ethereumOrderHash;
            orderToSuiEscrow[ethereumOrderHash] = suiEscrowId;
            crossChainMappingExists[ethereumOrderHash] = true;
        }
        
        // Emit coordination events
        emit LiveSecretCoordinated(
            suiEscrowId,
            ethereumOrderHash,
            revealedSecret,
            msg.sender,
            block.timestamp
        );
        
        emit SuiSecretUsed(ethereumOrderHash, revealedSecret, msg.sender);
        
        emit LiveCoordinationStatus(
            suiEscrowId,
            "SECRET_AVAILABLE_CROSS_CHAIN",
            block.timestamp
        );
    }

    /**
     * @dev 🔥 Register cross-chain mapping between Sui escrow and Ethereum order
     */
    function registerCrossChainMapping(
        bytes32 suiEscrowId,
        bytes32 ethereumOrderHash
    ) external {
        require(suiEscrowId != bytes32(0), "Invalid Sui escrow ID");
        require(ethereumOrderHash != bytes32(0), "Invalid Ethereum order hash");
        
        // Store the mapping
        suiEscrowToOrder[suiEscrowId] = ethereumOrderHash;
        orderToSuiEscrow[ethereumOrderHash] = suiEscrowId;
        crossChainMappingExists[ethereumOrderHash] = true;
        
        emit CrossChainMappingRegistered(suiEscrowId, ethereumOrderHash, msg.sender);
        emit LiveCoordinationStatus(suiEscrowId, "MAPPING_REGISTERED", block.timestamp);
    }

    /**
     * @dev 🔥 Get coordinated secret for cross-chain use
     */
    function getCoordinatedSecret(bytes32 suiEscrowId) external view returns (
        bytes32 secret,
        bool available,
        uint256 timestamp,
        address coordinator,
        string memory status
    ) {
        secret = liveSecrets[suiEscrowId];
        available = secretCoordinated[secret] && !revealedSecrets[secret];
        timestamp = secretTimestamp[secret];
        coordinator = secretCoordinator[secret];
        status = coordinationStatus[suiEscrowId];
        
        return (secret, available, timestamp, coordinator, status);
    }

    /**
     * @dev 🔥 Check if secret is available for coordination
     */
    function isSecretCoordinated(bytes32 secret) external view returns (bool) {
        return secretCoordinated[secret] && !revealedSecrets[secret];
    }

    /**
     * @dev 🔥 Use coordinated secret to withdraw from Ethereum escrow
     */
    function withdrawWithCoordinatedSecret(
        IEscrow escrow,
        IBaseEscrow.Immutables calldata immutables,
        bytes32 suiEscrowId
    ) external {
        // Get the coordinated secret
        bytes32 secret = liveSecrets[suiEscrowId];
        require(secret != bytes32(0), "No secret available");
        require(secretCoordinated[secret], "Secret not coordinated");
        
        // Prevent double-spending
        require(!revealedSecrets[secret], "Secret already used");
        revealedSecrets[secret] = true;
        
        // Update status
        coordinationStatus[suiEscrowId] = "SECRET_USED_ON_ETHEREUM";
        
        // Use the secret to withdraw from Ethereum escrow
        escrow.withdraw(secret, immutables);
        
        // Emit completion events
        bytes32 orderHash = suiEscrowToOrder[suiEscrowId];
        emit SuiSecretUsed(orderHash, secret, msg.sender);
        emit CrossChainSwapCompleted(orderHash, address(this), address(this), immutables.amount, immutables.amount);
        emit LiveCoordinationStatus(suiEscrowId, "ETHEREUM_WITHDRAWAL_COMPLETE", block.timestamp);
    }

    /**
     * @dev 🔥 Batch coordinate multiple secrets (for efficiency)
     */
    function batchCoordinateSecrets(
        bytes32[] calldata suiEscrowIds,
        bytes32[] calldata secrets,
        bytes32[] calldata ethereumOrderHashes
    ) external {
        require(suiEscrowIds.length == secrets.length, "Array length mismatch");
        require(secrets.length == ethereumOrderHashes.length, "Array length mismatch");
        
        for (uint256 i = 0; i < suiEscrowIds.length; i++) {
            if (!secretCoordinated[secrets[i]]) {
                // Use internal function to avoid re-entrancy
                _coordinateSecretInternal(suiEscrowIds[i], secrets[i], ethereumOrderHashes[i]);
            }
        }
        
        emit LiveCoordinationStatus(
            bytes32(uint256(suiEscrowIds.length)),
            "BATCH_COORDINATION_COMPLETE",
            block.timestamp
        );
    }

    /**
     * @dev Internal function for batch coordination
     */
    function _coordinateSecretInternal(
        bytes32 suiEscrowId,
        bytes32 revealedSecret,
        bytes32 ethereumOrderHash
    ) internal {
        liveSecrets[suiEscrowId] = revealedSecret;
        secretCoordinated[revealedSecret] = true;
        secretTimestamp[revealedSecret] = block.timestamp;
        secretCoordinator[revealedSecret] = msg.sender;
        coordinationStatus[suiEscrowId] = "SECRET_COORDINATED";
        
        // Update mappings
        suiEscrowToOrder[suiEscrowId] = ethereumOrderHash;
        orderToSuiEscrow[ethereumOrderHash] = suiEscrowId;
        
        emit LiveSecretCoordinated(
            suiEscrowId,
            ethereumOrderHash,
            revealedSecret,
            msg.sender,
            block.timestamp
        );
    }

    // ===========================================
    // 🔥 ORIGINAL ENHANCED FUNCTIONS (UPDATED)
    // ===========================================

    /**
     * @dev Deploy source escrow with Sui proof verification
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
        crossChainMappingExists[orderHash] = true;

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
        
        emit LiveCoordinationStatus(suiEscrow.escrowId, "ETHEREUM_ESCROW_DEPLOYED", block.timestamp);
    }

    /**
     * @dev Deploy destination escrow that will be unlocked by Sui secret reveal
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

        // Emit event for coordination
        emit SuiEscrowDeployed(
            orderHash,
            suiEscrowId,
            msg.sender,
            msg.sender,
            dstImmutables.amount
        );
        
        emit LiveCoordinationStatus(suiEscrowId, "DESTINATION_ESCROW_DEPLOYED", block.timestamp);
    }

    /**
     * @dev Enhanced withdrawal using secret revealed on Sui
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
        emit LiveCoordinationStatus(suiWithdrawal.escrowId, "WITHDRAWAL_COMPLETE", block.timestamp);
    }

    // ===========================================
    // UTILITY AND GETTER FUNCTIONS
    // ===========================================

    /**
     * @dev Get complete cross-chain coordination status
     */
    function getCrossChainStatus(bytes32 suiEscrowId) external view returns (
        bytes32 ethereumOrderHash,
        bytes32 revealedSecret,
        bool secretAvailable,
        uint256 revealTimestamp,
        address coordinator,
        string memory status
    ) {
        ethereumOrderHash = suiEscrowToOrder[suiEscrowId];
        revealedSecret = liveSecrets[suiEscrowId];
        secretAvailable = secretCoordinated[revealedSecret] && !revealedSecrets[revealedSecret];
        revealTimestamp = secretTimestamp[revealedSecret];
        coordinator = secretCoordinator[revealedSecret];
        status = coordinationStatus[suiEscrowId];
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

    /**
     * @dev Emergency function to reset coordination state
     */
    function emergencyResetCoordination(bytes32 suiEscrowId) external onlyOwner {
        bytes32 secret = liveSecrets[suiEscrowId];
        require(
            block.timestamp > secretTimestamp[secret] + COORDINATION_TIMEOUT,
            "Coordination too recent"
        );
        
        // Reset state
        delete liveSecrets[suiEscrowId];
        delete secretCoordinated[secret];
        delete secretTimestamp[secret];
        delete secretCoordinator[secret];
        coordinationStatus[suiEscrowId] = "RESET";
        
        emit LiveCoordinationStatus(suiEscrowId, "EMERGENCY_RESET", block.timestamp);
    }

    // ===========================================
    // INTERNAL FUNCTIONS
    // ===========================================

    /**
     * @dev Internal function to validate Sui escrow parameters match Ethereum order
     */
    function _validateSuiEscrowParams(
        IBaseEscrow.Immutables calldata ethImmutables,
        SuiEscrowCreated calldata suiEscrow
    ) internal pure {
        require(ethImmutables.orderHash == suiEscrow.ethereumOrderHash, "Order hash mismatch");
        require(suiEscrow.escrowId != bytes32(0), "Invalid escrow ID");
        require(suiEscrow.amount > 0, "Invalid amount");
        require(suiEscrow.hashLock != bytes32(0), "Invalid hash lock");
    }

    /**
     * @dev Internal function to hash 1inch order for tracking
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

    // ===========================================
    // REMAINING ORIGINAL FUNCTIONS (PRESERVED)
    // ===========================================

    function cancelWithSuiCoordination(
        IEscrow escrow,
        IBaseEscrow.Immutables calldata immutables,
        bytes32 suiEscrowId
    ) external {
        escrow.cancel(immutables);
        
        // Clean up cross-chain mappings
        bytes32 orderHash = suiEscrowToOrder[suiEscrowId];
        delete suiEscrowToOrder[suiEscrowId];
        delete orderToSuiEscrow[orderHash];
        coordinationStatus[suiEscrowId] = "CANCELLED";
        
        emit LiveCoordinationStatus(suiEscrowId, "COORDINATION_CANCELLED", block.timestamp);
    }

    function emergencyCancelWithSuiProof(
        IEscrow escrow,
        IBaseEscrow.Immutables calldata immutables,
        SuiTransactionProof calldata cancelProof
    ) external onlyOwner {
        require(this.verifySuiTransaction(cancelProof), "Invalid Sui cancel proof");
        escrow.cancel(immutables);
    }

    function batchProcessSuiProofs(
        SuiTransactionProof[] calldata proofs,
        bytes[] calldata actions
    ) external onlyOwner {
        require(proofs.length == actions.length, "Length mismatch");
        
        for (uint256 i = 0; i < proofs.length; i++) {
            require(this.verifySuiTransaction(proofs[i]), "Proof verification failed");
            (bool success,) = address(this).call(actions[i]);
            require(success, "Action execution failed");
        }
    }
}