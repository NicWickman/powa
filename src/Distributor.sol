// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "./token/POWA.sol";

contract PowaRevenueDistributor is Ownable {
    using SafeERC20 for IERC20;

    address public ocfVault;
    IERC20 public revenueAsset;

    struct Epoch {
        POWA investorToken;
        POWA contributorToken;
        uint64 weight;
    }

    Epoch[] public epochs;

    event EpochCreated(
        uint256 indexed epochIdx,
        address investorToken,
        address contributorToken
    );

    constructor(IERC20 _revenueAsset, address _ofcVault) Ownable(msg.sender) {
        ocfVault = _ofcVault;
        revenueAsset = _revenueAsset;
    }

    /* deploy the two (investor and contributor) tokens for a new epoch */
    function createEpoch(
        string calldata investorName,
        string calldata investorSymbol,
        string calldata contributorName,
        string calldata contributorSymbol,
        uint256 initialInvestorSupply,
        uint256 initialContributorSupply,
        uint64 epochWeight
    ) external onlyOwner {
        POWA investorToken = new POWA(
            investorName,
            investorSymbol,
            initialInvestorSupply,
            revenueAsset,
            address(this),
            ocfVault
        );

        POWA contributorToken = new POWA(
            contributorName,
            contributorSymbol,
            initialContributorSupply,
            revenueAsset,
            address(this),
            ocfVault
        );

        epochs.push(Epoch({
            investorToken:     investorToken,
            contributorToken:  contributorToken,
            weight: epochWeight
        }));

        emit EpochCreated(
            epochs.length-1,
            address(investorToken),
            address(contributorToken)
        );
    }

    /**
     * @notice Split `amount` of `revenueAsset` over every active epoch using
     *         (totalSupply × weight) as the pro-rata key and push each slice to
     *         the corresponding POWA token, which then rebases.
     *
     * @dev    - Weights are uint64 in basis-points (10 000 = 1.0000×).
     */
    function depositRevenue(uint256 amount) external {
        require(amount > 0, "zero amount");

        revenueAsset.safeTransferFrom(msg.sender, address(this), amount);
        uint256 distributable = revenueAsset.balanceOf(address(this));

        /* -------- first pass : accumulate weighted supply -------- */
        uint256 weightedTotal = 0;
        uint256 n = epochs.length;

        for (uint256 i = 0; i < n; ++i) {
            Epoch storage e = epochs[i];
            if (address(e.investorToken) == address(0)) continue;

            uint256 investorWeighted = Math.mulDiv(
                e.investorToken.totalSupply(),
                e.weight,
                1
            );
            uint256 contributorWeighted = Math.mulDiv(
                e.contributorToken.totalSupply(),
                e.weight,
                1
            );

            weightedTotal += investorWeighted + contributorWeighted;
        }
        
        require(weightedTotal != 0, "no shares outstanding");

        /* -------- second pass : push slices and rebase -------- */
        for (uint256 i = 0; i < n; ++i) {
            Epoch storage e = epochs[i];
            if (address(e.investorToken) == address(0)) continue;

            uint256 investorSlice = Math.mulDiv(
                distributable,
                e.investorToken.totalSupply() * e.weight,
                weightedTotal,
                Math.Rounding.Floor
            );

            uint256 contributorSlice = Math.mulDiv(
                distributable,
                e.contributorToken.totalSupply() * e.weight,
                weightedTotal,
                Math.Rounding.Floor
            );

            if (investorSlice != 0) {
                revenueAsset.approve(address(e.investorToken), investorSlice);
                e.investorToken.distribute(investorSlice);
                revenueAsset.approve(address(e.investorToken), 0);
            }
            if (contributorSlice != 0) {
                revenueAsset.approve(address(e.contributorToken), contributorSlice);
                e.contributorToken.distribute(contributorSlice);
                revenueAsset.approve(address(e.contributorToken), 0);
            }
        }
    }
}
