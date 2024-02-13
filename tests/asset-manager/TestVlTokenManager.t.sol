// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {Test} from 'forge-std/Test.sol';
import {AaveGovernanceV2} from 'aave-address-book/AaveGovernanceV2.sol';
import {AaveV3EthereumAssets} from 'aave-address-book/AaveV3Ethereum.sol';
import {IERC20} from 'solidity-utils/contracts/oz-common/interfaces/IERC20.sol';

import {IQuestDistributor, IQuestDelegationDistributor} from '../../src/asset-manager/interfaces/IQuestDistributor.sol';
import {QuestVoteType, QuestRewardsType, QuestCloseType, IQuestBoard} from '../../src/asset-manager/interfaces/IQuestBoard.sol';
import {IVlToken} from '../../src/asset-manager/interfaces/IVlToken.sol';
import {StrategicAssetsManager} from '../../src/asset-manager/StrategicAssetsManager.sol';
import {VlTokenManager} from '../../src/asset-manager/VlTokenManager.sol';
import {Common} from '../../src/asset-manager/Common.sol';

contract VlTokenManagerTest is Test {
  event ClaimVLAURARewards();
  event DelegatedVLAURA(address newDelegate);
  event EmergencyWithdraw(uint256 tokensUnlocked);
  event LockVLAURA(uint256 cummulativeTokensLocked, uint256 lockHorizon);
  event RelockVLAURA(uint256 cumulativeTokensLocked);
  event UnlockVLAURA(uint256 tokensUnlocked);

  address public constant AURA = 0xC0c293ce456fF0ED870ADd98a0828Dd4d2903DBF;
  address public constant VL_AURA = 0x3Fa73f1E5d8A792C80F426fc8F84FBF7Ce9bBCAC;
  address public constant AURA_BAL = 0x616e8BfA43F920657B3497DBf40D6b1A02D4608d;
  address public constant VL_AURA_OWNER = 0x5feA4413E3Cc5Cf3A29a49dB41ac0c24850417a0;

  StrategicAssetsManager public strategicAssets;

  function setUp() public {
    vm.createSelectFork(vm.rpcUrl('mainnet'), 19138307);

    vm.startPrank(AaveGovernanceV2.SHORT_EXECUTOR);
    strategicAssets = new StrategicAssetsManager();
    vm.stopPrank();
  }
}

contract QuestBoardTest is VlTokenManagerTest {
  error AddressZero();
  error CallerNotAllowed();
  error IncorrectAddDuration();
  error IncorrectDuration();
  error IncorrectFeeAmount();
  error InvalidQuestID();
  error InvalidQuestType();
  error MinValueOverMaxValue();
  error NullAmount();
  error RewardPerVoteTooLow();
  error TokenNotWhitelisted();

  event ExtendQuestDuration(uint256 indexed questID, uint256 addedDuration, uint256 addedRewardAmount);

  uint256 MIN_REWARD_PER_VOTE_AURA = 1500000000000000;

  address public constant GAUGE = 0x21c377cBB2bEdDd8534308E5CdfeBE35fDF817E8;
}

contract LockVLAURATest is VlTokenManagerTest {
  function test_revertsIf_invalidCaller() public {
    vm.expectRevert('ONLY_BY_OWNER_OR_GUARDIAN');
    strategicAssets.lockVLAURA(1_000e18);
  }

  function test_revertsIf_insufficientBalance() public {
    vm.startPrank(AaveGovernanceV2.SHORT_EXECUTOR);
    vm.expectRevert('ERC20: transfer amount exceeds balance');
    strategicAssets.lockVLAURA(1_000e18);
    vm.stopPrank();
  }

  function test_successful() public {
    deal(AURA, address(strategicAssets), 1_000e18);
    vm.startPrank(AaveGovernanceV2.SHORT_EXECUTOR);
    vm.expectEmit();
    emit LockVLAURA(1_000e18, 1717129271);
    strategicAssets.lockVLAURA(1_000e18);
    vm.stopPrank();

    (uint256 lockedBalance, , , ) = IVlToken(VL_AURA).lockedBalances(address(strategicAssets));
    assertEq(lockedBalance, 1_000e18);
  }
}

