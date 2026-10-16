// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IHolderMigrationController {
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
