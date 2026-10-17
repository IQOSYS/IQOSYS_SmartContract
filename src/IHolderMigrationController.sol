// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IHolderMigrationController {
    function MIGRATION_DELAY() external view returns (uint256);
    function abortedMigrations(bytes32 actionHash) external view returns (bool);
    function executedMigrations(bytes32 actionHash) external view returns (bool);
    function migrationReadyAt(address oldWallet, address newWallet, bytes32 referenceHash) external view returns (uint256);
    function getAbortHolderMigrationActionHash(address oldWallet, address newWallet, bytes32 referenceHash, bytes32 reasonHash) external view returns (bytes32);
    function abortHolderMigration(address oldWallet, address newWallet, bytes32 referenceHash, bytes32 reasonHash) external;

    struct HolderMigration {
        uint256 id;
        address oldWallet;
        address newWallet;
        bytes32 referenceHash;
        address executedBy;
        uint256 executedAt;
    }

    function getHolderMigrationActionHash(
        address oldWallet,
        address newWallet,
        bytes32 referenceHash
    ) external view returns (bytes32);

    function migrateHolder(
        address oldWallet,
        address newWallet,
        bytes32 referenceHash
    ) external returns (uint256);

    function migrationsf(uint256 migrationId)
        external view returns (HolderMigration memory);

    function migrationCount() external view returns (uint256);
}
