// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

import "./IGovernanceRegistry.sol";
import "./IAccessControl.sol";
import "./IAdminMultisig.sol";
import "./HashRegistry.sol";

/// @title Governance Registry
/// @notice Records off-chain voting outcomes on-chain as evidentiary anchors.
/// @dev Ballots and voter identities stay off-chain. The chain stores weighted outcome totals and hashes only.
contract GovernanceRegistry is IGovernanceRegistry, ReentrancyGuard, Pausable {
    IAccessControl public accessControl;
    HashRegistry public hashRegistry;
    IAdminMultisig public adminMultisig;

    uint256 private nextOutcomeId;
    uint256 public override latestOutcomeId;

    mapping(uint256 => GovernanceOutcome) private outcomes;
    mapping(uint256 => uint256) private outcomeIdPlusOneByVoteId;

    /// @notice Evidence commitment to off-chain SIGNED ballot records, keyed by voteId.
    /// @dev The registry does not independently verify signatures or tally all ballots.
    mapping(uint256 => bytes32) public ballotMerkleRootByVoteId;

    event GovernanceBallotRootAnchored(
        uint256 indexed voteId,
        bytes32 indexed ballotMerkleRoot,
        bytes32 indexed resultHash,
        address recordedBy,
        uint256 timestamp
    );

    event GovernanceOutcomeRecorded(
        uint256 indexed outcomeId,
        uint256 indexed voteId,
        bytes32 indexed resultHash,
        bytes32 metadataHash,
        uint256 participantCount,
        VotingPopulation population,
        VotingPowerSource powerSource,
        address recordedBy,
        uint256 timestamp
    );

    event GovernanceRegistryPaused(address indexed admin, uint256 timestamp);
    event GovernanceRegistryUnpaused(address indexed admin, uint256 timestamp);

    constructor(address _accessControl, address _hashRegistry, address _adminMultisig) {
        require(_accessControl != address(0), "Invalid access control");
        require(_hashRegistry != address(0), "Invalid hash registry");
        require(_adminMultisig != address(0), "Invalid admin multisig");
        accessControl = IAccessControl(_accessControl);
        hashRegistry = HashRegistry(_hashRegistry);
        adminMultisig = IAdminMultisig(_adminMultisig);
    }

    modifier onlyAdmin() {
        require(accessControl.isAdmin(msg.sender), "Caller is not an admin");
        _;
    }

    modifier onlyEmergency() {
        require(accessControl.hasRole(accessControl.ROLE_EMERGENCY(), msg.sender), "Caller is not emergency controller");
        _;
    }

    modifier onlyAdminOrEmergency() {
        require(accessControl.isAdmin(msg.sender) || accessControl.hasRole(accessControl.ROLE_EMERGENCY(), msg.sender), "Caller is not an admin or emergency controller");
        _;
    }

    function pause() external onlyAdminOrEmergency {
        _pause();
        emit GovernanceRegistryPaused(msg.sender, block.timestamp);
    }

    function unpause() external onlyEmergency {
        _unpause();
        emit GovernanceRegistryUnpaused(msg.sender, block.timestamp);
    }

    // Legacy hash, kept for current backend/bridge payload compatibility.
    function calculateResultHash(uint256 voteId, bytes32 metadataHash, uint256 participantCount, uint256[] calldata answerIds, uint256[] calldata votePowers) public view override returns (bytes32) {
        return keccak256(abi.encode(address(this), block.chainid, "GOVERNANCE_OUTCOME", voteId, metadataHash, participantCount, answerIds, votePowers));
    }

    function calculateResultHashWithPopulation(uint256 voteId, bytes32 metadataHash, uint256 participantCount, uint256[] calldata answerIds, uint256[] calldata votePowers, VotingPopulation population, VotingPowerSource powerSource) public view override returns (bytes32) {
        return keccak256(abi.encode(address(this), block.chainid, "GOVERNANCE_OUTCOME_V2", voteId, metadataHash, participantCount, answerIds, votePowers, population, powerSource));
    }

    /// @dev Retained in ABI so the old backend cannot silently publish unbacked votes.
    function recordOutcome(
        uint256, bytes32, uint256, uint256[] calldata, uint256[] calldata
    ) external pure override returns (uint256) {
        revert("Use ballot-root outcome API");
    }

    /// @dev Retained in ABI so the old backend cannot bypass the M-5 proof commitment.
    function recordOutcomeWithPopulation(
        uint256, bytes32, uint256, uint256[] calldata, uint256[] calldata,
        VotingPopulation, VotingPowerSource
    ) external pure override returns (uint256) {
        revert("Use ballot-root outcome API");
    }

    /// @notice Computes the commitment to the tally AND off-chain signed-ballot Merkle root.
    /// @dev The root is computed off-chain from canonical signed ballot records.
    ///      Contracts do NOT assert that the root represents verified signatures or an accurate tally.
    function calculateResultHashWithBallotRoot(
        uint256 voteId,
        bytes32 metadataHash,
        bytes32 ballotMerkleRoot,
        uint256 participantCount,
        uint256[] calldata answerIds,
        uint256[] calldata votePowers,
        VotingPopulation population,
        VotingPowerSource powerSource
    ) public view returns (bytes32) {
        return keccak256(abi.encode(
            address(this), block.chainid, "GOVERNANCE_RESULT_M5",
            voteId, metadataHash, ballotMerkleRoot, participantCount,
            answerIds, votePowers, population, powerSource
        ));
    }

    /// @notice Signers must review tally + root and approve THIS action hash for this module.
    function getRecordOutcomeActionHash(
        uint256 voteId,
        bytes32 metadataHash,
        bytes32 ballotMerkleRoot,
        uint256 participantCount,
        uint256[] calldata answerIds,
        uint256[] calldata votePowers,
        VotingPopulation population,
        VotingPowerSource powerSource
    ) public view returns (bytes32) {
        bytes32 resultHash = calculateResultHashWithBallotRoot(
            voteId, metadataHash, ballotMerkleRoot, participantCount,
            answerIds, votePowers, population, powerSource
        );
        return keccak256(abi.encode(
            address(this), block.chainid, "RECORD_GOVERNANCE_OUTCOME_M5", resultHash
        ));
    }

    /// @notice Publish a multisig-approved weighted tally backed by an immutable ballot root.
    /// @dev No full ballot, voter identity or signature is stored on-chain.
    function recordOutcomeWithBallotRoot(
        uint256 voteId,
        bytes32 metadataHash,
        bytes32 ballotMerkleRoot,
        uint256 participantCount,
        uint256[] calldata answerIds,
        uint256[] calldata votePowers,
        VotingPopulation population,
        VotingPowerSource powerSource
    ) external onlyAdmin whenNotPaused nonReentrant returns (uint256) {
        require(ballotMerkleRoot != bytes32(0), "Ballot root required");
        require(participantCount > 0, "Participants required");
        require(voteId > 0, "Vote id required");
        require(outcomeIdPlusOneByVoteId[voteId] == 0, "Vote outcome already recorded");

        bytes32 resultHash = calculateResultHashWithBallotRoot(
            voteId, metadataHash, ballotMerkleRoot, participantCount,
            answerIds, votePowers, population, powerSource
        );
        bytes32 actionHash = keccak256(abi.encode(
            address(this), block.chainid, "RECORD_GOVERNANCE_OUTCOME_M5", resultHash
        ));

        // M-4 consumer binding: the approval MUST be for GovernanceRegistry.
        adminMultisig.consumeApprovedAction(actionHash);

        ballotMerkleRootByVoteId[voteId] = ballotMerkleRoot;
        uint256 outcomeId = _recordOutcome(
            voteId, metadataHash, resultHash, participantCount,
            answerIds, votePowers, population, powerSource
        );
        emit GovernanceBallotRootAnchored(
            voteId, ballotMerkleRoot, resultHash, msg.sender, block.timestamp
        );
        return outcomeId;
    }

    function _recordOutcome(uint256 voteId, bytes32 metadataHash, bytes32 resultHash, uint256 participantCount, uint256[] calldata answerIds, uint256[] calldata votePowers, VotingPopulation population, VotingPowerSource powerSource) internal returns (uint256) {
        require(voteId > 0, "Vote id required");
        require(metadataHash != bytes32(0), "Metadata hash required");
        require(resultHash != bytes32(0), "Result hash required");
        require(answerIds.length > 0, "Answers required");
        require(answerIds.length == votePowers.length, "Array length mismatch");
        require(population != VotingPopulation.None, "Voting population required");
        require(powerSource != VotingPowerSource.None, "Voting power source required");
        require(outcomeIdPlusOneByVoteId[voteId] == 0, "Vote outcome already recorded");

        uint256 outcomeId = nextOutcomeId++;
        outcomes[outcomeId] = GovernanceOutcome({
            id: outcomeId,
            voteId: voteId,
            metadataHash: metadataHash,
            resultHash: resultHash,
            participantCount: participantCount,
            answerIds: answerIds,
            votePowers: votePowers,
            population: population,
            powerSource: powerSource,
            recordedBy: msg.sender,
            recordedAt: block.timestamp
        });

        outcomeIdPlusOneByVoteId[voteId] = outcomeId + 1;
        latestOutcomeId = outcomeId;
        hashRegistry.anchorModuleHash(resultHash, "VOTE_RESULT", voteId);

        emit GovernanceOutcomeRecorded(outcomeId, voteId, resultHash, metadataHash, participantCount, population, powerSource, msg.sender, block.timestamp);
        return outcomeId;
    }

    function outcomesf(uint256 outcomeId) external view override returns (GovernanceOutcome memory) {
        return outcomes[outcomeId];
    }

    function outcomeCount() external view override returns (uint256) {
        return nextOutcomeId;
    }

    function isVoteOutcomeRecorded(uint256 voteId) external view override returns (bool) {
        return outcomeIdPlusOneByVoteId[voteId] != 0;
    }

    function outcomeIdOfVote(uint256 voteId) external view override returns (uint256) {
        require(outcomeIdPlusOneByVoteId[voteId] != 0, "Outcome not found");
        return outcomeIdPlusOneByVoteId[voteId] - 1;
    }
}
