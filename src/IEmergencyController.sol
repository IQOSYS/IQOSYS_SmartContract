// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IEmergencyController {
    enum EmergencyScope {
        None,
        All,
        Distribution,
        Conversions,
        Transactions,
        Valuation,
        Governance
    }

    struct EmergencyStatus {
        bool tokenManagerPaused;
        bool bsaRegistryPaused;
        bool conversionModulePaused;
        bool ostTransferModulePaused;
        bool valuationAnchorPaused;
        bool governanceRegistryPaused;
    }

    function getEmergencyActionHash(
        EmergencyScope scope,
        bool shouldPause,
        bytes32 referenceHash
    ) external view returns (bytes32);

    function pauseAll(
        bytes32 referenceHash
    ) external;

    function unpauseAll(
        bytes32 referenceHash
    ) external;

    function pauseDistribution(
        bytes32 referenceHash
    ) external;

    function unpauseDistribution(
        bytes32 referenceHash
    ) external;

    function pauseConversions(
        bytes32 referenceHash
    ) external;

    function unpauseConversions(
        bytes32 referenceHash
    ) external;

    function pauseTransactions(
        bytes32 referenceHash
    ) external;

    function unpauseTransactions(
        bytes32 referenceHash
    ) external;

    function pauseValuation(
        bytes32 referenceHash
    ) external;

    function unpauseValuation(
        bytes32 referenceHash
    ) external;

    function pauseGovernance(
        bytes32 referenceHash
    ) external;

    function unpauseGovernance(
        bytes32 referenceHash
    ) external;

    function getEmergencyStatus()
        external
        view
        returns (EmergencyStatus memory);
}