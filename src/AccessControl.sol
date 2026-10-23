// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "./IAccessControl.sol";

interface IAdminSignerRegistry {
    function isSigner(address account) external view returns (bool);
}

/// @title Access Control Module
/// @notice Manages owner, authorized addresses, admins, whitelist and frozen accounts
contract AccessControl is Ownable2Step, IAccessControl {
    using EnumerableSet for EnumerableSet.AddressSet;

    EnumerableSet.AddressSet private iqosysWhiteList;

    mapping(address => bool) private authorizedAddresses;
    mapping(address => bool) private frozenAddresses;
    mapping(address => bool) private admins;

    bytes32 public constant override ROLE_ACCOUNT_MANAGER = keccak256("IQOSYS_ROLE_ACCOUNT_MANAGER");
    bytes32 public constant override ROLE_ANCHOR = keccak256("IQOSYS_ROLE_ANCHOR");
    bytes32 public constant override ROLE_EMERGENCY = keccak256("IQOSYS_ROLE_EMERGENCY");

    mapping(bytes32 => mapping(address => bool)) private scopedRoles;

    address public override adminSignerController;

    event AuthorizationUpdated(address indexed account, bool isAuthorized);
    event WhiteListed(address indexed account, bool status);
    event AddressFrozen(address indexed account, bool isFrozen);
    event AdminUpdated(address indexed account, bool isAdmin);
    event RoleUpdated(bytes32 indexed role, address indexed account, bool enabled);
    event AdminSignerControllerSet(address indexed controller);

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
    function addAdmin(address account) external override onlyOwner {
        require(account != address(0), "Invalid account");
        require(!admins[account], "Already admin");

        admins[account] = true;

        emit AdminUpdated(account, true);
    }

    /**
     * @notice Removes administrator rights.
     * @dev Active multisig signers cannot be removed directly. They must first
     *      be rotated through AdminMultisig.replaceSigner(), which updates both
     *      signer membership and admin rights atomically.
     */
    function removeAdmin(address account) external override onlyOwner {
        require(account != address(0), "Invalid account");
        require(admins[account], "Not admin");

        if (adminSignerController != address(0)) {
            require(
                !IAdminSignerRegistry(adminSignerController).isSigner(account),
                "Cannot remove active signer admin"
            );
        }

        admins[account] = false;

        emit AdminUpdated(account, false);
    }

    /**
     * @notice Checks whether an address is an administrator.
     */
    function isAdmin(address account) public view override returns (bool) {
        return admins[account];
    }

    /**
     * @notice Sets the dedicated signer-admin controller once during bootstrap.
     * @dev Expected to be the deployed AdminMultisig contract.
     */
    function setAdminSignerController(address controller) external override onlyOwner {
        require(controller != address(0), "Invalid controller");
        require(controller.code.length > 0, "Controller must be contract");
        require(adminSignerController == address(0), "Admin signer controller already set");

        adminSignerController = controller;

        emit AdminSignerControllerSet(controller);
    }

    /**
     * @notice Atomically moves admin rights from an old multisig signer to a new signer.
     * @dev Callable only by AdminMultisig. The signer state is checked before the
     *      AdminMultisig contract mutates its signer array.
     */
    function replaceSignerAdmin(address oldAdmin, address newAdmin) external override {
        require(msg.sender == adminSignerController, "Caller is not admin signer controller");
        require(oldAdmin != address(0), "Invalid old admin");
        require(newAdmin != address(0), "Invalid new admin");
        require(oldAdmin != newAdmin, "Admins must differ");
        require(admins[oldAdmin], "Old signer is not admin");
        require(IAdminSignerRegistry(msg.sender).isSigner(oldAdmin), "Old admin is not active signer");
        require(!IAdminSignerRegistry(msg.sender).isSigner(newAdmin), "New admin already signer");

        admins[oldAdmin] = false;
        emit AdminUpdated(oldAdmin, false);

        if (!admins[newAdmin]) {
            admins[newAdmin] = true;
            emit AdminUpdated(newAdmin, true);
        }
    }

    modifier onlyAdmin() {
        require(isAdmin(msg.sender), "Caller is not an admin");
        _;
    }

    // -------------------------------------------------------------------------
    // Least-privilege module permissions (managed only by the Ownable2Step owner)
    // -------------------------------------------------------------------------

    function hasRole(bytes32 role, address account) external view override returns (bool) {
        return scopedRoles[role][account];
    }

    function setRole(bytes32 role, address account, bool enabled) external override onlyOwner {
        require(account != address(0), "Invalid account");
        require(
            role == ROLE_ACCOUNT_MANAGER || role == ROLE_ANCHOR || role == ROLE_EMERGENCY,
            "Unsupported role"
        );
        require(scopedRoles[role][account] != enabled, "Role already in requested state");

        scopedRoles[role][account] = enabled;

        emit RoleUpdated(role, account, enabled);
    }

    modifier onlyAccountManagerOrAdmin() {
        require(
            isAdmin(msg.sender) || scopedRoles[ROLE_ACCOUNT_MANAGER][msg.sender],
            "Caller is not an account manager or admin"
        );
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

    /**
     * @notice Whitelist and authorize a holder in ONE admin transaction.
     * @dev Supports an account in a partially-approved state; emits events only
     *      for actual changes. Does not unfreeze an account or grant admin rights.
     *      Any revert rolls back both changes atomically.
     */
    function approveHolder(address account) external override onlyAdmin {
        require(account != address(0), "Invalid account");
        require(!frozenAddresses[account], "Account is frozen");
        require(
            !iqosysWhiteList.contains(account) || !authorizedAddresses[account],
            "Account already approved"
        );

        if (!iqosysWhiteList.contains(account)) {
            iqosysWhiteList.add(account);
            emit WhiteListed(account, true);
        }

        if (!authorizedAddresses[account]) {
            authorizedAddresses[account] = true;
            emit AuthorizationUpdated(account, true);
        }
    }

    function authorizeAddress(address account) external onlyAccountManagerOrAdmin override {
        require(account != address(0), "Invalid account");
        require(!authorizedAddresses[account], "Address already authorized");

        authorizedAddresses[account] = true;

        emit AuthorizationUpdated(account, true);
    }

    function revokeAuthorization(address account) external onlyAccountManagerOrAdmin override {
        require(account != address(0), "Invalid account");
        require(authorizedAddresses[account], "Address not authorized");

        authorizedAddresses[account] = false;

        emit AuthorizationUpdated(account, false);
    }

    function addToWhiteList(address account) external onlyAccountManagerOrAdmin override {
        require(account != address(0), "Invalid account");
        require(iqosysWhiteList.add(account), "Account already white-listed");

        emit WhiteListed(account, true);
    }

    function removeFromWhiteList(address account) external onlyAccountManagerOrAdmin override {
        require(account != address(0), "Invalid account");
        require(iqosysWhiteList.remove(account), "Account not in white-list");

        emit WhiteListed(account, false);
    }

    function freezeAddress(address account) external onlyAccountManagerOrAdmin override {
        require(account != address(0), "Invalid account");
        require(!frozenAddresses[account], "Address already frozen");

        frozenAddresses[account] = true;

        emit AddressFrozen(account, true);
    }

    function unfreezeAddress(address account) external onlyAccountManagerOrAdmin override {
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

    function getWhiteList() public view override returns (address[] memory) {
        return iqosysWhiteList.values();
    }
}
