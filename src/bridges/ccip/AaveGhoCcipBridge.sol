// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC165} from 'openzeppelin-contracts/contracts/utils/introspection/IERC165.sol';
import {IERC20} from 'openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';
import {SafeERC20} from 'openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol';
import {Ownable} from 'aave-v3-origin/contracts/dependencies/openzeppelin/contracts/Ownable.sol';
import {Rescuable} from 'solidity-utils/contracts/utils/Rescuable.sol';
import {RescuableBase, IRescuableBase} from 'solidity-utils/contracts/utils/RescuableBase.sol';

import {Client} from 'src/dependencies/chainlink/libraries/Client.sol';
import {CCIPReceiver} from 'src/dependencies/chainlink/CCIPReceiver.sol';
import {IAny2EVMMessageReceiver} from 'src/dependencies/chainlink/interfaces/IAny2EVMMessageReceiver.sol';
import {IOnRampClient} from 'src/dependencies/chainlink/interfaces/IOnRampClient.sol';
import {IRouter} from 'src/dependencies/chainlink/interfaces/IRouter.sol';
import {IRouterClient} from 'src/dependencies/chainlink/interfaces/IRouterClient.sol';
import {ITokenPool} from 'src/dependencies/chainlink/interfaces/ITokenPool.sol';
import {IAaveGhoCcipBridge} from 'src/bridges/ccip/interfaces/IAaveGhoCcipBridge.sol';

/**
 * @title AaveGhoCcipBridge
 * @author TokenLogic
 * @notice Provides bridging capabilities for the GHO token across networks.
 * @dev The fee token must be pre-funded for the bridge message to be sent. When doing a governance
 * proposal ensure funds are present on this contract beforehand (GHO/LINK) or transfer funds from the
 * treasury as part of the proposal.
 */
