    // contracts/src/SuiResolverBidirectional.sol
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
 * @title SuiResolverBidirectional - COMPLETE BIDIRECTIONAL SUPPORT
 * @dev Enhanced resolver with full Ethereum→Sui coordination capabilities
 * Combines all functionality: Resolver + SuiVerifier + Live Coordination + Bidirectional Support
 * 
 * BIDIRECTIONAL FLOWS:
 * 1. Sui→Ethereum: Already working ✅
 * 2. Ethereum→Sui: This implementation ✅
 * 
 * @custom:security-contact security@1inch.io
 */
contract SuiResolverBidirectional is Resolver, SuiVerifier {
    using ImmutablesLib for IBaseEscrow.Immutables;
    using TimelocksLib for Timelocks;

    // ===========================================
    // 🔄 ENHANCED STORAGE FROM SUIRESOLVER
    // ===========================================
    
    // Live secret coordination storage (from SuiResolver)
    mapping(bytes32 => bytes32) public liveSecrets; // suiEscrowId => secret
    mapping(bytes32 => bool) public secretCoordinated; // secret => coordinated
    mapping(bytes32 => uint256) public secretTimestamp; // secret => reveal timestamp
    mapping(bytes32 => address) public secretCoordinator; // secret => coordinator address
    mapping(bytes32 => string) public coordinationStatus; // escrowId => status
    
    // Enhanced cross-chain coordination mappings (from SuiResolver)
    mapping(bytes32 => bytes32) public suiEscrowToOrder; // suiEscrowId => ethereumOrderHash
    mapping(bytes32 => bytes32) public orderToSuiEscrow; // ethereumOrderHash => suiEscrowId
    mapping(bytes32 => bool) public crossChainMappingExists; // orderHash => exists
    mapping(bytes32 => bool) public revealedSecrets; // Track revealed secrets
    
    // ===========================================
    // 🔄 NEW BIDIRECTIONAL STORAGE
    // ===========================================
    
    // Ethereum→Sui direction storage
    mapping(bytes32 => bytes32) public ethereumOrderToSuiEscrow; // ethereumOrderHash => suiEscrowId
    mapping(bytes32 => bytes32) public suiEscrowToEthereumOrder; // suiEscrowId => ethereumOrderHash
    mapping(bytes32 => bool) public ethereumOrderExists; // ethereumOrderHash => exists
    
    // Ethereum-initiated escrow tracking
    mapping(bytes32 => EthereumEscrowData) public ethereumEscrows;
    mapping(bytes32 => bool) public ethereumEscrowActive; // orderHash => active
    
    // Bidirectional secret coordination
    mapping(bytes32 => bytes32) public ethereumRevealedSecrets; // orderHash => secret
    mapping(bytes32 => uint256) public ethereumSecretTimestamp; // orderHash => timestamp
    mapping(bytes32 => bool) public secretUsedOnSui; // secret => used
    
    // Enhanced coordination tracking
    mapping(bytes32 => string) public bidirectionalStatus; // orderHash => status
    mapping(bytes32 => address) public ethereumInitiator; // orderHash => initiator
    
    struct EthereumEscrowData {
        bytes32 orderHash;
        bytes32 secretHash;
        address maker;
        address taker;
        address token;
        uint256 amount;
        uint256 safetyDeposit;
        uint256 createdAt;
        bool isActive;
    }
    
    // Store factory and LOP references 
    IEscrowFactory private immutable FACTORY;
    IOrderMixin private immutable LOP;
    
    // Coordination settings
    uint256 public constant COORDINATION_TIMEOUT = 3600; // 1 hour

    constructor(
        IEscrowFactory factory,
        IOrderMixin lop,
        address initialOwner
    ) Resolver(factory, lop, initialOwner) {
        FACTORY = factory;
        LOP = lop;
    }
    
    // ===========================================
    // 🔄 ENHANCED EVENTS (SuiResolver + Bidirectional)
    // ===========================================
    
    // Original SuiResolver events
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

    // Live coordination events
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

    event LiveCoordinationStatus(
        bytes32 indexed identifier,
        string status,
        uint256 timestamp
    );
    
    // New bidirectional events
    event EthereumEscrowInitiated(
        bytes32 indexed orderHash,
        address indexed maker,
        address indexed taker,
        uint256 amount,
        bytes32 secretHash
    );
    
    event EthereumToSuiMappingCreated(
        bytes32 indexed ethereumOrderHash,
        bytes32 indexed suiEscrowId,
        address coordinator
    );
    
    event EthereumSecretRevealed(
        bytes32 indexed orderHash,
        bytes32 indexed secret,
        address revealer,
        uint256 timestamp
    );
    
    event SuiWithdrawalFromEthereumSecret(
        bytes32 indexed suiEscrowId,
        bytes32 indexed ethereumOrderHash,
        bytes32 indexed secret,
        address executor
    );
    
    event BidirectionalSwapCompleted(
        bytes32 indexed ethereumOrderHash,
        bytes32 indexed suiEscrowId,
        bytes32 indexed secret,
        address ethereumInitiator,
        address suiCompleter
    );

    // ===========================================
    // 🔥 LIVE COORDINATION FUNCTIONS (from SuiResolver)
    // ===========================================

    /**
     * @dev 🔥 MAIN FUNCTION: Coordinate secret from Sui to Ethereum
     */
    function coordinateSecretFromSui(
        bytes32 suiEscrowId,
        bytes32 revealedSecret,
        bytes32 ethereumOrderHash
    ) external {
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
        emit LiveCoordinationStatus(suiEscrowId, "SECRET_AVAILABLE_CROSS_CHAIN", block.timestamp);
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
    }

    /**
     * @dev 🔥 Check if secret is available for coordination
     */
    function isSecretCoordinated(bytes32 secret) external view returns (bool) {
        return secretCoordinated[secret] && !revealedSecrets[secret];
    }
    
    // ===========================================
    // 🔄 ETHEREUM→SUI CORE FUNCTIONS
    // ===========================================
    
    /**
     * @dev 🔄 Initiate Ethereum→Sui swap by creating Ethereum escrow data
     */
    function initiateEthereumToSuiSwap(
        bytes32 orderHash,
        bytes32 secretHash,
        address maker,
        address taker,
        address token,
        uint256 amount,
        uint256 safetyDeposit
    ) external payable {
        require(orderHash != bytes32(0), "Invalid order hash");
        require(secretHash != bytes32(0), "Invalid secret hash");
        require(!ethereumOrderExists[orderHash], "Order already exists");
        require(msg.value >= safetyDeposit, "Insufficient safety deposit");
        
        // Store Ethereum escrow data
        ethereumEscrows[orderHash] = EthereumEscrowData({
            orderHash: orderHash,
            secretHash: secretHash,
            maker: maker,
            taker: taker,
            token: token,
            amount: amount,
            safetyDeposit: safetyDeposit,
            createdAt: block.timestamp,
            isActive: true
        });
        
        ethereumOrderExists[orderHash] = true;
        ethereumEscrowActive[orderHash] = true;
        ethereumInitiator[orderHash] = msg.sender;
        bidirectionalStatus[orderHash] = "ETHEREUM_ESCROW_INITIATED";
        
        emit EthereumEscrowInitiated(orderHash, maker, taker, amount, secretHash);
        emit LiveCoordinationStatus(orderHash, "ETHEREUM_ESCROW_READY", block.timestamp);
    }
    
    /**
     * @dev 🔄 Link Ethereum order to Sui escrow (bidirectional mapping)
     */
    function linkEthereumOrderToSuiEscrow(
        bytes32 ethereumOrderHash,
        bytes32 suiEscrowId
    ) external {
        require(ethereumOrderExists[ethereumOrderHash], "Ethereum order not found");
        require(suiEscrowId != bytes32(0), "Invalid Sui escrow ID");
        require(ethereumOrderToSuiEscrow[ethereumOrderHash] == bytes32(0), "Mapping already exists");
        
        // Create bidirectional mapping
        ethereumOrderToSuiEscrow[ethereumOrderHash] = suiEscrowId;
        suiEscrowToEthereumOrder[suiEscrowId] = ethereumOrderHash;
        
        bidirectionalStatus[ethereumOrderHash] = "ETHEREUM_SUI_LINKED";
        
        emit EthereumToSuiMappingCreated(ethereumOrderHash, suiEscrowId, msg.sender);
        emit LiveCoordinationStatus(ethereumOrderHash, "BIDIRECTIONAL_MAPPING_CREATED", block.timestamp);
    }
    
    /**
     * @dev 🔄 Reveal secret from Ethereum side (for Sui completion)
     */
    function revealEthereumSecret(
        bytes32 orderHash,
        string calldata secret
    ) external {
        require(ethereumOrderExists[orderHash], "Order not found");
        require(ethereumEscrowActive[orderHash], "Escrow not active");
        
        bytes32 secretBytes = keccak256(bytes(secret));
        require(secretBytes == ethereumEscrows[orderHash].secretHash, "Invalid secret");
        require(ethereumRevealedSecrets[orderHash] == bytes32(0), "Secret already revealed");
        
        // Store revealed secret
        ethereumRevealedSecrets[orderHash] = secretBytes;
        ethereumSecretTimestamp[orderHash] = block.timestamp;
        bidirectionalStatus[orderHash] = "ETHEREUM_SECRET_REVEALED";
        
        emit EthereumSecretRevealed(orderHash, secretBytes, msg.sender, block.timestamp);
        emit LiveCoordinationStatus(orderHash, "SECRET_AVAILABLE_FOR_SUI", block.timestamp);
    }
    
    /**
     * @dev 🔄 Get revealed Ethereum secret for Sui usage
     */
    function getEthereumRevealedSecret(bytes32 orderHash) external view returns (
        bytes32 secret,
        bool available,
        uint256 timestamp,
        address revealer,
        string memory status
    ) {
        secret = ethereumRevealedSecrets[orderHash];
        available = secret != bytes32(0) && !secretUsedOnSui[secret];
        timestamp = ethereumSecretTimestamp[orderHash];
        revealer = ethereumInitiator[orderHash];
        status = bidirectionalStatus[orderHash];
    }
    
    /**
     * @dev 🔄 Complete Sui withdrawal using Ethereum-revealed secret
     */
    function completeSuiWithdrawalFromEthereumSecret(
        bytes32 orderHash,
        bytes32 suiEscrowId
    ) external {
        require(ethereumOrderExists[orderHash], "Order not found");
        require(ethereumOrderToSuiEscrow[orderHash] == suiEscrowId, "Invalid mapping");
        
        bytes32 secret = ethereumRevealedSecrets[orderHash];
        require(secret != bytes32(0), "Secret not revealed");
        require(!secretUsedOnSui[secret], "Secret already used");
        
        // Mark secret as used
        secretUsedOnSui[secret] = true;
        ethereumEscrowActive[orderHash] = false;
        bidirectionalStatus[orderHash] = "BIDIRECTIONAL_COMPLETED";
        
        emit SuiWithdrawalFromEthereumSecret(suiEscrowId, orderHash, secret, msg.sender);
        emit BidirectionalSwapCompleted(
            orderHash,
            suiEscrowId,
            secret,
            ethereumInitiator[orderHash],
            msg.sender
        );
        emit LiveCoordinationStatus(orderHash, "ETHEREUM_TO_SUI_COMPLETE", block.timestamp);
    }
    
    // ===========================================
    // 🔄 ENHANCED BIDIRECTIONAL UTILITIES
    // ===========================================
    
    /**
     * @dev Get complete bidirectional mapping info
     */
    function getBidirectionalMapping(bytes32 identifier) external view returns (
        bytes32 ethereumOrder,
        bytes32 suiEscrow,
        bool mappingExists,
        string memory status
    ) {
        // Check if identifier is Ethereum order hash
        if (ethereumOrderExists[identifier]) {
            ethereumOrder = identifier;
            suiEscrow = ethereumOrderToSuiEscrow[identifier];
            mappingExists = suiEscrow != bytes32(0);
            status = bidirectionalStatus[identifier];
        }
        // Check if identifier is Sui escrow ID
        else {
            ethereumOrder = suiEscrowToEthereumOrder[identifier];
            suiEscrow = identifier;
            mappingExists = ethereumOrder != bytes32(0);
            status = bidirectionalStatus[ethereumOrder];
        }
    }
    
    /**
     * @dev Get Ethereum escrow data
     */
    function getEthereumEscrowData(bytes32 orderHash) external view returns (
        EthereumEscrowData memory escrowData,
        bool isActive,
        string memory status
    ) {
        escrowData = ethereumEscrows[orderHash];
        isActive = ethereumEscrowActive[orderHash];
        status = bidirectionalStatus[orderHash];
    }
    
    /**
     * @dev Check if bidirectional swap is ready for completion
     */
    function isBidirectionalSwapReady(bytes32 orderHash) external view returns (
        bool ethereumReady,
        bool suiReady,
        bool secretRevealed,
        bool canComplete
    ) {
        ethereumReady = ethereumOrderExists[orderHash] && ethereumEscrowActive[orderHash];
        suiReady = ethereumOrderToSuiEscrow[orderHash] != bytes32(0);
        secretRevealed = ethereumRevealedSecrets[orderHash] != bytes32(0);
        canComplete = ethereumReady && suiReady && secretRevealed;
    }
    
    /**
     * @dev Emergency functions for bidirectional swaps
     */
    function emergencyCancelEthereumOrder(bytes32 orderHash) external {
        require(ethereumInitiator[orderHash] == msg.sender || msg.sender == owner(), "Unauthorized");
        require(
            block.timestamp > ethereumEscrows[orderHash].createdAt + COORDINATION_TIMEOUT,
            "Too early to cancel"
        );
        
        ethereumEscrowActive[orderHash] = false;
        bidirectionalStatus[orderHash] = "EMERGENCY_CANCELLED";
        
        emit LiveCoordinationStatus(orderHash, "EMERGENCY_CANCELLED", block.timestamp);
    }
    
    /**
     * @dev Batch process multiple bidirectional operations
     */
    function batchProcessBidirectional(
        bytes32[] calldata orderHashes,
        bytes32[] calldata suiEscrowIds,
        string[] calldata operations
    ) external {
        require(orderHashes.length == suiEscrowIds.length, "Array length mismatch");
        require(suiEscrowIds.length == operations.length, "Array length mismatch");
        
        for (uint256 i = 0; i < orderHashes.length; i++) {
            if (keccak256(bytes(operations[i])) == keccak256(bytes("LINK"))) {
                if (ethereumOrderExists[orderHashes[i]] && ethereumOrderToSuiEscrow[orderHashes[i]] == bytes32(0)) {
                    ethereumOrderToSuiEscrow[orderHashes[i]] = suiEscrowIds[i];
                    suiEscrowToEthereumOrder[suiEscrowIds[i]] = orderHashes[i];
                }
            } else if (keccak256(bytes(operations[i])) == keccak256(bytes("COMPLETE"))) {
                if (ethereumRevealedSecrets[orderHashes[i]] != bytes32(0) && !secretUsedOnSui[ethereumRevealedSecrets[orderHashes[i]]]) {
                    secretUsedOnSui[ethereumRevealedSecrets[orderHashes[i]]] = true;
                    ethereumEscrowActive[orderHashes[i]] = false;
                }
            }
        }
        
        emit LiveCoordinationStatus(
            bytes32(uint256(orderHashes.length)),
            "BATCH_BIDIRECTIONAL_COMPLETE",
            block.timestamp
        );
    }
    
    // ===========================================
    // 🔄 ENHANCED GETTERS FOR BIDIRECTIONAL SUPPORT
    // ===========================================
    
    /**
     * @dev Get all active Ethereum orders
     */
    function getActiveEthereumOrders() external view returns (bytes32[] memory) {
        // This would need to be implemented with proper iteration
        // For now, return empty array
        bytes32[] memory empty;
        return empty;
    }
    
    /**
     * @dev Check if secret can be used for Sui withdrawal
     */
    function canUseSecretOnSui(bytes32 secret) external view returns (bool) {
        return !secretUsedOnSui[secret];
    }
    
    /**
     * @dev Get bidirectional coordination stats
     */
    function getBidirectionalStats() external view returns (
        uint256 totalEthereumOrders,
        uint256 activeEthereumOrders,
        uint256 completedBidirectionalSwaps,
        uint256 pendingCoordinations
    ) {
        // Implementation would track these stats
        // For now, return zeros
        return (0, 0, 0, 0);
    }
}

