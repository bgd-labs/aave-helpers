// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {IERC20} from 'solidity-utils/contracts/oz-common/interfaces/IERC20.sol';
import {SafeERC20} from 'solidity-utils/contracts/oz-common/SafeERC20.sol';

import {IQuestDistributor, IQuestDelegationDistributor} from './interfaces/IQuestDistributor.sol';
import {QuestVoteType, QuestRewardsType, QuestCloseType, IQuestBoard} from './interfaces/IQuestBoard.sol';
import {IVlToken, LockedBalance} from './interfaces/IVlToken.sol';
import {Common} from './Common.sol';

/// @author efecarranza.eth
abstract contract VlTokenManager is Common {
  using SafeERC20 for IERC20;

  error InvalidSignatureLength();
  error InvalidSignatureS();
  error InvalidSignatureV();
  error InvalidSignature();

  event ClaimVLAURARewards();
  event DelegatedVLAURA(address newDelegate);
  event EmergencyWithdraw(uint256 tokensUnlocked);
  event LockVLAURA(uint256 cummulativeTokensLocked, uint256 lockHorizon);
  event RelockVLAURA(uint256 cumulativeTokensLocked);
  event UnlockVLAURA(uint256 tokensUnlocked);

  address public constant AURA = 0xC0c293ce456fF0ED870ADd98a0828Dd4d2903DBF;
  address public constant VL_AURA = 0x3Fa73f1E5d8A792C80F426fc8F84FBF7Ce9bBCAC;

  address public constant QUESTBOARD_VEBAL = 0xf0CeABf99Ddd591BbCC962596B228007eD4624Ae;
  address public constant QUESTBOARD_DISTRIBUTOR_VEBAL = 0xc413aB9c6d3E60E41a530b0A68817BAeA7bABbEC;
  address public constant QUEST_CHEST_VEBAL = 0x1Ae6DCBc88d6f81A7BCFcCC7198397D776F3592E;
  address public constant DELEGATED_DISTRIBUTOR = 0x997523eF97E0b0a5625Ed2C197e61250acF4e5F1;

  /// @notice Locks specified amount of AURA held in this contract into vlAURA
  /// @param amount The amount of AURA to lock
  function lockVLAURA(uint256 amount) external onlyOwnerOrGuardian {
    IERC20(AURA).forceApprove(VL_AURA, amount);
    IVlToken(VL_AURA).lock(address(this), amount);

    emit LockVLAURA(amount, block.timestamp + IVlToken(VL_AURA).lockDuration());
  }

  /// @notice Claim rewards generated by locking vlAURA
  function claimVLAURARewards() external onlyOwnerOrGuardian {
    IVlToken(VL_AURA).getReward(address(this));

    emit ClaimVLAURARewards();
  }

  /// @notice Delegate vlAURA held to a delegatee
  /// @param delegatee Address of user to delegate to
  function delegateVLAURA(address delegatee) external onlyOwnerOrGuardian {
    IVlToken(VL_AURA).delegate(delegatee);

    emit DelegatedVLAURA(delegatee);
  }

  /// @notice Re-lock vlAURA
  function relockVLAURA() external onlyOwnerOrGuardian {
    (uint256 lockedBalance, , , ) = IVlToken(VL_AURA).lockedBalances(address(this));
    IVlToken(VL_AURA).processExpiredLocks(true);

    emit RelockVLAURA(lockedBalance);
  }

  /// @notice Unlock held vlAURA
  function unlockVLAURA() external onlyOwnerOrGuardian {
    (uint256 lockedBalance, , , ) = IVlToken(VL_AURA).lockedBalances(address(this));
    IVlToken(VL_AURA).processExpiredLocks(false);

    emit UnlockVLAURA(lockedBalance);
  }

  /// @notice Emergency function to withdraw AURA if protocol is shutdown
  function emergencyWithdrawVLAURA() external onlyOwnerOrGuardian {
    (uint256 lockedBalance, , , ) = IVlToken(VL_AURA).lockedBalances(address(this));
    IVlToken(VL_AURA).emergencyWithdraw();

    emit EmergencyWithdraw(lockedBalance);
  }

  /// @notice Claims the reward for a user for a given period of a Quest
  /// @dev Claims the reward for a user for a given period of a Quest if the correct proof was given
  /// @param questID ID of the Quest
  /// @param period Timestamp of the period
  /// @param index Index in the Merkle Tree
  /// @param account Address of the user claiming the rewards
  /// @param amount Amount of rewards to claim
  /// @param merkleProof Proof to claim the rewards
  function claimQuestBoardRewards(
    uint256 questID,
    uint256 period,
    uint256 index,
    address account,
    uint256 amount,
    bytes32[] calldata merkleProof
  ) external onlyOwnerOrGuardian {
    IQuestDistributor(QUESTBOARD_DISTRIBUTOR_VEBAL).claim(
      questID,
      period,
      index,
      account,
      amount,
      merkleProof
    );
  }

  /// @notice Claims the reward for a user for a given period of a Quest
  /// @dev Claims the reward for a user for a given period of a Quest if the correct proof was given
  /// @param token Address of the token to claim
  /// @param index Index in the Merkle Tree
  /// @param account Address of the user claiming the rewards
  /// @param amount Amount of rewards to claim
  /// @param merkleProof Proof to claim the rewards
  function claimDelegatedQuestBoardRewards(
    address token,
    uint256 index,
    address account,
    uint256 amount,
    bytes32[] calldata merkleProof
  ) external onlyOwnerOrGuardian {
    IQuestDelegationDistributor(DELEGATED_DISTRIBUTOR).claim(
      token,
      index,
      account,
      amount,
      merkleProof
    );
  }

  /// @notice Creates a fixed rewards Quest based on the given parameters
  /// @dev Creates a Quest based on the given parameters & the given types with the Fixed Rewards type
  /// @param gauge Address of the gauge
  /// @param rewardToken Address of the reward token
  /// @param startNextPeriod (bool) true to start the Quest the next period
  /// @param duration Duration of the Quest (in weeks)
  /// @param rewardPerVote Amount of reward/vote (in wei)
  /// @param totalRewardAmount Total amount of rewards available for the full Quest duration
  /// @param feeAmount Amount of fees paid at creation
  /// @param voteType Vote type for the Quest
  /// @param closeType Close type for the Quest
  /// @param voterList List of voters for the Quest (to be used for Blacklist or Whitelist)
  /// @return uint256 : ID of the newly created Quest
  function createFixedQuest(
    address gauge,
    address rewardToken,
    bool startNextPeriod,
    uint48 duration,
    uint256 rewardPerVote,
    uint256 totalRewardAmount,
    uint256 feeAmount,
    QuestVoteType voteType,
    QuestCloseType closeType,
    address[] calldata voterList
  ) external onlyOwnerOrGuardian returns (uint256) {
    if (rewardToken == address(0)) revert InvalidZeroAddress();

    IERC20(rewardToken).approve(QUESTBOARD_VEBAL, totalRewardAmount + feeAmount);

    return
      IQuestBoard(QUESTBOARD_VEBAL).createFixedQuest(
        gauge,
        rewardToken,
        startNextPeriod,
        duration,
        rewardPerVote,
        totalRewardAmount,
        feeAmount,
        voteType,
        closeType,
        voterList
      );
  }

  /// @notice Creates a ranged rewards Quest based on the given parameters
  /// @dev Creates a Quest based on the given parameters & the given types with the Ranged Rewards type
  /// @param gauge Address of the gauge
  /// @param rewardToken Address of the reward token
  /// @param startNextPeriod (bool) true to start the Quest the next period
  /// @param duration Duration of the Quest (in weeks)
  /// @param minRewardPerVote Minimum amount of reward/vote (in wei)
  /// @param maxRewardPerVote Maximum amount of reward/vote (in wei)
  /// @param totalRewardAmount Total amount of rewards available for the full Quest duration
  /// @param feeAmount Amount of fees paid at creation
  /// @param voteType Vote type for the Quest
  /// @param closeType Close type for the Quest
  /// @param voterList List of voters for the Quest (to be used for Blacklist or Whitelist)
  /// @return uint256 : ID of the newly created Quest
  function createRangedQuest(
    address gauge,
    address rewardToken,
    bool startNextPeriod,
    uint48 duration,
    uint256 minRewardPerVote,
    uint256 maxRewardPerVote,
    uint256 totalRewardAmount,
    uint256 feeAmount,
    QuestVoteType voteType,
    QuestCloseType closeType,
    address[] calldata voterList
  ) external onlyOwnerOrGuardian returns (uint256) {
    if (rewardToken == address(0)) revert InvalidZeroAddress();

    IERC20(rewardToken).approve(QUESTBOARD_VEBAL, totalRewardAmount + feeAmount);

    return
      IQuestBoard(QUESTBOARD_VEBAL).createRangedQuest(
        gauge,
        rewardToken,
        startNextPeriod,
        duration,
        minRewardPerVote,
        maxRewardPerVote,
        totalRewardAmount,
        feeAmount,
        voteType,
        closeType,
        voterList
      );
  }

  /// @notice Increases the duration of a Quest
  /// @dev Adds more QuestPeriods and extends the duration of a Quest
  /// @param questID ID of the Quest
  /// @param addedDuration Number of period to add
  /// @param addedRewardAmount Amount of reward to add for the new periods (in wei)
  /// @param feeAmount Platform fees amount (in wei)
  function extendQuestDuration(
    uint256 questID,
    address rewardToken,
    uint48 addedDuration,
    uint256 addedRewardAmount,
    uint256 feeAmount
  ) external onlyOwnerOrGuardian {
    if (rewardToken == address(0)) revert InvalidZeroAddress();

    IERC20(rewardToken).approve(QUESTBOARD_VEBAL, addedRewardAmount + feeAmount);

    IQuestBoard(QUESTBOARD_VEBAL).extendQuestDuration(
      questID,
      addedDuration,
      addedRewardAmount,
      feeAmount
    );
  }

  /// @notice Withdraw all undistributed rewards from Closed Quest Periods
  /// @dev Withdraw all undistributed rewards from Closed Quest Periods
  /// @param questId ID of the Quest
  function withdrawUnusedRewards(uint256 questId) external onlyOwnerOrGuardian {
    IQuestBoard(QUESTBOARD_VEBAL).withdrawUnusedRewards(questId, address(this));
  }
}
