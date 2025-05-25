// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface ITarget {
  function onClaimRevenue(address account, uint256 amount) external returns (bytes32);
}

contract POWA is ERC20 {
  using SafeERC20 for IERC20;

  uint256 private constant PRECISION = 1e18;
  bytes32 private constant TARGET_HASH = keccak256("POWARevenueReceiver.onClaimRevenue");

  IERC20  public revenueToken;
  address public distributor;

  /// @dev scaled by 1e18: total revenue per share accrued so far
  uint256 public accRevenuePerShare;
  
  struct AccountInfo {
    address target;
    uint256 rewardDebt;
    uint256 pending;
  }

  mapping(address => AccountInfo) private accountInfo;

  constructor(
    string memory name_,
    string memory symbol_,
    uint256 initialSupply,
    IERC20 _revenueToken,
    address _distributor,
    address initialHolder
  ) ERC20(name_, symbol_) {
    require(initialSupply > 0, "zero supply");
    revenueToken  = _revenueToken;
    distributor   = _distributor;
    _mint(initialHolder, initialSupply);
  }

  /// @dev bump the global accumulator; revenueToken must be approved
  function distribute(uint256 revenueAmount) external {
    require(msg.sender == distributor, "only vault");
    require(revenueAmount > 0,      "zero revenue");
    
    uint256 supply = totalSupply();
    require(supply > 0, "No outstanding shares");

    uint256 beforeAmount = revenueToken.balanceOf(address(this));
    revenueToken.safeTransferFrom(msg.sender, address(this), revenueAmount);
    uint256 actualAmount = revenueToken.balanceOf(address(this)) - beforeAmount;

    accRevenuePerShare +=
      Math.mulDiv(actualAmount, PRECISION, supply);
  }

  function claimToTarget(address claimFor) external {
    _updateAccount(claimFor);
    
    AccountInfo storage account = accountInfo[claimFor];
    uint256 amt = account.pending;
    require(amt > 0, "no revenue");
    account.pending = 0;

    uint256 before = revenueToken.balanceOf(address(this));

    // Let the target pull and do what it wants
    revenueToken.approve(account.target, amt);
    bytes32 res = ITarget(account.target).onClaimRevenue(claimFor, amt);

    // Requiring return hash excludes targetting anything not explicitly implemented to support it
    // It is easy enough to deploy a simple forwarder to EOAs, wallets etc.
    require(res == keccak256("POWARevenueReceiver.onClaimRevenue"), "Target returned wrong hash");
    require(before - amt == revenueToken.balanceOf(address(this)), "Wrong amount claimed");
  }

  /// @dev OZ‐v5 hook called on mint, burn, or transfer
  function _update(
    address from,
    address to,
    uint256 value
  ) internal override {
    if (from   != address(0)) _updateAccount(from);
    if (to   != address(0)) _updateAccount(to);
    super._update(from, to, value); // call super._update AFTER _updateAccount to avoid double count
  }

  /// @dev accrue any new revenue since last checkpoint
  function _updateAccount(address account) internal {
    AccountInfo storage u = accountInfo[account];

    uint256 accumulated =
      Math.mulDiv(balanceOf(account), accRevenuePerShare, PRECISION);
    uint256 earned = accumulated - u.rewardDebt;

    if (earned > 0) {
      u.pending += earned;
    }

    // reset debt to current
    u.rewardDebt = accumulated;
  }

  function pendingRevenue(address account) external view returns (uint256) {
    AccountInfo storage u = accountInfo[account];
    uint256 accumulated =
      Math.mulDiv(balanceOf(account), accRevenuePerShare, PRECISION);
    return u.pending + (accumulated - u.rewardDebt);
  }
}
