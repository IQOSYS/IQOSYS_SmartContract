// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IAdminMultisig {
    struct ProposalReplacement {
        bytes32 actionHash;
        bytes32 expectedFingerprint;
        address consumer;
        bytes4 selector;
        bytes32 calldataHash;
        string description;
        uint256 deadline;
    }
    function proposalVersion(bytes32 actionHash) external view returns (uint256);
    function getActionProposalFingerprint(bytes32 actionHash) external view returns (bytes32);
    function getProposalReplacementHash(ProposalReplacement calldata replacement) external view returns (bytes32);
    function getProposalReplacementApprovalCount(bytes32 replacementHash) external view returns (uint256);
    function approveProposalReplacement(ProposalReplacement calldata replacement) external;
    function getActionQuorumReachedAt(bytes32 actionHash, uint256 threshold) external view returns (uint256);

    function requiredSignatures() external view returns (uint256);
    function signerEpoch() external view returns (uint256);
    function ACTION_APPROVAL_VALIDITY() external view returns (uint256);

    function signerCount() external view returns (uint256);
    function isSigner(address signer) external view returns (bool);
    function getSigners() external view returns (address[] memory);

    /// @notice Signers propose action intent; expired unconsumed proposals may be renewed.
    function proposeAction(
        bytes32 actionHash,
        address consumer,
        bytes4 selector,
        bytes32 calldataHash,
        string calldata description,
        uint256 deadline
    ) external;

    function getActionProposal(bytes32 actionHash)
        external view returns (
            bool exists,
            address proposer,
            address consumer,
            bytes4 selector,
            bytes32 calldataHash,
            string memory description,
            uint256 proposedAt,
            uint256 deadline
        );

    /// @notice Legacy approval API: binds an action to AdminMultisig itself.
    function approveAction(bytes32 actionHash) external;

    /// @notice Approves an action for a specific registered action consumer.
    function approveActionForConsumer(bytes32 actionHash, address consumer) external;

    function getActionConsumer(bytes32 actionHash) external view returns (address);
    function revokeApproval(bytes32 actionHash) external;

    function isActionApproved(bytes32 actionHash) external view returns (bool);

    function isActionApprovedWithRequiredSignatures(
        bytes32 actionHash,
        uint256 requiredApprovalCount
    ) external view returns (bool);

    function consumeApprovedAction(bytes32 actionHash) external;

    function consumeApprovedActionWithRequiredSignatures(
        bytes32 actionHash,
        uint256 requiredApprovalCount
    ) external;

    function getApprovalState(bytes32 actionHash)
        external
        view
        returns (uint256 approvalCount, bool consumed, bool exists);

    function hasApprovedAction(bytes32 actionHash, address signer) external view returns (bool);

    function getApprovalCountExcluding(
        bytes32 actionHash,
        address excludedSigner
    ) external view returns (uint256);

    function setActionConsumer(address consumer, bool status) external;
    function isActionConsumer(address consumer) external view returns (bool);

    function lockActionConsumerBootstrap() external;
    function actionConsumerBootstrapLocked() external view returns (bool);

    function getSetActionConsumerActionHash(
        address consumer,
        bool status,
        bytes32 referenceHash
    ) external view returns (bytes32);

    function setActionConsumerWithApproval(
        address consumer,
        bool status,
        bytes32 referenceHash
    ) external;

    function getReplaceSignerActionHash(
        address oldSigner,
        address newSigner,
        bytes32 referenceHash
    ) external view returns (bytes32);

    function replaceSigner(
        address oldSigner,
        address newSigner,
        bytes32 referenceHash
    ) external;

    function getSetRequiredSignaturesActionHash(
        uint256 newRequiredSignatures,
        bytes32 referenceHash
    ) external view returns (bytes32);

    function setRequiredSignaturesWithApproval(
        uint256 newRequiredSignatures,
        bytes32 referenceHash
    ) external;
}
