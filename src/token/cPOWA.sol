// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.20;

import "./POWA.sol";

contract cPOWA is POWA {
    constructor(
        string memory name_,
        string memory symbol_,
        uint256 initialSupply,
        IERC20 _revenueToken,
        address _distributor,
        uint256 _epochIdx
    )
        POWA(
            name_,
            symbol_,
            initialSupply,
            _revenueToken,
            _distributor,
            _epochIdx
        )
    {}

    function _update(
        address from,
        address to,
        uint256 value
    ) internal override {
        require(
            msg.sender == address(distributor) ||
                msg.sender == distributor.ocfVault(),
            "cPOWA transfers restricted"
        );
        super._update(from, to, value);
    }
}
