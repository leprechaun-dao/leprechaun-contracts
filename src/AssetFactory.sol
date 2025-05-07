// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./TokenizedAsset.sol";
import "./interfaces/IPriceOracle.sol";
import "./interfaces/IAssetFactory.sol";

/**
 * @title AssetFactory
 * @dev Creates and manages tokenized assets in the Leprechaun Protocol
 */
contract AssetFactory is IAssetFactory, Ownable {
    using SafeERC20 for IERC20;

    // Mapping from assetId to AssetType
    mapping(bytes32 => AssetType) public assetTypes;

    // Mapping from token address to CollateralType
    mapping(address => CollateralType) public collateralTypes;

    // Array of all asset IDs
    bytes32[] public allAssetIds;

    // Array of all collateral token addresses
    address[] public allCollateralTokens;

    // Mapping from assetId to Pyth price feed ID
    mapping(bytes32 => bytes32) public assetToPythId;

    // Maximum price staleness (1 hour by default)
    uint256 public maxPriceStaleness = 1 hours;

    // Minimum collateralization ratio (150% = 15000, using basis points)
    uint256 public constant MIN_COLLATERAL_RATIO = 15000;

    // Liquidation threshold (100% = 10000, using basis points)
    uint256 public constant LIQUIDATION_THRESHOLD = 10000;

    // Events
    event AssetTypeRegistered(
        bytes32 indexed assetId,
        string name,
        string symbol,
        address tokenAddress,
        address oracleAddress,
        uint256 minCollateralRatio
    );

    event PythPriceFeedRegistered(
        bytes32 indexed assetId,
        bytes32 indexed pythId
    );

    event CollateralTypeAdded(
        address indexed tokenAddress,
        address oracleAddress,
        uint256 collateralFactor
    );

    event CollateralTypeRemoved(address indexed tokenAddress);

    event AssetParametersUpdated(
        bytes32 indexed assetId,
        uint256 minCollateralRatio,
        uint256 liquidationPenalty
    );

    event MaxPriceStalenessUpdated(uint256 oldValue, uint256 newValue);

    /**
     * @dev Constructor initializes the owner
     */
    constructor() Ownable(msg.sender) {}

    /**
     * @dev Registers a new asset type in the protocol
     * @param name Name of the asset
     * @param symbol Symbol of the asset
     * @param oracleAddress Address of the price oracle for this asset
     * @param pythPriceFeedId Pyth Network price feed ID for this asset
     * @param minCollateralRatio Minimum collateralization ratio for this asset (in basis points)
     * @param liquidationPenalty Penalty applied during liquidation (in basis points)
     */
    function registerAssetType(
        string memory name,
        string memory symbol,
        address oracleAddress,
        bytes32 pythPriceFeedId,
        uint256 minCollateralRatio,
        uint256 liquidationPenalty
    ) external onlyOwner returns (bytes32 assetId) {
        require(
            oracleAddress != address(0),
            "AssetFactory: oracle address cannot be zero"
        );
        require(
            pythPriceFeedId != bytes32(0),
            "AssetFactory: price feed ID cannot be zero"
        );
        require(
            minCollateralRatio >= MIN_COLLATERAL_RATIO,
            "AssetFactory: ratio below minimum"
        );

        // Generate asset ID from name and symbol
        assetId = keccak256(abi.encodePacked(name, symbol));

        // Check if asset already exists
        require(
            assetTypes[assetId].isActive == false,
            "AssetFactory: asset already exists"
        );

        // Deploy new token contract for this asset
        TokenizedAsset tokenContract = new TokenizedAsset(
            name,
            symbol,
            address(this) // Factory is the owner/controller of the token
        );

        // Create asset type
        AssetType memory newAsset = AssetType({
            assetId: assetId,
            assetName: name,
            assetSymbol: symbol,
            tokenAddress: address(tokenContract),
            oracleAddress: oracleAddress,
            minCollateralRatio: minCollateralRatio,
            liquidationThreshold: LIQUIDATION_THRESHOLD,
            liquidationPenalty: liquidationPenalty,
            isActive: true
        });

        // Store asset type
        assetTypes[assetId] = newAsset;

        // Store Pyth price feed ID
        assetToPythId[assetId] = pythPriceFeedId;

        // Add to list of assets
        allAssetIds.push(assetId);

        // Emit events
        emit AssetTypeRegistered(
            assetId,
            name,
            symbol,
            address(tokenContract),
            oracleAddress,
            minCollateralRatio
        );

        emit PythPriceFeedRegistered(assetId, pythPriceFeedId);

        return assetId;
    }

    /**
     * @dev Set the maximum staleness for price feeds
     * @param staleness New maximum staleness in seconds
     */
    function setMaxPriceStaleness(uint256 staleness) external onlyOwner {
        require(staleness > 0, "AssetFactory: staleness must be positive");
        uint256 oldValue = maxPriceStaleness;
        maxPriceStaleness = staleness;

        emit MaxPriceStalenessUpdated(oldValue, staleness);
    }

    /**
     * @dev Adds a collateral type to the protocol
     * @param tokenAddress Address of the collateral token
     * @param oracleAddress Address of the price oracle for this collateral
     * @param collateralFactor Collateral factor (in basis points)
     */
    function addCollateralType(
        address tokenAddress,
        address oracleAddress,
        uint256 collateralFactor
    ) external onlyOwner {
        require(
            tokenAddress != address(0),
            "AssetFactory: token address cannot be zero"
        );
        require(
            oracleAddress != address(0),
            "AssetFactory: oracle address cannot be zero"
        );
        require(
            collateralFactor > 0,
            "AssetFactory: collateral factor must be positive"
        );

        // Check if token is ERC20 compliant
        IERC20(tokenAddress).totalSupply(); // This will revert if not ERC20

        // Create collateral type
        CollateralType memory newCollateral = CollateralType({
            tokenAddress: tokenAddress,
            oracleAddress: oracleAddress,
            collateralFactor: collateralFactor,
            isActive: true
        });

        // Store collateral type
        collateralTypes[tokenAddress] = newCollateral;

        // Add to list of collateral tokens
        allCollateralTokens.push(tokenAddress);

        // Emit event
        emit CollateralTypeAdded(tokenAddress, oracleAddress, collateralFactor);
    }

    /**
     * @dev Removes a collateral type from the protocol
     * @param tokenAddress Address of the collateral token to remove
     */
    function removeCollateralType(address tokenAddress) external onlyOwner {
        require(
            collateralTypes[tokenAddress].isActive,
            "AssetFactory: collateral not active"
        );

        // Disable collateral
        collateralTypes[tokenAddress].isActive = false;

        // Emit event
        emit CollateralTypeRemoved(tokenAddress);
    }

    /**
     * @dev Updates parameters for an asset type
     * @param assetId ID of the asset to update
     * @param minCollateralRatio New minimum collateralization ratio
     * @param liquidationPenalty New liquidation penalty
     */
    function updateAssetParameters(
        bytes32 assetId,
        uint256 minCollateralRatio,
        uint256 liquidationPenalty
    ) external onlyOwner {
        require(assetTypes[assetId].isActive, "AssetFactory: asset not active");
        require(
            minCollateralRatio >= MIN_COLLATERAL_RATIO,
            "AssetFactory: ratio below minimum"
        );

        // Update parameters
        assetTypes[assetId].minCollateralRatio = minCollateralRatio;
        assetTypes[assetId].liquidationPenalty = liquidationPenalty;

        // Emit event
        emit AssetParametersUpdated(
            assetId,
            minCollateralRatio,
            liquidationPenalty
        );
    }

    /**
     * @dev Get all registered asset types
     * @return Array of AssetType structs
     */
    function getAllAssetTypes() external view returns (AssetType[] memory) {
        AssetType[] memory result = new AssetType[](allAssetIds.length);

        for (uint256 i = 0; i < allAssetIds.length; i++) {
            result[i] = assetTypes[allAssetIds[i]];
        }

        return result;
    }

    /**
     * @dev Get all registered collateral types
     * @return Array of CollateralType structs
     */
    function getAllCollateralTypes()
        external
        view
        returns (CollateralType[] memory)
    {
        CollateralType[] memory result = new CollateralType[](
            allCollateralTokens.length
        );

        for (uint256 i = 0; i < allCollateralTokens.length; i++) {
            result[i] = collateralTypes[allCollateralTokens[i]];
        }

        return result;
    }

    /**
     * @dev Check if a collateral type is active
     * @param tokenAddress Address of the collateral token
     * @return True if collateral is active
     */
    function isCollateralActive(
        address tokenAddress
    ) external view returns (bool) {
        return collateralTypes[tokenAddress].isActive;
    }

    /**
     * @dev Get token address for an asset ID
     * @param assetId ID of the asset
     * @return Address of the tokenized asset contract
     */
    function getTokenAddress(bytes32 assetId) external view returns (address) {
        require(assetTypes[assetId].isActive, "AssetFactory: asset not active");
        return assetTypes[assetId].tokenAddress;
    }

    /**
     * @dev Get Pyth price feed ID for an asset
     * @param assetId ID of the asset
     * @return Pyth price feed ID
     */
    function getPythPriceFeedId(
        bytes32 assetId
    ) external view returns (bytes32) {
        require(assetTypes[assetId].isActive, "AssetFactory: asset not active");
        bytes32 pythId = assetToPythId[assetId];
        require(
            pythId != bytes32(0),
            "AssetFactory: price feed not registered"
        );
        return pythId;
    }

    /**
     * @dev Get asset price in USD (normalized to 18 decimals)
     * @param assetId ID of the asset
     * @return price Price in USD (18 decimals)
     * @return publishTime Timestamp when the price was published
     */
    function getAssetPrice(
        bytes32 assetId
    ) external view returns (uint256 price, uint256 publishTime) {
        require(assetTypes[assetId].isActive, "AssetFactory: asset not active");

        address oracleAddress = assetTypes[assetId].oracleAddress;
        IPriceOracle oracle = IPriceOracle(oracleAddress);

        // Check if price is stale
        require(
            !oracle.isPriceStale(assetId, maxPriceStaleness),
            "AssetFactory: price is stale"
        );

        // Get normalized price (18 decimals)
        return oracle.getNormalizedPrice(assetId);
    }

    /**
     * @dev Get asset type details
     * @param assetId ID of the asset
     * @return AssetType struct containing asset details
     */
    function getAssetType(
        bytes32 assetId
    ) external view returns (AssetType memory) {
        return assetTypes[assetId];
    }

    /**
     * @dev Get collateral type details
     * @param tokenAddress Address of the collateral token
     * @return CollateralType struct containing collateral details
     */
    function getCollateralType(
        address tokenAddress
    ) external view returns (CollateralType memory) {
        return collateralTypes[tokenAddress];
    }
}
