// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title Interface for Trade Module
/// @notice Executes and validates trades between matching buy/sell orders
interface ITradeModule {  
    struct ExecutedTrade {
        uint256 id;
        uint256 sellOrderId;
        uint256 buyOrderId;
        address seller;
        address buyer;
        uint256 amount;
        uint256 price;
        bool isIQS;
        uint256 timestamp;
    }

    struct ValidateExecutedTrade {
        uint256 id;
        uint256 sellOrderId; // id dans validatedSellOrders
        uint256 buyOrderId;  // id dans validatedBuyOrders
        address seller;
        address buyer;
        uint256 amount;
        uint256 price;       // prix unitaire en wei
        bool    isIQS;       // true si trade d'IQS, false si trade d'OST
        uint256 timestamp;
    }

    // --- EXECUTION STANDARD (On-chain) ---
    /// @notice Executes a trade by filling a sell order
    function OrderSellFill(uint256 sellOrderId) external;

    /// @notice Executes a trade by filling a buy order
    function OrderBuyFill(uint256 buyOrderId) external;

    // --- EXECUTION ADMINISTRATIVE (Flux FIAT Web2) ---
    /// @notice Allows Admin to fill a sell order on behalf of a specific buyer
    function adminOrderSellFill(uint256 sellOrderId, address intendedBuyer) external;

    /// @notice Allows Admin to fill a buy order on behalf of a specific seller
    function adminOrderBuyFill(uint256 buyOrderId, address intendedSeller) external;

    // --- VALIDATION / REJET ---
    /// @notice Validates an executed trade (owner/admin only)
    function validateExecutedTrade(uint256 executedTradeId) external;

    /// @notice Rejects an executed trade (owner/admin only)
    function rejectExecutedTrade(uint256 executedTradeId) external;

    // --- GETTERS ---
    /// @notice Returns an executed trade by id
    function executedTradesf(uint256 id) external view returns (ExecutedTrade memory);

    /// @notice Returns a validated executed trade by id
    function validateexecutedTradesf(uint256 id) external view returns (ExecutedTrade memory);

    /// @notice Returns the next executed trade ID
    function nextExecutedTradeIdf() external view returns (uint256);

    /// @notice Returns the next validated trade ID
    function nextValidateExecutedTradeIdf() external view returns (uint256);

    /// @notice Returns the cost of an executed trade
    function calculateTotalCost(uint256 executedTradeId) external view returns (uint256 total);

    /// @notice Returns the history of a user's validated trades
    function getUserValidatedTradesOrderBook(address user) external view returns (
            uint256[] memory ids,
            uint256[] memory sellOrderIds,
            uint256[] memory buyOrderIds,
            address[] memory sellers,
            address[] memory buyers,
            uint256[] memory amounts,
            uint256[] memory prices,
            bool[]    memory isIQSFlags,
            uint256[] memory timestamps
        );

    /// @notice Returns the history of a user's validated IQS trades
    function getUserIQSTradesOrderBook(address user) external view
        returns (
            uint256[] memory ids,
            uint256[] memory sellOrderIds,
            uint256[] memory buyOrderIds,
            address[] memory sellers,
            address[] memory buyers,
            uint256[] memory amounts,
            uint256[] memory prices,
            uint256[] memory timestamps
        );


    /// @notice Returns the history of trades
    function getAllValidatedTrades() external view
        returns (
            uint256[] memory ids,
            uint256[] memory sellOrderIds,
            uint256[] memory buyOrderIds,
            address[] memory sellers,
            address[] memory buyers,
            uint256[] memory amounts,
            uint256[] memory prices,
            bool[]    memory isIQSFlags,
            uint256[] memory timestamps
        );

    /// @notice Returns the length of the transaction history in the order book
    function getTransactionHistoryLengthOrderBook() external view returns (uint256);
}
