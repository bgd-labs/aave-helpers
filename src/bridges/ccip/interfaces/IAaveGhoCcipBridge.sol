// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Client} from "../chainlink/libraries/Client.sol";

/**
 * @title IAaveGhoCcipBridge
 * @author TokenLogic
 * @notice Defines the behaviour of an AaveGhoCcipBridge
 */
interface IAaveGhoCcipBridge {
    /**
     * @dev Insufficient fee paid for transfer
     */
    error InsufficientFee();

    /**
     * @dev Address cannot be the zero-address
     */
    error InvalidZeroAddress();

    /**
     * @dev Amount must be greater than zero
     */
    error InvalidZeroAmount();

    /**
     * @dev Function is only callable by self
     */
    error OnlySelf();

    /**
     * @dev The message with the specified ID cannot be found
     */
    error MessageNotFound();

    /**
     * @dev The bridge's rate limit has been exceeded
     */
    error RateLimitExceeded(uint256 limit);

    /**
     * @dev The source destination of the message is invalid
     */
    error UnknownSourceDestination();

    /**
     * @dev The destination chain is invalid
     */
    error UnsupportedChain();

    /**
     * @dev Emitted when a new GHO transfer is issued
     * @param messageId The ID of the cross-chain message
     * @param destinationChainSelector The selector of the destination chain
     * @param from The address of sender on source chain
     * @param amount The total amount of GHO transfered
     */
    event BridgeInitiated(
        bytes32 indexed messageId, uint64 indexed destinationChainSelector, address indexed from, uint256 amount
    );

    /**
     * @dev Emitted when the token transfer is executed on the destination chain
     * @param messageId The ID of the cross-chain message
     * @param to The address of receiver on destination chain
     * @param amount The amount of token to translated
     */
    event BridgeFinalized(bytes32 indexed messageId, address indexed to, uint256 amount);

    /**
     * @dev Emitted when the destination bridge data is updated
     * @param chainSelector The selector of the destination chain
     * @param bridge The address of the bridge on the destination chain
     */
    event DestinationChainSet(uint64 indexed chainSelector, address indexed bridge);

    /**
     * @dev Emitted when an invalid message is received by the bridge
     * @param messageId The ID of message
     * @param err The error on why the transfer failed
     */
    event FailedToFinalizeBridge(bytes32 indexed messageId, bytes err);

    /**
     * @dev Emits when receive invalid message
     * @param messageId The id of message
     */
    event RecoveredInvalidMessage(bytes32 indexed messageId);

    /**
     * @notice This role defines which users can call the send() function.
     * @return The bytes32 role identifier
     */
    function BRIDGER_ROLE() external view returns (bytes32);

    /**
     * @notice Returns the Chainlink CCIP router address
     * @return The address of the Chainlink CCIP router
     */
    function ROUTER() external view returns (address);

    /**
     * @notice Returns the GHO token address on the deployed chain.
     * @return The address of the GHO token contract
     */
    function GHO_TOKEN() external view returns (address);

    /**
     * @notice Returns the AaveCollector address on the deployed chain.
     * @return The address of the Collector contract
     */
    function COLLECTOR() external view returns (address);

    /**
     * @notice Returns the executor (governance) address on the deployed chain
     * @dev The executor has the DEFAULT_ADMIN_ROLE
     * @return The address of the Executor contract
     */
    function EXECUTOR() external view returns (address);

    /**
     * @notice Returns the address of the corresponding bridge for a specified chain selector.
     * @param chainSelector The chain selector of destination chain
     * @return The address of AaveGhoCcipBridge on destination chain
     */
    function destinations(uint64 chainSelector) external view returns (address);

    /**
     * @notice Transfers tokens to specified destination chain.
     * @dev chain selector can be found https://docs.chain.link/ccip/supported-networks/v1_2_0/mainnet
     * @param chainSelector The chain selector of the destination chain
     * @param amount The amount of GHO to transfer
     * @param gasLimit Gas limit for the callback on the destination chain. If this value is 0, default value is used
     * @param feeToken The address of the fee token to pay transfer with
     * @return The ID of the cross-chain message
     */
    function send(uint64 chainSelector, uint256 amount, uint256 gasLimit, address feeToken)
        external
        payable
        returns (bytes32);

    /**
     * @notice Wraps _ccipReceive() as an external function in order to leverage try/catch functionality.
     * @dev Only callable by the contract itself
     * @param message Struct containing the message's data
     */
    function processMessage(Client.Any2EVMMessage calldata message) external;

    /**
     * @notice Recovers tokens received via an invalid message
     * @dev Withdraws tokens included in invalid message to collector
     * @param messageId The ID of message received
     */
    function recoverFailedMessageTokens(bytes32 messageId) external;

    /**
     * @notice Sets a destination chain and corresponding bridge address.
     * @dev Only callable by ADMIN.
     * @param chainSelector The chain selector of the destination chain
     * @param bridge The address of the bridge on the destination chain
     */
    function setDestinationChain(uint64 chainSelector, address bridge) external;

    /**
     * @notice Removes a destination chain and corresponding bridge address.
     * @dev Only callable by ADMIN.
     * @param chainSelector The chain selector of the destination chain
     */
    function removeDestinationChain(uint64 chainSelector) external;

    /**
     * @notice Returns contents of specified invalid message.
     * @param messageId The ID of the message to query
     * @return Array of the message's tokens and amounts transferred
     */
    function getInvalidMessage(bytes32 messageId) external view returns (Client.EVMTokenAmount[] memory);

    /**
     * @dev Returns the bridge rate limit for a given chain.
     * @param chainSelector The chain selector of the destination chain
     * @return The rate limit of the chain
     */
    function getRateLimit(uint64 chainSelector) external view returns (uint128);

    /**
     * @notice Returns the fee amount cost to execute the bridge transfer.
     * @param chainSelector The chain selector of the destination chain
     * @param amount The amount of GHO to transfer
     * @param gasLimit Gas limit for the callback on the destination chain. If this value is 0, default value is used
     * @param feeToken The address of fee token to pay transfer with
     * @return The amount of fee tokens required
     */
    function quoteBridge(uint64 chainSelector, uint256 amount, uint256 gasLimit, address feeToken)
        external
        view
        returns (uint256);
}