contract RelockVLAURATest is VlTokenManagerTest {
  function test_revertsIf_invalidCaller() public {
    vm.expectRevert('ONLY_BY_OWNER_OR_GUARDIAN');
    strategicAssets.relockVLAURA();
  }

  function test_revertsIf_noLocks() public {
    vm.startPrank(AaveGovernanceV2.SHORT_EXECUTOR);
    vm.expectRevert('no locks');
    strategicAssets.relockVLAURA();
    vm.stopPrank();
  }

  function test_revertsIf_noExpiredLocks() public {
    deal(AURA, address(strategicAssets), 1_000e18);
    vm.startPrank(AaveGovernanceV2.SHORT_EXECUTOR);
    vm.expectEmit();
    emit LockVLAURA(1_000e18, 1717129271);
    strategicAssets.lockVLAURA(1_000e18);

    vm.expectRevert('no exp locks');
    strategicAssets.relockVLAURA();
    vm.stopPrank();
  }

  function test_successful() public {
    uint256 amount = 1_000e18;
    deal(AURA, address(strategicAssets), amount);

    assertEq(IERC20(AURA).balanceOf(address(strategicAssets)), amount);
    vm.startPrank(AaveGovernanceV2.SHORT_EXECUTOR);
    vm.expectEmit();
    emit LockVLAURA(amount, 1717129271);
    strategicAssets.lockVLAURA(amount);

    vm.warp(block.timestamp + IVlToken(VL_AURA).lockDuration());

    strategicAssets.relockVLAURA();
    vm.stopPrank();

    // No AURA Unlocked
    assertEq(IERC20(AURA).balanceOf(address(strategicAssets)), 0);
  }
}

contract UnlockVLAURATest is VlTokenManagerTest {
  function test_revertsIf_invalidCaller() public {
    vm.expectRevert('ONLY_BY_OWNER_OR_GUARDIAN');
    strategicAssets.unlockVLAURA();
  }

  function test_revertsIf_noLocks() public {
    vm.startPrank(AaveGovernanceV2.SHORT_EXECUTOR);
    vm.expectRevert('no locks');
    strategicAssets.unlockVLAURA();
    vm.stopPrank();
  }

  function test_revertsIf_noExpiredLocks() public {
    deal(AURA, address(strategicAssets), 1_000e18);
    vm.startPrank(AaveGovernanceV2.SHORT_EXECUTOR);
    vm.expectEmit();
    emit LockVLAURA(1_000e18, 1717129271);
    strategicAssets.lockVLAURA(1_000e18);

    vm.expectRevert('no exp locks');
    strategicAssets.unlockVLAURA();
    vm.stopPrank();
  }

  function test_successful() public {
    uint256 amount = 1_000e18;
    deal(AURA, address(strategicAssets), amount);

    assertEq(IERC20(AURA).balanceOf(address(strategicAssets)), amount);
    vm.startPrank(AaveGovernanceV2.SHORT_EXECUTOR);
    vm.expectEmit();
    emit LockVLAURA(amount, 1717129271);
    strategicAssets.lockVLAURA(amount);

    // AURA Locked
    assertEq(IERC20(AURA).balanceOf(address(strategicAssets)), 0);

    vm.warp(block.timestamp + IVlToken(VL_AURA).lockDuration());

    strategicAssets.unlockVLAURA();
    vm.stopPrank();

    // AURA unlocked
    assertEq(IERC20(AURA).balanceOf(address(strategicAssets)), amount);
  }
}

contract DelegateVLAURATest is VlTokenManagerTest {
  function test_revertsIf_invalidCaller() public {
    address delegatee = makeAddr('delegatee');

    vm.expectRevert('ONLY_BY_OWNER_OR_GUARDIAN');
    strategicAssets.delegateVLAURA(delegatee);
  }

  function test_revertsIf_nothingToDelegate() public {
    address delegatee = makeAddr('delegatee');

    vm.startPrank(AaveGovernanceV2.SHORT_EXECUTOR);
    vm.expectRevert('Nothing to delegate');
    strategicAssets.delegateVLAURA(delegatee);
    vm.stopPrank();
  }

  function test_revertsIf_successful() public {
    deal(AURA, address(strategicAssets), 1_000e18);
    address delegatee = makeAddr('delegatee');

    vm.startPrank(AaveGovernanceV2.SHORT_EXECUTOR);
    strategicAssets.lockVLAURA(1_000e18);

    vm.expectEmit();
    emit DelegatedVLAURA(delegatee);
    strategicAssets.delegateVLAURA(delegatee);
    vm.stopPrank();

    assertEq(delegatee, IVlToken(VL_AURA).delegates(address(strategicAssets)));
  }
}

