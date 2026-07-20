// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title Interface for IQS to OST Conversion Module
/// @notice Handles admin-mediated IQS to OST conversion requests, approvals, rejections, cancellations and receipt records.
interface IConversionModule {
    enum ConversionStatus {
        None,
        Requested,
        Approved,
        Rejected,
        Cancelled
    }

    struct IQSToOSTConversion {
        uint256 id;
        address requester;
        uint256 amount;
        uint256 timestamp;
        uint256 completedAt;
        ConversionStatus status;
        bytes32 referenceHash;
        bytes32 receiptHash;
    }

    function adminCreateIQSToOSTConversionRequest(
        address requester,
        uint256 amount,
        bytes32 referenceHash
    ) external returns (uint256);

    function approveIQSToOSTConversion(
        uint256 requestId
    ) external;

    function rejectIQSToOSTConversion(
        uint256 requestId
    ) external;

    function adminCancelIQSToOSTConversion(
        uint256 requestId
    ) external;

    function adminRecordIQSToOSTConversionReceiptHash(
        uint256 requestId,
        bytes32 receiptHash
    ) external;

    function getIQSToOSTConversion(
        uint256 requestId
    ) external view returns (IQSToOSTConversion memory);

    function getTransactionHistoryLengthIQStoOST()
        external
        view
        returns (uint256);
}