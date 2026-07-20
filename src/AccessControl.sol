// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "./IAccessControl.sol";

/// @title Access Control Module
/// @notice Manages owner, authorized addresses, admins, whitelist and frozen accounts
contract AccessControl is Ownable, IAccessControl {
    using EnumerableSet for EnumerableSet.AddressSet;

    EnumerableSet.AddressSet private iqosysWhiteList;

    mapping(address => bool) private authorizedAddresses;
    mapping(address => bool) private frozenAddresses;
    mapping(address => bool) private admins;

    event AuthorizationUpdated(address indexed account, bool isAuthorized);
    event WhiteListed(address indexed account, bool status);
    event AddressFrozen(address indexed account, bool isFrozen);
    event AdminUpdated(address indexed account, bool isAdmin);

    /**
     * @notice Initializes the module with the initial owner/admin.
     * @param initialOwner Address that will own and administer the module.
     */
    constructor(address initialOwner) Ownable(initialOwner) {
        require(initialOwner != address(0), "Invalid owner");

        admins[initialOwner] = true;
        authorizedAddresses[initialOwner] = true;
        iqosysWhiteList.add(initialOwner);

        emit AdminUpdated(initialOwner, true);
        emit AuthorizationUpdated(initialOwner, true);
        emit WhiteListed(initialOwner, true);
    }

    // -------------------------------------------------------------------------
    // Admin management
    // -------------------------------------------------------------------------

    /**
     * @notice Adds an administrator.
     */
    function addAdmin(address account) external onlyOwner {
        require(account != address(0), "Invalid account");
        require(!admins[account], "Already admin");

        admins[account] = true;

        emit AdminUpdated(account, true);
    }

    /**
     * @notice Removes administrator rights.
     */
    function removeAdmin(address account) external onlyOwner {
        require(account != address(0), "Invalid account");
        require(admins[account], "Not admin");

        admins[account] = false;

        emit AdminUpdated(account, false);
    }

    /**
     * @notice Checks whether an address is an administrator.
     */
    function isAdmin(address account) public view returns (bool) {
        return admins[account];
    }

    modifier onlyAdmin() {
        require(isAdmin(msg.sender), "Caller is not an admin");
        _;
    }

    // -------------------------------------------------------------------------
    // IAccessControl compatibility
    // -------------------------------------------------------------------------

    function owner() public view override(Ownable, IAccessControl) returns (address) {
        return Ownable.owner();
    }

    // -------------------------------------------------------------------------
    // Authorization / whitelist / freeze logic
    // -------------------------------------------------------------------------

    function authorizeAddress(address account) external onlyAdmin override {
        require(account != address(0), "Invalid account");
        require(!authorizedAddresses[account], "Address already authorized");

        authorizedAddresses[account] = true;

        emit AuthorizationUpdated(account, true);
    }

    function revokeAuthorization(address account) external onlyAdmin override {
        require(account != address(0), "Invalid account");
        require(authorizedAddresses[account], "Address not authorized");

        authorizedAddresses[account] = false;

        emit AuthorizationUpdated(account, false);
    }

    function addToWhiteList(address account) external onlyAdmin override {
        require(account != address(0), "Invalid account");
        require(iqosysWhiteList.add(account), "Account already white-listed");

        emit WhiteListed(account, true);
    }

    function removeFromWhiteList(address account) external onlyAdmin override {
        require(account != address(0), "Invalid account");
        require(iqosysWhiteList.remove(account), "Account not in white-list");

        emit WhiteListed(account, false);
    }

    function freezeAddress(address account) external onlyAdmin override {
        require(account != address(0), "Invalid account");
        require(!frozenAddresses[account], "Address already frozen");

        frozenAddresses[account] = true;

        emit AddressFrozen(account, true);
    }

    function unfreezeAddress(address account) external onlyAdmin override {
        require(account != address(0), "Invalid account");
        require(frozenAddresses[account], "Address not frozen");

        frozenAddresses[account] = false;

        emit AddressFrozen(account, false);
    }

    function isAuthorized(address account) external view override returns (bool) {
        return authorizedAddresses[account];
    }

    function isWhiteListed(address account) external view override returns (bool) {
        return iqosysWhiteList.contains(account);
    }

    function isFrozen(address account) external view override returns (bool) {
        return frozenAddresses[account];
    }

    function onlyValidSender(address account) external view override returns (bool) {
        require(iqosysWhiteList.contains(account), "Sender not white-listed");
        require(authorizedAddresses[account], "Sender not authorized");
        require(!frozenAddresses[account], "Sender is frozen");

        return true;
    }

    function getWhiteList() public view returns (address[] memory) {
        return iqosysWhiteList.values();
    }
}