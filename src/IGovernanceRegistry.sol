// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IGovernanceRegistry {
    enum VotingPopulation {
        None,
        OSTHolders,
        IQSHolders,
        IQSAndOSTHolders
    }

    enum VotingPowerSource {
        None,
        OST,
        IQS,
        IQSAndOST
    }

    struct GovernanceOutcome {
        uint256 id;
        uint256 voteId;
        bytes32 metadataHash;
        bytes32 resultHash;
        uint256 participantCount;
        uint256[] answerIds;
        uint256[] votePowers;
        VotingPopulation population;
        VotingPowerSource powerSource;
        address recordedBy;
        uint256 recordedAt;
    }

    function calculateResultHash(
        uint256 voteId,
        bytes32 metadataHash,
        uint256 participantCount,
        uint256[] calldata answerIds,
        uint256[] calldata votePowers
    ) external view returns (bytes32);

    function calculateResultHashWithPopulation(
        uint256 voteId,
        bytes32 metadataHash,
        uint256 participantCount,
        uint256[] calldata answerIds,
        uint256[] calldata votePowers,
        VotingPopulation population,
        VotingPowerSource powerSource
    ) external view returns (bytes32);

    function recordOutcome(
        uint256 voteId,
        bytes32 metadataHash,
        uint256 participantCount,
        uint256[] calldata answerIds,
        uint256[] calldata votePowers
    ) external returns (uint256);

    function recordOutcomeWithPopulation(
        uint256 voteId,
        bytes32 metadataHash,
        uint256 participantCount,
        uint256[] calldata answerIds,
        uint256[] calldata votePowers,
        VotingPopulation population,
        VotingPowerSource powerSource
    ) external returns (uint256);

    function outcomesf(
        uint256 outcomeId
    ) external view returns (GovernanceOutcome memory);

    function outcomeCount()
        external
        view
        returns (uint256);

    function latestOutcomeId()
        external
        view
        returns (uint256);

    function isVoteOutcomeRecorded(
        uint256 voteId
    ) external view returns (bool);

    function outcomeIdOfVote(
        uint256 voteId
    ) external view returns (uint256);
}