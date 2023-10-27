// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {IERC20} from 'solidity-utils/contracts/oz-common/interfaces/IERC20.sol';
import {SafeERC20} from 'solidity-utils/contracts/oz-common/SafeERC20.sol';

import {IVlToken, LockedBalance} from './interfaces/IVlToken.sol';
import {Common} from './Common.sol';

/// @author Llama
abstract contract VlTokenManager is Common {
  using SafeERC20 for IERC20;
  
  event ClaimVLAURARewards();
  event DelegatedVLAURA(address newDelegate);
  event EmergencyWithdraw(uint256 tokensUnlocked);
  event LockVLAURA(uint256 cummulativeTokensLocked, uint256 lockHorizon);
  event RelockVLAURA(uint256 cumulativeTokensLocked);
  event UnlockVLAURA(uint256 tokensUnlocked);

  address public constant AURA = 0xC0c293ce456fF0ED870ADd98a0828Dd4d2903DBF;
  address public constant VL_AURA = 0x3Fa73f1E5d8A792C80F426fc8F84FBF7Ce9bBCAC;

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
}
