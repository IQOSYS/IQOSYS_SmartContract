// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title Interface for P2P Transactions Module
/// @notice Handles proposing, confirming, canceling, validating P2P transactions
interface IP2PModule {
    struct PendingP2PTransaction {
        uint256 id;
        address from;
        address to;
        uint256 amount;
        uint256 price;
        bool isIQS;
        uint256 timestamp;
    }

    /// @notice Proposes a P2P transaction, escrow tokens
    function proposeP2PTransaction(address to, uint256 amount, uint256 price, bool isIQS) external;

    /// @notice Confirms participation in a P2P transaction
    function confirmP2PTransaction(uint256 id) external;

    /// @notice Cancels a pending P2P transaction
    function cancelP2PTransaction(uint256 id) external;

    /// @notice Validates a fully confirmed P2P transaction (requires both parties confirmed)
    function validateP2PTransaction(uint256 id) external;

    // --- AJOUT POUR LE FLUX FIAT ---
    /// @notice Rejects a P2P transaction (owner only)
    function rejectP2PTransaction(uint256 id) external;

    /// @notice Returns the length of the validated P2P history
    function getTransactionHistoryLengthP2P() external view returns (uint256);

    /// @notice Returns all validated P2P transactions
    function getValidatedP2PTransactions()
        external
        view
        returns (
            uint256[] memory ids,
            address[] memory froms,
            address[] memory tos,
            uint256[] memory amounts,
            uint256[] memory prices,
            bool[]    memory isIQSFlags,
            uint256[] memory timestamps
        );

    /// @notice Returns validated P2P transactions for a specific user
    function getUserValidatedP2PTransactions(address user)
        external
        view
        returns (
            uint256[] memory ids,
            address[] memory froms,
            address[] memory tos,
            uint256[] memory amounts,
            uint256[] memory prices,
            bool[]    memory isIQSFlags,
            uint256[] memory timestamps
        );
}