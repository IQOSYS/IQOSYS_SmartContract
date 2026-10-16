// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./IHolderMigrationController.sol";
import "./IAccessControl.sol";
import "./IAdminMultisig.sol";

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
/// @notice Unanimous multisig-controlled holder wallet recovery after identity re-proofing.
/// @dev No personal data is stored on-chain. referenceHash commits to private evidence.
contract HolderMigrationController is IHolderMigrationController {
    IAccessControl public accessControl;
    IAdminMultisig public adminMultisig;
    IWalletMigrationTokenManager public tokenManager;
    IWalletMigrationBSARegistry public bsaRegistry;
    uint256 private nextMigrationId;

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
    ) external override onlyAdmin returns (uint256) {
        require(oldWallet != address(0), "Invalid old wallet");
        require(newWallet != address(0), "Invalid new wallet");
        require(oldWallet != newWallet, "Wallets must differ");
        require(referenceHash != bytes32(0), "Reference hash required");

        bytes32 actionHash = getHolderMigrationActionHash(
            oldWallet, newWallet, referenceHash
        );

        // Audit C-1: ALL active signers must approve holder recovery.
        // General AdminMultisig.requiredSignatures() remains 2-of-3.
        adminMultisig.consumeApprovedActionWithRequiredSignatures(
            actionHash,
            adminMultisig.signerCount()
        );

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

    function migrationsf(uint256 migrationId)
        external view override returns (HolderMigration memory)
    {
        return migrations[migrationId];
    }

    function migrationCount() external view override returns (uint256) {
        return nextMigrationId;
    }
}
