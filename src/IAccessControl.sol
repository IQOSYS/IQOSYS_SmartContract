// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title Interface for Access Control Module
/// @notice Defines authorization, whitelist, and freeze functionalities
interface IAccessControl {
    /// @notice Returns the owner of the contract
    function owner() external view returns (address);
    
    /// @notice Grants authorization to an address
    function authorizeAddress(address account) external;

    /// @notice Revokes authorization of an address
    function revokeAuthorization(address account) external;

    /// @notice Adds an address to the whitelist
    function addToWhiteList(address account) external;

    /// @notice Removes an address from the whitelist
    function removeFromWhiteList(address account) external;

    /// @notice Freezes an address (blocks its operations)
    function freezeAddress(address account) external;

    /// @notice Unfreezes an address
    function unfreezeAddress(address account) external;

    /// @notice Checks whether an address is authorized
    function isAuthorized(address account) external view returns (bool);

    /// @notice Checks whether an address is whitelisted
    function isWhiteListed(address account) external view returns (bool);

    /// @notice Checks whether an address is frozen
    function isFrozen(address account) external view returns (bool);

    /// @notice Checks if the sender is valid (whitelisted, authorized, not frozen)
    function onlyValidSender(address account) external view returns (bool);

    /// @notice Returns the whitelist of addresses
    function getWhiteList() external view returns (address[] memory);

    // --- AJOUT POUR RÉSOUDRE L'ERREUR ---
    /// @notice Checks whether an address is an admin (Validator FIAT)
    function isAdmin(address account) external view returns (bool);
}