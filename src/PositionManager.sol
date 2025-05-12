// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./ProtocolRegistry.sol";

/**
 * @title PositionManager
 * @dev Manages collateralized debt positions (CDPs) for synthetic assets
 */
contract PositionManager is Ownable {
    using SafeERC20 for IERC20;

    // Protocol registry
    ProtocolRegistry public registry;

    // Struct to represent a CDP
    struct Position {
        address owner; // Position owner
        address syntheticAsset; // Synthetic asset address
        address collateralAsset; // Collateral asset address
        uint256 collateralAmount; // Amount of collateral deposited
        uint256 mintedAmount; // Amount of synthetic asset minted
        uint256 lastUpdateTimestamp; // Last update timestamp
        bool isActive; // Whether the position is active
    }

    // Mapping of position IDs to positions
    mapping(uint256 => Position) public positions;

    // Next position ID
    uint256 public nextPositionId = 1;

    // Mapping of user address to their position IDs
    mapping(address => uint256[]) public userPositions;

    // Mapping of synthetic asset to position IDs
    mapping(address => uint256[]) public assetPositions;

    // Events
    event PositionCreated(
        uint256 indexed positionId,
        address indexed owner,
        address indexed syntheticAsset,
        address collateralAsset,
        uint256 collateralAmount,
        uint256 mintedAmount
    );

    event CollateralDeposited(
        uint256 indexed positionId,
        uint256 amount,
        uint256 newCollateralAmount
    );

    event CollateralWithdrawn(
        uint256 indexed positionId,
        uint256 amount,
        uint256 fee,
        uint256 newCollateralAmount
    );

    event SyntheticAssetMinted(
        uint256 indexed positionId,
        uint256 amount,
        uint256 newMintedAmount
    );

    event SyntheticAssetBurned(
        uint256 indexed positionId,
        uint256 amount,
        uint256 newMintedAmount
    );

    event PositionClosed(uint256 indexed positionId);

    event LiquidationStarted(
        uint256 indexed positionId,
        address indexed liquidator
    );

    /**
     * @dev Constructor
     * @param _registry The address of the protocol registry
     * @param initialOwner The initial owner of the contract
     */
    constructor(
        address _registry,
        address _oracle,
        address initialOwner
    ) Ownable(initialOwner) {
        require(_registry != address(0), "Invalid registry address");
        require(_oracle != address(0), "Invalid oracle address");

        registry = ProtocolRegistry(_registry);
    }

    /**
     * @dev Create a new CDP
     * @param syntheticAsset The address of the synthetic asset
     * @param collateralAsset The address of the collateral asset
     * @param collateralAmount The amount of collateral to deposit
     * @param mintAmount The amount of synthetic asset to mint
     * @return positionId The ID of the created position
     */
    function createPosition(
        address syntheticAsset,
        address collateralAsset,
        uint256 collateralAmount,
        uint256 mintAmount
    ) external returns (uint256 positionId) {
        // Check if synthetic asset is active
        require(
            registry.isSyntheticAssetActive(syntheticAsset),
            "Synthetic asset not active"
        );

        // Check if collateral is active and allowed for this synthetic asset
        require(
            registry.isCollateralActive(collateralAsset),
            "Collateral not active"
        );
        require(
            registry.allowedCollateral(syntheticAsset, collateralAsset),
            "Collateral not allowed for this asset"
        );

        // Check if amount is valid
        require(
            collateralAmount > 0,
            "Collateral amount must be greater than 0"
        );
        require(mintAmount > 0, "Mint amount must be greater than 0");

        // Calculate minimum required collateral
        uint256 requiredCollateral = _calculateRequiredCollateral(
            syntheticAsset,
            collateralAsset,
            mintAmount
        );

        require(
            collateralAmount >= requiredCollateral,
            "Insufficient collateral"
        );

        // Create new position
        positionId = nextPositionId++;
        Position storage position = positions[positionId];

        position.owner = msg.sender;
        position.syntheticAsset = syntheticAsset;
        position.collateralAsset = collateralAsset;
        position.collateralAmount = collateralAmount;
        position.mintedAmount = mintAmount;
        position.lastUpdateTimestamp = block.timestamp;
        position.isActive = true;

        // Add position to user's positions
        userPositions[msg.sender].push(positionId);

        // Add position to asset's positions
        assetPositions[syntheticAsset].push(positionId);

        // Transfer collateral from user
        IERC20(collateralAsset).safeTransferFrom(
            msg.sender,
            address(this),
            collateralAmount
        );

        // Mint synthetic asset to user
        SyntheticAsset(syntheticAsset).mint(msg.sender, mintAmount);

        emit PositionCreated(
            positionId,
            msg.sender,
            syntheticAsset,
            collateralAsset,
            collateralAmount,
            mintAmount
        );

        return positionId;
    }

    /**
     * @dev Deposit additional collateral to a position
     * @param positionId The ID of the position
     * @param amount The amount of collateral to deposit
     */
    function depositCollateral(uint256 positionId, uint256 amount) external {
        Position storage position = positions[positionId];

        require(position.isActive, "Position not active");
        require(position.owner == msg.sender, "Not position owner");
        require(amount > 0, "Amount must be greater than 0");

        // Update collateral amount
        uint256 newCollateralAmount = position.collateralAmount + amount;
        position.collateralAmount = newCollateralAmount;
        position.lastUpdateTimestamp = block.timestamp;

        // Transfer collateral from user
        IERC20(position.collateralAsset).safeTransferFrom(
            msg.sender,
            address(this),
            amount
        );

        emit CollateralDeposited(positionId, amount, newCollateralAmount);
    }

    /**
     * @dev Withdraw collateral from a position
     * @param positionId The ID of the position
     * @param amount The amount of collateral to withdraw
     */
    function withdrawCollateral(uint256 positionId, uint256 amount) external {
        Position storage position = positions[positionId];

        require(position.isActive, "Position not active");
        require(position.owner == msg.sender, "Not position owner");
        require(amount > 0, "Amount must be greater than 0");
        require(
            amount <= position.collateralAmount,
            "Amount exceeds collateral"
        );

        // Calculate fee
        uint256 fee = (amount * registry.protocolFee()) / 10000;
        uint256 amountAfterFee = amount - fee;

        // Calculate minimum required collateral
        uint256 requiredCollateral = _calculateRequiredCollateral(
            position.syntheticAsset,
            position.collateralAsset,
            position.mintedAmount
        );

        // Check if remaining collateral is sufficient
        require(
            position.collateralAmount - amount >= requiredCollateral,
            "Insufficient remaining collateral"
        );

        // Update collateral amount
        position.collateralAmount = position.collateralAmount - amount;
        position.lastUpdateTimestamp = block.timestamp;

        // Transfer fee to fee collector
        if (fee > 0) {
            IERC20(position.collateralAsset).safeTransfer(
                registry.feeCollector(),
                fee
            );
        }

        // Transfer collateral to user
        IERC20(position.collateralAsset).safeTransfer(
            msg.sender,
            amountAfterFee
        );

        emit CollateralWithdrawn(
            positionId,
            amount,
            fee,
            position.collateralAmount
        );
    }

    /**
     * @dev Mint additional synthetic asset from a position
     * @param positionId The ID of the position
     * @param amount The amount of synthetic asset to mint
     */
    function mintSyntheticAsset(uint256 positionId, uint256 amount) external {
        Position storage position = positions[positionId];

        require(position.isActive, "Position not active");
        require(position.owner == msg.sender, "Not position owner");
        require(amount > 0, "Amount must be greater than 0");

        // Calculate new minted amount
        uint256 newMintedAmount = position.mintedAmount + amount;

        // Calculate minimum required collateral
        uint256 requiredCollateral = _calculateRequiredCollateral(
            position.syntheticAsset,
            position.collateralAsset,
            newMintedAmount
        );

        require(
            position.collateralAmount >= requiredCollateral,
            "Insufficient collateral"
        );

        // Update minted amount
        position.mintedAmount = newMintedAmount;
        position.lastUpdateTimestamp = block.timestamp;

        // Mint synthetic asset to user
        SyntheticAsset(position.syntheticAsset).mint(msg.sender, amount);

        emit SyntheticAssetMinted(positionId, amount, newMintedAmount);
    }

    /**
     * @dev Burn synthetic asset to reduce a position's debt
     * @param positionId The ID of the position
     * @param amount The amount of synthetic asset to burn
     */
    function burnSyntheticAsset(uint256 positionId, uint256 amount) external {
        Position storage position = positions[positionId];

        require(position.isActive, "Position not active");
        require(position.owner == msg.sender, "Not position owner");
        require(amount > 0, "Amount must be greater than 0");
        require(
            amount <= position.mintedAmount,
            "Amount exceeds minted amount"
        );

        // Update minted amount
        position.mintedAmount = position.mintedAmount - amount;
        position.lastUpdateTimestamp = block.timestamp;

        // Burn synthetic asset from user
        SyntheticAsset(position.syntheticAsset).burn(msg.sender, amount);

        emit SyntheticAssetBurned(positionId, amount, position.mintedAmount);
    }

    /**
     * @dev Close a position
     * @param positionId The ID of the position
     */
    function closePosition(uint256 positionId) external {
        Position storage position = positions[positionId];

        require(position.isActive, "Position not active");
        require(position.owner == msg.sender, "Not position owner");
        require(position.mintedAmount > 0, "No debt to close");

        // burn synthetic asset from user
        SyntheticAsset(position.syntheticAsset).burn(
            msg.sender,
            position.mintedAmount
        );

        // Calculate fee
        uint256 fee = (position.collateralAmount * registry.protocolFee()) /
            10000;
        uint256 amountAfterFee = position.collateralAmount - fee;

        // Transfer fee to fee collector
        if (fee > 0) {
            IERC20(position.collateralAsset).safeTransfer(
                registry.feeCollector(),
                fee
            );
        }

        // Transfer collateral to user
        IERC20(position.collateralAsset).safeTransfer(
            msg.sender,
            amountAfterFee
        );

        // Close position
        position.collateralAmount = 0;
        position.mintedAmount = 0;
        position.isActive = false;

        emit PositionClosed(positionId);
    }

    /**
     * @dev Liquidate an under-collateralized position
     * @param positionId The ID of the position
     */
    function liquidate(uint256 positionId) external {
        Position storage position = positions[positionId];

        require(position.isActive, "Position not active");
        require(position.mintedAmount > 0, "No debt to liquidate");

        // Get effective collateral ratio
        uint256 effectiveRatio = registry.getEffectiveCollateralRatio(
            position.syntheticAsset,
            position.collateralAsset
        );

        // Calculate current collateral ratio
        uint256 currentRatio = _calculateCollateralRatio(
            position.syntheticAsset,
            position.collateralAsset,
            position.collateralAmount,
            position.mintedAmount
        );

        require(
            currentRatio < effectiveRatio,
            "Position is not under-collateralized"
        );

        // burn synthetic asset from liquidator
        SyntheticAsset(position.syntheticAsset).burn(
            msg.sender,
            position.mintedAmount
        );

        // Calculate auction discount
        uint256 auctionDiscount = registry.getAuctionDiscount(
            position.syntheticAsset
        );

        // Calculate collateral to give to liquidator
        // Liquidator gets: (mintedAmount * (1 + auctionDiscount / 10000)) worth of collateral
        uint256 collateralToLiquidator = _calculateCollateralValue(
            position.syntheticAsset,
            position.collateralAsset,
            (position.mintedAmount * (10000 + auctionDiscount)) / 10000
        );

        if (collateralToLiquidator > position.collateralAmount) {
            collateralToLiquidator = position.collateralAmount;
        }

        // Calculate remaining collateral
        uint256 remainingCollateral = position.collateralAmount -
            collateralToLiquidator;

        // Calculate fee on remaining collateral
        uint256 fee = 0;
        if (remainingCollateral > 0) {
            fee = (remainingCollateral * registry.protocolFee()) / 10000;
        }

        // Transfer collateral to liquidator
        IERC20(position.collateralAsset).safeTransfer(
            msg.sender,
            collateralToLiquidator
        );

        // Transfer fee to fee collector
        if (fee > 0) {
            IERC20(position.collateralAsset).safeTransfer(
                registry.feeCollector(),
                fee
            );
        }

        // Transfer remaining collateral to position owner
        if (remainingCollateral > fee) {
            IERC20(position.collateralAsset).safeTransfer(
                position.owner,
                remainingCollateral - fee
            );
        }

        // Close position
        position.collateralAmount = 0;
        position.mintedAmount = 0;
        position.isActive = false;

        emit LiquidationStarted(positionId, msg.sender);
        emit PositionClosed(positionId);
    }

    /**
     * @dev Check if a position is under-collateralized
     * @param positionId The ID of the position
     * @return isUnderCollateralized Whether the position is under-collateralized
     */
    function isUnderCollateralized(
        uint256 positionId
    ) external view returns (bool) {
        Position storage position = positions[positionId];

        if (!position.isActive || position.mintedAmount == 0) {
            return false;
        }

        // Get effective collateral ratio
        uint256 effectiveRatio = registry.getEffectiveCollateralRatio(
            position.syntheticAsset,
            position.collateralAsset
        );

        // Calculate current collateral ratio
        uint256 currentRatio = _calculateCollateralRatio(
            position.syntheticAsset,
            position.collateralAsset,
            position.collateralAmount,
            position.mintedAmount
        );

        return currentRatio < effectiveRatio;
    }

    /**
     * @dev Get a position's collateral ratio
     * @param positionId The ID of the position
     * @return collateralRatio The position's collateral ratio (scaled by 10000)
     */
    function getCollateralRatio(
        uint256 positionId
    ) external view returns (uint256) {
        Position storage position = positions[positionId];

        require(position.isActive, "Position not active");
        require(position.mintedAmount > 0, "No debt");

        return
            _calculateCollateralRatio(
                position.syntheticAsset,
                position.collateralAsset,
                position.collateralAmount,
                position.mintedAmount
            );
    }

    /**
     * @dev Calculate the required collateral for a given amount of synthetic asset
     * @param syntheticAsset The address of the synthetic asset
     * @param collateralAsset The address of the collateral asset
     * @param mintAmount The amount of synthetic asset
     * @return requiredCollateral The required collateral amount
     */
    function _calculateRequiredCollateral(
        address syntheticAsset,
        address collateralAsset,
        uint256 mintAmount
    ) internal view returns (uint256) {
        if (mintAmount == 0) {
            return 0;
        }

        // Get effective collateral ratio
        uint256 effectiveRatio = registry.getEffectiveCollateralRatio(
            syntheticAsset,
            collateralAsset
        );

        // Get token decimals
        uint8 syntheticDecimals = ERC20(syntheticAsset).decimals();
        uint8 collateralDecimals = ERC20(collateralAsset).decimals();

        // Calculate the USD value of the minted amount
        uint256 mintedUsdValue = registry.oracle().getUsdValue(
            syntheticAsset,
            mintAmount,
            syntheticDecimals
        );

        // Calculate the required collateral value in USD
        uint256 requiredCollateralUsdValue = (mintedUsdValue * effectiveRatio) /
            10000;

        // Convert the USD value to collateral tokens
        // This is simplified and assumes 1:1 conversion based on price
        (int64 collateralPrice, , ) = registry.oracle().getPrice(
            collateralAsset
        );
        require(collateralPrice > 0, "Invalid collateral price");

        uint256 positiveCollateralPrice = uint256(uint64(collateralPrice));

        // Calculate required collateral: (requiredCollateralUsdValue * 10^collateralDecimals) / collateralPrice
        return
            (requiredCollateralUsdValue * (10 ** collateralDecimals)) /
            positiveCollateralPrice;
    }

    /**
     * @dev Calculate the collateral value in synthetic asset units
     * @param syntheticAsset The address of the synthetic asset
     * @param collateralAsset The address of the collateral asset
     * @param syntheticAmount The amount of synthetic asset
     * @return collateralAmount The required collateral amount
     */
    function _calculateCollateralValue(
        address syntheticAsset,
        address collateralAsset,
        uint256 syntheticAmount
    ) internal view returns (uint256) {
        if (syntheticAmount == 0) {
            return 0;
        }

        // Get token decimals
        uint8 syntheticDecimals = ERC20(syntheticAsset).decimals();
        uint8 collateralDecimals = ERC20(collateralAsset).decimals();

        // Get prices
        (int64 syntheticPrice, , ) = registry.oracle().getPrice(syntheticAsset);
        (int64 collateralPrice, , ) = registry.oracle().getPrice(
            collateralAsset
        );

        require(syntheticPrice > 0, "Invalid synthetic price");
        require(collateralPrice > 0, "Invalid collateral price");

        uint256 positiveSyntheticPrice = uint256(uint64(syntheticPrice));
        uint256 positiveCollateralPrice = uint256(uint64(collateralPrice));

        // Calculate synthetic value in USD
        uint256 syntheticValue = (syntheticAmount * positiveSyntheticPrice);

        // Adjust for decimals
        if (syntheticDecimals > 8) {
            syntheticValue = syntheticValue / (10 ** (syntheticDecimals - 8));
        } else {
            syntheticValue = syntheticValue * (10 ** (8 - syntheticDecimals));
        }

        // Convert to collateral amount: (syntheticValue * 10^collateralDecimals) / collateralPrice
        return
            (syntheticValue * (10 ** collateralDecimals)) /
            positiveCollateralPrice;
    }

    /**
     * @dev Calculate a position's collateral ratio
     * @param syntheticAsset The address of the synthetic asset
     * @param collateralAsset The address of the collateral asset
     * @param collateralAmount The amount of collateral
     * @param mintedAmount The amount of synthetic asset minted
     * @return collateralRatio The collateral ratio (scaled by 10000)
     */
    function _calculateCollateralRatio(
        address syntheticAsset,
        address collateralAsset,
        uint256 collateralAmount,
        uint256 mintedAmount
    ) internal view returns (uint256) {
        if (mintedAmount == 0) {
            return type(uint256).max; // Infinite ratio if no debt
        }

        if (collateralAmount == 0) {
            return 0; // Zero ratio if no collateral
        }

        // Get token decimals
        uint8 syntheticDecimals = ERC20(syntheticAsset).decimals();
        uint8 collateralDecimals = ERC20(collateralAsset).decimals();

        // Calculate the USD value of the collateral
        uint256 collateralUsdValue = registry.oracle().getUsdValue(
            collateralAsset,
            collateralAmount,
            collateralDecimals
        );

        // Calculate the USD value of the minted amount
        uint256 mintedUsdValue = registry.oracle().getUsdValue(
            syntheticAsset,
            mintedAmount,
            syntheticDecimals
        );

        // Calculate the collateral ratio: (collateralUsdValue * 10000) / mintedUsdValue
        return (collateralUsdValue * 10000) / mintedUsdValue;
    }

    /**
     * @dev Get the number of positions for a user
     * @param user The address of the user
     * @return count The number of positions
     */
    function getUserPositionCount(
        address user
    ) external view returns (uint256) {
        return userPositions[user].length;
    }

    /**
     * @dev Get the number of positions for a synthetic asset
     * @param syntheticAsset The address of the synthetic asset
     * @return count The number of positions
     */
    function getAssetPositionCount(
        address syntheticAsset
    ) external view returns (uint256) {
        return assetPositions[syntheticAsset].length;
    }

    /**
     * @dev Get a position by ID
     * @param positionId The ID of the position
     * @return owner The owner of the position
     * @return syntheticAsset The synthetic asset associated with the position
     * @return collateralAsset The collateral asset associated with the position
     * @return collateralAmount The amount of collateral in the position
     * @return mintedAmount The amount of synthetic asset minted
     * @return lastUpdateTimestamp The last time the position was updated
     * @return isActive The status of the position (active/inactive)
     */
    function getPosition(
        uint256 positionId
    )
        external
        view
        returns (
            address owner,
            address syntheticAsset,
            address collateralAsset,
            uint256 collateralAmount,
            uint256 mintedAmount,
            uint256 lastUpdateTimestamp,
            bool isActive
        )
    {
        Position storage position = positions[positionId];
        return (
            position.owner,
            position.syntheticAsset,
            position.collateralAsset,
            position.collateralAmount,
            position.mintedAmount,
            position.lastUpdateTimestamp,
            position.isActive
        );
    }
}
