// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title Interface for Hash Registry Module
/// @notice Append-only storage and verification of document/publication/receipt hashes.
interface IHashRegistry {
    function moduleAnchorKey(address module, bytes32 hash) external pure returns (bytes32);
    function anchorModuleHash(bytes32 hash, string calldata referenceType, uint256 referenceId) external;
    function getModuleHashRecord(address module, bytes32 hash) external view returns (bool exists, address submitter, uint256 timestamp, string memory referenceType, uint256 referenceId);
    function anchorHash(bytes32 hash, string calldata referenceType, uint256 referenceId) external;

    function addValidHash(bytes32 hash) external;

    function supersedeHash(bytes32 oldHash, bytes32 newHash, bytes32 reasonHash) external;

    function isHashValid(bytes32 hash) external view returns (bool);

    function isHashSuperseded(bytes32 hash) external view returns (bool);

    function getHashRecord(bytes32 hash)
        external
        view
        returns (
            bool exists,
            address submitter,
            uint256 timestamp,
            string memory referenceType,
            uint256 referenceId
        );

    function getSupersession(bytes32 hash)
        external
        view
        returns (
            bytes32 supersededByHash,
            bytes32 supersedesHash,
            bytes32 reasonHash
        );
}
