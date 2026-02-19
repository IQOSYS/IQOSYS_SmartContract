// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title Interface for Order Book Module
/// @notice Handles pending and validated sell & buy orders
interface IOrderBookModule {
    
    // --- STRUCTURES ---
    struct PendingSellOrder {
        uint256 id;
        address seller;
        uint256 amount;
        uint256 price;
        bool isIQS;
        uint256 timestamp;
    }

    struct SellOrder {
        uint256 id;
        address seller;
        uint256 amount;
        uint256 price;
        bool isIQS;
        uint256 timestamp;
    }

    struct PendingBuyOrder {
        uint256 id;
        address buyer;
        uint256 amount;
        uint256 price;
        bool isIQS;
        uint256 timestamp;
    }

    struct BuyOrder {
        uint256 id;
        address buyer;
        uint256 amount;
        uint256 price;
        bool isIQS;
        uint256 timestamp;
    }

    // --- SELL ORDERS ---
    function proposeSellOrder(uint256 amount, uint256 price, bool isIQS) external;
    function validatePendingSellOrder(uint256 id) external;
    function rejectPendingSellOrder(uint256 id) external;
    function cancelPendingSellOrder(uint256 id) external;
    function cancelSellOrder(uint256 id) external;
    function adminCancelSellOrder(uint256 id) external;
    function deleteSellOrder(uint256 id) external;

    // --- BUY ORDERS ---
    function proposeBuyOrder(uint256 amount, uint256 price, bool isIQS) external;
    function validatePendingBuyOrder(uint256 id) external;
    function rejectPendingBuyOrder(uint256 id) external;
    function cancelPendingBuyOrder(uint256 id) external;
    function cancelBuyOrder(uint256 id) external;
    function adminCancelBuyOrder(uint256 id) external;
    function deleteBuyOrder(uint256 id) external;

    // --- GETTERS (Nécessaires pour le TradeModule et le Frontend) ---
    function PendingSellOrdersf(uint256 id) external view returns (PendingSellOrder memory);
    function sellOrdersf(uint256 id) external view returns (SellOrder memory);
    function nextSellIdf() external view returns (uint256);
    function nextSellOrderIdf() external view returns (uint256);

    function PendingBuyOrdersf(uint256 id) external view returns (PendingBuyOrder memory);
    function buyOrdersf(uint256 id) external view returns (BuyOrder memory);
    function nextBuyIdf() external view returns (uint256);
    function nextBuyOrderIdf() external view returns (uint256);
}