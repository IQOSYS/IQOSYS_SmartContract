// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title Interface for Token Manager Module
/// @notice Handles IQS & OST token logic, fees, and conversion rates
interface ITokenManager {
    // --- IQS Token ---
    function nameIQS() external pure returns (string memory);
    function symbolIQS() external pure returns (string memory);
    function decimalsIQS() external pure returns (uint8);
    function maxSupplyIQS() external pure returns (uint256);
    function totalSupplyIQS() external view returns (uint256);
    function balanceOfIQS(address account) external view returns (uint256);
    function transferIQSfromAtoB(address from, address to, uint256 amount) external;
    function transferIQStoIQS(address to, uint256 amount) external;
    function mintIQS(uint256 amount) external;
    function burnIQS(uint256 amount, address acc) external;

    // --- OST Token ---
    function nameOST() external pure returns (string memory);
    function symbolOST() external pure returns (string memory);
    function initialSupplyOST() external pure returns (uint256);
    function totalSupplyOSTf() external view returns (uint256);
    function maxSupplyOSTf() external pure returns (uint256);
    function balanceOfOST(address account) external view returns (uint256);
    function transferOSTfromAtoB(address from, address to, uint256 amount) external;
    function transferOSTtoOST(address to, uint256 amount) external;

    // --- Holders ---
    function _addOSTHolder(address account) external;
    function _addIQSHolder(address account) external;
    function getIQSHolders() external view returns (address[] memory, uint256[] memory);
    function getOSTHolders() external view returns (address[] memory, uint256[] memory);

    // --- Tests ---
    function setBalanceForTesting(address account,uint256 iqosBalance,uint256 ostBalance) external;
    function getBalancesForTesting(address account) external view returns (uint256 iqosBalance, uint256 ostBalance);
    function setTotalSupplyForTesting( uint256 iqosSupply, uint256 ostSupply) external;
}
