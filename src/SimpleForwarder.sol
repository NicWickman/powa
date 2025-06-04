// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.20;

import "./Target.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract SimpleForwarder is Target {
    IERC20 public immutable revenueToken;

    constructor(IERC20 _revenueToken) {
        revenueToken = _revenueToken;
    }

    function onClaimRevenue(
        address account,
        uint256 amount
    ) external override returns (bytes32) {
        revenueToken.transferFrom(msg.sender, account, amount);
        return TARGET_HASH;
    }
}
