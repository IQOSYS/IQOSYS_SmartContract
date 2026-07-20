// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./IGovernanceRegistry.sol";
import "./IAccessControl.sol";

/// @title IQOSYS Governance Registry
/// @notice Immutable registry of final outcomes from off-chain voting procedures
contract GovernanceRegistry is IGovernanceRegistry {
    IAccessControl public immutable accessControl;

    struct GovernanceOutcome {
        bytes32 metadataHash;
        bytes32 resultHash;
        uint256 participantCount;
        uint256 recordedAt;
        address recordedBy;
        bool recorded;
    }

    mapping(uint256 => GovernanceOutcome) private _outcomes;

    mapping(uint256 => uint256[]) private _answerIds;
    mapping(uint256 => uint256[]) private _voteCounts;

    constructor(address _accessControl) {
        require(
            _accessControl != address(0),
            "Invalid access control"
        );

        accessControl =
            IAccessControl(_accessControl);
    }

    modifier onlyAdmin() {
        require(
            accessControl.isAdmin(msg.sender),
            "Caller is not an admin"
        );

        _;
    }

    /**
     * @notice Records a final governance outcome.
     *
     * Voting itself happens off-chain.
     * Only the immutable final result is stored on-chain.
     */
    function recordOutcome(
        uint256 voteId,
        bytes32 metadataHash,
        uint256 participantCount,
        uint256[] calldata answerIds,
        uint256[] calldata voteCounts
    )
        external
        override
        onlyAdmin
    {
        require(
            voteId > 0,
            "Invalid vote ID"
        );

        require(
            metadataHash != bytes32(0),
            "Invalid metadata hash"
        );

        require(
            !_outcomes[voteId].recorded,
            "Outcome already recorded"
        );

        require(
            answerIds.length >= 2,
            "At least two answers required"
        );

        require(
            answerIds.length == voteCounts.length,
            "Result array length mismatch"
        );

        uint256 totalSelections = 0;

        for (
            uint256 i = 0;
            i < answerIds.length;
            i++
        ) {
            require(
                answerIds[i] > 0,
                "Invalid answer ID"
            );

            /*
             * Even for multiple-choice votes,
             * one answer cannot have more votes
             * than the total number of participants.
             */
            require(
                voteCounts[i] <= participantCount,
                "Answer count exceeds participants"
            );

            /*
             * Answer IDs must be unique.
             */
            for (
                uint256 j = i + 1;
                j < answerIds.length;
                j++
            ) {
                require(
                    answerIds[i] != answerIds[j],
                    "Duplicate answer ID"
                );
            }

            totalSelections += voteCounts[i];
        }

        if (participantCount == 0) {
            require(
                totalSelections == 0,
                "Votes exist without participants"
            );
        } else {
            /*
             * Single choice:
             * totalSelections == participantCount
             *
             * Multiple choice:
             * totalSelections >= participantCount
             */
            require(
                totalSelections >= participantCount,
                "Invalid participation count"
            );
        }

        bytes32 resultHash =
            _calculateResultHash(
                voteId,
                metadataHash,
                participantCount,
                answerIds,
                voteCounts
            );

        _outcomes[voteId] =
            GovernanceOutcome({
                metadataHash: metadataHash,
                resultHash: resultHash,
                participantCount: participantCount,
                recordedAt: block.timestamp,
                recordedBy: msg.sender,
                recorded: true
            });

        for (
            uint256 i = 0;
            i < answerIds.length;
            i++
        ) {
            _answerIds[voteId].push(
                answerIds[i]
            );

            _voteCounts[voteId].push(
                voteCounts[i]
            );
        }

        emit GovernanceOutcomeRecorded(
            voteId,
            resultHash,
            metadataHash,
            participantCount,
            answerIds,
            voteCounts,
            block.timestamp,
            msg.sender
        );
    }

    function hasOutcome(
        uint256 voteId
    )
        external
        view
        override
        returns (bool)
    {
        return _outcomes[voteId].recorded;
    }

    function getOutcome(
        uint256 voteId
    )
        external
        view
        override
        returns (
            bytes32 metadataHash,
            bytes32 resultHash,
            uint256 participantCount,
            uint256 recordedAt,
            address recordedBy,
            uint256[] memory answerIds,
            uint256[] memory voteCounts
        )
    {
        GovernanceOutcome storage outcome =
            _outcomes[voteId];

        require(
            outcome.recorded,
            "Outcome not recorded"
        );

        return (
            outcome.metadataHash,
            outcome.resultHash,
            outcome.participantCount,
            outcome.recordedAt,
            outcome.recordedBy,
            _answerIds[voteId],
            _voteCounts[voteId]
        );
    }

    function calculateResultHash(
        uint256 voteId,
        bytes32 metadataHash,
        uint256 participantCount,
        uint256[] calldata answerIds,
        uint256[] calldata voteCounts
    )
        external
        pure
        override
        returns (bytes32)
    {
        return
            _calculateResultHash(
                voteId,
                metadataHash,
                participantCount,
                answerIds,
                voteCounts
            );
    }

    function _calculateResultHash(
        uint256 voteId,
        bytes32 metadataHash,
        uint256 participantCount,
        uint256[] calldata answerIds,
        uint256[] calldata voteCounts
    )
        internal
        pure
        returns (bytes32)
    {
        return keccak256(
            abi.encode(
                voteId,
                metadataHash,
                participantCount,
                answerIds,
                voteCounts
            )
        );
    }
}