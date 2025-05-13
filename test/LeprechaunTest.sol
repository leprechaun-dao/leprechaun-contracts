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

    // Additional method for Pyth interface
    function getPriceNoOlderThan(bytes32 priceId, uint256 age) external view returns (PythStructs.Price memory) {
        PythStructs.Price memory price = prices[priceId];
        require(block.timestamp - price.publishTime <= age, "Price too old");
        return price;
    }

    // Stubbed methods to satisfy interface
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
 * @title SimpleLeprechaunTest
 * @dev Simplified test to debug the price feed issue
 */
contract SimpleLeprechaunTest is Test {
    // Protocol contracts
    LeprechaunFactory public factory;
    PositionManager public positionManager;
    MockPyth public pyth;
    OracleInterface public oracle;

    // Test tokens
    MockToken public collateralToken;
    address public syntheticAsset;

    // Price feed IDs
    bytes32 public constant COLLATERAL_FEED_ID = keccak256("COLLATERAL_FEED");
    bytes32 public constant SYNTHETIC_FEED_ID = keccak256("SYNTHETIC_FEED");

    // Test accounts
    address public owner = address(1);
    address public feeCollector = address(2);
    address public user = address(3);

    // Test parameters
    uint256 public constant MIN_COLLATERAL_RATIO = 15000; // 150%
    uint256 public constant AUCTION_DISCOUNT = 1000; // 10%
    uint256 public constant COLLATERAL_MULTIPLIER = 12000; // 1.2x

    function setUp() public {
        vm.warp(1000000); // Set a non-zero timestamp

        // Deploy mock Pyth oracle
        pyth = new MockPyth();

        // Set initial prices
        pyth.setPrice(COLLATERAL_FEED_ID, 100000000, block.timestamp, -8); // $1.00
        pyth.setPrice(SYNTHETIC_FEED_ID, 200000000, block.timestamp, -8); // $2.00

        // Deploy oracle interface
        oracle = new OracleInterface(address(pyth));

        // Deploy test tokens
        collateralToken = new MockToken("Collateral Token", "COLL");

        // Deploy factory
        vm.prank(owner);
        factory = new LeprechaunFactory(owner, feeCollector, address(oracle));

        // Deploy position manager
        vm.prank(owner);
        positionManager = new PositionManager(address(factory), address(oracle), owner);

        // Register collateral type
        vm.prank(owner);
        factory.registerCollateralType(address(collateralToken), COLLATERAL_MULTIPLIER, COLLATERAL_FEED_ID);

        // Register synthetic asset
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

        // Allow collateral for synthetic asset
        vm.prank(owner);
        factory.allowCollateralForAsset(syntheticAsset, address(collateralToken));

        // Mint collateral token to user
        collateralToken.mint(user, 1000 ether);
    }

    /**
     * @dev Test a simple position creation
     */
    function testPositionCreation() public {
        uint256 collateralAmount = 200 ether; // $200
        uint256 mintAmount = 50 ether; // $100 (at $2 per synthetic token)

        vm.startPrank(user);
        collateralToken.approve(address(positionManager), collateralAmount);

        uint256 positionId =
            positionManager.createPosition(syntheticAsset, address(collateralToken), collateralAmount, mintAmount);
        vm.stopPrank();

        // Verify position
        (
            address positionOwner,
            address assetAddress,
            address collateralAddress,
            uint256 posCollateral,
            uint256 posMinted,
            ,
            bool isActive
        ) = positionManager.getPosition(positionId);

        assertEq(positionOwner, user, "Position owner mismatch");
        assertEq(assetAddress, syntheticAsset, "Synthetic asset mismatch");
        assertEq(collateralAddress, address(collateralToken), "Collateral mismatch");
        assertEq(posCollateral, collateralAmount, "Collateral amount mismatch");
        assertEq(posMinted, mintAmount, "Minted amount mismatch");
        assertTrue(isActive, "Position should be active");

        // Check collateral ratio
        uint256 ratio = positionManager.getCollateralRatio(positionId);
        uint256 minRatio = factory.getEffectiveCollateralRatio(syntheticAsset, address(collateralToken));
        assertTrue(ratio >= minRatio, "Collateral ratio too low");

        console.log("Position created successfully");
        console.log("Collateral ratio:", ratio);
        console.log("Minimum required ratio:", minRatio);
    }
}