contract ClaimVLAURARewardsTest is VlTokenManagerTest {
  function test_revertsIf_invalidCaller() public {
    vm.expectRevert('ONLY_BY_OWNER_OR_GUARDIAN');
    strategicAssets.claimVLAURARewards();
  }

  function test_successful() public {
    deal(AURA, address(strategicAssets), 1_000e18);

    assertEq(IERC20(AURA_BAL).balanceOf(address(strategicAssets)), 0);

    vm.startPrank(AaveGovernanceV2.SHORT_EXECUTOR);
    strategicAssets.lockVLAURA(1_000e18);

    vm.warp(block.timestamp + IVlToken(VL_AURA).lockDuration());

    vm.expectEmit();
    emit ClaimVLAURARewards();
    strategicAssets.claimVLAURARewards();
    vm.stopPrank();

    assertGt(IERC20(AURA_BAL).balanceOf(address(strategicAssets)), 0);
  }
}

contract EmergencyWithdrawVLAURA is VlTokenManagerTest {
  function test_revertsIf_invalidCaller() public {
    vm.expectRevert('ONLY_BY_OWNER_OR_GUARDIAN');
    strategicAssets.emergencyWithdrawVLAURA();
  }

  function test_successful() public {
    uint256 amount = 1_000e18;
    deal(AURA, address(strategicAssets), amount);

    assertEq(IERC20(AURA).balanceOf(address(strategicAssets)), amount);
    assertEq(IERC20(VL_AURA).balanceOf(address(strategicAssets)), 0);

    vm.startPrank(AaveGovernanceV2.SHORT_EXECUTOR);
    strategicAssets.lockVLAURA(amount);
    vm.stopPrank();

    assertEq(IERC20(AURA).balanceOf(address(strategicAssets)), 0);
    (uint256 lockedBalance, , , ) = IVlToken(VL_AURA).lockedBalances(address(strategicAssets));
    assertEq(lockedBalance, 1_000e18);

    vm.warp(block.timestamp + IVlToken(VL_AURA).lockDuration());

    vm.startPrank(VL_AURA_OWNER);
    IVlToken(VL_AURA).shutdown();
    vm.stopPrank();

    vm.startPrank(AaveGovernanceV2.SHORT_EXECUTOR);
    strategicAssets.emergencyWithdrawVLAURA();
    vm.stopPrank();

    assertEq(IERC20(AURA).balanceOf(address(strategicAssets)), amount);
    (uint256 lockedBalanceAfterWithdraw, , , ) = IVlToken(VL_AURA).lockedBalances(
      address(strategicAssets)
    );
    assertEq(lockedBalanceAfterWithdraw, 0);
  }
}

