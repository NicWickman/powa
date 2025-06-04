// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "../Distributor.sol";

interface ITarget {
    function onClaimRevenue(
        address account,
        uint256 amount
    ) external returns (bytes32);
}

interface IPowaRevenueDistributor {
    function ocfVault() external returns (address);
    function notifySupplyUpdate(
        uint256 epochIdx,
        uint256 oldSupply,
        uint256 newSupply
    ) external;
}

abstract contract POWA is ERC20, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 private constant PRECISION = 1e18;
    bytes32 private constant TARGET_HASH =
        keccak256("POWARevenueReceiver.onClaimRevenue");

    IERC20 public revenueToken;
    IPowaRevenueDistributor public distributor;

    /// @dev scaled by 1e18: total revenue per share accrued so far
    uint256 public accRevenuePerShare;

    uint256 public immutable epochIdx;

    struct AccountInfo {
        address target;
        uint256 rewardDebt;
        uint256 pending;
    }

    mapping(address => AccountInfo) public accountInfo;

    event TargetSet(address indexed account, address indexed target);

    constructor(
        string memory name_,
        string memory symbol_,
        uint256 initialSupply,
        IERC20 _revenueToken,
        address _distributor,
        uint256 _epochIdx
    ) ERC20(name_, symbol_) {
        require(initialSupply > 0, "zero supply");
        revenueToken = _revenueToken;
        distributor = IPowaRevenueDistributor(_distributor);
        epochIdx = _epochIdx;
        _mint(distributor.ocfVault(), initialSupply);
    }

    /// @dev bump the global accumulator; revenueToken must be approved
    function distribute(uint256 revenueAmount) external {
        require(msg.sender == address(distributor), "only distributor");
        require(revenueAmount > 0, "zero revenue");

        uint256 supply = totalSupply();
        require(supply > 0, "No outstanding shares");

        uint256 beforeAmount = revenueToken.balanceOf(address(this));
        revenueToken.safeTransferFrom(msg.sender, address(this), revenueAmount);
        uint256 actualAmount = revenueToken.balanceOf(address(this)) -
            beforeAmount;

        accRevenuePerShare += Math.mulDiv(actualAmount, PRECISION, supply);
    }

    function setTarget(address newTarget) external nonReentrant {
        require(newTarget != address(0), "zero target");

        // sanity check the target
        try ITarget(newTarget).onClaimRevenue(msg.sender, 0) returns (
            bytes32 ret
        ) {
            require(ret == TARGET_HASH, "bad target handshake");
        } catch {
            revert("target probe failed");
        }
        accountInfo[msg.sender].target = newTarget;
        emit TargetSet(msg.sender, newTarget);
    }

    function claimToTarget(address claimFor) external nonReentrant {
        _updateAccount(claimFor);

        AccountInfo storage account = accountInfo[claimFor];
        uint256 amt = account.pending;
        require(amt > 0, "no revenue");
        account.pending = 0;

        uint256 before = revenueToken.balanceOf(address(this));

        // Let the target pull and do what it wants
        revenueToken.approve(account.target, amt);
        bytes32 res = ITarget(account.target).onClaimRevenue(claimFor, amt);

        // Requiring return hash prevents targetting anything not explicitly implemented to support it
        // It is easy enough to deploy a simple forwarder to EOAs, wallets etc.
        require(
            res == keccak256("POWARevenueReceiver.onClaimRevenue"),
            "Target returned wrong hash"
        );
        require(
            before - amt == revenueToken.balanceOf(address(this)),
            "Wrong amount claimed"
        );
    }

    /// @dev OZ‐v5 hook called on mint, burn, or transfer
    function _update(
        address from,
        address to,
        uint256 value
    ) internal virtual override {
        uint256 supplyBefore = totalSupply();
        bool supplyChanges = (from == address(0) || to == address(0));

        if (from != address(0)) _updateAccount(from);
        if (to != address(0)) _updateAccount(to);

        super._update(from, to, value);

        if (supplyChanges) {
            uint256 supplyAfter = totalSupply();
            if (supplyAfter != supplyBefore) {
                distributor.notifySupplyUpdate(
                    epochIdx,
                    supplyBefore,
                    supplyAfter
                );
            }
        }
    }

    /// @dev accrue any new revenue since last checkpoint
    function _updateAccount(address account) internal {
        AccountInfo storage u = accountInfo[account];

        uint256 accumulated = Math.mulDiv(
            balanceOf(account),
            accRevenuePerShare,
            PRECISION
        );
        uint256 earned = accumulated - u.rewardDebt;

        if (earned > 0) {
            u.pending += earned;
        }

        // reset debt to current
        u.rewardDebt = accumulated;
    }

    function pendingRevenue(address account) external view returns (uint256) {
        AccountInfo storage u = accountInfo[account];
        uint256 accumulated = Math.mulDiv(
            balanceOf(account),
            accRevenuePerShare,
            PRECISION
        );
        return u.pending + (accumulated - u.rewardDebt);
    }
}
