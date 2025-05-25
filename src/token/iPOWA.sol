// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract POWA is ERC20, Ownable {
  using SafeERC20 for IERC20;

  uint256 private constant PRECISION = 1e18;

  IERC20  public immutable revenueToken;
  address public immutable distributor;

  /// @dev scaled by 1e18: total revenue per share accrued so far
  uint256 public accRevenuePerShare;
  
  struct UserInfo {
    uint256 rewardDebt;
    uint256 pending;
  }

  mapping(address => UserInfo) private userInfo;

  constructor(
    string memory name_,
    string memory symbol_,
    uint256 initialSupply,
    IERC20 _revenueToken,
    address _distributor,
    address initialHolder
  ) ERC20(name_, symbol_) Ownable(msg.sender) {
    require(initialSupply > 0, "zero supply");
    revenueToken  = _revenueToken;
    distributor   = _distributor;

    _mint(initialHolder, initialSupply);

    // Prevent initialHolder from claiming revenue that was accrued before mint
    userInfo[initialHolder].rewardDebt =
      Math.mulDiv(initialSupply, accRevenuePerShare, PRECISION);
  }

  /// @dev bump the global accumulator; revenueToken must be approved
  function distribute(uint256 revenueAmount) external {
    require(msg.sender == distributor, "only vault");
    require(revenueAmount > 0,      "zero revenue");

    uint256 supply = totalSupply();
    revenueToken.safeTransferFrom(msg.sender, address(this), revenueAmount);

    accRevenuePerShare +=
      Math.mulDiv(revenueAmount, PRECISION, supply);
  }

  /// @dev pull down your owed revenue without burning shares
  function claimRevenue() external {
    _updateAccount(msg.sender);
    uint256 amt = userInfo[msg.sender].pending;
    require(amt > 0, "no revenue");
    userInfo[msg.sender].pending = 0;
    revenueToken.safeTransfer(msg.sender, amt);
  }

  /// @dev OZ‐v5 hook called on mint, burn, or transfer
  function _update(
    address from,
    address to,
    uint256 /*amount*/
  ) internal override {
    if (from != address(0)) _updateAccount(from);
    if (to   != address(0)) _updateAccount(to);
  }

  /// @dev accrue any new revenue since last checkpoint
  function _updateAccount(address account) internal {
    UserInfo storage u = userInfo[account];

    uint256 accumulated =
      Math.mulDiv(balanceOf(account), accRevenuePerShare, PRECISION);
    uint256 earned = accumulated - u.rewardDebt;

    if (earned > 0) {
      u.pending += earned;
    }

    // reset debt to current
    u.rewardDebt = accumulated;
  }

  /// @notice view your pending claim
  function pendingRevenue(address account) external view returns (uint256) {
    UserInfo storage u = userInfo[account];
    uint256 accumulated =
      Math.mulDiv(balanceOf(account), accRevenuePerShare, PRECISION);
    return u.pending + (accumulated - u.rewardDebt);
  }
}
