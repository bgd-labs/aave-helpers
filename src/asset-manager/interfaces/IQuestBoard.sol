// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @notice Types of Vote logic for Quests ////
enum QuestVoteType {
  NORMAL,
  BLACKLIST,
  WHITELIST
}
/// NORMAL: basic vote logic
/// BLACKLIST: remove the blacklisted voters bias from the gauge biases
/// WHITELIST: only sum up the whitelisted voters biases

/// @notice Types of Rewards logic for Quests ////
enum QuestRewardsType {
  FIXED,
  RANGE
}
/// FIXED: reward per vote is fixed
/// RANGE: reward per vote is a range between min and max, based on the Quest completion between min objective and max objective

/// @notice Types of logic for undistributed rewards when closing Quest periods
enum QuestCloseType {
  NORMAL,
  ROLLOVER,
  DISTRIBUTE
}

/// NORMAL: undistributed rewards are available to be withdrawn by the creator
/// ROLLOVER: undistributed rewards are added to the next period, increasing the reward/vote parameter
/// DISTRIBUTE: undistributed rewards are sent to the gauge for direct distribution

interface IQuestBoard {
  /// @notice ID for the next Quest to be created
  function nextID() external returns (uint256);

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
  ) external returns (uint256);

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
  ) external returns (uint256);

  /// @notice Increases the duration of a Quest
  /// @dev Adds more QuestPeriods and extends the duration of a Quest
  /// @param questID ID of the Quest
  /// @param addedDuration Number of period to add
  /// @param addedRewardAmount Amount of reward to add for the new periods (in wei)
  /// @param feeAmount Platform fees amount (in wei)
  function extendQuestDuration(
    uint256 questID,
    uint48 addedDuration,
    uint256 addedRewardAmount,
    uint256 feeAmount
  ) external;

  /// @notice Withdraw all undistributed rewards from Closed Quest Periods
  /// @dev Withdraw all undistributed rewards from Closed Quest Periods
  /// @param questID ID of the Quest
  /// @param recipient Address to send the reward tokens to
  function withdrawUnusedRewards(uint256 questID, address recipient) external;

  /// @notice Closes the Period, and all QuestPeriods for this period
  /// @dev Closes all QuestPeriod for the given period, calculating rewards to distribute & send them to distributor
  /// @param period Timestamp of the period
  function closeQuestPeriod(uint256 period) external;
}