contract AaveGhoCcipBridge is CCIPReceiver, Ownable, Rescuable, IAaveGhoCcipBridge {
  using SafeERC20 for IERC20;

  /// @inheritdoc IAaveGhoCcipBridge
  bytes32 public constant BRIDGER_ROLE = keccak256('BRIDGER_ROLE');

  /// @inheritdoc IAaveGhoCcipBridge
  uint256 public constant DEFAULT_GAS_LIMIT = 200_000;

  /// @inheritdoc IAaveGhoCcipBridge
  address public immutable GHO_TOKEN;

  /// @inheritdoc IAaveGhoCcipBridge
  address public immutable ROUTER;

  /// @inheritdoc IAaveGhoCcipBridge
  address public immutable COLLECTOR;

  /// @inheritdoc IAaveGhoCcipBridge
  mapping(uint64 chainSelector => RemoteChainConfig remoteConfig) public destinations;

  /// @dev Map containing failed token transfer amounts for a message
  mapping(bytes32 messageId => Client.EVMTokenAmount[] destTokenAmounts)
    private _failedTokenTransfers;

  /// @dev Map containing failed messages and their status
  mapping(bytes32 messageId => bool isFailed) private _failedMessages;

  /**
   * @dev Modifier to allow only the contract itself to execute a function.
   *      Throws an exception if called by any account other than the contract itself.
   */
  modifier onlySelf() {
    if (msg.sender != address(this)) revert OnlySelf();
    _;
  }

  /**
   * @dev Constructor
   * @param router The address of the Chainlink CCIP router
   * @param gho The address of the GHO token
   * @param collector The address of the Aave Collector
   * @param initialOwner The address of the initial admin
   */
  constructor(
    address router,
    address gho,
    address collector,
    address initialOwner
  ) CCIPReceiver(router) {
    ROUTER = router;
    GHO_TOKEN = gho;
    COLLECTOR = collector;

    transferOwnership(initialOwner);
  }

  /// @inheritdoc IAaveGhoCcipBridge
  function send(
    uint64 chainSelector,
    uint256 amount,
    address feeToken
  ) external payable onlyOwner returns (bytes32) {
    _validateDestinationAndLimit(chainSelector, amount);

    Client.EVM2AnyMessage memory message = _buildCCIPMessage(chainSelector, amount, feeToken);

    uint256 fee = IRouterClient(ROUTER).getFee(chainSelector, message);

    if (feeToken == address(0)) {
      if (msg.value < fee) revert InsufficientFee();
    } else {
      IERC20(feeToken).safeTransferFrom(msg.sender, address(this), fee);
      IERC20(feeToken).safeIncreaseAllowance(ROUTER, fee);
    }

    IERC20(GHO_TOKEN).safeTransferFrom(msg.sender, address(this), amount);
    IERC20(GHO_TOKEN).safeIncreaseAllowance(ROUTER, amount);

    bytes32 messageId = IRouterClient(ROUTER).ccipSend{value: feeToken == address(0) ? fee : 0}(
      chainSelector,
      message
    );

    emit BridgeMessageInitiated(messageId, chainSelector, msg.sender, amount);

    return messageId;
  }

  /// @inheritdoc CCIPReceiver
  function ccipReceive(Client.Any2EVMMessage calldata message) external override onlyRouter {
    try this.processMessage(message) {} catch (bytes memory err) {
      _failedMessages[message.messageId] = true;

      uint256 amountsLength = message.destTokenAmounts.length;
      for (uint256 i = 0; i < amountsLength; i++) {
        _failedTokenTransfers[message.messageId].push(message.destTokenAmounts[i]);
      }

      emit BridgeMessageFailed(message.messageId, err);
    }
  }

  /// @inheritdoc IAaveGhoCcipBridge
  function processMessage(Client.Any2EVMMessage calldata message) external onlySelf {
    if (
      keccak256(destinations[message.sourceChainSelector].destination) != keccak256(message.sender)
    ) {
      revert UnknownSourceDestination();
    }

    uint256 ghoAmount = message.destTokenAmounts[0].amount;
    IERC20(GHO_TOKEN).safeTransfer(COLLECTOR, ghoAmount);

    emit BridgeMessageFinalized(message.messageId, COLLECTOR, ghoAmount);
  }

  /// @inheritdoc IAaveGhoCcipBridge
  function recoverFailedMessageTokens(bytes32 messageId) external onlyOwner {
    _validateMessageExists(messageId);
    _failedMessages[messageId] = false;

    Client.EVMTokenAmount[] memory destTokenAmounts = _failedTokenTransfers[messageId];

    uint256 length = destTokenAmounts.length;
    for (uint256 i = 0; i < length; i++) {
      IERC20(destTokenAmounts[i].token).safeTransfer(COLLECTOR, destTokenAmounts[i].amount);
    }

    emit BridgeMessageRecovered(messageId);
  }

  /// @inheritdoc IAaveGhoCcipBridge
  function setDestinationChain(
    uint64 chainSelector,
    bytes calldata destination,
    bytes calldata extraArgs,
    uint32 gasLimit
  ) external onlyOwner {
    if (destination.length == 0) {
      revert InvalidZeroAddress();
    }

    destinations[chainSelector] = RemoteChainConfig({
      destination: destination,
      extraArgsOverride: extraArgs,
      gasLimit: gasLimit
    });

    emit DestinationChainSet(chainSelector, destination, gasLimit);
  }

  /// @inheritdoc IAaveGhoCcipBridge
  function removeDestinationChain(uint64 chainSelector) external onlyOwner {
    delete destinations[chainSelector];

    emit DestinationChainSet(chainSelector, bytes(''), 0);
  }

  /// @inheritdoc IAaveGhoCcipBridge
  function getInvalidMessage(
    bytes32 messageId
  ) external view returns (Client.EVMTokenAmount[] memory) {
    _validateMessageExists(messageId);
    return _failedTokenTransfers[messageId];
  }

  /// @inheritdoc IAaveGhoCcipBridge
  function getRateLimit(uint64 chainSelector) external view returns (uint128) {
    return _getRateLimit(chainSelector);
  }

  /// @inheritdoc IAaveGhoCcipBridge
  function quoteBridge(
    uint64 chainSelector,
    uint256 amount,
    address feeToken
  ) external view returns (uint256) {
    _validateDestinationAndLimit(chainSelector, amount);

    Client.EVM2AnyMessage memory message = _buildCCIPMessage(chainSelector, amount, feeToken);

    return IRouterClient(ROUTER).getFee(chainSelector, message);
  }

  /// @inheritdoc IRescuableBase
  function maxRescue(
    address token
  ) public view override(RescuableBase, IRescuableBase) returns (uint256) {
    return IERC20(token).balanceOf(address(this));
  }

  /// @inheritdoc Rescuable
  function whoCanRescue() public view override returns (address) {
    return owner();
  }

  /**
   * @dev See {IERC165-supportsInterface}.
   */
  function supportsInterface(
    bytes4 interfaceId
  ) public pure virtual override(CCIPReceiver) returns (bool) {
    return
      interfaceId == type(IAny2EVMMessageReceiver).interfaceId ||
      interfaceId == type(IERC165).interfaceId;
  }

  /// @inheritdoc CCIPReceiver
  /// @dev Intentionally left blank
  function _ccipReceive(Client.Any2EVMMessage memory message) internal override {}

  /**
   * @dev Builds ccip message for token transfer
   * @dev Some lanes must allow out of order execution due to technical constraints. Always best to allow.
   * See: https://docs.chain.link/ccip/concepts/best-practices/evm#setting-allowoutoforderexecution
   * @param chainSelector The chain selector of the destination chain
   * @param amount The amount of GHO to transfer
   * @param feeToken The address of the fee token (use address(0) for fee in native token)
   * @return message EVM2AnyMessage to transfer GHO cross-chain
   */
  function _buildCCIPMessage(
    uint64 chainSelector,
    uint256 amount,
    address feeToken
  ) internal view returns (Client.EVM2AnyMessage memory) {
    if (amount == 0) {
      revert InvalidZeroAmount();
    }

    Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
    tokenAmounts[0] = Client.EVMTokenAmount({token: GHO_TOKEN, amount: amount});

    RemoteChainConfig memory remoteConfig = destinations[chainSelector];

    Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
      receiver: remoteConfig.destination,
      data: '',
      tokenAmounts: tokenAmounts,
      extraArgs: remoteConfig.extraArgsOverride.length > 0
        ? remoteConfig.extraArgsOverride
        : Client._argsToBytes(
          Client.GenericExtraArgs({gasLimit: remoteConfig.gasLimit, allowOutOfOrderExecution: true})
        ),
      feeToken: feeToken
    });

    return message;
  }

  /**
   * @dev Returns the rate limit of a specified chain.
   * @param chainSelector The chain selector of the destination chain
   * @return The rate limit of the chain
   */
  function _getRateLimit(uint64 chainSelector) internal view returns (uint128) {
    address onRamp = IRouter(ROUTER).getOnRamp(chainSelector);
    ITokenPool tokenPool = ITokenPool(
      IOnRampClient(onRamp).getPoolBySourceToken(chainSelector, GHO_TOKEN)
    );
    (uint128 limit, , , , ) = tokenPool.getCurrentOutboundRateLimiterState(chainSelector);

    return limit;
  }

  /**
   * @dev Checks if the destination chain has been set up and amount exceeds the rate limit
   * @param chainSelector The chain selector of the destination chain
   * @param amount The amount of GHO to transfer
   */
  function _validateDestinationAndLimit(uint64 chainSelector, uint256 amount) internal view {
    if (destinations[chainSelector].destination.length == 0) {
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
    if (!_failedMessages[messageId]) revert MessageNotFound();
  }
}
