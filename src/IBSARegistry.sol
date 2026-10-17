// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title BSA Registry Interface
/// @notice Records signed BSA terms and controls IQS awards under each BSA. No personal data must be stored on-chain.
interface IBSARegistry {
    enum BSAStatus {
        None,
        Active,
        Exhausted,
        Expired,
        Cancelled
    }

    struct BSARecord {
        uint256 id;
        address holder;
        bytes32 bsaReferenceHash;
        bytes32 termsHash;
        uint256 strikePrice; // Integer EUR cents per OST: 185 means EUR 1.85.
        uint256 maxIQS;
        uint256 awardedIQS;
        uint256 convertedIQS;
        uint256 premiumPaid; // Integer EUR cents for the entire BSA.
        uint256 expiryDate;
        uint256 createdAt;
        BSAStatus status;
    }

    function getRecordBSAActionHash(
        address holder,
        bytes32 bsaReferenceHash,
        bytes32 termsHash,
        uint256 strikePrice,
        uint256 maxIQS,
        uint256 expiryDate,
        uint256 premiumPaid
    ) external view returns (bytes32);

    function recordBSA(
        address holder,
        bytes32 bsaReferenceHash,
        bytes32 termsHash,
        uint256 strikePrice,
        uint256 maxIQS,
        uint256 expiryDate,
        uint256 premiumPaid
    ) external returns (uint256);

    function getCreditIQSActionHash(uint256 bsaId, uint256 amount, bytes32 awardReferenceHash) external view returns (bytes32);
    function creditIQS(uint256 bsaId, uint256 amount, bytes32 awardReferenceHash) external;
    function recordIQSConverted(uint256 bsaId, uint256 amount, bytes32 conversionReferenceHash) external;
    function getCancelBSAActionHash(uint256 bsaId, bytes32 reasonHash) external view returns (bytes32);
    function totalIQSInEscrow() external view returns (uint256);
    function iqsInEscrowOf(address holder) external view returns (uint256);
    function cancelBSA(uint256 bsaId, bytes32 reasonHash) external;
    function syncBSAStatus(uint256 bsaId) external;
    function setConversionModule(address conversionModule) external;

    function bsasf(uint256 bsaId) external view returns (BSARecord memory);
    function activeBSAOf(address holder) external view returns (uint256);
    function bsaCount() external view returns (uint256);
    function remainingIQSToAward(uint256 bsaId) external view returns (uint256);
    function availableIQSToExercise(uint256 bsaId) external view returns (uint256);
    function expiredIQSBurnedOf(uint256 bsaId) external view returns (uint256);

    function holderMigrationController() external view returns (address);
    function setHolderMigrationController(address holderMigrationController) external;
    function migrateHolderBSA(address oldWallet, address newWallet) external returns (uint256 migratedCount);
    function getBSAIdsOf(address holder) external view returns (uint256[] memory);
}
