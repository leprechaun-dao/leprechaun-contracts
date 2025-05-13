// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/LeprechaunFactory.sol";
import "../src/PositionManager.sol";
import "../src/OracleInterface.sol";
import "../src/SyntheticAsset.sol";
import "../src/interfaces/IPyth.sol";
import "../src/interfaces/PythStructs.sol";

/**
 * @title MockToken
 * @dev Simple ERC20 token for testing
 */
contract MockToken is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }
}

/**
 * @dev Custom ERC20 that supports different decimal places
 */
contract CustomDecimalToken is ERC20 {
    uint8 private _decimals;

    constructor(string memory name, string memory symbol, uint8 decimalsValue) ERC20(name, symbol) {
        _decimals = decimalsValue;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }
}

/**
 * @title MockPyth
 * @dev Mock Pyth oracle implementation for testing
 */
contract MockPyth {
    mapping(bytes32 => PythStructs.Price) public prices;

    // Set a price for a feed
    function setPrice(bytes32 priceId, int64 price, uint256 publishTime, int32 expo) external {
        prices[priceId] = PythStructs.Price({price: price, conf: 0, expo: expo, publishTime: publishTime});
    }

    // Implement IPyth interface
    function getPrice(bytes32 priceId) external view returns (PythStructs.Price memory) {
        return prices[priceId];
    }

    function getPriceNoOlderThan(bytes32 priceId, uint256 age) external view returns (PythStructs.Price memory) {
        PythStructs.Price memory price = prices[priceId];
        require(block.timestamp - price.publishTime <= age, "Price too old");
        return price;
    }

    // Other required Pyth interface methods
    function getUpdateFee(bytes[] calldata) external pure returns (uint256) {
        return 0.01 ether;
    }

    function updatePriceFeeds(bytes[] calldata) external payable {
        // Mock implementation
    }

    function getValidTimePeriod() external pure returns (uint256) {
        return 3600; // 1 hour
    }

    function getPriceUnsafe(bytes32 priceId) external view returns (PythStructs.Price memory) {
        return prices[priceId];
    }

    function getEmaPrice(bytes32 priceId) external view returns (PythStructs.Price memory) {
        return prices[priceId]; // Simplified for testing
    }

    function getEmaPriceUnsafe(bytes32 priceId) external view returns (PythStructs.Price memory) {
        return prices[priceId]; // Simplified for testing
    }

    function getEmaPriceNoOlderThan(bytes32 priceId, uint256 age) external view returns (PythStructs.Price memory) {
        PythStructs.Price memory price = prices[priceId];
        require(block.timestamp - price.publishTime <= age, "Price too old");
        return price;
    }

    function parsePriceFeedUpdates(bytes[] calldata) external payable returns (bytes32[] memory) {
        return new bytes32[](0);
    }

    function updatePriceFeedsIfNecessary(bytes[] calldata, bytes32[] calldata, uint64, uint64)
        external
        payable
        returns (bool)
    {
        return true;
    }

    function parsePriceUpdateData(bytes calldata) external pure returns (bytes32, PythStructs.Price memory) {
        return (bytes32(0), PythStructs.Price({price: 0, conf: 0, expo: 0, publishTime: 0}));
    }
}

/**
 * @title ComprehensiveMathTest
 * @dev Comprehensive test for all mathematical functionality in Leprechaun Protocol
 */
