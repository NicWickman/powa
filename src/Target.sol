// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.20;

abstract contract Target {
    // The expected return hash for a compliant POWA revenue target
    bytes32 public constant TARGET_HASH = keccak256("POWARevenueReceiver.onClaimRevenue");

    /**
     * @notice Handle a revenue claim. Called by a POWA token.
     * @dev Must return TARGET_HASH to confirm execution.
     * @param account The user who is claiming revenue.
     * @param amount The amount of revenue to claim.
     * @return bytes32 Must return TARGET_HASH.
     */
    function onClaimRevenue(address account, uint256 amount) external virtual returns (bytes32);
}