contract CreateFixedQuest is QuestBoardTest {
  function test_revertsIf_invalidCaller() public {
    address[] memory voterList = new address[](0);
    vm.expectRevert('ONLY_BY_OWNER_OR_GUARDIAN');
    strategicAssets.createFixedQuest(
      address(0),
      address(0),
      true,
      2,
      100,
      100e18,
      500,
      QuestVoteType.NORMAL,
      QuestCloseType.NORMAL,
      voterList
    );
  }

  function test_revertsIf_gaugeIsAddressZeroAddress() public {
    address[] memory voterList = new address[](0);
    vm.expectRevert(AddressZero.selector);
    vm.startPrank(AaveGovernanceV2.SHORT_EXECUTOR);
    strategicAssets.createFixedQuest(
      address(0),
      AURA,
      true,
      2,
      100,
      100e18,
      500,
      QuestVoteType.NORMAL,
      QuestCloseType.NORMAL,
      voterList
    );
    vm.stopPrank();
  }

  function test_revertsIf_rewardTokenIsZeroAddress() public {
    address[] memory voterList = new address[](0);
    vm.expectRevert(Common.InvalidZeroAddress.selector);
    vm.startPrank(AaveGovernanceV2.SHORT_EXECUTOR);
    strategicAssets.createFixedQuest(
      GAUGE,
      address(0),
      true,
      2,
      100,
      100e18,
      500,
      QuestVoteType.NORMAL,
      QuestCloseType.NORMAL,
      voterList
    );
    vm.stopPrank();
  }

  function test_revertsIf_rewardIsTooLow() public {
    address[] memory voterList = new address[](0);
    vm.expectRevert(RewardPerVoteTooLow.selector);
    vm.startPrank(AaveGovernanceV2.SHORT_EXECUTOR);
    strategicAssets.createFixedQuest(
      GAUGE,
      AURA,
      true,
      2,
      100,
      100e18,
      500,
      QuestVoteType.NORMAL,
      QuestCloseType.NORMAL,
      voterList
    );
    vm.stopPrank();
  }

  function test_revertsIf_tokenNotAllowed() public {
    address[] memory voterList = new address[](0);
    vm.expectRevert(TokenNotWhitelisted.selector);
    vm.startPrank(AaveGovernanceV2.SHORT_EXECUTOR);
    strategicAssets.createFixedQuest(
      GAUGE,
      AaveV3EthereumAssets.ONE_INCH_UNDERLYING,
      true,
      2,
      100,
      100e18,
      500,
      QuestVoteType.NORMAL,
      QuestCloseType.NORMAL,
      voterList
    );
    vm.stopPrank();
  }

  function test_revertsIf_invalidDuration() public {
    address[] memory voterList = new address[](0);
    vm.expectRevert(IncorrectDuration.selector);
    vm.startPrank(AaveGovernanceV2.SHORT_EXECUTOR);
    strategicAssets.createFixedQuest(
      GAUGE,
      AURA,
      true,
      0,
      100,
      100e18,
      500,
      QuestVoteType.NORMAL,
      QuestCloseType.NORMAL,
      voterList
    );
    vm.stopPrank();
  }

  function test_revertsIf_nullAmount() public {
    address[] memory voterList = new address[](0);
    vm.expectRevert(NullAmount.selector);
    vm.startPrank(AaveGovernanceV2.SHORT_EXECUTOR);
    strategicAssets.createFixedQuest(
      GAUGE,
      AURA,
      true,
      2,
      MIN_REWARD_PER_VOTE_AURA,
      0,
      500,
      QuestVoteType.NORMAL,
      QuestCloseType.NORMAL,
      voterList
    );
    vm.stopPrank();
  }

  function test_revertsIf_incorrectFeeAmount() public {
    address[] memory voterList = new address[](0);
    vm.expectRevert(IncorrectFeeAmount.selector);
    vm.startPrank(AaveGovernanceV2.SHORT_EXECUTOR);
    strategicAssets.createFixedQuest(
      GAUGE,
      AURA,
      true,
      2,
      MIN_REWARD_PER_VOTE_AURA,
      100 ether,
      500,
      QuestVoteType.NORMAL,
      QuestCloseType.NORMAL,
      voterList
    );
    vm.stopPrank();
  }

  function test_revertsIf_notEnoughBalance() public {
    address[] memory voterList = new address[](0);
    vm.expectRevert('ERC20: transfer amount exceeds balance');
    vm.startPrank(AaveGovernanceV2.SHORT_EXECUTOR);
    strategicAssets.createFixedQuest(
      GAUGE,
      AURA,
      true,
      2,
      MIN_REWARD_PER_VOTE_AURA,
      100 ether,
      4 ether,
      QuestVoteType.NORMAL,
      QuestCloseType.NORMAL,
      voterList
    );
    vm.stopPrank();
  }

  function test_successful() public {
    deal(AURA, address(strategicAssets), 1_000 ether);

    address[] memory voterList = new address[](0);

    uint256 nextId = IQuestBoard(strategicAssets.QUESTBOARD_VEBAL()).nextID();

    vm.startPrank(AaveGovernanceV2.SHORT_EXECUTOR);
    uint256 createdId = strategicAssets.createFixedQuest(
      GAUGE,
      AURA,
      true,
      2,
      MIN_REWARD_PER_VOTE_AURA,
      100 ether,
      4 ether,
      QuestVoteType.NORMAL,
      QuestCloseType.NORMAL,
      voterList
    );
    vm.stopPrank();

    assertEq(nextId, createdId);
  }
}

