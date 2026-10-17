// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title Interface for OST Transfer Module
/// @notice AMF production model: whitelisted P2P OST transfers with registrar/admin validation. Controlled transfer flow only.
interface IOSTTransferModule {
    function activeTransferCount(address wallet) external view returns (uint256);
    function openTransferCount() external view returns (uint256);
    function PAYMENT_VALIDATION_TIMEOUT() external view returns (uint256);
    function paymentValidationDeadline(uint256 id) external view returns (uint256);
    function getAdminCreateTransferRequestActionHash(TransferType transferType, address seller, address buyer, uint256 amount, uint256 pricePerOST, bytes32 referenceHash) external view returns (bytes32);
    function getAdminValidateSellerPaymentActionHash(uint256 id, bytes32 sellerReceiptHash) external view returns (bytes32);
    function getAdminConfirmOSTTransactionActionHash(uint256 id, bytes32 receiptHash) external view returns (bytes32);
    function ESCROW_TIMEOUT() external view returns (uint256);
    enum TransferStatus {
        None,
        Requested,
        Countered,
        Escrowed,
        PaymentProofRegistered,
        SellerValidatedPayment,
        Disputed,
        Released,
        Returned,
        Cancelled,
        Rejected
    }

    enum TransferType {
        None,
        SellRequest,
        BuyRequest
    }

    struct OSTTransfer {
        uint256 id;
        TransferType transferType;
        address proposer;
        address lastActionBy;
        address seller;
        address buyer;
        uint256 amount;
        uint256 pricePerOST; // Integer EUR cents per OST.
        uint256 createdAt;
        uint256 updatedAt;
        uint256 completedAt;
        uint256 escrowDeadline;
        TransferStatus status;
        bytes32 referenceHash;
        bytes32 counterOfferHash;
        bytes32 agreementHash;
        bytes32 paymentProofHash;
        bytes32 sellerReceiptHash;
        bytes32 receiptHash;
        bytes32 resolutionHash;
    }

    function createSellTransferRequest(address seller, address buyer, uint256 amount, uint256 pricePerOST, bytes32 referenceHash) external returns (uint256);
    function createBuyTransferRequest(address buyer, address seller, uint256 amount, uint256 pricePerOST, bytes32 referenceHash) external returns (uint256);

    function getAdminCreateAgreedSellTransferActionHash(
        address seller,
        address buyer,
        uint256 amount,
        uint256 pricePerOST,
        bytes32 referenceHash,
        bytes32 agreementHash
    ) external view returns (bytes32);

    function adminCreateAgreedSellTransferAndLockEscrow(
        address seller,
        address buyer,
        uint256 amount,
        uint256 pricePerOST,
        bytes32 referenceHash,
        bytes32 agreementHash
    ) external returns (uint256);

    function getAdminAcceptTransferAndLockEscrowActionHash(uint256 id, bytes32 agreementHash) external view returns (bytes32);
    function adminAcceptTransferAndLockEscrow(uint256 id, bytes32 agreementHash) external;

    function adminRejectTransfer(uint256 id, bytes32 reasonHash) external;
    function adminRegisterBuyerPaymentProof(uint256 id, bytes32 paymentProofHash) external;
    function adminValidateSellerPaymentReceipt(uint256 id, bytes32 sellerReceiptHash) external;
    function getAdminMarkTransferDisputedActionHash(uint256 id, bytes32 disputeHash) external view returns (bytes32);
    function adminMarkTransferDisputed(uint256 id, bytes32 disputeHash) external;

    function counterTransfer(uint256 id, uint256 newAmount, uint256 newPricePerOST, bytes32 counterOfferHash) external;
    function acceptTransfer(uint256 id, bytes32 agreementHash) external;
    function rejectTransfer(uint256 id, bytes32 reasonHash) external;
    function cancelTransfer(uint256 id) external;

    function registerBuyerPaymentProof(uint256 id, bytes32 paymentProofHash) external;
    function sellerValidatePaymentReceipt(uint256 id, bytes32 sellerReceiptHash) external;
    function markTransferDisputed(uint256 id, bytes32 disputeHash) external;
    function reclaimExpiredEscrow(uint256 id) external;

    function adminConfirmOSTTransaction(uint256 id, bytes32 receiptHash) external;

    function getAdminResolveTransferActionHash(
        uint256 id,
        bool releaseToBuyer,
        bytes32 resolutionHash,
        bytes32 receiptHash
    ) external view returns (bytes32);

    function adminResolveTransfer(uint256 id, bool releaseToBuyer, bytes32 resolutionHash, bytes32 receiptHash) external;
    function adminRecordTransferReceiptHash(uint256 id, bytes32 receiptHash) external;


    function transfersf(uint256 id) external view returns (OSTTransfer memory);
    function nextTransferIdf() external view returns (uint256);
    function escrowAddress() external view returns (address);
}
