// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IQuestDistributor {
  /// @notice Checks if the rewards were claimed for a user on a given period
  /// @dev Checks if the rewards were claimed for a user (based on the index) on a given period
  /// @param questID ID of the Quest
  /// @param period Amount of underlying to borrow
  /// @param index Index of the claim
  /// @return bool : true if already claimed
  function isClaimed(uint256 questID, uint256 period, uint256 index) external returns (bool);

  /// @notice Claims the reward for a user for a given period of a Quest
  /// @dev Claims the reward for a user for a given period of a Quest if the correct proof was given
  /// @param questID ID of the Quest
  /// @param period Timestamp of the period
  /// @param index Index in the Merkle Tree
  /// @param account Address of the user claiming the rewards
  /// @param amount Amount of rewards to claim
  /// @param merkleProof Proof to claim the rewards
  function claim(
    uint256 questID,
    uint256 period,
    uint256 index,
    address account,
    uint256 amount,
    bytes32[] calldata merkleProof
  ) external;

  /// @notice Updates the period of a Quest by adding the Merkle Root
  /// @dev Add the Merkle Root for the eriod of the given Quest
  /// @param questID ID of the Quest
  /// @param period timestamp of the period
  /// @param totalAmount sum of all rewards for the Merkle Tree
  /// @param merkleRoot MerkleRoot to add
  /// @return bool: success
  function updateQuestPeriod(
    uint256 questID,
    uint256 period,
    uint256 totalAmount,
    bytes32 merkleRoot
  ) external returns (bool);
}

interface IQuestDelegationDistributor {
  /// @notice Checks if the rewards were claimed for an index
  /// @dev Checks if the rewards were claimed for an index for the current update
  /// @param token addredd of the token to claim
  /// @param index Index of the claim
  /// @return bool : true if already claimed
  function isClaimed(address token, uint256 index) external view returns (bool);

  /// @notice Claims rewards for a given token for the user
  /// @dev Claims the reward for an user for the current update of the Merkle Root for the given token
  /// @param token Address of the token to claim
  /// @param index Index in the Merkle Tree
  /// @param account Address of the user claiming the rewards
  /// @param amount Amount of rewards to claim
  /// @param merkleProof Proof to claim the rewards
  function claim(
    address token,
    uint256 index,
    address account,
    uint256 amount,
    bytes32[] calldata merkleProof
  ) external;
}