contract CreateRangedQuest is QuestBoardTest {
  function test_revertsIf_invalidCaller() public {
    address[] memory voterList = new address[](0);
    vm.expectRevert('ONLY_BY_OWNER_OR_GUARDIAN');
    strategicAssets.createRangedQuest(
      address(0),
      address(0),
      true,
      2,
      100,
      500,
      100e18,
      500,
      QuestVoteType.NORMAL,
      QuestCloseType.NORMAL,
      voterList
    );
  }

  function test_revertsIf_gaugeIsAddressZeroAddress() public {
    address[] memory voterList = new address[](0);
    vm.expectRevert(AddressZero.selector);
    vm.startPrank(AaveGovernanceV2.SHORT_EXECUTOR);
    strategicAssets.createRangedQuest(
      address(0),
      AURA,
      true,
      2,
      100,
      200,
      100e18,
      500,
      QuestVoteType.NORMAL,
      QuestCloseType.NORMAL,
      voterList
    );
    vm.stopPrank();
  }

  function test_revertsIf_rewardTokenIsZeroAddress() public {
    address[] memory voterList = new address[](0);
    vm.expectRevert(Common.InvalidZeroAddress.selector);
    vm.startPrank(AaveGovernanceV2.SHORT_EXECUTOR);
    strategicAssets.createRangedQuest(
      GAUGE,
      address(0),
      true,
      2,
      100,
      200,
      100e18,
      500,
      QuestVoteType.NORMAL,
      QuestCloseType.NORMAL,
      voterList
    );
    vm.stopPrank();
  }

  function test_revertsIf_rewardIsTooLow() public {
    address[] memory voterList = new address[](0);
    vm.expectRevert(RewardPerVoteTooLow.selector);
    vm.startPrank(AaveGovernanceV2.SHORT_EXECUTOR);
    strategicAssets.createRangedQuest(
      GAUGE,
      AURA,
      true,
      2,
      100,
      200,
      100e18,
      500,
      QuestVoteType.NORMAL,
      QuestCloseType.NORMAL,
      voterList
    );
    vm.stopPrank();
  }

  function test_revertsIf_tokenNotAllowed() public {
    address[] memory voterList = new address[](0);
    vm.expectRevert(TokenNotWhitelisted.selector);
    vm.startPrank(AaveGovernanceV2.SHORT_EXECUTOR);
    strategicAssets.createRangedQuest(
      GAUGE,
      AaveV3EthereumAssets.ONE_INCH_UNDERLYING,
      true,
      2,
      100,
      200,
      100e18,
      500,
      QuestVoteType.NORMAL,
      QuestCloseType.NORMAL,
      voterList
    );
    vm.stopPrank();
  }

  function test_revertsIf_invalidDuration() public {
    address[] memory voterList = new address[](0);
    vm.expectRevert(IncorrectDuration.selector);
    vm.startPrank(AaveGovernanceV2.SHORT_EXECUTOR);
    strategicAssets.createRangedQuest(
      GAUGE,
      AURA,
      true,
      0,
      100,
      200,
      100e18,
      500,
      QuestVoteType.NORMAL,
      QuestCloseType.NORMAL,
      voterList
    );
    vm.stopPrank();
  }

  function test_revertsIf_nullAmount() public {
    address[] memory voterList = new address[](0);
    vm.expectRevert(NullAmount.selector);
    vm.startPrank(AaveGovernanceV2.SHORT_EXECUTOR);
    strategicAssets.createRangedQuest(
      GAUGE,
      AURA,
      true,
      2,
      MIN_REWARD_PER_VOTE_AURA,
      200,
      0,
      500,
      QuestVoteType.NORMAL,
      QuestCloseType.NORMAL,
      voterList
    );
    vm.stopPrank();
  }

  function test_revertsIf_incorrectFeeAmount() public {
    address[] memory voterList = new address[](0);
    vm.expectRevert(IncorrectFeeAmount.selector);
    vm.startPrank(AaveGovernanceV2.SHORT_EXECUTOR);
    strategicAssets.createRangedQuest(
      GAUGE,
      AURA,
      true,
      2,
      MIN_REWARD_PER_VOTE_AURA,
      MIN_REWARD_PER_VOTE_AURA + 10000,
      100 ether,
      500,
      QuestVoteType.NORMAL,
      QuestCloseType.NORMAL,
      voterList
    );
    vm.stopPrank();
  }

  function test_revertsIf_minValueOverMaxValue() public {
    address[] memory voterList = new address[](0);
    vm.expectRevert(MinValueOverMaxValue.selector);
    vm.startPrank(AaveGovernanceV2.SHORT_EXECUTOR);
    strategicAssets.createRangedQuest(
      GAUGE,
      AURA,
      true,
      2,
      MIN_REWARD_PER_VOTE_AURA,
      200,
      100 ether,
      4 ether,
      QuestVoteType.NORMAL,
      QuestCloseType.NORMAL,
      voterList
    );
    vm.stopPrank();
  }

  function test_revertsIf_notEnoughBalance() public {
    address[] memory voterList = new address[](0);
    vm.expectRevert('ERC20: transfer amount exceeds balance');
    vm.startPrank(AaveGovernanceV2.SHORT_EXECUTOR);
    strategicAssets.createRangedQuest(
      GAUGE,
      AURA,
      true,
      2,
      MIN_REWARD_PER_VOTE_AURA,
      MIN_REWARD_PER_VOTE_AURA + 10000,
      100 ether,
      4 ether,
      QuestVoteType.NORMAL,
      QuestCloseType.NORMAL,
      voterList
    );
    vm.stopPrank();
  }

  function test_successful() public {
    deal(AURA, address(strategicAssets), 1_000 ether);

    address[] memory voterList = new address[](0);

    uint256 nextId = IQuestBoard(strategicAssets.QUESTBOARD_VEBAL()).nextID();

    vm.startPrank(AaveGovernanceV2.SHORT_EXECUTOR);
    uint256 createdId = strategicAssets.createRangedQuest(
      GAUGE,
      AURA,
      true,
      2,
      MIN_REWARD_PER_VOTE_AURA,
      MIN_REWARD_PER_VOTE_AURA + 10000,
      100 ether,
      4 ether,
      QuestVoteType.NORMAL,
      QuestCloseType.NORMAL,
      voterList
    );
    vm.stopPrank();

    assertEq(nextId, createdId);
  }
}

