// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "./IValuationAnchor.sol";
import "./IAccessControl.sol";
import "./IAdminMultisig.sol";
import "./IHashRegistry.sol";

/// @notice Anchors off-chain valuations; each correction is a new immutable record.
/// @dev The hash includes the off-chain period and record identifier (prepared by Laravel).
contract ValuationAnchor is IValuationAnchor, ReentrancyGuard, Pausable {
    IAccessControl public accessControl;
    IAdminMultisig public adminMultisig;
    IHashRegistry public hashRegistry;

    // L-4: zero unambiguously means no correction / no published anchor.
    uint256 private nextAnchorId = 1;
    uint256 public override latestAnchorId;
    mapping(uint256 => ValuationAnchorRecord) private anchors;

    event ValuationAnchored(uint256 indexed anchorId, bytes32 indexed periodHash, bytes32 indexed valuationHash, bytes32 methodologyHash, uint256 referenceId, address recordedBy, uint256 timestamp);
    event ValuationCorrectionAnchored(uint256 indexed anchorId, uint256 indexed correctedAnchorId, bytes32 indexed periodHash, bytes32 valuationHash, bytes32 methodologyHash, uint256 referenceId, address recordedBy, uint256 timestamp);
    event ValuationAnchorPaused(address indexed admin, uint256 timestamp);
    event ValuationAnchorUnpaused(address indexed admin, uint256 timestamp);

    constructor(address _accessControl, address _adminMultisig, address _hashRegistry) {
        require(_accessControl != address(0), "Invalid access control");
        require(_adminMultisig != address(0), "Invalid admin multisig");
        require(_hashRegistry != address(0), "Invalid hash registry");
        accessControl = IAccessControl(_accessControl);
        adminMultisig = IAdminMultisig(_adminMultisig);
        hashRegistry = IHashRegistry(_hashRegistry);
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
        emit ValuationAnchorPaused(msg.sender, block.timestamp);
    }
    function unpause() external onlyEmergency {
        _unpause();
        emit ValuationAnchorUnpaused(msg.sender, block.timestamp);
    }

    function getPublishValuationActionHash(
        bytes32 periodHash, bytes32 valuationHash, bytes32 methodologyHash,
        uint256 referenceId, bool isCorrection, uint256 correctedAnchorId
    ) public view override returns (bytes32) {
        return keccak256(abi.encode(address(this), block.chainid, "PUBLISH_VALUATION", periodHash, valuationHash, methodologyHash, referenceId, isCorrection, correctedAnchorId));
    }

    function publishQuarterlyValuation(bytes32 periodHash, bytes32 valuationHash, bytes32 methodologyHash, uint256 referenceId)
        external override onlyAdmin whenNotPaused nonReentrant returns (uint256)
    {
        return _publishValuation(periodHash, valuationHash, methodologyHash, referenceId, false, 0);
    }

    function publishCorrectionValuation(bytes32 periodHash, bytes32 valuationHash, bytes32 methodologyHash, uint256 referenceId, uint256 correctedAnchorId)
        external override onlyAdmin whenNotPaused nonReentrant returns (uint256)
    {
        require(correctedAnchorId > 0 && correctedAnchorId < nextAnchorId, "Corrected anchor not found");
        require(anchors[correctedAnchorId].kind != AnchorKind.None, "Corrected anchor not found");
        // Correction must belong to the original quarterly period.
        require(anchors[correctedAnchorId].periodHash == periodHash, "Correction period mismatch");
        return _publishValuation(periodHash, valuationHash, methodologyHash, referenceId, true, correctedAnchorId);
    }

    function _publishValuation(bytes32 periodHash, bytes32 valuationHash, bytes32 methodologyHash, uint256 referenceId, bool isCorrection, uint256 correctedAnchorId)
        internal returns (uint256)
    {
        require(periodHash != bytes32(0), "Period hash required");
        require(valuationHash != bytes32(0), "Valuation hash required");
        require(methodologyHash != bytes32(0), "Methodology hash required");
        require(referenceId > 0, "Reference id required");
        bytes32 actionHash = getPublishValuationActionHash(periodHash, valuationHash, methodologyHash, referenceId, isCorrection, correctedAnchorId);
        adminMultisig.consumeApprovedAction(actionHash);
        uint256 anchorId = nextAnchorId++;
        anchors[anchorId] = ValuationAnchorRecord({
            id: anchorId,
            periodHash: periodHash,
            valuationHash: valuationHash,
            methodologyHash: methodologyHash,
            referenceId: referenceId,
            correctedAnchorId: correctedAnchorId,
            recordedBy: msg.sender,
            recordedAt: block.timestamp,
            kind: isCorrection ? AnchorKind.Correction : AnchorKind.Quarterly
        });
        latestAnchorId = anchorId;
        hashRegistry.anchorModuleHash(valuationHash, isCorrection ? "VALUATION_CORRECTION" : "VALUATION", referenceId);
        if (isCorrection) {
            emit ValuationCorrectionAnchored(anchorId, correctedAnchorId, periodHash, valuationHash, methodologyHash, referenceId, msg.sender, block.timestamp);
        } else {
            emit ValuationAnchored(anchorId, periodHash, valuationHash, methodologyHash, referenceId, msg.sender, block.timestamp);
        }
        return anchorId;
    }

    function anchorsf(uint256 anchorId) external view override returns (ValuationAnchorRecord memory) {
        return anchors[anchorId];
    }

    function anchorCount() external view override returns (uint256) {
        return nextAnchorId - 1;
    }
}
