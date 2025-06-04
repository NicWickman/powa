// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/Distributor.sol";
import "../src/token/iPOWA.sol";
import "../src/token/cPOWA.sol";
import "../src/Target.sol";

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
    PowaRevenueDistributor distributor;
    ERC20Mock revenueToken;
    address ocfVault = address(0xABCD);
    address Ivan = address(0x1);
    address Claire = address(0x2);
    address Ingrid = address(0x3);
    address Carl = address(0x4);

    function setUp() public {
        // deploy a mock ERC20 as the revenue asset
        revenueToken = new ERC20Mock("RevenueToken", "RVT");
        // mint enough tokens to this contract so we can deposit 20k
        revenueToken.mint(address(this), 20_000 * 1e18);

        // deploy the distributor, giving it the revenue token and ocfVault
        distributor = new PowaRevenueDistributor(revenueToken, ocfVault);

        // create epoch 0 with weight = 1e18, iPOWA supply = 2,000,000, cPOWA supply = 3,000,000
        distributor.createEpoch(
            "iPOWA.E0",
            "iPOWA0",
            "cPOWA.E0",
            "cPOWA0",
            2_000_000,
            3_000_000,
            1e18
        );
        // fetch the deployed token addresses
        (iPOWA inv0, cPOWA con0, , , ) = distributor.epochs(0);

        // create epoch 1 with weight = 0.5e18, iPOWA supply = 3,000,000, cPOWA supply = 4,500,000
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

        // allocate from ocfVault: epoch 0 investor -> Ivan: 1,500,000 out of 2,000,000
        vm.prank(ocfVault);
        inv0.transfer(Ivan, 1_500_000);
        // allocate epoch 0 contributor -> Claire: 250,000 out of 3,000,000
        vm.prank(ocfVault);
        con0.transfer(Claire, 250_000);

        // allocate epoch 1 investor -> Ingrid: 2,250,000 out of 3,000,000
        vm.prank(ocfVault);
        inv1.transfer(Ingrid, 2_250_000);
        // allocate epoch 1 contributor -> Carl: 450,000 out of 4,500,000
        vm.prank(ocfVault);
        con1.transfer(Carl, 450_000);

        // approve and deposit 20,000 revenue tokens into the distributor
        revenueToken.approve(address(distributor), 20_000 * 1e18);
        distributor.depositRevenue(20_000 * 1e18);
    }

    function testPendingRevenueAmounts() public {
        (iPOWA inv0, cPOWA con0, , , ) = distributor.epochs(0);
        (iPOWA inv1, cPOWA con1, , , ) = distributor.epochs(1);

        // epoch 0 investor: Ivan should have 3,428 * 1e18 pending
        uint256 pendingIvan = inv0.pendingRevenue(Ivan);
        assertEq(pendingIvan, 3_428 * 1e18);

        // epoch 0 contributor: Claire should have 571 * 1e18 pending
        uint256 pendingClaire = con0.pendingRevenue(Claire);
        assertEq(pendingClaire, 571 * 1e18);

        // epoch 1 investor: Ingrid should have 2,571 * 1e18 pending
        uint256 pendingIngrid = inv1.pendingRevenue(Ingrid);
        assertEq(pendingIngrid, 2_571 * 1e18);

        // epoch 1 contributor: Carl should have 514 * 1e18 pending
        uint256 pendingCarl = con1.pendingRevenue(Carl);
        assertEq(pendingCarl, 514 * 1e18);

        // additionally, verify that the ocfVault (as holder of the leftover shares)
        // has received the truncated remainders on each token:

        // epoch 0 inv leftover = total 2_000_000 - 1_500_000 = 500_000 -> should earn 1,142 * 1e18
        uint256 pendingVaultInv0 = inv0.pendingRevenue(ocfVault);
        assertEq(pendingVaultInv0, 1_142 * 1e18);

        // epoch 0 con leftover = 3_000_000 - 250_000 = 2_750_000 -> should earn 6,285 * 1e18
        uint256 pendingVaultCon0 = con0.pendingRevenue(ocfVault);
        assertEq(pendingVaultCon0, 6_285 * 1e18);

        // epoch 1 inv leftover = 3_000_000 - 2_250_000 = 750_000 -> should earn 857 * 1e18
        uint256 pendingVaultInv1 = inv1.pendingRevenue(ocfVault);
        assertEq(pendingVaultInv1, 857 * 1e18);

        // epoch 1 con leftover = 4_500_000 - 450_000 = 4_050_000 -> should earn 4,628 * 1e18
        uint256 pendingVaultCon1 = con1.pendingRevenue(ocfVault);
        assertEq(pendingVaultCon1, 4_628 * 1e18);
    }
}