contract ExtendQuestDurationTest is QuestBoardTest {
  function test_revertsIf_invalidCaller() public {
    vm.expectRevert('ONLY_BY_OWNER_OR_GUARDIAN');
    strategicAssets.extendQuestDuration(
      1,
      address(0),
      100,
      100,
      500
    );
  }

  function test_revertsIf_invalidQuestId() public {
    vm.expectRevert(InvalidQuestID.selector);
    vm.startPrank(AaveGovernanceV2.SHORT_EXECUTOR);
    strategicAssets.extendQuestDuration(
      10000,
      AURA,
      100,
      100,
      500
    );
  }

  function test_revertsIf_invalidCreator() public {
    uint256 id = IQuestBoard(strategicAssets.QUESTBOARD_VEBAL()).nextID() - 1;
    vm.expectRevert(CallerNotAllowed.selector);
    vm.startPrank(AaveGovernanceV2.SHORT_EXECUTOR);
    strategicAssets.extendQuestDuration(
      id,
      AURA,
      100,
      100,
      500
    );
  }

  function test_revertsIf_invalidRewardTokenZeroAddress() public {
    vm.expectRevert(Common.InvalidZeroAddress.selector);
    vm.startPrank(AaveGovernanceV2.SHORT_EXECUTOR);
    strategicAssets.extendQuestDuration(
      1,
      address(0),
      100,
      100,
      500
    );
  }

  function test_revertsIf_invalidAddedDuration() public {
    deal(AURA, address(strategicAssets), 1_000 ether);

    address[] memory voterList = new address[](0);

    vm.startPrank(AaveGovernanceV2.SHORT_EXECUTOR);
    uint256 createdId = strategicAssets.createRangedQuest(
      GAUGE,
      AURA,
      true,
      2,
      MIN_REWARD_PER_VOTE_AURA,
      MIN_REWARD_PER_VOTE_AURA + 10000,
      100 ether,
      4 ether,
      QuestVoteType.NORMAL,
      QuestCloseType.NORMAL,
      voterList
    );

    vm.expectRevert(IncorrectAddDuration.selector);
    strategicAssets.extendQuestDuration(
      createdId,
      AURA,
      0,
      100,
      500
    );
    vm.stopPrank();
  }

  function test_revertsIf_invalidAddAmount() public {
    deal(AURA, address(strategicAssets), 1_000 ether);

    address[] memory voterList = new address[](0);

    vm.startPrank(AaveGovernanceV2.SHORT_EXECUTOR);
    uint256 createdId = strategicAssets.createRangedQuest(
      GAUGE,
      AURA,
      true,
      2,
      MIN_REWARD_PER_VOTE_AURA,
      MIN_REWARD_PER_VOTE_AURA + 10000,
      100 ether,
      4 ether,
      QuestVoteType.NORMAL,
      QuestCloseType.NORMAL,
      voterList
    );

    vm.expectRevert(NullAmount.selector);
    strategicAssets.extendQuestDuration(
      createdId,
      AURA,
      2,
      0,
      500
    );
    vm.stopPrank();
  }

  function test_successful() public {
    deal(AURA, address(strategicAssets), 1_000 ether);

    address[] memory voterList = new address[](0);

    vm.startPrank(AaveGovernanceV2.SHORT_EXECUTOR);
    uint256 createdId = strategicAssets.createRangedQuest(
      GAUGE,
      AURA,
      true,
      2,
      MIN_REWARD_PER_VOTE_AURA,
      MIN_REWARD_PER_VOTE_AURA + 10000,
      100 ether,
      4 ether,
      QuestVoteType.NORMAL,
      QuestCloseType.NORMAL,
      voterList
    );

    vm.warp(block.timestamp + 7 days);

    vm.expectEmit(true, true, true, true, strategicAssets.QUESTBOARD_VEBAL());
    emit ExtendQuestDuration(createdId, 2, 100 ether);
    strategicAssets.extendQuestDuration(
      createdId,
      AURA,
      2,
      100 ether,
      4 ether
    );
    vm.stopPrank();
  }
}