contract ComprehensiveMathTest is Test {
    // Protocol contracts
    LeprechaunFactory public factory;
    PositionManager public positionManager;
    MockPyth public pyth;
    OracleInterface public oracle;

    // Test tokens
    MockToken public collateralToken;
    CustomDecimalToken public token6Dec;
    CustomDecimalToken public token8Dec;
    address public syntheticAsset;

    // Price feed IDs
    bytes32 public constant COLLATERAL_FEED_ID = keccak256("COLLATERAL_FEED");
    bytes32 public constant TOKEN6_FEED_ID = keccak256("TOKEN6_FEED");
    bytes32 public constant TOKEN8_FEED_ID = keccak256("TOKEN8_FEED");
    bytes32 public constant SYNTHETIC_FEED_ID = keccak256("SYNTHETIC_FEED");
    bytes32 public constant DOW_FEED_ID = keccak256("DOW_FEED");

    // Test accounts
    address public owner = address(1);
    address public feeCollector = address(2);
    address public user = address(3);
    address public liquidator = address(4);

    // Test parameters
    uint256 public constant MIN_COLLATERAL_RATIO = 15000; // 150%
    uint256 public constant AUCTION_DISCOUNT = 1000; // 10%
    uint256 public constant COLLATERAL_MULTIPLIER = 12000; // 1.2x
    uint256 public constant PROTOCOL_FEE = 150; // 1.5%

    function setUp() public {
        vm.warp(1000000); // Set a non-zero timestamp

        // Deploy mock Pyth oracle
        pyth = new MockPyth();

        // Set initial prices for test tokens
        pyth.setPrice(COLLATERAL_FEED_ID, 100000000, block.timestamp, -8); // $1.00
        pyth.setPrice(TOKEN6_FEED_ID, 100000000, block.timestamp, -8); // $1.00
        pyth.setPrice(TOKEN8_FEED_ID, 100000000, block.timestamp, -8); // $1.00
        pyth.setPrice(SYNTHETIC_FEED_ID, 200000000, block.timestamp, -8); // $2.00
        pyth.setPrice(DOW_FEED_ID, 3098500, block.timestamp, -5); // $30.985 (DOW-like)

        // Deploy oracle interface
        oracle = new OracleInterface(address(pyth));

        // Deploy test tokens
        collateralToken = new MockToken("Collateral Token", "COLL");
        token6Dec = new CustomDecimalToken("Six Dec Token", "SIX", 6);
        token8Dec = new CustomDecimalToken("Eight Dec Token", "EIGHT", 8);

        // Deploy factory
        vm.prank(owner);
        factory = new LeprechaunFactory(owner, feeCollector, address(oracle));

        // Deploy position manager
        vm.prank(owner);
        positionManager = new PositionManager(address(factory), address(oracle), owner);

        // Register collateral types - these will register price feeds internally
        vm.startPrank(owner);
        factory.registerCollateralType(address(collateralToken), COLLATERAL_MULTIPLIER, COLLATERAL_FEED_ID);

        factory.registerCollateralType(address(token6Dec), COLLATERAL_MULTIPLIER, TOKEN6_FEED_ID);

        factory.registerCollateralType(address(token8Dec), COLLATERAL_MULTIPLIER, TOKEN8_FEED_ID);
        vm.stopPrank();

        // Register synthetic asset - will register price feed internally
        vm.prank(owner);
        factory.registerSyntheticAsset(
            "Synthetic Gold",
            "sGOLD",
            MIN_COLLATERAL_RATIO,
            AUCTION_DISCOUNT,
            SYNTHETIC_FEED_ID,
            address(positionManager)
        );

        // Get the synthetic asset address
        syntheticAsset = factory.allSyntheticAssets(0);

        // Allow collateral types for synthetic asset
        vm.startPrank(owner);
        factory.allowCollateralForAsset(syntheticAsset, address(collateralToken));
        factory.allowCollateralForAsset(syntheticAsset, address(token6Dec));
        factory.allowCollateralForAsset(syntheticAsset, address(token8Dec));
        vm.stopPrank();

        // Mint test tokens to users
        collateralToken.mint(user, 10000 ether);
        collateralToken.mint(liquidator, 10000 ether);
        token6Dec.mint(user, 10000 * 10 ** 6);
        token8Dec.mint(user, 10000 * 10 ** 8);

        // Log setup completion
        console.log(
            "Setup complete. Effective collateral ratio:",
            factory.getEffectiveCollateralRatio(syntheticAsset, address(collateralToken))
        );
    }

    /**
     * @dev Test bidirectional calculations (collateral to synthetic and back)
     */
    function testBidirectionalCalculations() public {
        console.log("\n=== Testing Bidirectional Calculations ===");

        // Test with small, medium, and large amounts of standard token
        _testBidirectionalCalculation("SMALL", 1 ether);
        _testBidirectionalCalculation("MEDIUM", 10 ether);
        _testBidirectionalCalculation("LARGE", 100 ether);

        // Test with tokens of different decimals
        _testBidirectionalCalculationDifferentDecimals("6 DECIMALS", address(token6Dec), 100 * 10 ** 6);
        _testBidirectionalCalculationDifferentDecimals("8 DECIMALS", address(token8Dec), 100 * 10 ** 8);
    }

    /**
     * @dev Helper function to test bidirectional calculation
     */
    function _testBidirectionalCalculation(string memory label, uint256 collateralAmount) internal view {
        console.log(label, "amount:", collateralAmount / 1e18, "tokens");

        // Calculate mintable amount
        uint256 mintableAmount =
            positionManager.getMintableAmount(syntheticAsset, address(collateralToken), collateralAmount);

        console.log("  Mintable synthetic tokens:", mintableAmount / 1e18);

        // Calculate required collateral for the mintable amount
        uint256 requiredCollateral =
            positionManager.getRequiredCollateral(syntheticAsset, address(collateralToken), mintableAmount);

        console.log("  Required collateral for mintable amount:", requiredCollateral / 1e18);

        // Calculate percentage difference
        uint256 differencePercentage;
        if (collateralAmount > 0) {
            if (requiredCollateral > collateralAmount) {
                differencePercentage = ((requiredCollateral - collateralAmount) * 100) / collateralAmount;
            } else {
                differencePercentage = ((collateralAmount - requiredCollateral) * 100) / collateralAmount;
            }
        }

        console.log("  Difference percentage: ", differencePercentage, "%");

        // The difference should be very small (less than 1%)
        assertLe(differencePercentage, 1, "Bidirectional calculation difference too large");
    }

    /**
     * @dev Helper function to test bidirectional calculation with different decimal tokens
     */
    function _testBidirectionalCalculationDifferentDecimals(
        string memory label,
        address collateralAsset,
        uint256 collateralAmount
    ) internal view {
        console.log("\nTesting", label);

        uint8 decimals;
        if (collateralAsset == address(token6Dec)) {
            decimals = 6;
            console.log("  Collateral amount:", collateralAmount / 1e6, "tokens");
        } else if (collateralAsset == address(token8Dec)) {
            decimals = 8;
            console.log("  Collateral amount:", collateralAmount / 1e8, "tokens");
        } else {
            decimals = 18;
            console.log("  Collateral amount:", collateralAmount / 1e18, "tokens");
        }

        // Calculate mintable amount
        uint256 mintableAmount = positionManager.getMintableAmount(syntheticAsset, collateralAsset, collateralAmount);

        console.log("  Mintable synthetic tokens:", mintableAmount / 1e18);

        // Skip if mintable amount is zero
        if (mintableAmount == 0) {
            console.log("  Mintable amount is zero, skipping reverse calculation");
            return;
        }

        // Calculate required collateral for the mintable amount
        uint256 requiredCollateral =
            positionManager.getRequiredCollateral(syntheticAsset, collateralAsset, mintableAmount);

        if (decimals == 6) {
            console.log("  Required collateral:", requiredCollateral / 1e6);
        } else if (decimals == 8) {
            console.log("  Required collateral:", requiredCollateral / 1e8);
        } else {
            console.log("  Required collateral:", requiredCollateral / 1e18);
        }

        // Calculate percentage difference
        uint256 differencePercentage;
        if (collateralAmount > 0 && requiredCollateral > 0) {
            if (requiredCollateral > collateralAmount) {
                differencePercentage = ((requiredCollateral - collateralAmount) * 100) / collateralAmount;
            } else {
                differencePercentage = ((collateralAmount - requiredCollateral) * 100) / collateralAmount;
            }
        }

        console.log("  Difference percentage: ", differencePercentage, "%");

        // The difference should be very small (less than 1%)
        assertLe(differencePercentage, 1, "Bidirectional calculation difference too large");
    }

    /**
     * @dev Test for the DOW scenario with -5 exponent price
     */
    function testDowScenario() public {
        console.log("\n=== Testing DOW Scenario with -5 Exponent ===");

        // Change the synthetic asset price to mimic DOW with -5 exponent
        pyth.setPrice(SYNTHETIC_FEED_ID, 3098500, block.timestamp, -5); // $30.985

        // Test with a specific amount of collateral
        uint256 collateralAmount = 1000 * 10 ** 6; // 1,000 USDC

        // Calculate mintable amount
        uint256 mintableAmount = positionManager.getMintableAmount(syntheticAsset, address(token6Dec), collateralAmount);

        console.log("  Collateral amount (USDC):", collateralAmount / 1e6);
        console.log("  Mintable DOW tokens:", mintableAmount / 1e18);

        // Create position
        vm.startPrank(user);
        token6Dec.approve(address(positionManager), collateralAmount);

        uint256 positionId =
            positionManager.createPosition(syntheticAsset, address(token6Dec), collateralAmount, mintableAmount);
        vm.stopPrank();

        // Check position
        (
            address positionOwner, // asset address // collateral address
            ,
            ,
            uint256 posCollateral,
            uint256 posMinted,
            ,
            bool isActive
        ) = positionManager.getPosition(positionId);

        console.log("\n  Created Position:");
        console.log("    Owner:", positionOwner);
        console.log("    Collateral amount:", posCollateral / 1e6);
        console.log("    Minted amount:", posMinted / 1e18);
        console.log("    Active:", isActive);

        // Check collateral ratio
        uint256 ratio = positionManager.getCollateralRatio(positionId);
        uint256 minRatio = factory.getEffectiveCollateralRatio(syntheticAsset, address(token6Dec));

        console.log("    Collateral ratio:", ratio);
        console.log("    Required ratio:", minRatio);

        assertTrue(ratio >= minRatio, "Position should be properly collateralized");
    }

    /**
     * @dev Test liquidation with price changes
     */
    function testLiquidation() public {
        console.log("\n=== Testing Liquidation ===");

        // Create a position with just enough collateral
        uint256 collateralAmount = 400 ether; // $400
        uint256 mintAmount = 100 ether; // $200 (price = $2)

        // Create position
        vm.startPrank(user);
        collateralToken.approve(address(positionManager), collateralAmount);
        uint256 positionId =
            positionManager.createPosition(syntheticAsset, address(collateralToken), collateralAmount, mintAmount);
        vm.stopPrank();

        // Check initial ratio
        uint256 initialRatio = positionManager.getCollateralRatio(positionId);
        console.log("  Initial collateral ratio:", initialRatio);

        // Make position under-collateralized by dropping collateral price
        pyth.setPrice(COLLATERAL_FEED_ID, 20000000, block.timestamp, -8); // $0.20

        // Check updated ratio
        uint256 updatedRatio = positionManager.getCollateralRatio(positionId);
        console.log("  Updated ratio after price drop:", updatedRatio);

        // Check if position is under-collateralized
        bool isUnder = positionManager.isUnderCollateralized(positionId);
        console.log("  Is under-collateralized:", isUnder);

        uint256 minRatio = factory.getEffectiveCollateralRatio(syntheticAsset, address(collateralToken));
        console.log("  Minimum required ratio:", minRatio);

        assertTrue(isUnder, "Position should be under-collateralized after price drop");

        // Create a position for liquidator to get synthetic tokens
        // Creating a position with price dropped to $0.20 requires 5x more collateral
        vm.startPrank(liquidator);
        collateralToken.approve(address(positionManager), 5000 ether);

        // Create position with enough synthetic tokens to liquidate
        // Need at least $20 * 100 tokens * (18000/10000) = $360 worth of collateral
        // At $0.20 per collateral token, we need at least 1800 tokens
        uint256 liquidatorCollateral = 2000 ether; // 2000 tokens = $400 at $0.20 price

        positionManager.createPosition(syntheticAsset, address(collateralToken), liquidatorCollateral, mintAmount);

        // Get balances before liquidation
        uint256 liquidatorCollateralBefore = collateralToken.balanceOf(liquidator);
        uint256 liquidatorSyntheticBefore = SyntheticAsset(syntheticAsset).balanceOf(liquidator);

        // Approve synthetic tokens for burning during liquidation
        SyntheticAsset(syntheticAsset).approve(address(positionManager), mintAmount);

        // Liquidate the position
        positionManager.liquidate(positionId);
        vm.stopPrank();

        // Check results
        uint256 liquidatorCollateralAfter = collateralToken.balanceOf(liquidator);
        uint256 liquidatorSyntheticAfter = SyntheticAsset(syntheticAsset).balanceOf(liquidator);

        uint256 collateralReceived = liquidatorCollateralAfter - liquidatorCollateralBefore;
        uint256 syntheticSpent = liquidatorSyntheticBefore - liquidatorSyntheticAfter;

        console.log("  Liquidator spent:", syntheticSpent / 1e18, "synthetic tokens");
        console.log("  Liquidator received:", collateralReceived / 1e18, "collateral tokens");

        assertTrue(collateralReceived > 0, "Liquidator should receive collateral");
        assertEq(syntheticSpent, mintAmount, "Liquidator should spend the debt amount");

        // Verify position is closed
        (,,,,,, bool isActive) = positionManager.getPosition(positionId);
        assertFalse(isActive, "Position should be closed after liquidation");
    }

    /**
     * @dev Test extreme price scenarios
     */
    function testExtremePriceScenarios() public {
        console.log("\n=== Testing Extreme Price Scenarios ===");

        // Very high price - $1,000,000 per token
        pyth.setPrice(SYNTHETIC_FEED_ID, 100000000000000, block.timestamp, -8); // $1,000,000.00

        // Try small collateral amount
        uint256 collateralAmount = 1 ether; // $1
        uint256 mintableAmount =
            positionManager.getMintableAmount(syntheticAsset, address(collateralToken), collateralAmount);

        console.log("  With synthetic price $1,000,000:");
        console.log("    Collateral: $1");
        console.log("    Mintable synthetic:", mintableAmount / 1e18);

        // Very low price - $0.00001 per token
        pyth.setPrice(SYNTHETIC_FEED_ID, 1000, block.timestamp, -8); // $0.00001

        // Try large collateral amount
        collateralAmount = 1000 ether; // $1000
        mintableAmount = positionManager.getMintableAmount(syntheticAsset, address(collateralToken), collateralAmount);

        console.log("  With synthetic price $0.00001:");
        console.log("    Collateral: $1000");
        console.log("    Mintable synthetic:", mintableAmount / 1e18);

        // Create a position with extreme values
        if (mintableAmount > 0) {
            vm.startPrank(user);
            collateralToken.approve(address(positionManager), collateralAmount);

            uint256 positionId = positionManager.createPosition(
                syntheticAsset, address(collateralToken), collateralAmount, mintableAmount
            );
            vm.stopPrank();

            // Check position
            uint256 ratio = positionManager.getCollateralRatio(positionId);
            console.log("    Position collateral ratio:", ratio);
            console.log("    Position created successfully with extreme price");
        }

        // Reset price for other tests
        pyth.setPrice(SYNTHETIC_FEED_ID, 200000000, block.timestamp, -8); // $2.00
    }

    /**
     * @dev Test with very small token amounts
     */
    function testSmallAmounts() public view {
        console.log("\n=== Testing Very Small Token Amounts ===");

        // Try with 0.000001 tokens
        uint256 tinyAmount = 1000; // 0.000000000000001 ETH

        uint256 mintableAmount = positionManager.getMintableAmount(syntheticAsset, address(collateralToken), tinyAmount);

        console.log("  Collateral: 0.000000000000001 tokens");
        console.log("  Mintable synthetic:", mintableAmount);

        if (mintableAmount > 0) {
            uint256 requiredCollateral =
                positionManager.getRequiredCollateral(syntheticAsset, address(collateralToken), mintableAmount);

            console.log("  Required collateral for mintable amount:", requiredCollateral);

            // Calculate percentage difference
            uint256 differencePercentage;
            if (tinyAmount > 0 && requiredCollateral > 0) {
                if (requiredCollateral > tinyAmount) {
                    differencePercentage = ((requiredCollateral - tinyAmount) * 100) / tinyAmount;
                } else {
                    differencePercentage = ((tinyAmount - requiredCollateral) * 100) / tinyAmount;
                }
            }

            console.log("  Difference percentage: ", differencePercentage, "%");
        }
    }
}