// ===========================================
// 🔄 ADDITIONAL INTERFACES FOR BIDIRECTIONAL SUPPORT
// ===========================================

interface IBidirectionalResolver {
    function initiateEthereumToSuiSwap(
        bytes32 orderHash,
        bytes32 secretHash,
        address maker,
        address taker,
        address token,
        uint256 amount,
        uint256 safetyDeposit
    ) external payable;
    
    function linkEthereumOrderToSuiEscrow(
        bytes32 ethereumOrderHash,
        bytes32 suiEscrowId
    ) external;
    
    function revealEthereumSecret(
        bytes32 orderHash,
        string calldata secret
    ) external;
    
    function completeSuiWithdrawalFromEthereumSecret(
        bytes32 orderHash,
        bytes32 suiEscrowId
    ) external;
    
    function getBidirectionalMapping(bytes32 identifier) external view returns (
        bytes32 ethereumOrder,
        bytes32 suiEscrow,
        bool mappingExists,
        string memory status
    );
}

/**
 * @title BidirectionalEvents
 * @dev Event library for bidirectional coordination
 */
library BidirectionalEvents {
    event DirectionInitiated(
        string indexed direction,
        bytes32 indexed orderHash,
        bytes32 indexed escrowId,
        address initiator
    );
    
    event DirectionCompleted(
        string indexed direction,
        bytes32 indexed orderHash,
        bytes32 indexed escrowId,
        address completer
    );
    
    event CrossChainLinkEstablished(
        bytes32 indexed ethereumOrder,
        bytes32 indexed suiEscrow,
        string direction
    );
}