contract WithdrawRewardsThatHaveBeenUndistributed is QuestBoardTest {
  function test_revertsIf_invalidCaller() public {
    vm.expectRevert('ONLY_BY_OWNER_OR_GUARDIAN');
    strategicAssets.withdrawUnusedRewards(1);
  }

  function test_revertsIf_invalidQuestId() public {
    vm.expectRevert(InvalidQuestID.selector);
    vm.startPrank(AaveGovernanceV2.SHORT_EXECUTOR);
    strategicAssets.withdrawUnusedRewards(100000);
  }

  function test_revertsIf_invalidCreator() public {
    uint256 id = IQuestBoard(strategicAssets.QUESTBOARD_VEBAL()).nextID() - 1;
    vm.expectRevert(CallerNotAllowed.selector);
    vm.startPrank(AaveGovernanceV2.SHORT_EXECUTOR);
    strategicAssets.withdrawUnusedRewards(id);
  }

  function test_successful() public {
    address canCloseQuests = 0x2F793E40CF7473A371A3E6f3d3682F81070D3041;

    deal(AURA, address(strategicAssets), 1_000 ether);

    address[] memory voterList = new address[](0);

    vm.startPrank(AaveGovernanceV2.SHORT_EXECUTOR);
    uint256 createdId = strategicAssets.createRangedQuest(
      GAUGE,
      AURA,
      true,
      4,
      MIN_REWARD_PER_VOTE_AURA,
      MIN_REWARD_PER_VOTE_AURA + 10000,
      100 ether,
      4 ether,
      QuestVoteType.NORMAL,
      QuestCloseType.NORMAL,
      voterList
    );
    vm.stopPrank();


    vm.warp(block.timestamp + 15 days);

    uint256 period = block.timestamp;

    vm.warp(block.timestamp + 15 days);

    vm.startPrank(canCloseQuests);
    IQuestBoard(strategicAssets.QUESTBOARD_VEBAL()).closeQuestPeriod(period);
    vm.stopPrank();

    uint256 balanceBeforeWithdraw = IERC20(AURA).balanceOf(address(strategicAssets));

    vm.startPrank(AaveGovernanceV2.SHORT_EXECUTOR);
    strategicAssets.withdrawUnusedRewards(createdId);
    vm.stopPrank();

    assertGt(IERC20(AURA).balanceOf(address(strategicAssets)), balanceBeforeWithdraw);
  }
}

