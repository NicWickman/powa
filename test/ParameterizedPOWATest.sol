// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import "forge-std/StdJson.sol";
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

contract ParameterizedPOWATest is Test {
    using stdJson for string;
    
    PowaRevenueDistributor public distributor;
    ERC20Mock public revenueToken;
    address public ocfVault = address(0xABCD);
    
    // Arrays to store epoch data
    iPOWA[] public iPOWATokens;
    cPOWA[] public cPOWATokens;
    
    // Track deposited revenue
    uint256 public depositedRevenue;
    
    // Config structure
    struct EpochConfig {
        uint256 iPOWA;
        uint256 cPOWA;
        uint256 weight;
    }
    
    struct UserHolding {
        uint256 epochIndex;
        uint256 iPOWA;
        uint256 cPOWA;
    }
    
    function setUp() public {
        // Read config file
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/test/powa-config.json");
        string memory json = vm.readFile(path);
        
        // Parse revenue amount
        uint256 revenueAmount = json.readUint(".revenueAmount");
        
        // Deploy the mock revenue token and mint revenue
        revenueToken = new ERC20Mock("RevenueToken", "RVT");
        revenueToken.mint(address(this), revenueAmount * 1e18);

        // Deploy the distributor
        distributor = new PowaRevenueDistributor(revenueToken, ocfVault);

        // Parse and create epochs
        bytes memory epochsRaw = json.parseRaw(".epochs");
        EpochConfig[] memory epochs = abi.decode(epochsRaw, (EpochConfig[]));
        
        for (uint256 i = 0; i < epochs.length; i++) {
            // Convert basis points to wei (10000 bps = 1.0 = 1e18 wei)
            uint128 weightWei = uint128((epochs[i].weight * 1e18) / 10000);
            
            // Create epoch
            distributor.createEpoch(
                string.concat("iPOWA.E", vm.toString(i)),
                string.concat("iPOWA", vm.toString(i)),
                string.concat("cPOWA.E", vm.toString(i)),
                string.concat("cPOWA", vm.toString(i)),
                epochs[i].iPOWA,
                epochs[i].cPOWA,
                weightWei
            );
            
            // Store tokens for later reference
            (iPOWA inv, cPOWA con, , , ) = distributor.epochs(i);
            iPOWATokens.push(inv);
            cPOWATokens.push(con);
        }

        // Approve and deposit revenue into distributor
        depositedRevenue = revenueAmount * 1e18;
        revenueToken.approve(address(distributor), depositedRevenue);
        distributor.depositRevenue(depositedRevenue);
    }

    // Helper function to format tokens with 3 decimal places
    function formatTokens(uint256 weiAmount) internal pure returns (string memory) {
        uint256 tokens = weiAmount / 1e18;
        uint256 decimals = (weiAmount % 1e18) / 1e15; // Get 3 decimal places
        
        // Format with leading zeros if needed
        if (decimals < 10) {
            return string.concat(vm.toString(tokens), ".00", vm.toString(decimals));
        } else if (decimals < 100) {
            return string.concat(vm.toString(tokens), ".0", vm.toString(decimals));
        } else {
            return string.concat(vm.toString(tokens), ".", vm.toString(decimals));
        }
    }

    function testDistribution() public view {
        uint256 epochCount = iPOWATokens.length;
        
        console2.log("=== POWA Revenue Distribution Test ===");
        console2.log(string.concat("Total Revenue Deposited: ", formatTokens(depositedRevenue), " tokens"));
        console2.log("Number of Epochs:", epochCount);
        console2.log("");
        
        uint256 totalDistributed = 0;
        
        for (uint256 i = 0; i < epochCount; i++) {
            (iPOWA inv, cPOWA con, uint128 weight, ,) = distributor.epochs(i);
            uint256 iPOWASupply = inv.totalSupply();
            uint256 cPOWASupply = con.totalSupply();
            
            console2.log("Epoch", i, "Configuration:");
            console2.log("  iPOWA Supply:", iPOWASupply);
            console2.log("  cPOWA Supply:", cPOWASupply);
            console2.log("  Total Supply:", iPOWASupply + cPOWASupply);
            console2.log("  Weight (bps):", (uint256(weight) * 10000) / 1e18);
            
            // Check actual revenue received by tokens
            uint256 iPOWARevenue = revenueToken.balanceOf(address(inv));
            uint256 cPOWARevenue = revenueToken.balanceOf(address(con));
            uint256 epochActualRevenue = iPOWARevenue + cPOWARevenue;
            totalDistributed += epochActualRevenue;
            
            console2.log(string.concat("  Actual iPOWA Revenue: ", formatTokens(iPOWARevenue), " tokens"));
            console2.log(string.concat("  Actual cPOWA Revenue: ", formatTokens(cPOWARevenue), " tokens"));
            console2.log(string.concat("  Total Epoch Revenue: ", formatTokens(epochActualRevenue), " tokens"));
            
            // Revenue per token in wei (more precise for small amounts)
            if (iPOWASupply + cPOWASupply > 0) {
                uint256 revenuePerToken = epochActualRevenue / (iPOWASupply + cPOWASupply);
                console2.log("  Revenue per Token:", revenuePerToken, "wei");
                console2.log("  Revenue per Token:", formatTokens(revenuePerToken), "tokens");
            }
            console2.log("");
        }
        
        console2.log("=== Invariant Check ===");
        console2.log(string.concat("Total Distributed: ", formatTokens(totalDistributed), " tokens"));
        console2.log("                   ", totalDistributed, "wei");
        console2.log(string.concat("Should Equal:      ", formatTokens(depositedRevenue), " tokens"));
        console2.log("                   ", depositedRevenue, "wei");
        uint256 difference = depositedRevenue > totalDistributed ? 
            (depositedRevenue - totalDistributed) : (totalDistributed - depositedRevenue);
        console2.log("Difference:        ", difference, "wei");
        if (difference > 0){
            console2.log("                   ", "Dust is OK - it just rolls forward to the next distribution");
        }
    }
    
    function testUserClaims() public {
        // Read config file again for user holdings
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/test/powa-config.json");
        string memory json = vm.readFile(path);
        
        address testUser = address(0x1234);
        
        console2.log("=== User Claims Test ===");
        console2.log("Test User:", testUser);
        console2.log("");
        
        uint256 totalClaimable = 0;
        
        // Try to parse userHoldings for each epoch
        for (uint256 i = 0; i < iPOWATokens.length; i++) {
            string memory idx = vm.toString(i);
            string memory basePath = string.concat(".userHoldings.", idx);
            
            // Try to read user holdings for this epoch
            try vm.parseJsonUint(json, string.concat(basePath, ".iPOWA")) returns (uint256 userIPOWA) {
                if (userIPOWA > 0) {
                    // Transfer iPOWA tokens to user
                    vm.prank(ocfVault);
                    iPOWATokens[i].transfer(testUser, userIPOWA);
                    
                    uint256 pending = iPOWATokens[i].pendingRevenue(testUser);
                    totalClaimable += pending;
                    
                    console2.log("Epoch", i, "iPOWA:");
                    console2.log("  Holdings:", userIPOWA);
                    console2.log(string.concat("  Pending Revenue: ", formatTokens(pending), " tokens"));
                }
            } catch {
                // No iPOWA holdings for this epoch
            }
            
            try vm.parseJsonUint(json, string.concat(basePath, ".cPOWA")) returns (uint256 userCPOWA) {
                if (userCPOWA > 0) {
                    // Transfer cPOWA tokens to user
                    vm.prank(ocfVault);
                    cPOWATokens[i].transfer(testUser, userCPOWA);
                    
                    uint256 pending = cPOWATokens[i].pendingRevenue(testUser);
                    totalClaimable += pending;
                    
                    console2.log("Epoch", i, "cPOWA:");
                    console2.log("  Holdings:", userCPOWA);
                    console2.log(string.concat("  Pending Revenue: ", formatTokens(pending), " tokens"));
                }
            } catch {
                // No cPOWA holdings for this epoch
            }
        }
        
        console2.log("");
        console2.log(string.concat("Total Claimable by User: ", formatTokens(totalClaimable), " tokens"));
    }
    
    function testScenario() public {
        // Run both tests
        testDistribution();
        console2.log("");
        console2.log("=====================================");
        console2.log("");
        testUserClaims();
    }
}