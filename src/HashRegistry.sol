// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./IHashRegistry.sol";
import "./IAccessControl.sol";

/// @title Hash Registry Module
/// @notice Stores and verifies document/publication/receipt hashes with metadata.
contract HashRegistry is Ownable, IHashRegistry {
    struct HashRecord {
        bool exists;
        address submitter;
        uint256 timestamp;
        string referenceType;
        uint256 referenceId;
    }

    IAccessControl public accessControl;

    mapping(bytes32 => HashRecord) private records;

    event HashAnchored(
        bytes32 indexed hash,
        string referenceType,
        uint256 indexed referenceId,
        address indexed submitter,
        uint256 timestamp
    );

    event HashRemoved(
        bytes32 indexed hash,
        address indexed removedBy,
        uint256 timestamp
    );

    /**
     * Legacy event compatibility.
     */
    event HashAdded(bytes32 indexed hash);

    constructor(
        address initialOwner,
        address accessControlAddress
    )
        Ownable(initialOwner)
    {
        require(
            initialOwner != address(0),
            "Invalid owner"
        );

        require(
            accessControlAddress != address(0),
            "Invalid access control"
        );

        accessControl =
            IAccessControl(accessControlAddress);
    }

    modifier onlyAdmin() {
        require(
            accessControl.isAdmin(msg.sender),
            "Caller is not an admin"
        );
        _;
    }

    /**
     * New ToR-compliant anchoring function.
     */
    function anchorHash(
        bytes32 hash,
        string calldata referenceType,
        uint256 referenceId
    )
        external
        onlyAdmin
        override
    {
        _anchorHash(
            hash,
            referenceType,
            referenceId,
            msg.sender
        );
    }

    /**
     * New metadata-aware removal function.
     */
    function removeHash(
        bytes32 hash
    )
        external
        onlyAdmin
        override
    {
        _removeHash(
            hash,
            msg.sender
        );
    }

    /**
     * Legacy compatibility.
     * Old code can still call addValidHash(hash).
     */
    function addValidHash(
        bytes32 hash
    )
        external
        onlyAdmin
        override
    {
        _anchorHash(
            hash,
            "LEGACY",
            0,
            msg.sender
        );

        emit HashAdded(hash);
    }

    /**
     * Legacy compatibility.
     * Old code can still call removeValidHash(hash).
     */
    function removeValidHash(
        bytes32 hash
    )
        external
        onlyAdmin
        override
    {
        _removeHash(
            hash,
            msg.sender
        );
    }

    function isHashValid(
        bytes32 hash
    )
        external
        view
        override
        returns (bool)
    {
        return records[hash].exists;
    }

    function getHashRecord(
        bytes32 hash
    )
        external
        view
        override
        returns (
            bool exists,
            address submitter,
            uint256 timestamp,
            string memory referenceType,
            uint256 referenceId
        )
    {
        HashRecord memory record =
            records[hash];

        return (
            record.exists,
            record.submitter,
            record.timestamp,
            record.referenceType,
            record.referenceId
        );
    }

    function _anchorHash(
        bytes32 hash,
        string memory referenceType,
        uint256 referenceId,
        address submitter
    )
        internal
    {
        require(
            hash != bytes32(0),
            "Invalid hash"
        );

        require(
            !records[hash].exists,
            "Hash already anchored"
        );

        require(
            bytes(referenceType).length > 0,
            "Reference type required"
        );

        records[hash] = HashRecord({
            exists: true,
            submitter: submitter,
            timestamp: block.timestamp,
            referenceType: referenceType,
            referenceId: referenceId
        });

        emit HashAnchored(
            hash,
            referenceType,
            referenceId,
            submitter,
            block.timestamp
        );
    }

    function _removeHash(
        bytes32 hash,
        address removedBy
    )
        internal
    {
        require(
            hash != bytes32(0),
            "Invalid hash"
        );

        require(
            records[hash].exists,
            "Hash not anchored"
        );

        delete records[hash];

        emit HashRemoved(
            hash,
            removedBy,
            block.timestamp
        );
    }
}