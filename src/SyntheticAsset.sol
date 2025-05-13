// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title SyntheticAsset
 * @dev An ERC20 token representing a synthetic asset in the Leprechaun protocol
 *      This contract implements a permissioned ERC20 token where only the authorized
 *      position manager can mint and burn tokens. Each instance of this contract
 *      represents a different synthetic asset (e.g., synthetic gold, synthetic stocks).
 */
contract SyntheticAsset is ERC20 {
    /**
     * @dev The address of the position manager contract that has permission
     *      to mint and burn tokens.
     */
    address public positionManager;

    /**
     * @dev Constructor
     * @param name_ The human-readable name of the token (e.g., "Synthetic Gold")
     * @param symbol_ The trading symbol of the token (e.g., "sGOLD")
     * @param _positionManager The address of the position manager contract that will have
     *        exclusive permission to mint and burn tokens
     */
    constructor(string memory name_, string memory symbol_, address _positionManager) ERC20(name_, symbol_) {
        require(_positionManager != address(0), "Invalid position manager address");
        positionManager = _positionManager;
    }

    /**
     * @dev Mint new tokens to a specified address
     * @param to The address that will receive the newly minted tokens
     * @param amount The amount of tokens to mint
     * @notice This function can only be called by the authorized position manager
     * @notice This function is called when users create or expand positions in the protocol
     */
    function mint(address to, uint256 amount) external {
        require(msg.sender == positionManager, "Only position manager can mint");

        _mint(to, amount);
    }

    /**
     * @dev Burn tokens from a specified address
     * @param from The address from which tokens will be burned
     * @param amount The amount of tokens to burn
     * @notice This function can only be called by the authorized position manager
     * @notice This function is called when users repay debt, close positions, or during liquidations
     */
    function burn(address from, uint256 amount) external {
        require(msg.sender == positionManager, "Only position manager can burn");

        _burn(from, amount);
    }
}
