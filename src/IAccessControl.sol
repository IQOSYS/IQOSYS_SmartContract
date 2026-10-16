// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title Interface for Access Control Module
/// @notice Defines admin, authorization, whitelist, freeze and scoped-role functionalities
interface IAccessControl {
    function ROLE_ACCOUNT_MANAGER() external view returns (bytes32);
    function ROLE_ANCHOR() external view returns (bytes32);
    function ROLE_EMERGENCY() external view returns (bytes32);

    function hasRole(bytes32 role, address account) external view returns (bool);
    function setRole(bytes32 role, address account, bool enabled) external;

    /// @notice Returns the owner of the contract.
    function owner() external view returns (address);

    /// @notice Returns the dedicated controller allowed to atomically rotate signer-admin rights.
    function adminSignerController() external view returns (address);

    /// @notice Sets the signer-admin controller once during bootstrap.
    function setAdminSignerController(address controller) external;

    /// @notice Atomically removes admin rights from an old signer and grants them to a new signer.
    /// @dev Callable only by the configured adminSignerController.
    function replaceSignerAdmin(address oldAdmin, address newAdmin) external;

    /// @notice Adds an administrator.
    function addAdmin(address account) external;

    /// @notice Removes an administrator.
    function removeAdmin(address account) external;

    /// @notice Checks whether an address is an admin.
    function isAdmin(address account) external view returns (bool);

    /// @notice Atomically grants both whitelist membership and authorization to a non-frozen address.
    function approveHolder(address account) external;

    /// @notice Grants authorization to an address.
    function authorizeAddress(address account) external;

    /// @notice Revokes authorization from an address.
    function revokeAuthorization(address account) external;

    /// @notice Adds an address to the whitelist.
    function addToWhiteList(address account) external;

    /// @notice Removes an address from the whitelist.
    function removeFromWhiteList(address account) external;

    /// @notice Freezes an address and blocks its operations.
    function freezeAddress(address account) external;

    /// @notice Unfreezes an address.
    function unfreezeAddress(address account) external;

    /// @notice Checks whether an address is authorized.
    function isAuthorized(address account) external view returns (bool);

    /// @notice Checks whether an address is whitelisted.
    function isWhiteListed(address account) external view returns (bool);

    /// @notice Checks whether an address is frozen.
    function isFrozen(address account) external view returns (bool);

    /// @notice Checks if an account is valid: whitelisted, authorized, and not frozen.
    function onlyValidSender(address account) external view returns (bool);

    /// @notice Returns the whitelist of addresses.
    function getWhiteList() external view returns (address[] memory);
}
