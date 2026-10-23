// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IConversionModule {
    enum ExerciseStatus {
        None,
        Requested,
        Approved,
        Rejected,
        CapitalReceived,
        Settled,
        Cancelled
    }

    struct IQSExerciseRequest {
        uint256 id;
        uint256 bsaId;
        address requester;
        uint256 amount;
        uint256 strikePrice;
        uint256 capitalDue;
        bytes32 bsaReferenceHash;
        bytes32 referenceHash;
        bytes32 capitalPaymentHash;
        bytes32 receiptHash;
        bytes32 rejectionReasonHash;
        ExerciseStatus status;
        uint256 requestedAt;
        uint256 approvedAt;
        uint256 capitalConfirmedAt;
        uint256 settledAt;
        uint256 rejectedAt;
        uint256 cancelledAt;
    }

    function requestExercise(uint256 bsaId, uint256 amount, bytes32 referenceHash) external returns (uint256);
    function approveExercise(uint256 requestId) external;
    function getRejectCapitalReceivedExerciseActionHash(uint256 requestId, bytes32 reasonHash) external view returns (bytes32);
    function rejectExercise(uint256 requestId, bytes32 reasonHash) external;
    function cancelExercise(uint256 requestId) external;
    function confirmCapitalReceived(uint256 requestId, bytes32 capitalPaymentHash) external;
    function finalizeExercise(uint256 requestId, bytes32 receiptHash) external;
    function recordExerciseReceiptHash(uint256 requestId, bytes32 receiptHash) external;

    function getFinalizeExerciseActionHash(
        uint256 requestId,
        bytes32 receiptHash
    ) external view returns (bytes32);

    function getExerciseRequest(
        uint256 requestId
    ) external view returns (IQSExerciseRequest memory);

    function exerciseRequestCount() external view returns (uint256);
    function pendingExerciseIQSForBSA(uint256 bsaId) external view returns (uint256);

    function adminCreateIQSToOSTConversionRequest(
        address requester,
        uint256 amount,
        bytes32 referenceHash
    ) external returns (uint256);

    function approveIQSToOSTConversion(uint256 requestId) external;
    function rejectIQSToOSTConversion(uint256 requestId) external;
    function adminCancelIQSToOSTConversion(uint256 requestId) external;
    function adminRecordIQSToOSTConversionReceiptHash(uint256 requestId, bytes32 receiptHash) external;

    function getIQSToOSTConversion(
        uint256 requestId
    ) external view returns (IQSExerciseRequest memory);
}
