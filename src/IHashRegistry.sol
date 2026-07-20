// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title Interface for Hash Registry Module
/// @notice Manages storage and verification of document/publication/receipt hashes.
interface IHashRegistry {
    function anchorHash(
        bytes32 hash,
        string calldata referenceType,
        uint256 referenceId
    ) external;

    function addValidHash(
        bytes32 hash
    ) external;

    function removeHash(
        bytes32 hash
    ) external;

    function removeValidHash(
        bytes32 hash
    ) external;

    function isHashValid(
        bytes32 hash
    ) external view returns (bool);

    function getHashRecord(
        bytes32 hash
    )
        external
        view
        returns (
            bool exists,
            address submitter,
            uint256 timestamp,
            string memory referenceType,
            uint256 referenceId
        );
}