// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title Interface for Token Manager Module
/// @notice AMF production model: IQS are non-transferable BSA rights, OST are ordinary shares moved only by controlled modules.
interface ITokenManager {
    // -------------------------------------------------------------------------
    // IQS Token / BSA rights
    // -------------------------------------------------------------------------

    function nameIQS() external pure returns (string memory);
    function symbolIQS() external pure returns (string memory);
    function decimalsIQS() external pure returns (uint8);

    /// @notice Kept for legacy compatibility. IQS issuance is unlimited in the AMF model.
    function maxSupplyIQS() external pure returns (uint256);

    function totalSupplyIQS() external view returns (uint256);
    function totalIQSInEscrow() external view returns (uint256);
    function balanceOfIQS(address account) external view returns (uint256);
    function iqsInEscrowOf(address account) external view returns (uint256);

    /// @notice Legacy function kept only for ABI compatibility. Must revert in AMF model.
    function transferIQSfromAtoB(
        address from,
        address to,
        uint256 amount
    ) external;

    /// @notice Legacy treasury mint kept only for ABI compatibility. Must revert in AMF model.
    function mintIQS(
        uint256 amount
    ) external;

    /// @notice Credits IQS/BSA rights directly to a whitelisted holder.
    function mintIQSTo(
        address account,
        uint256 amount,
        bytes32 referenceHash
    ) external;

    /// @notice Burns IQS when IQS are exercised into OST.
    function burnIQS(
        uint256 amount,
        address account
    ) external;

    // -------------------------------------------------------------------------
    // OST Token / ordinary shares
    // -------------------------------------------------------------------------

    function nameOST() external pure returns (string memory);
    function symbolOST() external pure returns (string memory);

    /// @notice Kept for legacy compatibility. AMF model starts with no automatic treasury OST mint.
    function initialSupplyOST() external pure returns (uint256);

    function totalSupplyOSTf() external view returns (uint256);

    /// @notice Kept for legacy compatibility. OST issuance is unlimited in the AMF model.
    function maxSupplyOSTf() external pure returns (uint256);

    function balanceOfOST(address account) external view returns (uint256);

    /// @notice Mints OST during finalized IQS exercise or controlled treasury award.
    function mintOSTTo(
        address account,
        uint256 amount,
        bytes32 referenceHash
    ) external;

    /// @notice Controlled OST movement, normally called only by OSTTransferModule.
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
    // Wallet migration controller
    // -------------------------------------------------------------------------

    function walletMigrationController()
        external
        view
        returns (address);

    function setWalletMigrationController(
        address walletMigrationController
    ) external;

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
    function tokenOperatorController()
    external
    view
    returns (address);

    function setTokenOperatorController(
        address tokenOperatorController
    ) external;
}