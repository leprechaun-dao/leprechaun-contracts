// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/IPriceOracle.sol";

/**
 * @title MockPriceOracle
 * @dev Mock implementation of a price oracle for testing, mimicking Pyth Network behavior
 */
contract MockPriceOracle is IPriceOracle, Ownable {
    // Mapping from asset ID to price data
    mapping(bytes32 => PriceData) private priceData;

    // Mapping from asset ID to Pyth price feed ID
    mapping(bytes32 => bytes32) private assetToPythId;

    // Default maximum staleness period (1 hour)
    uint256 public defaultMaxStaleness = 1 hours;

    // Events
    event PriceUpdated(
        bytes32 indexed assetId,
        int64 price,
        uint64 conf,
        int32 expo,
        uint256 publishTime
    );
    event AssetPriceFeedRegistered(
        bytes32 indexed assetId,
        bytes32 indexed pythId
    );

    /**
     * @dev Constructor initializes the owner
     */
    constructor() Ownable(msg.sender) {}

    /**
     * @dev Register asset with a mock Pyth price feed ID
     * @param assetId Protocol's asset ID
     * @param pythId Mock Pyth price feed ID
     */
    function registerAssetPriceFeed(
        bytes32 assetId,
        bytes32 pythId
    ) external onlyOwner {
        require(
            assetId != bytes32(0),
            "MockPriceOracle: assetId cannot be zero"
        );
        require(pythId != bytes32(0), "MockPriceOracle: pythId cannot be zero");

        assetToPythId[assetId] = pythId;

        emit AssetPriceFeedRegistered(assetId, pythId);
    }

    /**
     * @dev Set mock price for an asset
     * @param assetId ID of the asset
     * @param price Price value (signed)
     * @param conf Confidence interval
     * @param expo Price exponent (e.g., -8 for 8 decimal places)
     */
    function setMockPrice(
        bytes32 assetId,
        int64 price,
        uint64 conf,
        int32 expo
    ) public onlyOwner {
        require(
            assetId != bytes32(0),
            "MockPriceOracle: assetId cannot be zero"
        );

        PriceData memory data = PriceData({
            price: price,
            conf: conf,
            expo: expo,
            publishTime: block.timestamp
        });

        priceData[assetId] = data;

        emit PriceUpdated(assetId, price, conf, expo, block.timestamp);
    }

    /**
     * @dev Convenience function to set mock price with common format
     * @param assetId ID of the asset
     * @param priceUSD Price in USD (with 8 decimals)
     * @param confidencePercentage Confidence as percentage of price (1-100)
     */
    function setMockPriceUSD(
        bytes32 assetId,
        uint256 priceUSD,
        uint8 confidencePercentage
    ) external onlyOwner {
        require(
            priceUSD <= uint256(uint64(type(int64).max)),
            "MockPriceOracle: price too large"
        );
        require(
            confidencePercentage <= 100,
            "MockPriceOracle: confidence too large"
        );

        int64 price = int64(uint64(priceUSD));
        uint64 conf = uint64((priceUSD * confidencePercentage) / 100);
        int32 expo = -8; // Standard 8 decimals for USD prices

        setMockPrice(assetId, price, conf, expo);
    }

    /**
     * @dev Set the default maximum staleness period
     * @param maxStaleness New maximum staleness in seconds
     */
    function setDefaultMaxStaleness(uint256 maxStaleness) external onlyOwner {
        require(
            maxStaleness > 0,
            "MockPriceOracle: max staleness must be positive"
        );
        defaultMaxStaleness = maxStaleness;
    }

    /**
     * @dev Get latest price data for an asset
     * @param assetId ID of the asset
     * @return price PriceData struct containing price information
     */
    function getLatestPriceData(
        bytes32 assetId
    ) public view override returns (PriceData memory price) {
        PriceData memory data = priceData[assetId];
        //require(data.available, "MockPriceOracle: price not available");
        return data;
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
        PriceData memory data = getLatestPriceData(assetId);

        // Convert to positive value (assumes price feeds are for USD pairs)
        int64 rawPrice = data.price;
        require(rawPrice > 0, "MockPriceOracle: negative price not supported");

        // Normalize to 18 decimals
        int32 expo = data.expo;
        uint256 normalizedPrice = uint256(uint64(rawPrice)) *
            10 ** uint32(18 + (-expo));
        return (normalizedPrice, data.publishTime);
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
        PriceData memory data = getLatestPriceData(assetId);

        // Use default if maxAge is 0
        if (maxAge == 0) {
            maxAge = defaultMaxStaleness;
        }

        return (block.timestamp - data.publishTime) > maxAge;
    }

    /**
     * @dev Get Pyth price feed ID for a given asset
     * @param assetId Protocol's asset ID
     * @return pythId Pyth price feed ID
     */
    function getPythPriceFeedId(
        bytes32 assetId
    ) external view override returns (bytes32 pythId) {
        pythId = assetToPythId[assetId];
        require(
            pythId != bytes32(0),
            "MockPriceOracle: price feed not registered"
        );
        return pythId;
    }
}
