// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../src/LeprechaunFactory.sol";
import "../src/PositionManager.sol";
import "../src/SyntheticAsset.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title LeprechaunLens
 * @dev A single contract that provides formatted data access for the Leprechaun Protocol frontend
 */
contract LeprechaunLens {
    LeprechaunFactory public factory;
    PositionManager public positionManager;

    /**
     * @dev Constructor
     * @param _factory Address of the LeprechaunFactory contract
     * @param _positionManager Address of the PositionManager contract
     */
    constructor(address _factory, address _positionManager) {
        factory = LeprechaunFactory(_factory);
        positionManager = PositionManager(_positionManager);
    }

    /**
     * @dev Struct definitions for return types
     */
    struct SyntheticAssetInfo {
        address tokenAddress;
        string name;
        string symbol;
        uint256 minCollateralRatio;
        uint256 auctionDiscount;
        bool isActive;
    }

    struct CollateralTypeInfo {
        address tokenAddress;
        uint256 multiplier;
        bool isActive;
        string symbol;
        string name;
        uint8 decimals;
        uint256 effectiveRatio;
    }

    struct PositionDetails {
        uint256 positionId;
        address owner;
        address syntheticAsset;
        string syntheticSymbol;
        address collateralAsset;
        string collateralSymbol;
        uint256 collateralAmount;
        uint256 mintedAmount;
        uint256 lastUpdateTimestamp;
        bool isActive;
        uint256 currentRatio;
        uint256 requiredRatio;
        bool isUnderCollateralized;
        uint256 collateralUsdValue;
        uint256 debtUsdValue;
    }

    struct ProtocolInfo {
        uint256 fee;
        address collector;
        address oracleAddress;
        address owner;
        uint256 assetCount;
        uint256 collateralCount;
    }

    /**
     * @dev Get protocol configuration in a single call
     * @return info The protocol configuration information
     */
    function getProtocolInfo() external view returns (ProtocolInfo memory) {
        return ProtocolInfo({
            fee: factory.protocolFee(),
            collector: factory.feeCollector(),
            oracleAddress: address(factory.oracle()),
            owner: factory.owner(),
            assetCount: factory.getSyntheticAssetCount(),
            collateralCount: factory.getCollateralTypeCount()
        });
    }

    /**
     * @dev Get all synthetic assets with their details
     * @return assets Array of synthetic asset details
     */
    function getAllSyntheticAssets() external view returns (SyntheticAssetInfo[] memory assets) {
        uint256 assetCount = factory.getSyntheticAssetCount();
        assets = new SyntheticAssetInfo[](assetCount);

        for (uint256 i = 0; i < assetCount; i++) {
            address assetAddress = factory.allSyntheticAssets(i);
            (
                address tokenAddress,
                string memory name,
                string memory symbol,
                uint256 minCollateralRatio,
                uint256 auctionDiscount,
                bool isActive
            ) = factory.syntheticAssets(assetAddress);

            assets[i] = SyntheticAssetInfo({
                tokenAddress: tokenAddress,
                name: name,
                symbol: symbol,
                minCollateralRatio: minCollateralRatio,
                auctionDiscount: auctionDiscount,
                isActive: isActive
            });
        }

        return assets;
    }

    /**
     * @dev Get detailed information about a synthetic asset with its allowed collateral types
     * @param syntheticAsset The address of the synthetic asset
     * @return assetInfo The synthetic asset details
     * @return allowedCollaterals Array of allowed collateral details
     */
    function getSyntheticAssetWithCollateral(address syntheticAsset)
        external
        view
        returns (SyntheticAssetInfo memory assetInfo, CollateralTypeInfo[] memory allowedCollaterals)
    {
        (
            address tokenAddress,
            string memory name,
            string memory symbol,
            uint256 minCollateralRatio,
            uint256 auctionDiscount,
            bool isActive
        ) = factory.syntheticAssets(syntheticAsset);

        require(tokenAddress != address(0), "Asset not registered");

        // Get asset info
        assetInfo = SyntheticAssetInfo({
            tokenAddress: tokenAddress,
            name: name,
            symbol: symbol,
            minCollateralRatio: minCollateralRatio,
            auctionDiscount: auctionDiscount,
            isActive: isActive
        });

        // Get all collateral types to find the allowed ones
        uint256 collateralCount = factory.getCollateralTypeCount();
        uint256 allowedCount = 0;

        // First, count allowed collateral
        for (uint256 i = 0; i < collateralCount; i++) {
            address collateralAddress = factory.allCollateralTypes(i);
            if (factory.allowedCollateral(syntheticAsset, collateralAddress)) {
                allowedCount++;
            }
        }

        // Now create the array of allowed collateral
        allowedCollaterals = new CollateralTypeInfo[](allowedCount);
        uint256 index = 0;

        for (uint256 i = 0; i < collateralCount; i++) {
            address collateralAddress = factory.allCollateralTypes(i);

            if (factory.allowedCollateral(syntheticAsset, collateralAddress)) {
                (address cTokenAddress, uint256 multiplier, bool cIsActive) = factory.collateralTypes(collateralAddress);

                // Get token details
                string memory cSymbol = ERC20(collateralAddress).symbol();
                string memory cName = ERC20(collateralAddress).name();
                uint8 cDecimals = ERC20(collateralAddress).decimals();

                // Calculate effective ratio
                uint256 effectiveRatio = factory.getEffectiveCollateralRatio(syntheticAsset, collateralAddress);

                allowedCollaterals[index] = CollateralTypeInfo({
                    tokenAddress: cTokenAddress,
                    multiplier: multiplier,
                    isActive: cIsActive,
                    symbol: cSymbol,
                    name: cName,
                    decimals: cDecimals,
                    effectiveRatio: effectiveRatio
                });

                index++;
            }
        }

        return (assetInfo, allowedCollaterals);
    }

    /**
     * @dev Get all positions for a user with detailed information
     * @param user The address of the user
     * @return positions Array of position details
     */
    function getUserPositions(address user) external view returns (PositionDetails[] memory positions) {
        uint256 positionCount = positionManager.getUserPositionCount(user);
        positions = new PositionDetails[](positionCount);

        for (uint256 i = 0; i < positionCount; i++) {
            // Get position ID
            uint256 positionId = positionManager.userPositions(user, i);

            // Get position details
            positions[i] = _getPositionDetails(positionId);
        }

        return positions;
    }

    /**
     * @dev Get detailed information about a specific position
     * @param positionId The ID of the position
     * @return details The position details
     */
    function getPosition(uint256 positionId) external view returns (PositionDetails memory details) {
        return _getPositionDetails(positionId);
    }

    /**
     * @dev Get all positions at risk of liquidation
     * @param skip Number of positions to skip (for pagination)
     * @param limit Maximum number of positions to return (for pagination)
     * @return positions Array of position details
     * @return total Total number of at-risk positions
     */
    function getLiquidatablePositions(uint256 skip, uint256 limit)
        external
        view
        returns (PositionDetails[] memory positions, uint256 total)
    {
        // First, count total liquidatable positions
        uint256 liquidatableCount = 0;
        uint256 nextPositionId = positionManager.nextPositionId();

        for (uint256 posId = 1; posId < nextPositionId; posId++) {
            (,,,,,, bool isActive) = positionManager.getPosition(posId);

            if (isActive && positionManager.isUnderCollateralized(posId)) {
                liquidatableCount++;
            }
        }

        total = liquidatableCount;

        // Adjust limit if it exceeds the available positions
        uint256 availablePositions = (skip >= total) ? 0 : total - skip;
        uint256 actualLimit = (limit > availablePositions) ? availablePositions : limit;

        positions = new PositionDetails[](actualLimit);

        // Find liquidatable positions
        uint256 skipped = 0;
        uint256 added = 0;

        for (uint256 posId = 1; posId < nextPositionId && added < actualLimit; posId++) {
            (,,,,,, bool isActive) = positionManager.getPosition(posId);

            if (isActive && positionManager.isUnderCollateralized(posId)) {
                if (skipped < skip) {
                    skipped++;
                } else {
                    positions[added] = _getPositionDetails(posId);
                    added++;
                }
            }
        }

        return (positions, total);
    }

    /**
     * @dev Calculate potential liquidation returns for a position
     * @param positionId The ID of the position to liquidate
     * @return syntheticAmount The amount of synthetic asset needed to liquidate
     * @return collateralReceived The amount of collateral that would be received
     * @return discount The liquidation discount applied
     * @return fee The protocol fee that would be charged
     */
    function calculateLiquidationReturns(uint256 positionId)
        external
        view
        returns (uint256 syntheticAmount, uint256 collateralReceived, uint256 discount, uint256 fee)
    {
        // Make sure position exists
        require(positionId > 0 && positionId < positionManager.nextPositionId(), "Invalid position ID");

        // Get position details
        (
            ,
            address syntheticAsset,
            address collateralAsset,
            uint256 collateralAmount,
            uint256 mintedAmount,
            ,
            bool isActive
        ) = positionManager.getPosition(positionId);

        // If position is not active or has no debt, return zeros
        if (!isActive || mintedAmount == 0) {
            return (0, 0, 0, 0);
        }

        // Check if position can be liquidated
        if (!positionManager.isUnderCollateralized(positionId)) {
            return (0, 0, 0, 0);
        }

        // Calculate auction discount
        discount = factory.getAuctionDiscount(syntheticAsset);

        // Calculate the amount of collateral the liquidator would receive
        syntheticAmount = mintedAmount;

        // Get the value of the debt in USD terms
        uint8 syntheticDecimals = ERC20(syntheticAsset).decimals();
        uint8 collateralDecimals = ERC20(collateralAsset).decimals();

        uint256 debtUsdValue = factory.oracle().getUsdValue(syntheticAsset, mintedAmount, syntheticDecimals);

        // Apply the auction discount to the debt value
        uint256 discountedDebtValue = (debtUsdValue * (10000 + discount)) / 10000;

        // Convert the discounted debt value to collateral tokens
        collateralReceived = factory.oracle().getTokenAmount(collateralAsset, discountedDebtValue, collateralDecimals);

        // Cap the amount to the total collateral available
        if (collateralReceived > collateralAmount) {
            collateralReceived = collateralAmount;
        }

        // Calculate fee on remaining collateral
        uint256 remainingCollateral = collateralAmount - collateralReceived;
        fee = (remainingCollateral * factory.protocolFee()) / 10000;

        return (syntheticAmount, collateralReceived, discount, fee);
    }

    /**
     * @dev Helper function to get position details
     * @param positionId The ID of the position
     * @return details The position details
     */
    function _getPositionDetails(uint256 positionId) internal view returns (PositionDetails memory details) {
        // Make sure position exists
        require(positionId > 0 && positionId < positionManager.nextPositionId(), "Invalid position ID");

        // Get position details
        (
            address owner,
            address syntheticAsset,
            address collateralAsset,
            uint256 collateralAmount,
            uint256 mintedAmount,
            uint256 lastUpdateTimestamp,
            bool isActive
        ) = positionManager.getPosition(positionId);

        // Calculate current collateral ratio
        uint256 collateralRatio = 0;
        if (isActive && mintedAmount > 0) {
            collateralRatio = positionManager.getCollateralRatio(positionId);
        }

        // Get required collateral ratio
        uint256 requiredRatio = 0;
        if (isActive) {
            requiredRatio = factory.getEffectiveCollateralRatio(syntheticAsset, collateralAsset);
        }

        // Check if position is at risk of liquidation
        bool isUnderCollateralized = false;
        if (isActive) {
            isUnderCollateralized = positionManager.isUnderCollateralized(positionId);
        }

        // Get token symbols
        string memory syntheticSymbol = "";
        string memory collateralSymbol = "";
        if (isActive) {
            syntheticSymbol = ERC20(syntheticAsset).symbol();
            collateralSymbol = ERC20(collateralAsset).symbol();
        }

        // Calculate USD values
        uint256 collateralUsdValue = 0;
        uint256 debtUsdValue = 0;

        if (isActive) {
            uint8 syntheticDecimals = ERC20(syntheticAsset).decimals();
            uint8 collateralDecimals = ERC20(collateralAsset).decimals();

            collateralUsdValue = factory.oracle().getUsdValue(collateralAsset, collateralAmount, collateralDecimals);

            debtUsdValue = factory.oracle().getUsdValue(syntheticAsset, mintedAmount, syntheticDecimals);
        }

        // Create position details
        details = PositionDetails({
            positionId: positionId,
            owner: owner,
            syntheticAsset: syntheticAsset,
            syntheticSymbol: syntheticSymbol,
            collateralAsset: collateralAsset,
            collateralSymbol: collateralSymbol,
            collateralAmount: collateralAmount,
            mintedAmount: mintedAmount,
            lastUpdateTimestamp: lastUpdateTimestamp,
            isActive: isActive,
            currentRatio: collateralRatio,
            requiredRatio: requiredRatio,
            isUnderCollateralized: isUnderCollateralized,
            collateralUsdValue: collateralUsdValue,
            debtUsdValue: debtUsdValue
        });

        return details;
    }

    /**
     * @dev Calculate the amount of synthetic asset that can be minted with a given collateral amount
     * @param syntheticAsset The address of the synthetic asset to mint
     * @param collateralAsset The address of the collateral asset to use
     * @param collateralAmount The amount of collateral
     * @return mintableAmount The amount of synthetic asset that can be minted
     * @return usdCollateralValue The USD value of the collateral
     * @return effectiveRatio The effective collateral ratio required
     */
    function getMintableAmount(address syntheticAsset, address collateralAsset, uint256 collateralAmount)
        external
        view
        returns (uint256 mintableAmount, uint256 usdCollateralValue, uint256 effectiveRatio)
    {
        // Get token decimals
        uint8 collateralDecimals = ERC20(collateralAsset).decimals();

        // Get effective ratio
        effectiveRatio = factory.getEffectiveCollateralRatio(syntheticAsset, collateralAsset);

        // Get collateral USD value
        usdCollateralValue = factory.oracle().getUsdValue(collateralAsset, collateralAmount, collateralDecimals);

        // Calculate max mint amount
        mintableAmount = positionManager.getMintableAmount(syntheticAsset, collateralAsset, collateralAmount);

        return (mintableAmount, usdCollateralValue, effectiveRatio);
    }

    /**
     * @dev Calculate mint amount to achieve a target collateral ratio
     * @param syntheticAsset The address of the synthetic asset to mint
     * @param collateralAsset The address of the collateral asset
     * @param collateralAmount The amount of collateral to use
     * @param targetRatio The desired collateral ratio in basis points (e.g., 25000 for 250%)
     * @return mintAmount The amount to mint to achieve the target ratio
     * @return maxMintable The maximum amount that could be minted
     * @return effectiveRatio The actual ratio that would be achieved
     * @return minRequiredRatio The minimum ratio required by the protocol
     */
    function calculateMintAmountForTargetRatio(
        address syntheticAsset,
        address collateralAsset,
        uint256 collateralAmount,
        uint256 targetRatio
    ) public view returns (uint256 mintAmount, uint256 maxMintable, uint256 effectiveRatio, uint256 minRequiredRatio) {
        // Get the minimum required ratio for this asset/collateral pair
        minRequiredRatio = factory.getEffectiveCollateralRatio(syntheticAsset, collateralAsset);

        // Ensure target ratio is not less than minimum required
        require(targetRatio >= minRequiredRatio, "Target ratio below minimum required");

        // Get maximum mintable amount for reference
        maxMintable = positionManager.getMintableAmount(syntheticAsset, collateralAsset, collateralAmount);

        // Get token decimals
        uint8 collateralDecimals = ERC20(collateralAsset).decimals();
        uint8 syntheticDecimals = ERC20(syntheticAsset).decimals();

        // Get the USD value of the collateral
        uint256 collateralUsdValue = factory.oracle().getUsdValue(collateralAsset, collateralAmount, collateralDecimals);

        // Calculate the USD value to mint to achieve target ratio
        uint256 usdValueToMint = (collateralUsdValue * 10000) / targetRatio;

        // Convert USD value to synthetic token amount
        mintAmount = factory.oracle().getTokenAmount(syntheticAsset, usdValueToMint, syntheticDecimals);

        // Cap at maximum mintable (safety check)
        if (mintAmount > maxMintable) {
            mintAmount = maxMintable;
        }

        // Calculate the effective ratio that would be achieved with this mint amount
        if (mintAmount > 0) {
            uint256 mintUsdValue = factory.oracle().getUsdValue(syntheticAsset, mintAmount, syntheticDecimals);
            effectiveRatio = (collateralUsdValue * 10000) / mintUsdValue;
        } else {
            effectiveRatio = type(uint256).max; // Infinite ratio if mint amount is 0
        }

        return (mintAmount, maxMintable, effectiveRatio, minRequiredRatio);
    }

    /**
     * @dev Preview a position with a target collateral ratio
     * @param syntheticAsset The address of the synthetic asset to mint
     * @param collateralAsset The address of the collateral asset
     * @param collateralAmount The amount of collateral to use
     * @param targetRatio The desired collateral ratio in basis points (e.g., 25000 for 250%)
     * @return mintAmount The amount to mint to achieve the target ratio
     * @return collateralUsdValue The USD value of the collateral
     * @return syntheticUsdValue The USD value of the synthetic tokens to mint
     * @return effectiveRatio The actual ratio that would be achieved
     * @return minRequiredRatio The minimum ratio required by the protocol
     */
    function previewPositionWithTargetRatio(
        address syntheticAsset,
        address collateralAsset,
        uint256 collateralAmount,
        uint256 targetRatio
    )
        external
        view
        returns (
            uint256 mintAmount,
            uint256 collateralUsdValue,
            uint256 syntheticUsdValue,
            uint256 effectiveRatio,
            uint256 minRequiredRatio
        )
    {
        // Get the minimum required ratio for this asset/collateral pair
        minRequiredRatio = factory.getEffectiveCollateralRatio(syntheticAsset, collateralAsset);

        // Get token decimals
        uint8 collateralDecimals = ERC20(collateralAsset).decimals();
        uint8 syntheticDecimals = ERC20(syntheticAsset).decimals();

        // Get the USD value of the collateral
        collateralUsdValue = factory.oracle().getUsdValue(collateralAsset, collateralAmount, collateralDecimals);

        // Calculate mint amount based on target ratio
        (mintAmount,, effectiveRatio,) =
            calculateMintAmountForTargetRatio(syntheticAsset, collateralAsset, collateralAmount, targetRatio);

        // Calculate synthetic USD value
        syntheticUsdValue = factory.oracle().getUsdValue(syntheticAsset, mintAmount, syntheticDecimals);

        return (mintAmount, collateralUsdValue, syntheticUsdValue, effectiveRatio, minRequiredRatio);
    }

    /**
     * @dev Calculate collateral amount needed for a specific target ratio and mint amount
     * @param syntheticAsset The address of the synthetic asset to mint
     * @param collateralAsset The address of the collateral asset
     * @param mintAmount The amount of synthetic asset to mint
     * @param targetRatio The desired collateral ratio in basis points (e.g., 25000 for 250%)
     * @return collateralAmount The amount of collateral needed
     * @return collateralUsdValue The USD value of the required collateral
     * @return syntheticUsdValue The USD value of the synthetic tokens
     * @return minRequiredRatio The minimum ratio required by the protocol
     */
    function calculateCollateralForMintAmount(
        address syntheticAsset,
        address collateralAsset,
        uint256 mintAmount,
        uint256 targetRatio
    )
        external
        view
        returns (
            uint256 collateralAmount,
            uint256 collateralUsdValue,
            uint256 syntheticUsdValue,
            uint256 minRequiredRatio
        )
    {
        // Get the minimum required ratio for this asset/collateral pair
        minRequiredRatio = factory.getEffectiveCollateralRatio(syntheticAsset, collateralAsset);

        // Ensure target ratio is not less than minimum required
        require(targetRatio >= minRequiredRatio, "Target ratio below minimum required");

        // Get token decimals
        uint8 collateralDecimals = ERC20(collateralAsset).decimals();
        uint8 syntheticDecimals = ERC20(syntheticAsset).decimals();

        // Calculate the USD value of the synthetic asset amount
        syntheticUsdValue = factory.oracle().getUsdValue(syntheticAsset, mintAmount, syntheticDecimals);

        // Calculate the required USD value of collateral based on the target ratio
        collateralUsdValue = (syntheticUsdValue * targetRatio) / 10000;

        // Convert to collateral token amount
        collateralAmount = factory.oracle().getTokenAmount(collateralAsset, collateralUsdValue, collateralDecimals);

        return (collateralAmount, collateralUsdValue, syntheticUsdValue, minRequiredRatio);
    }

    /**
     * @dev Calculate how much additional collateral is needed for an existing position to reach a target ratio
     * @param positionId The ID of the position
     * @param targetRatio The desired collateral ratio in basis points (e.g., 25000 for 250%)
     * @return additionalCollateral The additional collateral needed
     * @return currentRatio The current collateral ratio of the position
     * @return targetUsdValue The USD value needed to achieve the target ratio
     * @return currentCollateralUsdValue The current USD value of collateral
     */
    function calculateAdditionalCollateralForPosition(uint256 positionId, uint256 targetRatio)
        external
        view
        returns (
            uint256 additionalCollateral,
            uint256 currentRatio,
            uint256 targetUsdValue,
            uint256 currentCollateralUsdValue
        )
    {
        // Get position details
        PositionDetails memory position = _getPositionDetails(positionId);
        require(position.isActive, "Position not active");
        require(position.mintedAmount > 0, "Position has no debt");

        // Get token decimals
        uint8 collateralDecimals = ERC20(position.collateralAsset).decimals();

        // Get current ratio
        currentRatio = position.currentRatio;

        // If already at or above target ratio, no additional collateral needed
        if (currentRatio >= targetRatio) {
            return (0, currentRatio, position.collateralUsdValue, position.collateralUsdValue);
        }

        // Calculate target USD value needed
        targetUsdValue = (position.debtUsdValue * targetRatio) / 10000;
        currentCollateralUsdValue = position.collateralUsdValue;

        // Calculate additional USD value needed
        uint256 additionalUsdValue = targetUsdValue - currentCollateralUsdValue;

        // Convert to collateral tokens
        additionalCollateral =
            factory.oracle().getTokenAmount(position.collateralAsset, additionalUsdValue, collateralDecimals);

        return (additionalCollateral, currentRatio, targetUsdValue, currentCollateralUsdValue);
    }
}
