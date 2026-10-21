// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "./IAdminMultisig.sol";

import "./IAccessControl.sol";

/// @title Admin Multisig

/// @notice Lightweight on-chain multisig approval registry for sensitive AMF operations.

/// @dev Stores approvals by action hash. Does not store personal data.

///      Pending approvals are bound to a signer epoch and expire after ACTION_APPROVAL_VALIDITY.

contract AdminMultisig is IAdminMultisig {

    IAccessControl public accessControl;

    uint256 public override requiredSignatures;

    uint256 public override signerEpoch = 1;

    uint256 public constant override ACTION_APPROVAL_VALIDITY = 7 days;

    uint256 public constant override SIGNER_ROTATION_DELAY = 48 hours;
    mapping(bytes32 => bool) public override abortedSignerRotations;

    event SignerRotationAborted(bytes32 indexed actionHash, bytes32 indexed reasonHash, address indexed executedBy, uint256 timestamp);

    bool public override actionConsumerBootstrapLocked;

    address[] private signers;

    mapping(address => bool) public override isSigner;

    mapping(address => bool) private actionConsumers;

    struct ActionApproval {

        uint256 approvalCount;

        bool consumed;

        bool exists;

        uint256 signerEpoch;

        uint256 expiresAt;

        address intendedConsumer;

        mapping(address => uint256) approvedAtEpoch;
        mapping(address => uint256) approvedAtTime;

    }

    mapping(bytes32 => ActionApproval) private approvals;

    /// @notice Human-reviewable context, immutable until an unconsumed proposal expires.

    /// @dev calldataHash is the hash of exact ABI-encoded execution calldata,

    ///      computed off-chain. The multisig cannot generically derive it from

    ///      individual modules' bespoke action hashes: signers MUST compare

    ///      it to the prepared transaction independently before approval.

    struct ActionProposal {

        bool exists;

        address proposer;

        address consumer;

        bytes4 selector;

        bytes32 calldataHash;

        string description;

        uint256 proposedAt;

        uint256 deadline;

    }

    mapping(bytes32 => ActionProposal) private proposals;
    mapping(bytes32 => uint256) public override proposalVersion;
    struct QuorumBinding { bool exists; address consumer; bytes4 selector; bytes32 calldataHash; }
    mapping(bytes32 => QuorumBinding) private quorumBindings;
    mapping(bytes32 => mapping(address => bool)) private replacementVotes;
    event ProposalReplacementApproved(bytes32 indexed replacementHash, bytes32 indexed actionHash, address indexed signer);
    event ActionProposalCancelled(bytes32 indexed actionHash, bytes32 indexed previousFingerprint, bytes32 indexed replacementHash);


    event ActionProposed(

        bytes32 indexed actionHash,

        address indexed consumer,

        address indexed proposer,

        bytes4 selector,

        bytes32 calldataHash,

        string description,

        uint256 deadline

    );

    event ActionApproved(

        bytes32 indexed actionHash,

        address indexed signer,

        uint256 approvalCount,

        uint256 timestamp

    );

    event ActionConsumerBound(

        bytes32 indexed actionHash,

        address indexed consumer,

        uint256 indexed signerEpoch

    );

    event ActionApprovalRevoked(

        bytes32 indexed actionHash,

        address indexed signer,

        uint256 approvalCount,

        uint256 signerEpoch,

        uint256 timestamp

    );

    event ActionConsumed(

        bytes32 indexed actionHash,

        address indexed consumer,

        uint256 timestamp

    );

    event ActionConsumerUpdated(

        address indexed consumer,

        bool status,

        address indexed updatedBy,

        uint256 timestamp

    );

    event ActionConsumerBootstrapLocked(

        address indexed lockedBy,

        uint256 timestamp

    );

    event SignerReplaced(

        address indexed oldSigner,

        address indexed newSigner,

        bytes32 indexed referenceHash,

        address executedBy,

        uint256 timestamp

    );

    event RequiredSignaturesUpdated(

        uint256 oldRequiredSignatures,

        uint256 newRequiredSignatures,

        bytes32 indexed referenceHash,

        address executedBy,

        uint256 timestamp

    );

    constructor(address _accessControl, address[] memory _signers, uint256 _requiredSignatures) {

        require(_accessControl != address(0), "Invalid access control");

        require(_signers.length > 0, "Signers required");

        require(

            _requiredSignatures >= 2 && _requiredSignatures <= _signers.length,

            "Invalid required signatures"

        );

        accessControl = IAccessControl(_accessControl);

        requiredSignatures = _requiredSignatures;

        for (uint256 i = 0; i < _signers.length; i++) {

            address signer = _signers[i];

            require(signer != address(0), "Invalid signer");

            require(!isSigner[signer], "Duplicate signer");
            require(accessControl.isAdmin(signer), "Signer is not admin");

            isSigner[signer] = true;

            signers.push(signer);

        }

    }

    modifier onlyAdmin() {

        require(accessControl.isAdmin(msg.sender), "Caller is not an admin");

        _;

    }

    modifier onlySigner() {

        require(isSigner[msg.sender], "Caller is not signer");

        _;

    }

    modifier onlyActionConsumer() {

        require(actionConsumers[msg.sender], "Caller is not action consumer");

        _;

    }

    function signerCount() external view override returns (uint256) {

        return signers.length;

    }

    function getSigners() external view override returns (address[] memory) {

        return signers;

    }

    /// @notice Propose intent before approval; expired unconsumed intent may be renewed.

    /// @param actionHash Hash computed by the target module's get...ActionHash helper.

    /// @param consumer Actual module that will call consumeApprovedAction(hash).

    /// @param selector Function selector of the execution transaction.

    /// @param calldataHash keccak256 of the exact execution calldata, verified

    ///        independently by each signer using the proposed transaction.

    /// @param description Short public explanation with NO private information.

    /// @param deadline Explicit expiration; at most 7 days from proposal.

    function proposeAction(

        bytes32 actionHash,

        address consumer,

        bytes4 selector,

        bytes32 calldataHash,

        string calldata description,

        uint256 deadline

    ) external override {

        require(isSigner[msg.sender],

            "Caller cannot propose");

        require(actionHash != bytes32(0), "Invalid action hash");

        require(consumer == address(this) || actionConsumers[consumer],

            "Consumer not registered");

        require(selector != bytes4(0), "Selector required");

        require(calldataHash != bytes32(0), "Calldata hash required");

        require(bytes(description).length > 0 && bytes(description).length <= 160,

            "Invalid description length");

        require(deadline > block.timestamp &&

            deadline <= block.timestamp + ACTION_APPROVAL_VALIDITY,

            "Invalid proposal deadline");

        QuorumBinding storage binding = quorumBindings[actionHash];
        require(!binding.exists || (binding.consumer == consumer && binding.selector == selector
            && binding.calldataHash == calldataHash), "Action intent fixed by quorum");
        ActionProposal storage previous = proposals[actionHash];
        require(!previous.exists || block.timestamp > previous.deadline, "Action already proposed");

        require(!approvals[actionHash].consumed, "Action already consumed");
        if (previous.exists) _clearActionApprovals(actionHash);
        proposalVersion[actionHash]++;

        proposals[actionHash] = ActionProposal({

            exists: true,

            proposer: msg.sender,

            consumer: consumer,

            selector: selector,

            calldataHash: calldataHash,

            description: description,

            proposedAt: block.timestamp,

            deadline: deadline

        });

        emit ActionProposed(

            actionHash, consumer, msg.sender, selector,

            calldataHash, description, deadline

        );

    }

    /// @notice Fingerprint includes a monotonic version; same-block renewals are distinct.
    function getActionProposalFingerprint(bytes32 actionHash) public view override returns (bytes32) {
        return keccak256(abi.encode(address(this), block.chainid, actionHash,
            proposalVersion[actionHash], proposals[actionHash]));
    }

    function getProposalReplacementHash(ProposalReplacement calldata replacement)
        public view override returns (bytes32)
    {
        return keccak256(abi.encode(address(this), block.chainid, "REPLACE_ACTION_PROPOSAL",
            signerEpoch, replacement));
    }

    function getProposalReplacementApprovalCount(bytes32 replacementHash) public view override returns (uint256 count) {
        for (uint256 i; i < signers.length; i++) {
            if (replacementVotes[replacementHash][signers[i]]) count++;
        }
    }

    /// @notice Two signers (or a higher configured quorum) cancel and replace a
    /// squatted proposal atomically. Votes are separate from the squatted action.
    /// The repaired consumer/selector/calldata remain fixed across later renewals,
    /// so the rogue signer cannot squat the hash again at the next deadline.
    function approveProposalReplacement(ProposalReplacement calldata replacement)
        external override onlySigner
    {
        bytes32 hash = replacement.actionHash;
        require(proposals[hash].exists, "Action not proposed");
        require(!approvals[hash].consumed, "Action already consumed");
        require(replacement.expectedFingerprint == getActionProposalFingerprint(hash), "Proposal changed");
        require(replacement.consumer == address(this) || actionConsumers[replacement.consumer], "Consumer not registered");
        require(replacement.selector != bytes4(0), "Selector required");
        require(replacement.calldataHash != bytes32(0), "Calldata hash required");
        require(bytes(replacement.description).length > 0 && bytes(replacement.description).length <= 160,
            "Invalid description length");
        require(replacement.deadline > block.timestamp && replacement.deadline <= block.timestamp + ACTION_APPROVAL_VALIDITY,
            "Invalid proposal deadline");
        bytes32 voteHash = getProposalReplacementHash(replacement);
        require(!replacementVotes[voteHash][msg.sender], "Signer already voted");
        replacementVotes[voteHash][msg.sender] = true;
        emit ProposalReplacementApproved(voteHash, hash, msg.sender);
        uint256 threshold = requiredSignatures < 2 ? 2 : requiredSignatures;
        if (getProposalReplacementApprovalCount(voteHash) < threshold) return;
        _clearActionApprovals(hash);
        quorumBindings[hash] = QuorumBinding(true, replacement.consumer, replacement.selector, replacement.calldataHash);
        proposalVersion[hash]++;
        proposals[hash] = ActionProposal(true, msg.sender, replacement.consumer, replacement.selector,
            replacement.calldataHash, replacement.description, block.timestamp, replacement.deadline);
        emit ActionProposalCancelled(hash, replacement.expectedFingerprint, voteHash);
        emit ActionProposed(hash, replacement.consumer, msg.sender, replacement.selector,
            replacement.calldataHash, replacement.description, replacement.deadline);
    }

    function _clearActionApprovals(bytes32 hash) private {
        // Deleting a struct does not clear its nested mappings.
        for (uint256 i; i < signers.length; i++) {
            delete approvals[hash].approvedAtEpoch[signers[i]];
            delete approvals[hash].approvedAtTime[signers[i]];
        }
        delete approvals[hash];
    }

    /// @notice Time of the threshold-th signature among CURRENT valid approvals.
    /// Revocation/reapproval, rotation, expiry and proposal replacement cannot
    /// reuse an old signature's time to skip a consumer's execution delay.
    function getActionQuorumReachedAt(bytes32 hash, uint256 threshold) external view override returns (uint256) {
        require(threshold >= requiredSignatures && threshold <= signers.length, "Invalid required approval count");
        return _quorumReachedAtExcluding(hash, threshold, address(0));
    }

    function _quorumReachedAtExcluding(bytes32 hash, uint256 threshold, address excludedSigner)
        private view returns (uint256)
    {
        if (!isActionApprovedWithRequiredSignatures(hash, threshold)) return 0;
        uint256[] memory times = new uint256[](signers.length);
        uint256 count;
        ActionApproval storage approval = approvals[hash];
        for (uint256 i; i < signers.length; i++) {
            address signer = signers[i];
            if (signer == excludedSigner) continue;
            if (approval.approvedAtEpoch[signer] != signerEpoch) continue;
            uint256 timestamp = approval.approvedAtTime[signer];
            uint256 j = count;
            while (j > 0 && times[j - 1] > timestamp) { times[j] = times[j - 1]; j--; }
            times[j] = timestamp;
            count++;
        }
        return count >= threshold ? times[threshold - 1] : 0;
    }

    function getActionProposal(bytes32 actionHash)

        external view override returns (

            bool exists,

            address proposer,

            address consumer,

            bytes4 selector,

            bytes32 calldataHash,

            string memory description,

            uint256 proposedAt,

            uint256 deadline

        )

    {

        ActionProposal storage proposal = proposals[actionHash];

        return (

            proposal.exists, proposal.proposer, proposal.consumer,

            proposal.selector, proposal.calldataHash,

            proposal.description, proposal.proposedAt, proposal.deadline

        );

    }

    /// @notice Legacy API for multisig's *own* configuration actions only.

    /// @dev Approving a module action requires approveActionForConsumer(hash, module).

    function approveAction(bytes32 actionHash) external override onlySigner {

        _approveActionForConsumer(actionHash, address(this));

    }

    /// @notice Approves an action for exactly one registered consuming module.

    /// @dev All signers approving a hash must agree on its intended consumer.

    function approveActionForConsumer(bytes32 actionHash, address consumer)

        external

        override

        onlySigner

    {

        require(

            consumer == address(this) || actionConsumers[consumer],

            "Consumer not registered"

        );

        _approveActionForConsumer(actionHash, consumer);

    }

    function _approveActionForConsumer(bytes32 actionHash, address consumer) internal {

        require(actionHash != bytes32(0), "Invalid action hash");

        require(consumer != address(0), "Invalid consumer");

        ActionProposal storage proposal = proposals[actionHash];

        require(proposal.exists, "Action not proposed");

        require(proposal.consumer == consumer, "Action bound to different consumer");

        require(block.timestamp <= proposal.deadline, "Action approval expired");

        ActionApproval storage approval = approvals[actionHash];

        require(!approval.consumed, "Action already consumed");

        if (!approval.exists || approval.signerEpoch != signerEpoch) {

            // Rotation creates a fresh signer-epoch approval cycle; historical

            // consumed hashes still cannot be restarted.

            approval.exists = true;

            approval.approvalCount = 0;

            approval.signerEpoch = signerEpoch;

            approval.expiresAt = proposal.deadline;

            approval.intendedConsumer = proposal.consumer;

            emit ActionConsumerBound(actionHash, consumer, signerEpoch);

        } else {

            require(

                approval.intendedConsumer == consumer,

                "Action bound to different consumer"

            );

        }

        require(block.timestamp <= approval.expiresAt, "Action approval expired");

        require(

            approval.approvedAtEpoch[msg.sender] != signerEpoch,

            "Signer already approved"

        );

        approval.approvedAtEpoch[msg.sender] = signerEpoch;
        approval.approvedAtTime[msg.sender] = block.timestamp;

        approval.approvalCount++;

        emit ActionApproved(

            actionHash,

            msg.sender,

            approval.approvalCount,

            block.timestamp

        );

    }

    function revokeApproval(bytes32 actionHash) external override onlySigner {

        ActionApproval storage approval = approvals[actionHash];

        require(approval.exists, "Action not found");

        require(!approval.consumed, "Action already consumed");

        require(

            approval.signerEpoch == signerEpoch,

            "Action belongs to old signer epoch"

        );

        require(block.timestamp <= approval.expiresAt, "Action approval expired");

        require(

            approval.approvedAtEpoch[msg.sender] == signerEpoch,

            "Signer has not approved"

        );

        approval.approvedAtEpoch[msg.sender] = 0;
        approval.approvedAtTime[msg.sender] = 0;

        approval.approvalCount--;

        emit ActionApprovalRevoked(

            actionHash,

            msg.sender,

            approval.approvalCount,

            signerEpoch,

            block.timestamp

        );

    }

    /// @notice Returns the consumer selected by the first signer in the current

    ///         (or latest historical) signer-epoch approval cycle.

    function getActionConsumer(bytes32 actionHash)

        external

        view

        override

        returns (address)

    {

        return approvals[actionHash].intendedConsumer;

    }

    function isActionApproved(bytes32 actionHash) public view override returns (bool) {

        ActionApproval storage approval = approvals[actionHash];

        return

            approval.exists &&

            !approval.consumed &&

            approval.signerEpoch == signerEpoch &&

            block.timestamp <= approval.expiresAt &&

            approval.approvalCount >= requiredSignatures;

    }

    function isActionApprovedWithRequiredSignatures(

        bytes32 actionHash,

        uint256 requiredApprovalCount

    ) public view override returns (bool) {

        require(

            requiredApprovalCount > 0 && requiredApprovalCount <= signers.length,

            "Invalid required approval count"

        );

        ActionApproval storage approval = approvals[actionHash];

        return

            approval.exists &&

            !approval.consumed &&

            approval.signerEpoch == signerEpoch &&

            block.timestamp <= approval.expiresAt &&

            approval.approvalCount >= requiredApprovalCount;

    }

    function consumeApprovedAction(bytes32 actionHash)

        external

        override

        onlyActionConsumer

    {

        _consumeApprovedAction(actionHash, msg.sender);

    }

    function consumeApprovedActionWithRequiredSignatures(

        bytes32 actionHash,

        uint256 requiredApprovalCount

    ) external override onlyActionConsumer {
        require(requiredApprovalCount >= requiredSignatures, "Threshold below multisig minimum");

        _consumeApprovedActionWithRequiredSignatures(

            actionHash,

            requiredApprovalCount,

            msg.sender

        );

    }

    function _requireActionConsumer(bytes32 actionHash, address consumer)

        internal

        view

    {

        require(

            approvals[actionHash].intendedConsumer == consumer,

            "Action belongs to different consumer"

        );

    }

    function _consumeApprovedAction(bytes32 actionHash, address consumer) internal {

        _requireActionConsumer(actionHash, consumer);

        require(isActionApproved(actionHash), "Action not approved");

        approvals[actionHash].consumed = true;

        emit ActionConsumed(actionHash, consumer, block.timestamp);

    }

    function _consumeApprovedActionWithRequiredSignatures(

        bytes32 actionHash,

        uint256 requiredApprovalCount,

        address consumer

    ) internal {

        _requireActionConsumer(actionHash, consumer);

        require(

            isActionApprovedWithRequiredSignatures(

                actionHash,

                requiredApprovalCount

            ),

            "Action not approved"

        );

        approvals[actionHash].consumed = true;

        emit ActionConsumed(actionHash, consumer, block.timestamp);

    }

    function getApprovalState(bytes32 actionHash)

        external

        view

        override

        returns (uint256 approvalCount, bool consumed, bool exists)

    {

        ActionApproval storage approval = approvals[actionHash];

        if (!approval.exists) {

            return (0, false, false);

        }

        // Historical consumed actions keep the approval count they had

        // when they were executed, even after a later signer rotation.

        if (approval.consumed) {

            return (

                approval.approvalCount,

                true,

                true

            );

        }

        // Pending approvals from an old signer set or an expired approval

        // window must not count toward the current signer set.

        if (

            approval.signerEpoch != signerEpoch ||

            block.timestamp > approval.expiresAt

        ) {

            return (0, false, true);

        }

        return (

            approval.approvalCount,

            false,

            true

        );

    }

    function hasApprovedAction(

        bytes32 actionHash,

        address signer

    ) external view override returns (bool) {

        ActionApproval storage approval = approvals[actionHash];

        return

            approval.exists &&

            !approval.consumed &&

            approval.signerEpoch == signerEpoch &&

            block.timestamp <= approval.expiresAt &&

            approval.approvedAtEpoch[signer] == signerEpoch;

    }

    function getApprovalCountExcluding(

        bytes32 actionHash,

        address excludedSigner

    ) public view override returns (uint256 count) {

        ActionApproval storage approval = approvals[actionHash];

        if (

            !approval.exists ||

            approval.consumed ||

            approval.signerEpoch != signerEpoch ||

            block.timestamp > approval.expiresAt

        ) {

            return 0;

        }

        for (uint256 i = 0; i < signers.length; i++) {

            address signer = signers[i];

            if (

                signer != excludedSigner &&

                approval.approvedAtEpoch[signer] == signerEpoch

            ) {

                count++;

            }

        }

        return count;

    }

    function setActionConsumer(

        address consumer,

        bool status

    ) external override onlyAdmin {

        require(

            !actionConsumerBootstrapLocked,

            "Action consumer bootstrap is locked"

        );

        require(consumer != address(0), "Invalid consumer");

        actionConsumers[consumer] = status;

        emit ActionConsumerUpdated(

            consumer,

            status,

            msg.sender,

            block.timestamp

        );

    }

    function isActionConsumer(address consumer) external view override returns (bool) {

        return actionConsumers[consumer];

    }

    function lockActionConsumerBootstrap() external override onlyAdmin {

        require(

            !actionConsumerBootstrapLocked,

            "Action consumer bootstrap already locked"

        );

        actionConsumerBootstrapLocked = true;

        emit ActionConsumerBootstrapLocked(

            msg.sender,

            block.timestamp

        );

    }

    function getSetActionConsumerActionHash(

        address consumer,

        bool status,

        bytes32 referenceHash

    ) public view override returns (bytes32) {

        return keccak256(

            abi.encode(

                address(this),

                block.chainid,

                "SET_ACTION_CONSUMER",

                consumer,

                status,

                referenceHash

            )

        );

    }

    function setActionConsumerWithApproval(

        address consumer,

        bool status,

        bytes32 referenceHash

    ) external override onlyAdmin {

        require(consumer != address(0), "Invalid consumer");

        require(referenceHash != bytes32(0), "Reference hash required");

        bytes32 actionHash = getSetActionConsumerActionHash(

            consumer,

            status,

            referenceHash

        );

        _consumeApprovedAction(actionHash, address(this));

        actionConsumers[consumer] = status;

        emit ActionConsumerUpdated(

            consumer,

            status,

            msg.sender,

            block.timestamp

        );

    }

    function _consumeApprovedActionExcludingSigner(

        bytes32 actionHash,

        address excludedSigner,

        uint256 requiredApprovalCount

    ) internal {

        _requireActionConsumer(actionHash, address(this));

        require(requiredApprovalCount > 0, "Invalid required approval count");

        uint256 availableSigners = signers.length - 1;

        require(

            requiredApprovalCount <= availableSigners,

            "Replacement threshold exceeds remaining signers"

        );

        require(

            getApprovalCountExcluding(

                actionHash,

                excludedSigner

            ) >= requiredApprovalCount,

            "Action not approved by remaining signers"

        );

        approvals[actionHash].consumed = true;

        emit ActionConsumed(actionHash, msg.sender, block.timestamp);

    }

    function getReplaceSignerActionHash(

        address oldSigner,

        address newSigner,

        bytes32 referenceHash

    ) public view override returns (bytes32) {

        return keccak256(

            abi.encode(

                address(this),

                block.chainid,

                "REPLACE_ADMIN_SIGNER",

                oldSigner,

                newSigner,

                referenceHash

            )

        );

    }

    function replaceSigner(

        address oldSigner,

        address newSigner,

        bytes32 referenceHash

    ) external override onlyAdmin {

        require(oldSigner != address(0), "Invalid old signer");

        require(newSigner != address(0), "Invalid new signer");

        require(oldSigner != newSigner, "Signers must differ");

        require(isSigner[oldSigner], "Old signer not found");

        require(!isSigner[newSigner], "New signer already exists");

        require(referenceHash != bytes32(0), "Reference hash required");

        bytes32 actionHash = getReplaceSignerActionHash(

            oldSigner,

            newSigner,

            referenceHash

        );

        uint256 remainingSignerCount = signers.length - 1;

        uint256 replacementRequiredSignatures =

            requiredSignatures > remainingSignerCount

                ? remainingSignerCount

                : requiredSignatures;

        // Recovery never counts the departing signer, even toward the delay.
        require(replacementRequiredSignatures >= 2, "Insufficient remaining signers");
        require(!abortedSignerRotations[actionHash], "Signer rotation aborted");
        uint256 quorumAt = _quorumReachedAtExcluding(actionHash, replacementRequiredSignatures, oldSigner);
        require(quorumAt != 0, "Action not approved by remaining signers");
        require(block.timestamp >= quorumAt + SIGNER_ROTATION_DELAY, "Signer rotation delay not elapsed");

        _consumeApprovedActionExcludingSigner(

            actionHash,

            oldSigner,

            replacementRequiredSignatures

        );

        // Keep the invariant that every multisig signer is also an AccessControl admin.
        // If anything below reverts, the admin rotation is reverted in the same transaction.
        accessControl.replaceSignerAdmin(oldSigner, newSigner);

        isSigner[oldSigner] = false;

        isSigner[newSigner] = true;

        bool replaced = false;

        for (uint256 i = 0; i < signers.length; i++) {

            if (signers[i] == oldSigner) {

                signers[i] = newSigner;

                replaced = true;

                break;

            }

        }

        require(replaced, "Signer array mismatch");

        // H-4: every pending approval created under the old signer set

        // becomes ineffective after a signer rotation.

        signerEpoch++;

        emit SignerReplaced(

            oldSigner,

            newSigner,

            referenceHash,

            msg.sender,

            block.timestamp

        );

    }

    /// @notice Returns zero if the attempt is aborted, consumed, stale or lacks quorum.
    function signerRotationReadyAt(address oldSigner, address newSigner, bytes32 referenceHash)
        external view override returns (uint256)
    {
        if (!isSigner[oldSigner] || newSigner == address(0) || isSigner[newSigner]
            || referenceHash == bytes32(0)) return 0;
        bytes32 hash = getReplaceSignerActionHash(oldSigner, newSigner, referenceHash);
        if (abortedSignerRotations[hash]) return 0;
        uint256 remaining = signers.length - 1;
        uint256 threshold = requiredSignatures > remaining ? remaining : requiredSignatures;
        if (threshold < 2) return 0;
        uint256 quorumAt = _quorumReachedAtExcluding(hash, threshold, oldSigner);
        return quorumAt == 0 ? 0 : quorumAt + SIGNER_ROTATION_DELAY;
    }

    function getAbortSignerRotationActionHash(address oldSigner, address newSigner, bytes32 referenceHash, bytes32 reasonHash)
        public view override returns (bytes32)
    {
        return keccak256(abi.encode(address(this), block.chainid, "ABORT_ADMIN_SIGNER_ROTATION",
            getReplaceSignerActionHash(oldSigner, newSigner, referenceHash), reasonHash));
    }

    /// @notice A separate current quorum can abort without waiting 48 hours.
    /// The attempt stays cancelled permanently; retry with a fresh reference hash.
    function abortSignerRotation(address oldSigner, address newSigner, bytes32 referenceHash, bytes32 reasonHash)
        external override onlyAdmin
    {
        require(isSigner[oldSigner] && newSigner != address(0) && !isSigner[newSigner], "Invalid signer rotation");
        require(referenceHash != bytes32(0) && reasonHash != bytes32(0), "Reference and reason required");
        bytes32 hash = getReplaceSignerActionHash(oldSigner, newSigner, referenceHash);
        require(!abortedSignerRotations[hash], "Signer rotation aborted");
        require(!approvals[hash].consumed, "Signer rotation already executed");
        _consumeApprovedAction(getAbortSignerRotationActionHash(oldSigner, newSigner, referenceHash, reasonHash), address(this));
        abortedSignerRotations[hash] = true;
        emit SignerRotationAborted(hash, reasonHash, msg.sender, block.timestamp);
    }

    function getSetRequiredSignaturesActionHash(

        uint256 newRequiredSignatures,

        bytes32 referenceHash

    ) public view override returns (bytes32) {

        return keccak256(

            abi.encode(

                address(this),

                block.chainid,

                "SET_REQUIRED_SIGNATURES",

                newRequiredSignatures,

                referenceHash

            )

        );

    }

    function setRequiredSignaturesWithApproval(

        uint256 newRequiredSignatures,

        bytes32 referenceHash

    ) external override onlyAdmin {

        require(

            newRequiredSignatures >= 2 &&

                newRequiredSignatures <= signers.length,

            "Invalid required signatures"

        );

        require(referenceHash != bytes32(0), "Reference hash required");

        bytes32 actionHash = getSetRequiredSignaturesActionHash(

            newRequiredSignatures,

            referenceHash

        );

        _consumeApprovedAction(actionHash, address(this));

        uint256 oldRequiredSignatures = requiredSignatures;

        requiredSignatures = newRequiredSignatures;

        emit RequiredSignaturesUpdated(

            oldRequiredSignatures,

            newRequiredSignatures,

            referenceHash,

            msg.sender,

            block.timestamp

        );

    }

}
