// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./OracleInterface.sol";
import "./SyntheticAsset.sol";

/**
 * @title LeprechaunRegistry
 * @dev Manages the registration of synthetic assets and their parameters
 */
contract LeprechaunFactory is Ownable {
    // Struct to hold synthetic asset parameters
    struct SyntheticAssetInfo {
        address tokenAddress; // The address of the synthetic token
        string name; // The name of the synthetic asset (e.g., "Gold Index")
        string symbol; // The symbol of the synthetic asset (e.g., "sGOLD")
        uint256 minCollateralRatio; // Minimum collateral ratio (150% = 15000)
        uint256 auctionDiscount; // Auction discount for liquidations (20% = 2000)
        bool isActive; // Whether the asset is active
    }

    // Struct to hold collateral parameters
    struct CollateralType {
        address tokenAddress; // The address of the collateral token
        uint256 multiplier; // Collateral multiplier (e.g., 1.33x = 13300)
        bool isActive; // Whether the collateral is active
    }

    // Protocol-wide parameters
    uint256 public protocolFee = 150; // 1.5% = 150 basis points
    address public feeCollector; // Address where fees are sent

    // Mapping of synthetic assets by token address
    mapping(address => SyntheticAssetInfo) public syntheticAssets;
    // Mapping of synthetic assets by symbol
    mapping(string => address) public syntheticAssetsBySymbol;
    // Array of all synthetic asset addresses
    address[] public allSyntheticAssets;

    // Mapping of collateral types by token address
    mapping(address => CollateralType) public collateralTypes;
    // Array of all collateral addresses
    address[] public allCollateralTypes;

    // Mapping of allowed collateral for each synthetic asset
    mapping(address => mapping(address => bool)) public allowedCollateral; // syntheticAsset => collateral => allowed

    // Oracle interface
    OracleInterface public oracle;

    // Events
    event SyntheticAssetRegistered(address indexed tokenAddress, string symbol);
    event SyntheticAssetUpdated(address indexed tokenAddress);
    event SyntheticAssetDeactivated(address indexed tokenAddress);

    event CollateralTypeRegistered(
        address indexed tokenAddress,
        uint256 multiplier
    );
    event CollateralTypeUpdated(
        address indexed tokenAddress,
        uint256 multiplier
    );
    event CollateralTypeDeactivated(address indexed tokenAddress);

    event CollateralAllowedForAsset(
        address indexed syntheticAsset,
        address indexed collateral
    );
    event CollateralDisallowedForAsset(
        address indexed syntheticAsset,
        address indexed collateral
    );

    event ProtocolFeeUpdated(uint256 newFee);
    event FeeCollectorUpdated(address newCollector);

    constructor(
        address initialOwner,
        address _feeCollector,
        address _oracle
    ) Ownable(initialOwner) {
        require(_oracle != address(0), "Invalid oracle address");
        require(feeCollector != address(0), "Invalid feeCollector address");

        oracle = OracleInterface(_oracle);
        feeCollector = _feeCollector;
    }

    /**
     * @dev Register a new synthetic asset
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
        require(
            syntheticAssetsBySymbol[symbol] == address(0),
            "Symbol already in use"
        );
        require(
            positionManager != address(0),
            "Invalid position manager address"
        );
        require(
            minCollateralRatio >= 10000,
            "Collateral ratio must be at least 100%"
        );
        require(priceFeedId != bytes32(0), "Invalid price feed id");

        // Deploy new token contract for this asset
        address tokenAddress = address(
            new SyntheticAsset(name, symbol, positionManager)
        );

        oracle.registerPriceFeed(tokenAddress, priceFeedId);

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
     */
    function updateSyntheticAsset(
        address tokenAddress,
        uint256 minCollateralRatio,
        uint256 auctionDiscount
    ) external onlyOwner {
        require(
            syntheticAssets[tokenAddress].tokenAddress != address(0),
            "Asset not registered"
        );
        require(
            minCollateralRatio >= 10000,
            "Collateral ratio must be at least 100%"
        );

        SyntheticAssetInfo storage asset = syntheticAssets[tokenAddress];
        asset.minCollateralRatio = minCollateralRatio;
        asset.auctionDiscount = auctionDiscount;

        emit SyntheticAssetUpdated(tokenAddress);
    }

    /**
     * @dev Deactivate a synthetic asset
     */
    function deactivateSyntheticAsset(address tokenAddress) external onlyOwner {
        require(
            syntheticAssets[tokenAddress].tokenAddress != address(0),
            "Asset not registered"
        );
        require(
            syntheticAssets[tokenAddress].isActive,
            "Asset already deactivated"
        );

        syntheticAssets[tokenAddress].isActive = false;

        emit SyntheticAssetDeactivated(tokenAddress);
    }

    /**
     * @dev Register a new collateral type
     */
    function registerCollateralType(
        address tokenAddress,
        uint256 multiplier,
        bytes32 priceFeedId
    ) external onlyOwner {
        require(tokenAddress != address(0), "Invalid token address");
        require(
            collateralTypes[tokenAddress].tokenAddress == address(0),
            "Collateral already registered"
        );
        require(multiplier >= 10000, "Multiplier must be at least 1x (10000)");
        require(priceFeedId != bytes32(0), "Invalid price feed id");

        oracle.registerPriceFeed(tokenAddress, priceFeedId);
        CollateralType memory collateral = CollateralType({
            tokenAddress: tokenAddress,
            multiplier: multiplier,
            isActive: true
        });

        collateralTypes[tokenAddress] = collateral;
        allCollateralTypes.push(tokenAddress);

        emit CollateralTypeRegistered(tokenAddress, multiplier);
    }

    /**
     * @dev Update a collateral type's parameters
     */
    function updateCollateralType(
        address tokenAddress,
        uint256 multiplier
    ) external onlyOwner {
        require(
            collateralTypes[tokenAddress].tokenAddress != address(0),
            "Collateral not registered"
        );
        require(multiplier >= 10000, "Multiplier must be at least 1x (10000)");

        collateralTypes[tokenAddress].multiplier = multiplier;

        emit CollateralTypeUpdated(tokenAddress, multiplier);
    }

    /**
     * @dev Deactivate a collateral type
     */
    function deactivateCollateralType(address tokenAddress) external onlyOwner {
        require(
            collateralTypes[tokenAddress].tokenAddress != address(0),
            "Collateral not registered"
        );
        require(
            collateralTypes[tokenAddress].isActive,
            "Collateral already deactivated"
        );

        collateralTypes[tokenAddress].isActive = false;

        emit CollateralTypeDeactivated(tokenAddress);
    }

    /**
     * @dev Allow a collateral type for a synthetic asset
     */
    function allowCollateralForAsset(
        address syntheticAsset,
        address collateralAddress
    ) external onlyOwner {
        require(
            syntheticAssets[syntheticAsset].tokenAddress != address(0),
            "Synthetic asset not registered"
        );
        require(
            collateralTypes[collateralAddress].tokenAddress != address(0),
            "Collateral not registered"
        );
        require(
            !allowedCollateral[syntheticAsset][collateralAddress],
            "Collateral already allowed for this asset"
        );

        allowedCollateral[syntheticAsset][collateralAddress] = true;

        emit CollateralAllowedForAsset(syntheticAsset, collateralAddress);
    }

    /**
     * @dev Disallow a collateral type for a synthetic asset
     */
    function disallowCollateralForAsset(
        address syntheticAsset,
        address collateralAddress
    ) external onlyOwner {
        require(
            allowedCollateral[syntheticAsset][collateralAddress],
            "Collateral not allowed for this asset"
        );

        allowedCollateral[syntheticAsset][collateralAddress] = false;

        emit CollateralDisallowedForAsset(syntheticAsset, collateralAddress);
    }

    /**
     * @dev Update the protocol fee
     */
    function updateProtocolFee(uint256 newFee) external onlyOwner {
        require(newFee <= 1000, "Fee cannot exceed 10%");
        protocolFee = newFee;
        emit ProtocolFeeUpdated(newFee);
    }

    /**
     * @dev Update the fee collector address
     */
    function updateFeeCollector(address newCollector) external onlyOwner {
        require(newCollector != address(0), "Invalid fee collector address");
        feeCollector = newCollector;
        emit FeeCollectorUpdated(newCollector);
    }

    /**
     * @dev Get the effective minimum collateral ratio for a synthetic asset and collateral type
     */
    function getEffectiveCollateralRatio(
        address syntheticAsset,
        address collateralAddress
    ) external view returns (uint256) {
        require(
            syntheticAssets[syntheticAsset].tokenAddress != address(0),
            "Synthetic asset not registered"
        );
        require(
            collateralTypes[collateralAddress].tokenAddress != address(0),
            "Collateral not registered"
        );
        require(
            allowedCollateral[syntheticAsset][collateralAddress],
            "Collateral not allowed for this asset"
        );

        uint256 assetMinRatio = syntheticAssets[syntheticAsset]
            .minCollateralRatio;
        uint256 collateralMultiplier = collateralTypes[collateralAddress]
            .multiplier;

        // Calculate effective ratio (minRatio * multiplier / 10000)
        return (assetMinRatio * collateralMultiplier) / 10000;
    }

    /**
     * @dev Check if a synthetic asset is active
     */
    function isSyntheticAssetActive(
        address syntheticAsset
    ) external view returns (bool) {
        return syntheticAssets[syntheticAsset].isActive;
    }

    /**
     * @dev Check if a collateral type is active
     */
    function isCollateralActive(
        address collateralAddress
    ) external view returns (bool) {
        return collateralTypes[collateralAddress].isActive;
    }

    /**
     * @dev Get the auction discount for a synthetic asset
     */
    function getAuctionDiscount(
        address syntheticAsset
    ) external view returns (uint256) {
        return syntheticAssets[syntheticAsset].auctionDiscount;
    }

    /**
     * @dev Get the number of registered synthetic assets
     */
    function getSyntheticAssetCount() external view returns (uint256) {
        return allSyntheticAssets.length;
    }

    /**
     * @dev Get the number of registered collateral types
     */
    function getCollateralTypeCount() external view returns (uint256) {
        return allCollateralTypes.length;
    }
}
