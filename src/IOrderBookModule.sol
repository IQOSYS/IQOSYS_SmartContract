// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title Interface for Order Book Module
/// @notice Handles admin-mediated IQS/OST buy and sell orders with staged settlement.
interface IOrderBookModule {
    enum OrderStatus {
        None,
        Placed,
        Accepted,
        SettlementInProgress,
        Completed,
        Cancelled,
        Rejected
    }

    struct SellOrder {
        uint256 id;
        address seller;
        uint256 amount;
        uint256 price;
        bool isIQS;
        uint256 timestamp;
        uint256 completedAt;
        OrderStatus status;
        bytes32 referenceHash;
        bytes32 fiatReferenceHash;
        bytes32 receiptHash;
    }

    struct BuyOrder {
        uint256 id;
        address buyer;
        uint256 amount;
        uint256 price;
        bool isIQS;
        uint256 timestamp;
        uint256 completedAt;
        OrderStatus status;
        bytes32 referenceHash;
        bytes32 fiatReferenceHash;
        bytes32 receiptHash;
    }

    function adminCreateSellOrder(
        address seller,
        uint256 amount,
        uint256 price,
        bool isIQS,
        bytes32 referenceHash
    ) external returns (uint256);

    function adminAcceptSellOrder(
        uint256 id
    ) external;

    function adminStartSellSettlement(
        uint256 id
    ) external;

    function adminCompleteSellOrder(
        uint256 id
    ) external;

    function adminCompleteSellOrder(
        uint256 id,
        bytes32 fiatReferenceHash
    ) external;

    function adminCancelSellOrder(
        uint256 id
    ) external;

    function adminRejectSellOrder(
        uint256 id
    ) external;

    function adminRecordSellReceiptHash(
        uint256 id,
        bytes32 receiptHash
    ) external;

    function adminCreateBuyOrder(
        address buyer,
        uint256 amount,
        uint256 price,
        bool isIQS,
        bytes32 referenceHash
    ) external returns (uint256);

    function adminAcceptBuyOrder(
        uint256 id
    ) external;

    function adminStartBuySettlement(
        uint256 id
    ) external;

    function adminCompleteBuyOrder(
        uint256 id
    ) external;

    function adminCompleteBuyOrder(
        uint256 id,
        bytes32 fiatReferenceHash
    ) external;

    function adminCancelBuyOrder(
        uint256 id
    ) external;

    function adminRejectBuyOrder(
        uint256 id
    ) external;

    function adminRecordBuyReceiptHash(
        uint256 id,
        bytes32 receiptHash
    ) external;

    function sellOrdersf(
        uint256 id
    ) external view returns (SellOrder memory);

    function buyOrdersf(
        uint256 id
    ) external view returns (BuyOrder memory);

    function nextSellOrderIdf()
        external
        view
        returns (uint256);

    function nextBuyOrderIdf()
        external
        view
        returns (uint256);

    function escrowAddress()
        external
        view
        returns (address);
}