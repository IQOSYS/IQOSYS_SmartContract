// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title Interface for Token Manager Module
/// @notice Handles IQS and OST token logic, holders, and controlled transfers.
interface ITokenManager {
    // -------------------------------------------------------------------------
    // IQS Token
    // -------------------------------------------------------------------------

    function nameIQS() external pure returns (string memory);
    function symbolIQS() external pure returns (string memory);
    function decimalsIQS() external pure returns (uint8);
    function maxSupplyIQS() external pure returns (uint256);
    function totalSupplyIQS() external view returns (uint256);
    function balanceOfIQS(address account) external view returns (uint256);

    function transferIQSfromAtoB(
        address from,
        address to,
        uint256 amount
    ) external;

    function mintIQS(
        uint256 amount
    ) external;

    function burnIQS(
        uint256 amount,
        address account
    ) external;

    // -------------------------------------------------------------------------
    // OST Token
    // -------------------------------------------------------------------------

    function nameOST() external pure returns (string memory);
    function symbolOST() external pure returns (string memory);
    function initialSupplyOST() external pure returns (uint256);
    function totalSupplyOSTf() external view returns (uint256);
    function maxSupplyOSTf() external pure returns (uint256);
    function balanceOfOST(address account) external view returns (uint256);

    function transferOSTfromAtoB(
        address from,
        address to,
        uint256 amount
    ) external;

    // -------------------------------------------------------------------------
    // Token operators
    // -------------------------------------------------------------------------

    function setTokenOperator(
        address operator,
        bool status
    ) external;

    function isTokenOperator(
        address operator
    ) external view returns (bool);

    // -------------------------------------------------------------------------
    // Pause
    // -------------------------------------------------------------------------

    function pause() external;
    function unpause() external;
    function paused() external view returns (bool);

    // -------------------------------------------------------------------------
    // Holders
    // -------------------------------------------------------------------------

    function getIQSHolders()
        external
        view
        returns (
            address[] memory,
            uint256[] memory
        );

    function getOSTHolders()
        external
        view
        returns (
            address[] memory,
            uint256[] memory
        );
    function adminMigrateWallet(
        address oldWallet,
        address newWallet,
        bytes32 referenceHash
    )
        external
        returns (
            uint256 iqsAmount,
            uint256 ostAmount
        );
}