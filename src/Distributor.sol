// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./token/cPOWA.sol";
import "./token/iPOWA.sol";

contract PowaRevenueDistributor is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 internal constant WEIGHT_SCALE = 1e18; // 1×

    address public ocfVault;
    IERC20 public revenueAsset;
    uint256 public totalWeightedSupply; // cached sum of all epoch weighted supplies

    struct Epoch {
        iPOWA investorToken;
        cPOWA contributorToken;
        uint128 weightFP; // 18-dec fixed-point factor
        uint256 invWeightedSupply; // cached = totalSupply * weightFP / WEIGHT_SCALE
        uint256 conWeightedSupply;
    }

    Epoch[] public epochs;
    bool private inEpochCreation;

    event EpochCreated(
        uint256 indexed epochIdx,
        address investorToken,
        address contributorToken
    );

    constructor(IERC20 _revenueAsset, address _ofcVault) Ownable(msg.sender) {
        ocfVault = _ofcVault;
        revenueAsset = _revenueAsset;
        inEpochCreation = false;
    }

    /**
     * @dev Deploy the two (investor and contributor) tokens for a new epoch.
     *      Suppresses notifySupplyUpdate during the initial minting to ocfVault.
     */
    function createEpoch(
        string calldata investorName,
        string calldata investorSymbol,
        string calldata contributorName,
        string calldata contributorSymbol,
        uint256 initialInvestorSupply,
        uint256 initialContributorSupply,
        uint128 weightFP
    ) external onlyOwner {
        require(weightFP > 0 && weightFP <= 1e24, "Epoch weight out of range");

        // Suppress notifySupplyUpdate during initial mint to ocfVault
        inEpochCreation = true;

        iPOWA investorToken = new iPOWA(
            investorName,
            investorSymbol,
            initialInvestorSupply,
            revenueAsset,
            address(this),
            epochs.length
        );

        cPOWA contributorToken = new cPOWA(
            contributorName,
            contributorSymbol,
            initialContributorSupply,
            revenueAsset,
            address(this),
            epochs.length
        );

        // Compute weighted supplies for the new epoch
        uint256 invWeightedSupply = Math.mulDiv(
            initialInvestorSupply,
            weightFP,
            WEIGHT_SCALE
        );
        uint256 conWeightedSupply = Math.mulDiv(
            initialContributorSupply,
            weightFP,
            WEIGHT_SCALE
        );

        // Push the new epoch struct now that tokens are deployed
        epochs.push(
            Epoch({
                investorToken: investorToken,
                contributorToken: contributorToken,
                weightFP: weightFP,
                invWeightedSupply: invWeightedSupply,
                conWeightedSupply: conWeightedSupply
            })
        );

        // Update the total weighted supply (epoch now exists)
        totalWeightedSupply += invWeightedSupply + conWeightedSupply;

        // Re-enable notifySupplyUpdate for future supply changes
        inEpochCreation = false;

        emit EpochCreated(
            epochs.length - 1,
            address(investorToken),
            address(contributorToken)
        );
    }

    function depositRevenue(uint256 amount) external nonReentrant {
        require(amount > 0, "zero amount");

        revenueAsset.safeTransferFrom(msg.sender, address(this), amount);
        uint256 distributable = revenueAsset.balanceOf(address(this));
        uint256 denom = totalWeightedSupply;
        require(denom != 0, "no shares outstanding");

        for (uint256 i; i < epochs.length; ++i) {
            Epoch storage e = epochs[i];

            uint256 invSlice = Math.mulDiv(
                distributable,
                e.invWeightedSupply,
                denom
            );
            uint256 conSlice = Math.mulDiv(
                distributable,
                e.conWeightedSupply,
                denom
            );

            if (invSlice != 0) {
                revenueAsset.approve(address(e.investorToken), invSlice);
                e.investorToken.distribute(invSlice);
                revenueAsset.approve(address(e.investorToken), 0);
            }
            if (conSlice != 0) {
                revenueAsset.approve(address(e.contributorToken), conSlice);
                e.contributorToken.distribute(conSlice);
                revenueAsset.approve(address(e.contributorToken), 0);
            }
        }
    }

    function notifySupplyUpdate(
        uint256 epochIdx,
        uint256 oldSupply,
        uint256 newSupply
    ) external {
        // If we're in createEpoch(), skip index check and weight recalculation
        if (inEpochCreation) {
            return;
        }

        require(epochIdx < epochs.length, "bad index");
        Epoch storage e = epochs[epochIdx];

        bool isInvestor = msg.sender == address(e.investorToken);
        require(
            isInvestor || msg.sender == address(e.contributorToken),
            "unauthorised"
        );

        uint256 cachedWeighted = isInvestor
            ? e.invWeightedSupply
            : e.conWeightedSupply;

        uint256 cachedSupply = Math.mulDiv(
            cachedWeighted,
            WEIGHT_SCALE,
            e.weightFP
        ); // inverse, for sanity

        require(cachedSupply == oldSupply, "wrong oldSupply");

        uint256 newWeighted = Math.mulDiv(newSupply, e.weightFP, WEIGHT_SCALE);

        totalWeightedSupply =
            totalWeightedSupply -
            cachedWeighted +
            newWeighted;

        if (isInvestor) {
            e.invWeightedSupply = newWeighted;
        } else {
            e.conWeightedSupply = newWeighted;
        }
    }
}
