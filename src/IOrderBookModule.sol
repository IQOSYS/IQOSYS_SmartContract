// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title Interface for Order Book Module
/// @notice Handles active sell & buy orders directly in the order book
interface IOrderBookModule {
    
    // --- STRUCTURES ---

    struct SellOrder {
        uint256 id;
        address seller;
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
    function cancelSellOrder(uint256 id) external;
    function adminCancelSellOrder(uint256 id) external;
    function deleteSellOrder(uint256 id) external;

    // --- BUY ORDERS ---
    function proposeBuyOrder(uint256 amount, uint256 price, bool isIQS) external;
    function cancelBuyOrder(uint256 id) external;
    function adminCancelBuyOrder(uint256 id) external;
    function deleteBuyOrder(uint256 id) external;

    // --- GETTERS (Nécessaires pour le TradeModule et le Frontend) ---
    function sellOrdersf(uint256 id) external view returns (SellOrder memory);
    function nextSellOrderIdf() external view returns (uint256);

    function buyOrdersf(uint256 id) external view returns (BuyOrder memory);
    function nextBuyOrderIdf() external view returns (uint256);
}