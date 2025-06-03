// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.20;

import "./POWA.sol";

contract iPOWA is POWA {
    constructor(
        string memory name_,
        string memory symbol_,
        uint256 initialSupply,
        IERC20 _revenueToken,
        address _distributor,
        address initialHolder,
        uint256 _epochIdx
    )
        POWA(
            name_,
            symbol_,
            initialSupply,
            _revenueToken,
            _distributor,
            initialHolder,
            _epochIdx
        )
    {}
}
