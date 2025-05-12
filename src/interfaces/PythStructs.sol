// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title PythStructs
 * @dev Structs used by the Pyth protocol
 */
library PythStructs {
    // Price information for a price feed
    struct Price {
        // Price value
        int64 price;
        // Confidence interval
        uint64 conf;
        // Price exponent
        int32 expo;
        // Unix timestamp of the price update
        uint256 publishTime;
    }

    // Price feed information
    struct PriceFeed {
        // Price feed ID
        bytes32 id;
        // Latest available price
        Price price;
        // Latest available exponentially-weighted moving average price
        Price emaPrice;
    }
}
