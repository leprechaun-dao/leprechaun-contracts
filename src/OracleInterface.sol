// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./interfaces/IPyth.sol";
import "./interfaces/PythStructs.sol";

/**
 * @title DecimalMath
 * @dev Library for handling decimal math operations with different decimal precisions
 */
library DecimalMath {
    // Standard precision used internally (18 decimals)
    uint256 public constant PRECISION_DECIMALS = 18;
    uint256 public constant PRECISION = 10 ** PRECISION_DECIMALS;

    /**
     * @dev Converts a value from one decimal precision to another
     * @param value The value to convert
     * @param fromDecimals The current decimal precision of the value
     * @param toDecimals The target decimal precision for the result
     * @return The converted value with the target decimal precision
     */
    function convertDecimals(uint256 value, uint8 fromDecimals, uint8 toDecimals) internal pure returns (uint256) {
        if (fromDecimals == toDecimals) {
            return value;
        } else if (fromDecimals < toDecimals) {
            return value * (10 ** (toDecimals - fromDecimals));
        } else {
            return value / (10 ** (fromDecimals - toDecimals));
        }
    }

    /**
     * @dev Normalizes a price value according to its exponent to standard 18 decimal precision
     * @param price The price value from the oracle
     * @param exponent The exponent of the price (usually negative)
     * @return The normalized price with 18 decimal precision
     */
    function normalizePrice(uint256 price, int32 exponent) internal pure returns (uint256) {
        // Convert to 18 decimal precision regardless of exponent
        if (exponent < 0) {
            // For negative exponents (e.g., -8), we need to divide by 10^(abs(exponent) - 18)
            // or multiply by 10^(18 + exponent) [where exponent is negative]
            uint256 scaleFactor = 10 ** uint32(PRECISION_DECIMALS - uint32(-exponent));
            return price * scaleFactor;
        } else {
            // For positive exponents (rare), we multiply by 10^(exponent + 18)
            uint256 scaleFactor = 10 ** uint32(PRECISION_DECIMALS + uint32(exponent));
            return price * scaleFactor;
        }
    }

    /**
     * @dev Safely calculates (a * b) / c with overflow protection
     * @param a First multiplicand
     * @param b Second multiplicand
     * @param c Divisor
     * @return The result of (a * b) / c
     */
    function mulDiv(uint256 a, uint256 b, uint256 c) internal pure returns (uint256) {
        // Ensure we don't divide by zero
        require(c > 0, "Division by zero");

        // Use assembly for safe multiplication and division of large numbers
        uint256 result;
        assembly {
            // First multiply a and b
            let product := mul(a, b)

            // Check for overflow
            if or(
                // Either a or b is zero, thus no overflow
                or(iszero(a), iszero(b)),
                // No overflow if (a * b) / a == b
                eq(div(product, a), b)
            ) { result := div(product, c) }
        }
        return result;
    }
}

/**
 * @title OracleInterface
 * @dev Enhanced interface for oracle price feeds using the Pyth Network
 *      This refactored implementation standardizes all price-related calculations
 *      to use a consistent decimal approach and provides clearer, more reliable
 *      methods for price conversions.
 */
