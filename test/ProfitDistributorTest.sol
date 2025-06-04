// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import "../src/Distributor.sol";
import "../src/token/iPOWA.sol";
import "../src/token/cPOWA.sol";

/// @notice A minimal ERC20 that lets us mint arbitrary amounts.
contract ERC20Mock is ERC20 {
    constructor(
        string memory name_,
        string memory symbol_
    ) ERC20(name_, symbol_) {}
    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}

contract ProfitDistributorTest is Test {
    PowaRevenueDistributor public distributor;
    ERC20Mock public revenueToken;
    address public ocfVault = address(0xABCD);
    address public Ivan = address(0x1);
    address public Claire = address(0x2);
    address public Ingrid = address(0x3);
    address public Carl = address(0x4);

    function setUp() public {
        // Deploy the mock revenue token and mint 10k RVT to this contract
        revenueToken = new ERC20Mock("RevenueToken", "RVT");
        revenueToken.mint(address(this), 10_000 * 1e18);

        // Deploy the distributor
        distributor = new PowaRevenueDistributor(revenueToken, ocfVault);

        // Create epoch 0: weight = 1e18, iPOWA = 2_000_000, cPOWA = 3_000_000
        distributor.createEpoch(
            "iPOWA.E0",
            "iPOWA0",
            "cPOWA.E0",
            "cPOWA0",
            2_000_000,
            3_000_000,
            1e18
        );
        (iPOWA inv0, cPOWA con0, , , ) = distributor.epochs(0);

        // Create epoch 1: weight = 0.5e18, iPOWA = 3_000_000, cPOWA = 4_500_000
        distributor.createEpoch(
            "iPOWA.E1",
            "iPOWA1",
            "cPOWA.E1",
            "cPOWA1",
            3_000_000,
            4_500_000,
            5e17
        );
        (iPOWA inv1, cPOWA con1, , , ) = distributor.epochs(1);

        // Allocate from ocfVault:
        // Epoch 0 investor → Ivan: 1_500_000 / 2_000_000
        vm.prank(ocfVault);
        inv0.transfer(Ivan, 1_500_000);
        // Epoch 0 contributor → Claire: 250_000 / 3_000_000
        vm.prank(ocfVault);
        con0.transfer(Claire, 250_000);

        // Epoch 1 investor → Ingrid: 2_250_000 / 3_000_000
        vm.prank(ocfVault);
        inv1.transfer(Ingrid, 2_250_000);
        // Epoch 1 contributor → Carl: 450_000 / 4_500_000
        vm.prank(ocfVault);
        con1.transfer(Carl, 450_000);

        // Approve and deposit 10_000 RVT into distributor
        revenueToken.approve(address(distributor), 10_000 * 1e18);
        distributor.depositRevenue(10_000 * 1e18);
    }

    function testLogPendingRevenue() public {
        (iPOWA inv0, cPOWA con0, , , ) = distributor.epochs(0);
        (iPOWA inv1, cPOWA con1, , , ) = distributor.epochs(1);

        uint256 pIvan = inv0.pendingRevenue(Ivan);
        uint256 pClaire = con0.pendingRevenue(Claire);
        uint256 pIngrid = inv1.pendingRevenue(Ingrid);
        uint256 pCarl = con1.pendingRevenue(Carl);

        uint256 pVaultInv0 = inv0.pendingRevenue(ocfVault);
        uint256 pVaultCon0 = con0.pendingRevenue(ocfVault);
        uint256 pVaultInv1 = inv1.pendingRevenue(ocfVault);
        uint256 pVaultCon1 = con1.pendingRevenue(ocfVault);

        console2.logUint(pIvan);
        console2.logUint(pClaire);
        console2.logUint(pIngrid);
        console2.logUint(pCarl);
        console2.logUint(pVaultInv0);
        console2.logUint(pVaultCon0);
        console2.logUint(pVaultInv1);
        console2.logUint(pVaultCon1);

        // Optional sanity checks—ensure nobody has zero revenue
        assertTrue(pIvan > 0);
        assertTrue(pClaire > 0);
        assertTrue(pIngrid > 0);
        assertTrue(pCarl > 0);
    }
}
