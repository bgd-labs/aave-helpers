// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC165} from "openzeppelin-contracts/contracts/utils/introspection/IERC165.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {
    AccessControl,
    IAccessControl
} from "aave-v3-origin/contracts/dependencies/openzeppelin/contracts/AccessControl.sol";
import {Rescuable} from "solidity-utils/contracts/utils/Rescuable.sol";
import {RescuableBase, IRescuableBase} from "solidity-utils/contracts/utils/RescuableBase.sol";

import {Client} from "./libraries/Client.sol";
import {CCIPReceiver} from "./CCIPReceiver.sol";
import {IAny2EVMMessageReceiver} from "./interfaces/IAny2EVMMessageReceiver.sol";
import {IOnRampClient} from "./interfaces/IOnRampClient.sol";
import {IRouter} from "./interfaces/IRouter.sol";
import {IRouterClient} from "./interfaces/IRouterClient.sol";
import {ITokenPool} from "./interfaces/ITokenPool.sol";
import {IAaveGhoCcipBridge} from "./interfaces/IAaveGhoCcipBridge.sol";

/**
 * @title AaveGhoCcipBridge
 * @author TokenLogic
 * @notice It provides bridging capabilities for the GHO token across networks.
 *
 * -- Permissions
 * The contract implements AccessControl for permissioned functions.
 * The DEFAULT_ADMIN will always be the respective network's Short Executor (Governance).
 * The BRIDGER_ROLE will be given to "Facilitator" type contracts to mint and then bridge GHO.
 *
 * -- Security Considerations
 * A new destination chain and corresponding bridge contract must be previously pre-approved by governance.
 * The contract inherits from `Rescuable`. Using the inherited functions it can transfer tokens out from this contract.
 * In the case of malformed or invalid messages, the contract implements a rescue mechanism to send tokens to the Collector contract,
 * following CCIP's defensive approach as shown here:
 * https://github.com/smartcontractkit/chainlink/blob/62c23768cd483b179301625603a785dd773f2c78/contracts/src/v0.8/ccip/applications/DefensiveExample.sol
 *
 * -- Destination Chains
 * The chain selector for a given chain is defined by CCIP. The list of chain selectors can be found here:
 * https://docs.chain.link/ccip/directory/mainnet
 */