contract OracleInterface {
    /**
     * @dev Reference to the Pyth Network contract that provides price data
     */
    IPyth public pyth;

    /**
     * @dev Mapping of asset addresses to their corresponding Pyth price feed IDs
     */
    mapping(address => bytes32) public priceFeedIds;

    /**
     * @dev Maximum allowed age for price data in seconds
     *      Prices older than this threshold are considered stale and will be rejected
     */
    uint256 public constant MAX_PRICE_AGE = 3600; // 1 hour

    // Events
    /**
     * @dev Emitted when a new price feed is registered for an asset
     * @param asset The address of the asset (synthetic or collateral)
     * @param feedId The Pyth price feed ID assigned to the asset
     */
    event PriceFeedRegistered(address indexed asset, bytes32 feedId);

    /**
     * @dev Emitted when a price is updated for an asset
     * @param asset The address of the asset
     * @param price The new price value (scaled by 10^8)
     * @param timestamp The timestamp when the price was published
     */
    event PriceUpdated(address indexed asset, int64 price, uint256 timestamp);

    /**
     * @dev Constructor
     * @param _pythAddress The address of the Pyth contract on the current chain
     * @notice Initializes the oracle interface with a connection to the Pyth Network
     */
    constructor(address _pythAddress) {
        require(_pythAddress != address(0), "Invalid Pyth address");
        pyth = IPyth(_pythAddress);
    }

    /**
     * @dev Register a price feed for an asset
     * @param asset The address of the asset (synthetic or collateral)
     * @param feedId The Pyth price feed ID for the asset's price data
     * @notice Only one price feed can be registered per asset
     * @notice This function is called by the LeprechaunFactory when registering new assets
     */
    function registerPriceFeed(address asset, bytes32 feedId) external {
        require(asset != address(0), "Invalid asset address");
        require(feedId != bytes32(0), "Invalid feed ID");
        require(priceFeedIds[asset] == bytes32(0), "Price feed already registered");

        priceFeedIds[asset] = feedId;

        emit PriceFeedRegistered(asset, feedId);
    }

    /**
     * @dev Get the normalized USD price for an asset
     * @param asset The address of the asset
     * @return price The normalized price in USD (scaled to 18 decimals)
     * @return timestamp The timestamp of the price
     * @notice Returns the price normalized to 18 decimals for consistent calculations
     */
    function getNormalizedPrice(address asset) public view returns (uint256 price, uint256 timestamp) {
        bytes32 feedId = priceFeedIds[asset];
        require(feedId != bytes32(0), "Price feed not registered");

        // Get the price from Pyth using the recommended method with MAX_PRICE_AGE
        // This will revert with StalePrice error if the price is older than MAX_PRICE_AGE
        PythStructs.Price memory pythPrice = pyth.getPriceNoOlderThan(feedId, block.timestamp - MAX_PRICE_AGE);

        // Convert to positive uint256 and normalize to 18 decimals
        uint256 normalizedPrice = DecimalMath.normalizePrice(uint256(uint64(pythPrice.price)), pythPrice.expo);

        return (normalizedPrice, pythPrice.publishTime);
    }

    /**
     * @dev Get the raw price data from Pyth
     * @param asset The address of the asset
     * @return price The price in USD (as reported by Pyth)
     * @return timestamp The timestamp of the price
     * @return decimals The exponent in the price
     */
    function getRawPrice(address asset) external view returns (int64 price, uint256 timestamp, int32 decimals) {
        bytes32 feedId = priceFeedIds[asset];
        require(feedId != bytes32(0), "Price feed not registered");

        PythStructs.Price memory pythPrice = pyth.getPriceNoOlderThan(feedId, block.timestamp - MAX_PRICE_AGE);
        return (pythPrice.price, pythPrice.publishTime, pythPrice.expo);
    }

    /**
     * @dev Check if a price feed is registered for an asset
     * @param asset The address of the asset
     * @return registered Whether the price feed is registered
     */
    function isPriceFeedRegistered(address asset) external view returns (bool) {
        return priceFeedIds[asset] != bytes32(0);
    }

    /**
     * @dev Get the USD value of a token amount
     * @param asset The address of the asset
     * @param amount The amount of tokens
     * @param assetDecimals The number of decimals in the asset
     * @return value The USD value of the tokens (scaled to 18 decimals)
     */
    function getUsdValue(address asset, uint256 amount, uint8 assetDecimals) external view returns (uint256) {
        (uint256 normalizedPrice,) = getNormalizedPrice(asset);

        // Convert amount to 18 decimals for consistent calculations
        uint256 standardizedAmount = DecimalMath.convertDecimals(amount, assetDecimals, 18);

        // Calculate USD value: amount * price / 10^18
        // Since price is already normalized to 18 decimals, we just need to scale the result
        return DecimalMath.mulDiv(standardizedAmount, normalizedPrice, 10 ** 18);
    }

    /**
     * @dev Convert USD value to token amount
     * @param asset The address of the asset
     * @param usdValue The USD value (scaled to 18 decimals)
     * @param assetDecimals The number of decimals in the asset
     * @return amount The equivalent amount of tokens
     */
    function getTokenAmount(address asset, uint256 usdValue, uint8 assetDecimals) external view returns (uint256) {
        (uint256 normalizedPrice,) = getNormalizedPrice(asset);
        require(normalizedPrice > 0, "Invalid price");

        // Calculate token amount in 18 decimals: usdValue * 10^18 / price
        uint256 standardizedAmount = DecimalMath.mulDiv(usdValue, 10 ** 18, normalizedPrice);

        // Convert amount from 18 decimals to asset decimals
        return DecimalMath.convertDecimals(standardizedAmount, 18, assetDecimals);
    }
}
