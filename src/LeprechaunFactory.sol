// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./OracleInterface.sol";
import "./SyntheticAsset.sol";

/**
 * @title LeprechaunFactory
 * @dev Manages the registration and configuration of synthetic assets and collateral types
 *      This contract serves as the central registry for the protocol, storing all parameters
 *      related to synthetic assets, collateral types, and their relationships.
 */
contract LeprechaunFactory is Ownable {
    /**
     * @dev Struct containing all parameters for a synthetic asset
     * @param tokenAddress The address of the synthetic token contract
     * @param name The human-readable name of the synthetic asset (e.g., "Gold Index")
     * @param symbol The trading symbol of the synthetic asset (e.g., "sGOLD")
     * @param minCollateralRatio The minimum collateral ratio required (150% = 15000, scaled by 10000)
     * @param auctionDiscount The discount applied during liquidation auctions (20% = 2000, scaled by 10000)
     * @param isActive Whether the asset is currently active and can be used in the protocol
     */
    struct SyntheticAssetInfo {
        address tokenAddress;
        string name;
        string symbol;
        uint256 minCollateralRatio;
        uint256 auctionDiscount;
        bool isActive;
    }

    /**
     * @dev Struct containing all parameters for a collateral type
     * @param tokenAddress The address of the collateral token contract
     * @param multiplier The risk multiplier applied to this collateral (e.g., 1.33x = 13300, scaled by 10000)
     *        Higher values indicate higher risk and require higher collateralization
     * @param isActive Whether the collateral is currently active and can be used in the protocol
     */
    struct CollateralType {
        address tokenAddress;
        uint256 multiplier;
        bool isActive;
    }

    /**
     * @dev Protocol fee in basis points (1.5% = 150 basis points)
     *      Applied to various operations in the protocol
     */
    uint256 public protocolFee = 150;

    /**
     * @dev Address where protocol fees are sent
     */
    address public feeCollector;

    /**
     * @dev Mapping of synthetic asset information by token address
     */
    mapping(address => SyntheticAssetInfo) public syntheticAssets;

    /**
     * @dev Mapping of synthetic asset addresses by symbol for easy lookup
     */
    mapping(string => address) public syntheticAssetsBySymbol;

    /**
     * @dev Array of all synthetic asset addresses for enumeration
     */
    address[] public allSyntheticAssets;

    /**
     * @dev Mapping of collateral type information by token address
     */
    mapping(address => CollateralType) public collateralTypes;

    /**
     * @dev Array of all collateral addresses for enumeration
     */
    address[] public allCollateralTypes;

    /**
     * @dev Mapping of allowed collateral for each synthetic asset
     *      syntheticAsset => collateral => allowed
     */
    mapping(address => mapping(address => bool)) public allowedCollateral;

    /**
     * @dev Oracle interface for price feeds
     */
    OracleInterface public oracle;

    /**
     * @dev Emitted when a new synthetic asset is registered
     * @param tokenAddress The address of the synthetic token
     * @param symbol The symbol of the synthetic asset
     */
    event SyntheticAssetRegistered(address indexed tokenAddress, string symbol);

    /**
     * @dev Emitted when a synthetic asset's parameters are updated
     * @param tokenAddress The address of the synthetic token
     */
    event SyntheticAssetUpdated(address indexed tokenAddress);

    /**
     * @dev Emitted when a synthetic asset is deactivated
     * @param tokenAddress The address of the synthetic token
     */
    event SyntheticAssetDeactivated(address indexed tokenAddress);

    /**
     * @dev Emitted when a new collateral type is registered
     * @param tokenAddress The address of the collateral token
     * @param multiplier The collateral multiplier
     */
    event CollateralTypeRegistered(address indexed tokenAddress, uint256 multiplier);

    /**
     * @dev Emitted when a collateral type's parameters are updated
     * @param tokenAddress The address of the collateral token
     * @param multiplier The new collateral multiplier
     */
    event CollateralTypeUpdated(address indexed tokenAddress, uint256 multiplier);

    /**
     * @dev Emitted when a collateral type is deactivated
     * @param tokenAddress The address of the collateral token
     */
    event CollateralTypeDeactivated(address indexed tokenAddress);

    /**
     * @dev Emitted when a collateral is allowed for a synthetic asset
     * @param syntheticAsset The address of the synthetic asset
     * @param collateral The address of the collateral
     */
    event CollateralAllowedForAsset(address indexed syntheticAsset, address indexed collateral);

    /**
     * @dev Emitted when a collateral is disallowed for a synthetic asset
     * @param syntheticAsset The address of the synthetic asset
     * @param collateral The address of the collateral
     */
    event CollateralDisallowedForAsset(address indexed syntheticAsset, address indexed collateral);

    /**
     * @dev Emitted when the protocol fee is updated
     * @param newFee The new protocol fee in basis points
     */
    event ProtocolFeeUpdated(uint256 newFee);

    /**
     * @dev Emitted when the fee collector address is updated
     * @param newCollector The new fee collector address
     */
    event FeeCollectorUpdated(address newCollector);

    /**
     * @dev Constructor
     * @param initialOwner The address that will own this contract
     * @param _feeCollector The address where protocol fees will be sent
     * @param _oracle The address of the oracle contract for price feeds
     */
    constructor(address initialOwner, address _feeCollector, address _oracle) Ownable(initialOwner) {
        require(_oracle != address(0), "Invalid oracle address");
        require(_feeCollector != address(0), "Invalid feeCollector address");

        oracle = OracleInterface(_oracle);
        feeCollector = _feeCollector;
    }

    /**
     * @dev Register a new synthetic asset
     * @param name The name of the synthetic asset
     * @param symbol The symbol of the synthetic asset
     * @param minCollateralRatio The minimum collateral ratio (scaled by 10000)
     * @param auctionDiscount The discount applied during liquidations (scaled by 10000)
     * @param priceFeedId The ID of the price feed in the oracle
     * @param positionManager The address of the position manager contract
     */
    function registerSyntheticAsset(
        string memory name,
        string memory symbol,
        uint256 minCollateralRatio,
        uint256 auctionDiscount,
        bytes32 priceFeedId,
        address positionManager
    ) external onlyOwner {
        require(bytes(symbol).length > 0, "Symbol cannot be empty");
        require(syntheticAssetsBySymbol[symbol] == address(0), "Symbol already in use");
        require(positionManager != address(0), "Invalid position manager address");
        require(minCollateralRatio >= 10000, "Collateral ratio must be at least 100%");
        require(priceFeedId != bytes32(0), "Invalid price feed id");

        // Deploy new token contract for this asset
        address tokenAddress = address(new SyntheticAsset(name, symbol, positionManager));

        // Register price feed for the new asset
        oracle.registerPriceFeed(tokenAddress, priceFeedId);

        // Store asset information
        syntheticAssets[tokenAddress] = SyntheticAssetInfo({
            tokenAddress: tokenAddress,
            name: name,
            symbol: symbol,
            minCollateralRatio: minCollateralRatio,
            auctionDiscount: auctionDiscount,
            isActive: true
        });
        syntheticAssetsBySymbol[symbol] = tokenAddress;
        allSyntheticAssets.push(tokenAddress);

        emit SyntheticAssetRegistered(tokenAddress, symbol);
    }

    /**
     * @dev Update a synthetic asset's parameters
     * @param tokenAddress The address of the synthetic asset token
     * @param minCollateralRatio The new minimum collateral ratio (scaled by 10000)
     * @param auctionDiscount The new auction discount for liquidations (scaled by 10000)
     */
    function updateSyntheticAsset(address tokenAddress, uint256 minCollateralRatio, uint256 auctionDiscount)
        external
        onlyOwner
    {
        require(syntheticAssets[tokenAddress].tokenAddress != address(0), "Asset not registered");
        require(minCollateralRatio >= 10000, "Collateral ratio must be at least 100%");

        SyntheticAssetInfo storage asset = syntheticAssets[tokenAddress];
        asset.minCollateralRatio = minCollateralRatio;
        asset.auctionDiscount = auctionDiscount;

        emit SyntheticAssetUpdated(tokenAddress);
    }

    /**
     * @dev Deactivate a synthetic asset
     * @param tokenAddress The address of the synthetic asset token
     * @notice Once deactivated, no new positions can be created with this asset
     */
    function deactivateSyntheticAsset(address tokenAddress) external onlyOwner {
        require(syntheticAssets[tokenAddress].tokenAddress != address(0), "Asset not registered");
        require(syntheticAssets[tokenAddress].isActive, "Asset already deactivated");

        syntheticAssets[tokenAddress].isActive = false;

        emit SyntheticAssetDeactivated(tokenAddress);
    }

    /**
     * @dev Register a new collateral type
     * @param tokenAddress The address of the collateral token
     * @param multiplier The collateral multiplier (scaled by 10000)
     * @param priceFeedId The ID of the price feed in the oracle
     * @notice Higher multiplier values indicate higher risk and require more collateral
     */
    function registerCollateralType(address tokenAddress, uint256 multiplier, bytes32 priceFeedId) external onlyOwner {
        require(tokenAddress != address(0), "Invalid token address");
        require(collateralTypes[tokenAddress].tokenAddress == address(0), "Collateral already registered");
        require(multiplier >= 10000, "Multiplier must be at least 1x (10000)");
        require(priceFeedId != bytes32(0), "Invalid price feed id");

        // Register price feed for the collateral
        oracle.registerPriceFeed(tokenAddress, priceFeedId);

        // Store collateral information
        CollateralType memory collateral =
            CollateralType({tokenAddress: tokenAddress, multiplier: multiplier, isActive: true});

        collateralTypes[tokenAddress] = collateral;
        allCollateralTypes.push(tokenAddress);

        emit CollateralTypeRegistered(tokenAddress, multiplier);
    }

    /**
     * @dev Update a collateral type's parameters
     * @param tokenAddress The address of the collateral token
     * @param multiplier The new collateral multiplier (scaled by 10000)
     */
    function updateCollateralType(address tokenAddress, uint256 multiplier) external onlyOwner {
        require(collateralTypes[tokenAddress].tokenAddress != address(0), "Collateral not registered");
        require(multiplier >= 10000, "Multiplier must be at least 1x (10000)");

        collateralTypes[tokenAddress].multiplier = multiplier;

        emit CollateralTypeUpdated(tokenAddress, multiplier);
    }

    /**
     * @dev Deactivate a collateral type
     * @param tokenAddress The address of the collateral token
     * @notice Once deactivated, no new positions can be created with this collateral
     */
    function deactivateCollateralType(address tokenAddress) external onlyOwner {
        require(collateralTypes[tokenAddress].tokenAddress != address(0), "Collateral not registered");
        require(collateralTypes[tokenAddress].isActive, "Collateral already deactivated");

        collateralTypes[tokenAddress].isActive = false;

        emit CollateralTypeDeactivated(tokenAddress);
    }

    /**
     * @dev Allow a collateral type to be used for a specific synthetic asset
     * @param syntheticAsset The address of the synthetic asset
     * @param collateralAddress The address of the collateral token
     */
    function allowCollateralForAsset(address syntheticAsset, address collateralAddress) external onlyOwner {
        require(syntheticAssets[syntheticAsset].tokenAddress != address(0), "Synthetic asset not registered");
        require(collateralTypes[collateralAddress].tokenAddress != address(0), "Collateral not registered");
        require(!allowedCollateral[syntheticAsset][collateralAddress], "Collateral already allowed for this asset");

        allowedCollateral[syntheticAsset][collateralAddress] = true;

        emit CollateralAllowedForAsset(syntheticAsset, collateralAddress);
    }

    /**
     * @dev Disallow a collateral type for a specific synthetic asset
     * @param syntheticAsset The address of the synthetic asset
     * @param collateralAddress The address of the collateral token
     * @notice Existing positions with this collateral will not be affected
     */
    function disallowCollateralForAsset(address syntheticAsset, address collateralAddress) external onlyOwner {
        require(allowedCollateral[syntheticAsset][collateralAddress], "Collateral not allowed for this asset");

        allowedCollateral[syntheticAsset][collateralAddress] = false;

        emit CollateralDisallowedForAsset(syntheticAsset, collateralAddress);
    }

    /**
     * @dev Update the protocol fee
     * @param newFee The new protocol fee in basis points (e.g., 150 = 1.5%)
     */
    function updateProtocolFee(uint256 newFee) external onlyOwner {
        require(newFee <= 1000, "Fee cannot exceed 10%");
        protocolFee = newFee;
        emit ProtocolFeeUpdated(newFee);
    }

    /**
     * @dev Update the fee collector address
     * @param newCollector The new address where protocol fees will be sent
     */
    function updateFeeCollector(address newCollector) external onlyOwner {
        require(newCollector != address(0), "Invalid fee collector address");
        feeCollector = newCollector;
        emit FeeCollectorUpdated(newCollector);
    }

    /**
     * @dev Get the effective minimum collateral ratio for a synthetic asset and collateral type
     * @param syntheticAsset The address of the synthetic asset
     * @param collateralAddress The address of the collateral token
     * @return The effective minimum collateral ratio (scaled by 10000)
     * @notice This takes into account both the asset's minimum ratio and the collateral's risk multiplier
     */
    function getEffectiveCollateralRatio(address syntheticAsset, address collateralAddress)
        external
        view
        returns (uint256)
    {
        require(syntheticAssets[syntheticAsset].tokenAddress != address(0), "Synthetic asset not registered");
        require(collateralTypes[collateralAddress].tokenAddress != address(0), "Collateral not registered");
        require(allowedCollateral[syntheticAsset][collateralAddress], "Collateral not allowed for this asset");

        uint256 assetMinRatio = syntheticAssets[syntheticAsset].minCollateralRatio;
        uint256 collateralMultiplier = collateralTypes[collateralAddress].multiplier;

        // Calculate effective ratio (minRatio * multiplier / 10000)
        return (assetMinRatio * collateralMultiplier) / 10000;
    }

    /**
     * @dev Check if a synthetic asset is active
     * @param syntheticAsset The address of the synthetic asset
     * @return Whether the synthetic asset is active
     */
    function isSyntheticAssetActive(address syntheticAsset) external view returns (bool) {
        return syntheticAssets[syntheticAsset].isActive;
    }

    /**
     * @dev Check if a collateral type is active
     * @param collateralAddress The address of the collateral token
     * @return Whether the collateral type is active
     */
    function isCollateralActive(address collateralAddress) external view returns (bool) {
        return collateralTypes[collateralAddress].isActive;
    }

    /**
     * @dev Get the auction discount for a synthetic asset
     * @param syntheticAsset The address of the synthetic asset
     * @return The auction discount (scaled by 10000)
     * @notice This is the discount applied to the collateral during liquidations
     */
    function getAuctionDiscount(address syntheticAsset) external view returns (uint256) {
        return syntheticAssets[syntheticAsset].auctionDiscount;
    }

    /**
     * @dev Get the number of registered synthetic assets
     * @return The count of all registered synthetic assets
     */
    function getSyntheticAssetCount() external view returns (uint256) {
        return allSyntheticAssets.length;
    }

    /**
     * @dev Get the number of registered collateral types
     * @return The count of all registered collateral types
     */
    function getCollateralTypeCount() external view returns (uint256) {
        return allCollateralTypes.length;
    }
}
