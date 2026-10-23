// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./IHolderMigrationController.sol";
import "./IAccessControl.sol";
import "./IAdminMultisig.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface IWalletMigrationTokenManager {
    function adminMigrateWallet(
        address oldWallet,
        address newWallet,
        bytes32 referenceHash
    ) external;
}

interface IWalletMigrationBSARegistry {
    function migrateHolderBSA(
        address oldWallet,
        address newWallet
    ) external returns (uint256 migratedCount);
}

/// @title Holder Migration Controller
/// @notice Quorum-controlled holder wallet recovery after a 48-hour on-chain delay.
/// @dev No personal data is stored on-chain. referenceHash commits to private evidence.
contract HolderMigrationController is IHolderMigrationController, ReentrancyGuard {
    IAccessControl public accessControl;
    IAdminMultisig public adminMultisig;
    IWalletMigrationTokenManager public tokenManager;
    IWalletMigrationBSARegistry public bsaRegistry;
    uint256 private nextMigrationId;
    uint256 public constant override MIGRATION_DELAY = 48 hours;
    mapping(bytes32 => bool) public override abortedMigrations;
    mapping(bytes32 => bool) public override executedMigrations;
    event HolderMigrationAborted(bytes32 indexed actionHash, bytes32 indexed reasonHash, address indexed executedBy, uint256 timestamp);

    mapping(uint256 => HolderMigration) private migrations;

    event HolderWalletMigratedByController(
        uint256 indexed migrationId,
        address indexed oldWallet,
        address indexed newWallet,
        bytes32 referenceHash,
        address executedBy,
        uint256 timestamp
    );

    constructor(
        address _accessControl,
        address _adminMultisig,
        address _tokenManager,
        address _bsaRegistry
    ) {
        require(_accessControl != address(0), "Invalid access control");
        require(_adminMultisig != address(0), "Invalid admin multisig");
        require(_tokenManager != address(0), "Invalid token manager");
        require(_bsaRegistry != address(0), "Invalid BSA registry");

        bsaRegistry = IWalletMigrationBSARegistry(_bsaRegistry);
        accessControl = IAccessControl(_accessControl);
        adminMultisig = IAdminMultisig(_adminMultisig);
        tokenManager = IWalletMigrationTokenManager(_tokenManager);
    }

    modifier onlyAdmin() {
        require(accessControl.isAdmin(msg.sender), "Caller is not an admin");
        _;
    }

    function getHolderMigrationActionHash(
        address oldWallet,
        address newWallet,
        bytes32 referenceHash
    ) public view override returns (bytes32) {
        return keccak256(abi.encode(
            address(this), block.chainid, "HOLDER_WALLET_MIGRATION",
            oldWallet, newWallet, referenceHash
        ));
    }

    function migrateHolder(
        address oldWallet,
        address newWallet,
        bytes32 referenceHash
    ) external override onlyAdmin nonReentrant returns (uint256) {
        require(oldWallet != address(0), "Invalid old wallet");
        require(newWallet != address(0), "Invalid new wallet");
        require(oldWallet != newWallet, "Wallets must differ");
        require(referenceHash != bytes32(0), "Reference hash required");

        bytes32 actionHash = getHolderMigrationActionHash(
            oldWallet, newWallet, referenceHash
        );

        require(!abortedMigrations[actionHash], "Migration aborted");
        require(!executedMigrations[actionHash], "Migration already executed");
        uint256 threshold = _migrationThreshold();
        uint256 quorumAt = adminMultisig.getActionQuorumReachedAt(actionHash, threshold);
        require(quorumAt != 0, "Action not approved");
        require(block.timestamp >= quorumAt + MIGRATION_DELAY, "Migration delay not elapsed");
        adminMultisig.consumeApprovedActionWithRequiredSignatures(actionHash, threshold);
        executedMigrations[actionHash] = true;

        bsaRegistry.migrateHolderBSA(oldWallet, newWallet);
        tokenManager.adminMigrateWallet(oldWallet, newWallet, referenceHash);

        uint256 migrationId = nextMigrationId++;
        migrations[migrationId] = HolderMigration({
            id: migrationId,
            oldWallet: oldWallet,
            newWallet: newWallet,
            referenceHash: referenceHash,
            executedBy: msg.sender,
            executedAt: block.timestamp
        });

        emit HolderWalletMigratedByController(
            migrationId, oldWallet, newWallet,
            referenceHash, msg.sender, block.timestamp
        );
        return migrationId;
    }

    function migrationReadyAt(address oldWallet, address newWallet, bytes32 referenceHash)
        external view override returns (uint256)
    {
        bytes32 hash = getHolderMigrationActionHash(oldWallet, newWallet, referenceHash);
        if (abortedMigrations[hash] || executedMigrations[hash]) return 0;
        uint256 quorumAt = adminMultisig.getActionQuorumReachedAt(hash, _migrationThreshold());
        return quorumAt == 0 ? 0 : quorumAt + MIGRATION_DELAY;
    }

    function getAbortHolderMigrationActionHash(address oldWallet, address newWallet, bytes32 referenceHash, bytes32 reasonHash)
        public view override returns (bytes32)
    {
        return keccak256(abi.encode(address(this), block.chainid, "ABORT_HOLDER_WALLET_MIGRATION",
            getHolderMigrationActionHash(oldWallet, newWallet, referenceHash), reasonHash));
    }

    /// @notice A separate quorum action aborts this migration attempt permanently.
    /// Abort has no 48-hour delay and is available until execution. A new attempt
    /// needs a fresh evidence reference, new approvals and a new full delay.
    function abortHolderMigration(address oldWallet, address newWallet, bytes32 referenceHash, bytes32 reasonHash)
        external override onlyAdmin nonReentrant
    {
        require(oldWallet != address(0) && newWallet != address(0) && oldWallet != newWallet, "Invalid wallets");
        require(referenceHash != bytes32(0) && reasonHash != bytes32(0), "Reference and reason required");
        bytes32 hash = getHolderMigrationActionHash(oldWallet, newWallet, referenceHash);
        require(!abortedMigrations[hash], "Migration aborted");
        require(!executedMigrations[hash], "Migration already executed");
        adminMultisig.consumeApprovedActionWithRequiredSignatures(
            getAbortHolderMigrationActionHash(oldWallet, newWallet, referenceHash, reasonHash), _migrationThreshold());
        abortedMigrations[hash] = true;
        emit HolderMigrationAborted(hash, reasonHash, msg.sender, block.timestamp);
    }

    function _migrationThreshold() private view returns (uint256) {
        uint256 configured = adminMultisig.requiredSignatures();
        return configured < 2 ? 2 : configured;
    }

    function migrationsf(uint256 migrationId)
        external view override returns (HolderMigration memory)
    {
        return migrations[migrationId];
    }

    function migrationCount() external view override returns (uint256) {
        return nextMigrationId;
    }
}
