// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./IHashRegistry.sol";
import "./IAccessControl.sol";

/// @title Hash Registry Module
/// @notice Append-only storage and verification of document/publication/receipt hashes with metadata.
/// @dev Anchored hashes are never deleted. Corrections are represented by immutable supersession links.
contract HashRegistry is IHashRegistry {
    struct HashRecord {
        bool exists;
        address submitter;
        uint256 timestamp;
        string referenceType;
        uint256 referenceId;
    }

    IAccessControl public accessControl;

    mapping(bytes32 => HashRecord) private records;
    mapping(bytes32 => HashRecord) private moduleRecords;
    event ModuleHashAnchored(address indexed module, bytes32 indexed hash, bytes32 indexed key, string referenceType, uint256 referenceId, uint256 timestamp);
    mapping(bytes32 => bytes32) private supersededBy;
    mapping(bytes32 => bytes32) private supersedes;
    mapping(bytes32 => bytes32) private supersessionReasonHash;

    event HashAnchored(
        bytes32 indexed hash,
        string referenceType,
        uint256 indexed referenceId,
        address indexed submitter,
        uint256 timestamp
    );

    event HashSuperseded(
        bytes32 indexed oldHash,
        bytes32 indexed newHash,
        bytes32 indexed reasonHash,
        address supersededByAdmin,
        uint256 timestamp
    );

    /// @dev Legacy event compatibility for addValidHash().
    event HashAdded(bytes32 indexed hash);

    constructor(address accessControlAddress) {
        require(accessControlAddress != address(0), "Invalid access control");

        accessControl = IAccessControl(accessControlAddress);
    }

    modifier onlyAdmin() {
        require(accessControl.isAdmin(msg.sender), "Caller is not an admin");
        _;
    }

    modifier onlyAdminOrAnchor() {
        require(accessControl.isAdmin(msg.sender) || accessControl.hasRole(accessControl.ROLE_ANCHOR(), msg.sender), "Caller is not an admin or anchor");
        _;
    }

    /// @notice Store a module anchor under a key that other callers cannot occupy.
    function moduleAnchorKey(address module, bytes32 hash) public pure override returns (bytes32) {
        return keccak256(abi.encode("IQOSYS_MODULE_ANCHOR", module, hash));
    }

    function anchorModuleHash(bytes32 hash, string calldata referenceType, uint256 referenceId)
        external override
    {
        require(accessControl.hasRole(accessControl.ROLE_ANCHOR(), msg.sender), "Caller is not an anchor");
        require(hash != bytes32(0), "Invalid hash");
        // Separate storage prevents squatting even if an admin preanchors the key.
        bytes32 key = moduleAnchorKey(msg.sender, hash);
        require(!moduleRecords[key].exists, "Module hash already anchored");
        require(bytes(referenceType).length > 0, "Reference type required");
        moduleRecords[key] = HashRecord(true, msg.sender, block.timestamp, referenceType, referenceId);
        emit ModuleHashAnchored(msg.sender, hash, key, referenceType, referenceId, block.timestamp);
    }

    function getModuleHashRecord(address module, bytes32 hash) external view override
        returns (bool exists, address submitter, uint256 timestamp, string memory referenceType, uint256 referenceId)
    {
        HashRecord memory record = moduleRecords[moduleAnchorKey(module, hash)];
        return (record.exists, record.submitter, record.timestamp, record.referenceType, record.referenceId);
    }

    /// @notice Anchors a new immutable hash with metadata.
    function anchorHash(bytes32 hash, string calldata referenceType, uint256 referenceId) external onlyAdminOrAnchor override {
        _anchorHash(hash, referenceType, referenceId, msg.sender);
    }

    /// @notice Legacy compatibility wrapper for callers that do not provide metadata.
    /// @dev This remains append-only and cannot later be deleted.
    function addValidHash(bytes32 hash) external onlyAdminOrAnchor override {
        _anchorHash(hash, "LEGACY", 0, msg.sender);
        emit HashAdded(hash);
    }

    /// @notice Records a correction without deleting or mutating the original anchor.
    /// @dev The new hash inherits the original reference metadata. The original remains permanently queryable.
    function supersedeHash(bytes32 oldHash, bytes32 newHash, bytes32 reasonHash) external onlyAdmin override {
        require(oldHash != bytes32(0), "Invalid old hash");
        require(newHash != bytes32(0), "Invalid new hash");
        require(reasonHash != bytes32(0), "Reason hash required");
        require(oldHash != newHash, "Hashes must differ");
        require(records[oldHash].exists, "Old hash not anchored");
        require(!records[newHash].exists, "New hash already anchored");
        require(supersededBy[oldHash] == bytes32(0), "Hash already superseded");

        HashRecord storage oldRecord = records[oldHash];

        _anchorHash(
            newHash,
            oldRecord.referenceType,
            oldRecord.referenceId,
            msg.sender
        );

        supersededBy[oldHash] = newHash;
        supersedes[newHash] = oldHash;
        supersessionReasonHash[oldHash] = reasonHash;

        emit HashSuperseded(
            oldHash,
            newHash,
            reasonHash,
            msg.sender,
            block.timestamp
        );
    }

    /// @notice Returns true if the hash has ever been anchored.
    /// @dev Superseded hashes remain valid historical anchors and therefore still return true.
    function isHashValid(bytes32 hash) external view override returns (bool) {
        return records[hash].exists;
    }

    /// @notice Returns true if this anchored hash has been superseded by a correction.
    function isHashSuperseded(bytes32 hash) external view override returns (bool) {
        return supersededBy[hash] != bytes32(0);
    }

    function getHashRecord(bytes32 hash)
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
        HashRecord memory record = records[hash];

        return (
            record.exists,
            record.submitter,
            record.timestamp,
            record.referenceType,
            record.referenceId
        );
    }

    /// @notice Returns immutable correction lineage for an anchored hash.
    /// @return supersededByHash The newer hash that replaced this hash, or zero if none.
    /// @return supersedesHash The older hash that this hash replaced, or zero if none.
    /// @return reasonHash The reason hash recorded when this hash was superseded, or zero if none.
    function getSupersession(bytes32 hash)
        external
        view
        override
        returns (
            bytes32 supersededByHash,
            bytes32 supersedesHash,
            bytes32 reasonHash
        )
    {
        return (
            supersededBy[hash],
            supersedes[hash],
            supersessionReasonHash[hash]
        );
    }

    function _anchorHash(bytes32 hash, string memory referenceType, uint256 referenceId, address submitter) internal {
        require(hash != bytes32(0), "Invalid hash");
        require(!records[hash].exists, "Hash already anchored");
        require(bytes(referenceType).length > 0, "Reference type required");

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
}
