// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IPyth} from "./interfaces/IPyth.sol";
import {PythStructs} from "./interfaces/PythStructs.sol";
import "./interfaces/IPriceOracle.sol";

/**
 * @title PythPriceOracle
 * @dev Implementation of price oracle using Pyth Network
 */
contract PythPriceOracle is IPriceOracle, Ownable {
    // Pyth Network contract
    IPyth public immutable pyth;

    // Mapping from asset ID to Pyth price feed ID
    mapping(bytes32 => bytes32) private assetToPythId;

    // Default maximum staleness period (1 hour)
    uint256 public defaultMaxStaleness = 1 hours;

    // Events
    event AssetPriceFeedRegistered(
        bytes32 indexed assetId,
        bytes32 indexed pythId
    );
    event DefaultMaxStalenessUpdated(uint256 oldValue, uint256 newValue);

    /**
     * @dev Constructor initializes the Pyth Network connection
     * @param _pythAddress Address of the Pyth contract
     */
    constructor(address _pythAddress) Ownable(msg.sender) {
        require(
            _pythAddress != address(0),
            "PythPriceOracle: pyth address cannot be zero"
        );
        pyth = IPyth(_pythAddress);
    }

    /**
     * @dev Register a new asset with its Pyth price feed ID
     * @param assetId Protocol's asset ID
     * @param pythId Pyth price feed ID
     */
    function registerAssetPriceFeed(
        bytes32 assetId,
        bytes32 pythId
    ) external onlyOwner {
        require(
            assetId != bytes32(0),
            "PythPriceOracle: assetId cannot be zero"
        );
        require(pythId != bytes32(0), "PythPriceOracle: pythId cannot be zero");
        require(
            assetToPythId[assetId] == bytes32(0),
            "PythPriceOracle: asset already registered"
        );

        assetToPythId[assetId] = pythId;

        emit AssetPriceFeedRegistered(assetId, pythId);
    }

    /**
     * @dev Set the default maximum staleness period
     * @param maxStaleness New maximum staleness in seconds
     */
    function setDefaultMaxStaleness(uint256 maxStaleness) external onlyOwner {
        require(
            maxStaleness > 0,
            "PythPriceOracle: max staleness must be positive"
        );
        uint256 oldValue = defaultMaxStaleness;
        defaultMaxStaleness = maxStaleness;

        emit DefaultMaxStalenessUpdated(oldValue, maxStaleness);
    }

    /**
     * @dev Get latest price data for an asset
     * @param assetId ID of the asset
     * @return price PriceData struct containing price information
     */
    function getLatestPriceData(
        bytes32 assetId
    ) public view override returns (PriceData memory price) {
        bytes32 pythId = getPythPriceFeedId(assetId);
        require(pythId != bytes32(0), "PythPriceOracle: asset not registered");

        PythStructs.Price memory pythPrice = pyth.getPriceUnsafe(pythId);

        return
            PriceData({
                price: pythPrice.price,
                conf: pythPrice.conf,
                expo: pythPrice.expo,
                publishTime: pythPrice.publishTime
            });
    }

    /**
     * @dev Get normalized price value for an asset in USD (18 decimals)
     * @param assetId ID of the asset
     * @return price Price in USD (18 decimals precision)
     * @return publishTime Timestamp when the price was published
     */
    function getNormalizedPrice(
        bytes32 assetId
    ) external view override returns (uint256 price, uint256 publishTime) {
        PriceData memory priceData = getLatestPriceData(assetId);

        // Convert to positive value (assumes price feeds are for USD pairs)
        int64 rawPrice = priceData.price;
        require(rawPrice > 0, "PythPriceOracle: negative price not supported");

        // Normalize to 18 decimals
        int32 expo = priceData.expo;
        uint256 normalizedPrice;

        // Convert to 18 decimals
        if (expo < 0) {
            // If price has decimals, multiply by 10^18 and divide by 10^(-expo)
            uint256 denominator = uint256(10 ** uint32(-expo));
            normalizedPrice = (uint256(uint64(rawPrice)) * 1e18) / denominator;
        } else {
            // If price is whole number, multiply by 10^18 and by 10^expo
            normalizedPrice =
                uint256(uint64(rawPrice)) *
                1e18 *
                uint256(10 ** uint32(expo));
        }

        // Verify the price is not zero after normalization
        require(
            normalizedPrice > 0,
            "PythPriceOracle: normalized price is zero"
        );

        return (normalizedPrice, priceData.publishTime);
    }

    /**
     * @dev Check if price is stale (not updated recently)
     * @param assetId ID of the asset
     * @param maxAge Maximum age in seconds (0 to use default)
     * @return True if price is stale
     */
    function isPriceStale(
        bytes32 assetId,
        uint256 maxAge
    ) external view override returns (bool) {
        PriceData memory priceData = getLatestPriceData(assetId);

        // Use default if maxAge is 0
        if (maxAge == 0) {
            maxAge = defaultMaxStaleness;
        }

        return (block.timestamp - priceData.publishTime) > maxAge;
    }

    /**
     * @dev Get Pyth price feed ID for a given asset
     * @param assetId Protocol's asset ID
     * @return Pyth price feed ID
     */
    function getPythPriceFeedId(
        bytes32 assetId
    ) public view override returns (bytes32) {
        bytes32 pythId = assetToPythId[assetId];
        return pythId;
    }
}