contract AaveGhoCcipBridge is CCIPReceiver, AccessControl, Rescuable, IAaveGhoCcipBridge {
    using SafeERC20 for IERC20;

    /// @inheritdoc IAaveGhoCcipBridge
    bytes32 public constant BRIDGER_ROLE = keccak256("BRIDGER_ROLE");

    /// @inheritdoc IAaveGhoCcipBridge
    address public immutable GHO_TOKEN;

    /// @inheritdoc IAaveGhoCcipBridge
    address public immutable ROUTER;

    /// @inheritdoc IAaveGhoCcipBridge
    address public immutable COLLECTOR;

    /// @inheritdoc IAaveGhoCcipBridge
    address public immutable EXECUTOR;

    /// @inheritdoc IAaveGhoCcipBridge
    mapping(uint64 chainSelector => address bridge) public destinations;

    /// @dev Map containing failed token transfer amounts for a message
    mapping(bytes32 messageId => Client.Any2EVMMessage message) private failedTokenTransfers;

    /// @dev Map containing failed messages and their status
    mapping(bytes32 messageId => bool isFailed) private failedMessages;

    /**
     * @dev Modifier to allow only the contract itself to execute a function.
     *      Throws an exception if called by any account other than the contract itself.
     */
    modifier onlySelf() {
        if (msg.sender != address(this)) revert OnlySelf();
        _;
    }

    /**
     * @param router The address of the Chainlink CCIP router
     * @param gho The address of the GHO token
     * @param collector The address of collector on same chain
     * @param executor The address of the contract executor
     */
    constructor(address router, address gho, address collector, address executor) CCIPReceiver(router) {
        ROUTER = router;
        GHO_TOKEN = gho;
        COLLECTOR = collector;
        EXECUTOR = executor;

        _setupRole(DEFAULT_ADMIN_ROLE, executor);
    }

    /// @inheritdoc IAaveGhoCcipBridge
    function send(uint64 chainSelector, uint256 amount, uint256 gasLimit, address feeToken)
        external
        payable
        onlyRole(BRIDGER_ROLE)
        returns (bytes32)
    {
        _validateDestinationAndLimit(chainSelector, amount);
        Client.EVM2AnyMessage memory message = _buildCCIPMessage(chainSelector, amount, gasLimit, feeToken);

        uint256 fee = IRouterClient(ROUTER).getFee(chainSelector, message);

        if (feeToken == address(0)) {
            if (msg.value < fee) revert InsufficientFee();
        } else {
            IERC20(feeToken).transferFrom(msg.sender, address(this), fee);
            IERC20(feeToken).safeIncreaseAllowance(ROUTER, fee);
        }

        IERC20(GHO_TOKEN).transferFrom(msg.sender, address(this), amount);
        IERC20(GHO_TOKEN).safeIncreaseAllowance(ROUTER, amount);

        bytes32 messageId =
            IRouterClient(ROUTER).ccipSend{value: feeToken == address(0) ? fee : 0}(chainSelector, message);

        emit BridgeInitiated(messageId, chainSelector, msg.sender, amount);

        return messageId;
    }

    /// @inheritdoc CCIPReceiver
    function ccipReceive(Client.Any2EVMMessage calldata message) external override onlyRouter {
        try this.processMessage(message) {}
        catch (bytes memory err) {
            failedMessages[message.messageId] = true;
            failedTokenTransfers[message.messageId] = message;

            emit FailedToFinalizeBridge(message.messageId, err);
        }
    }

    /// @inheritdoc IAaveGhoCcipBridge
    function processMessage(Client.Any2EVMMessage calldata message) external onlySelf {
        if (destinations[message.sourceChainSelector] != abi.decode(message.sender, (address))) {
            revert UnknownSourceDestination();
        }

        _ccipReceive(message);
    }

    /// @inheritdoc IAaveGhoCcipBridge
    function recoverFailedMessageTokens(bytes32 messageId) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _validateMessageExists(messageId);
        failedMessages[messageId] = false;

        Client.Any2EVMMessage memory message = failedTokenTransfers[messageId];

        uint256 length = message.destTokenAmounts.length;
        for (uint256 i = 0; i < length; i++) {
            IERC20(message.destTokenAmounts[i].token).safeTransfer(COLLECTOR, message.destTokenAmounts[i].amount);
        }

        emit RecoveredInvalidMessage(messageId);
    }

    /// @inheritdoc IAaveGhoCcipBridge
    function setDestinationChain(uint64 chainSelector, address bridge) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (bridge == address(0)) {
            revert InvalidZeroAddress();
        }

        destinations[chainSelector] = bridge;

        emit DestinationChainSet(chainSelector, bridge);
    }

    /// @inheritdoc IAaveGhoCcipBridge
    function removeDestinationChain(uint64 chainSelector) external onlyRole(DEFAULT_ADMIN_ROLE) {
        delete destinations[chainSelector];

        emit DestinationChainRemoved(chainSelector);
    }

    /// @inheritdoc IAaveGhoCcipBridge
    function getInvalidMessage(bytes32 messageId) external view returns (Client.EVMTokenAmount[] memory) {
        _validateMessageExists(messageId);
        return failedTokenTransfers[messageId].destTokenAmounts;
    }

    /// @inheritdoc IAaveGhoCcipBridge
    function getRateLimit(uint64 chainSelector) external view returns (uint128) {
        return _getRateLimit(chainSelector);
    }

    /// @inheritdoc IAaveGhoCcipBridge
    function quoteBridge(uint64 chainSelector, uint256 amount, uint256 gasLimit, address feeToken)
        external
        view
        returns (uint256)
    {
        _validateDestinationAndLimit(chainSelector, amount);

        Client.EVM2AnyMessage memory message = _buildCCIPMessage(chainSelector, amount, gasLimit, feeToken);

        return IRouterClient(ROUTER).getFee(chainSelector, message);
    }

    /// @inheritdoc IRescuableBase
    function maxRescue(address token) public view override(RescuableBase, IRescuableBase) returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }

    /// @inheritdoc Rescuable
    function whoCanRescue() public view override returns (address) {
        return EXECUTOR;
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId)
        public
        pure
        virtual
        override(AccessControl, CCIPReceiver)
        returns (bool)
    {
        return interfaceId == type(IAccessControl).interfaceId
            || interfaceId == type(IAny2EVMMessageReceiver).interfaceId || interfaceId == type(IERC165).interfaceId;
    }

    /**
     * @dev Builds ccip message for token transfer
     * @param chainSelector The chain selector of the destination chain
     * @param amount The amount of GHO to transfer
     * @param gasLimit The gas limit on the destination chain
     * @param feeToken The address of the fee token (use address(0) for fee in native token)
     * @return message EVM2AnyMessage to transfer GHO cross-chain
     */
    function _buildCCIPMessage(uint64 chainSelector, uint256 amount, uint256 gasLimit, address feeToken)
        internal
        view
        returns (Client.EVM2AnyMessage memory)
    {
        if (amount == 0) {
            revert InvalidZeroAmount();
        }

        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({token: GHO_TOKEN, amount: amount});

        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(destinations[chainSelector]),
            data: "",
            tokenAmounts: tokenAmounts,
            extraArgs: gasLimit == 0
                ? bytes("")
                : Client._argsToBytes(Client.EVMExtraArgsV2({gasLimit: gasLimit, allowOutOfOrderExecution: false})),
            feeToken: feeToken
        });

        return message;
    }

    /// @inheritdoc CCIPReceiver
    function _ccipReceive(Client.Any2EVMMessage memory message) internal override {
        uint256 ghoAmount = message.destTokenAmounts[0].amount;

        IERC20(GHO_TOKEN).transfer(COLLECTOR, ghoAmount);

        emit BridgeFinalized(message.messageId, COLLECTOR, ghoAmount);
    }

    /**
     * @dev Returns the rate limit of a specified chain.
     * @param chainSelector The chain selector of the destination chain
     * @return The rate limit of the chain
     */
    function _getRateLimit(uint64 chainSelector) internal view returns (uint128) {
        address onRamp = IRouter(ROUTER).getOnRamp(chainSelector);
        ITokenPool tokenPool = ITokenPool(IOnRampClient(onRamp).getPoolBySourceToken(chainSelector, GHO_TOKEN));
        (uint128 limit,,,,) = tokenPool.getCurrentOutboundRateLimiterState(chainSelector);

        return limit;
    }

    /**
     * @dev Checks if the destination chain has been set up and amount exceeds the rate limit
     * @param chainSelector The chain selector of the destination chain
     * @param amount The amount of GHO to transfer
     */
    function _validateDestinationAndLimit(uint64 chainSelector, uint256 amount) internal view {
        if (destinations[chainSelector] == address(0)) {
            revert UnsupportedChain();
        }

        uint128 limit = _getRateLimit(chainSelector);
        if (amount > limit) {
            revert RateLimitExceeded(limit);
        }
    }

    /**
     * @dev Checks if invalid message exists
     * @param messageId The message ID to validate
     */
    function _validateMessageExists(bytes32 messageId) internal view {
        if (!failedMessages[messageId]) revert MessageNotFound();
    }
}
