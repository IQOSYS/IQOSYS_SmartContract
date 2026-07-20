// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title IQOSYS Governance Registry Interface
/// @notice Stores immutable final outcomes of off-chain voting procedures
interface IGovernanceRegistry {
    event GovernanceOutcomeRecorded(
        uint256 indexed voteId,
        bytes32 indexed resultHash,
        bytes32 metadataHash,
        uint256 participantCount,
        uint256[] answerIds,
        uint256[] voteCounts,
        uint256 recordedAt,
        address indexed recordedBy
    );

    /**
     * @notice Record the final result of a closed off-chain vote.
     *
     * @param voteId Laravel vote identifier
     * @param metadataHash Hash of canonical off-chain vote metadata
     * @param participantCount Number of unique participants
     * @param answerIds Answer identifiers
     * @param voteCounts Final vote count for each answer
     */
    function recordOutcome(
        uint256 voteId,
        bytes32 metadataHash,
        uint256 participantCount,
        uint256[] calldata answerIds,
        uint256[] calldata voteCounts
    ) external;

    /**
     * @notice Returns whether a result has already been recorded.
     */
    function hasOutcome(
        uint256 voteId
    ) external view returns (bool);

    /**
     * @notice Returns the stored final outcome.
     */
    function getOutcome(
        uint256 voteId
    )
        external
        view
        returns (
            bytes32 metadataHash,
            bytes32 resultHash,
            uint256 participantCount,
            uint256 recordedAt,
            address recordedBy,
            uint256[] memory answerIds,
            uint256[] memory voteCounts
        );

    /**
     * @notice Deterministically calculates the result hash.
     */
    function calculateResultHash(
        uint256 voteId,
        bytes32 metadataHash,
        uint256 participantCount,
        uint256[] calldata answerIds,
        uint256[] calldata voteCounts
    ) external pure returns (bytes32);
}