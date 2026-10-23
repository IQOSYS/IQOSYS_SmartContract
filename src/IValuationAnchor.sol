// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
interface IValuationAnchor {
    enum AnchorKind { None, Quarterly, Correction }
    struct ValuationAnchorRecord {
        uint256 id;
        bytes32 periodHash;
        bytes32 valuationHash;
        bytes32 methodologyHash;
        uint256 referenceId;
        uint256 correctedAnchorId;
        address recordedBy;
        uint256 recordedAt;
        AnchorKind kind;
    }
    function getPublishValuationActionHash(bytes32 periodHash, bytes32 valuationHash, bytes32 methodologyHash, uint256 referenceId, bool isCorrection, uint256 correctedAnchorId) external view returns (bytes32);
    function publishQuarterlyValuation(bytes32 periodHash, bytes32 valuationHash, bytes32 methodologyHash, uint256 referenceId) external returns (uint256);
    function publishCorrectionValuation(bytes32 periodHash, bytes32 valuationHash, bytes32 methodologyHash, uint256 referenceId, uint256 correctedAnchorId) external returns (uint256);
    function anchorsf(uint256 anchorId) external view returns (ValuationAnchorRecord memory);
    function latestAnchorId() external view returns (uint256);
    function anchorCount() external view returns (uint256);
}