contract ClaimQuestBoardRewards is QuestBoardTest {
  error MerkleRootNotUpdated();

  function test_revertsIf_invalidCaller() public {
    bytes32[] memory proof = new bytes32[](0);
    vm.expectRevert('ONLY_BY_OWNER_OR_GUARDIAN');
    strategicAssets.claimQuestBoardRewards(
      1,
      1,
      1,
      address(strategicAssets),
      1,
      proof
    );
  }

  function test_revertsIf_accountIsAddressZero() public {
    bytes32[] memory proof = new bytes32[](0);
    vm.expectRevert(AddressZero.selector);
    vm.startPrank(AaveGovernanceV2.SHORT_EXECUTOR);
    strategicAssets.claimQuestBoardRewards(
      1,
      1,
      1,
      address(0),
      1,
      proof
    );
  }

  function test_revertsIf_merkleRootDoesNotExist() public {
    bytes32[] memory proof = new bytes32[](0);
    vm.expectRevert(MerkleRootNotUpdated.selector);
    vm.startPrank(AaveGovernanceV2.SHORT_EXECUTOR);
    strategicAssets.claimQuestBoardRewards(
      1,
      1,
      1,
      address(strategicAssets),
      1,
      proof
    );
  }

  function test_successful() public {
    assertFalse(IQuestDistributor(strategicAssets.QUESTBOARD_DISTRIBUTOR_VEBAL()).isClaimed(3, 1698278400, 1));

    bytes32[] memory proof = new bytes32[](1);
    proof[0] = 0x9a1d1d9c7596d7f2194084dea94fd283da911db4d837889b3f53ea528b65403d;

    vm.startPrank(AaveGovernanceV2.SHORT_EXECUTOR);
    strategicAssets.claimQuestBoardRewards(
      3,
      1698278400,
      1,
      0x1F08863F246fe456F94579D1A2009108B574F509,
      2537917350598567728000,
      proof
    );

    assertTrue(IQuestDistributor(strategicAssets.QUESTBOARD_DISTRIBUTOR_VEBAL()).isClaimed(3, 1698278400, 1));
  }
}

contract ClaimDelegatedQuestBoardRewards is QuestBoardTest {
  error MerkleRootNotUpdated();
  error ZeroAddress();

  function test_revertsIf_invalidCaller() public {
    bytes32[] memory proof = new bytes32[](0);
    vm.expectRevert('ONLY_BY_OWNER_OR_GUARDIAN');
    strategicAssets.claimDelegatedQuestBoardRewards(
      address(0),
      1,
      address(strategicAssets),
      1,
      proof
    );
  }

  function test_revertsIf_accountIsAddressZero() public {
    bytes32[] memory proof = new bytes32[](0);
    vm.expectRevert(ZeroAddress.selector);
    vm.startPrank(AaveGovernanceV2.SHORT_EXECUTOR);
    strategicAssets.claimDelegatedQuestBoardRewards(
      AURA,
      1,
      address(0),
      1,
      proof
    );
  }

  function test_revertsIf_merkleRootDoesNotExist() public {
    bytes32[] memory proof = new bytes32[](0);
    vm.expectRevert(MerkleRootNotUpdated.selector);
    vm.startPrank(AaveGovernanceV2.SHORT_EXECUTOR);
    strategicAssets.claimDelegatedQuestBoardRewards(
      AURA,
      1,
      address(strategicAssets),
      1,
      proof
    );
  }

  function test_successful() public {
    assertFalse(IQuestDelegationDistributor(strategicAssets.DELEGATED_DISTRIBUTOR()).isClaimed(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, 7));

    bytes32[] memory proof = new bytes32[](7);
    proof[0] = 0x082bc9625258a404af82cc1571c9488f9d36f124a3388686eb137ac62209a347;
    proof[1] = 0xfe9e19df7df113e2aec8cb167ca8c864e6d7f285e312b964e2a57e57c1e174b2;
    proof[2] = 0xcf5636342e6b8b4a9071e8bcbc7b8d5a799c65e53a6772e5ea76029e3023a697;
    proof[3] = 0x03a5dbeb933649a4a2ab40d1f84417a11d93d56c737035428806a5a9ee27d3b9;
    proof[4] = 0xf78ff64bdc1589f53e7aa13cc65d2a804612fa4d501376ab10e91bd7d6ed70d1;
    proof[5] = 0xfe2e4d85be17a8dcf174753461d1daf596515519c336b1ce1837a9038051b890;
    proof[6] = 0x13fa75c45e144a131122b3342dcd852d572a5cbb1e48144f8fc855e7b4281760;

    vm.startPrank(AaveGovernanceV2.SHORT_EXECUTOR);
    strategicAssets.claimDelegatedQuestBoardRewards(
      0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, // USDC
      7,
      0x20907A020A4A85669F2940D645e94C5B6490d1ad,
      1154795643,
      proof
    );

    assertTrue(IQuestDelegationDistributor(strategicAssets.DELEGATED_DISTRIBUTOR()).isClaimed(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, 7));
  }
}
