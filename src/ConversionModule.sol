// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

import "./IConversionModule.sol";
import "./IAccessControl.sol";
import "./ITokenManager.sol";

/// @title Conversion Module
/// @notice Admin-mediated IQS to OST conversion with burn-and-release settlement.
contract ConversionModule is
    IConversionModule,
    ReentrancyGuard,
    Pausable
{
    IAccessControl public accessControl;
    ITokenManager public tokenManager;

    uint256 private nextConversionRequestId;

    mapping(uint256 => IQSToOSTConversion) private conversions;

    event IQSToOSTConversionRequested(
        uint256 indexed requestId,
        address indexed user,
        uint256 amount,
        bytes32 indexed referenceHash,
        uint256 timestamp
    );

    event IQSToOSTConversionApproved(
        uint256 indexed requestId,
        address indexed user,
        uint256 amount,
        uint256 timestamp
    );

    event IQSToOSTConversionRejected(
        uint256 indexed requestId,
        address indexed user,
        uint256 timestamp
    );

    event IQSToOSTConversionCancelled(
        uint256 indexed requestId,
        address indexed user,
        uint256 timestamp
    );

    event IQSToOSTConversionReceiptHashRecorded(
        uint256 indexed requestId,
        bytes32 indexed receiptHash,
        uint256 timestamp
    );

    event ConversionModulePaused(
        address indexed admin,
        uint256 timestamp
    );

    event ConversionModuleUnpaused(
        address indexed admin,
        uint256 timestamp
    );

    /// @param _accessControl Address of AccessControl module.
    /// @param _tokenManager Address of TokenManager module.
    constructor(
        address _accessControl,
        address _tokenManager
    ) {
        require(
            _accessControl != address(0),
            "Invalid access control"
        );

        require(
            _tokenManager != address(0),
            "Invalid token manager"
        );

        accessControl =
            IAccessControl(_accessControl);

        tokenManager =
            ITokenManager(_tokenManager);
    }

    modifier onlyAdmin() {
        require(
            accessControl.isAdmin(msg.sender),
            "Caller is not an admin"
        );
        _;
    }

    modifier conversionExists(
        uint256 requestId
    ) {
        require(
            conversions[requestId].requester != address(0),
            "Conversion request not found"
        );
        _;
    }

    // -------------------------------------------------------------------------
    // Pause
    // -------------------------------------------------------------------------

    function pause()
        external
        onlyAdmin
    {
        _pause();

        emit ConversionModulePaused(
            msg.sender,
            block.timestamp
        );
    }

    function unpause()
        external
        onlyAdmin
    {
        _unpause();

        emit ConversionModuleUnpaused(
            msg.sender,
            block.timestamp
        );
    }

    // -------------------------------------------------------------------------
    // Conversion flow
    // -------------------------------------------------------------------------

    /// @notice Admin creates an on-chain conversion request after user 2FA/backend authorization.
    function adminCreateIQSToOSTConversionRequest(
        address requester,
        uint256 amount,
        bytes32 referenceHash
    )
        external
        override
        onlyAdmin
        whenNotPaused
        nonReentrant
        returns (uint256)
    {
        require(
            requester != address(0),
            "Invalid requester"
        );

        require(
            amount > 0,
            "Amount must be greater than zero"
        );

        require(
            referenceHash != bytes32(0),
            "Reference hash required"
        );

        accessControl.onlyValidSender(
            requester
        );

        require(
            tokenManager.balanceOfIQS(requester) >= amount,
            "Insufficient IQS balance"
        );

        uint256 requestId =
            nextConversionRequestId++;

        conversions[requestId] =
            IQSToOSTConversion({
                id: requestId,
                requester: requester,
                amount: amount,
                timestamp: block.timestamp,
                completedAt: 0,
                status: ConversionStatus.Requested,
                referenceHash: referenceHash,
                receiptHash: bytes32(0)
            });

        emit IQSToOSTConversionRequested(
            requestId,
            requester,
            amount,
            referenceHash,
            block.timestamp
        );

        return requestId;
    }

    /// @notice Approves a pending conversion request.
    /// @dev Burns IQS from requester and releases OST from treasury to requester.
    function approveIQSToOSTConversion(
        uint256 requestId
    )
        external
        override
        onlyAdmin
        whenNotPaused
        nonReentrant
        conversionExists(requestId)
    {
        IQSToOSTConversion storage request =
            conversions[requestId];

        require(
            request.status == ConversionStatus.Requested,
            "Invalid status"
        );

        require(
            tokenManager.balanceOfIQS(request.requester) >= request.amount,
            "Insufficient IQS balance"
        );

        address treasury =
            accessControl.owner();

        require(
            tokenManager.balanceOfOST(treasury) >= request.amount,
            "Insufficient OST treasury balance"
        );

        request.status =
            ConversionStatus.Approved;

        request.completedAt =
            block.timestamp;

        tokenManager.burnIQS(
            request.amount,
            request.requester
        );

        tokenManager.transferOSTfromAtoB(
            treasury,
            request.requester,
            request.amount
        );

        emit IQSToOSTConversionApproved(
            requestId,
            request.requester,
            request.amount,
            block.timestamp
        );
    }

    function rejectIQSToOSTConversion(
        uint256 requestId
    )
        external
        override
        onlyAdmin
        whenNotPaused
        conversionExists(requestId)
    {
        IQSToOSTConversion storage request =
            conversions[requestId];

        require(
            request.status == ConversionStatus.Requested,
            "Invalid status"
        );

        request.status =
            ConversionStatus.Rejected;

        request.completedAt =
            block.timestamp;

        emit IQSToOSTConversionRejected(
            requestId,
            request.requester,
            block.timestamp
        );
    }

    function adminCancelIQSToOSTConversion(
        uint256 requestId
    )
        external
        override
        onlyAdmin
        whenNotPaused
        conversionExists(requestId)
    {
        IQSToOSTConversion storage request =
            conversions[requestId];

        require(
            request.status == ConversionStatus.Requested,
            "Invalid status"
        );

        request.status =
            ConversionStatus.Cancelled;

        request.completedAt =
            block.timestamp;

        emit IQSToOSTConversionCancelled(
            requestId,
            request.requester,
            block.timestamp
        );
    }

    function adminRecordIQSToOSTConversionReceiptHash(
        uint256 requestId,
        bytes32 receiptHash
    )
        external
        override
        onlyAdmin
        whenNotPaused
        conversionExists(requestId)
    {
        IQSToOSTConversion storage request =
            conversions[requestId];

        require(
            request.status == ConversionStatus.Approved,
            "Conversion not approved"
        );

        require(
            receiptHash != bytes32(0),
            "Invalid receipt hash"
        );

        require(
            request.receiptHash == bytes32(0),
            "Receipt already recorded"
        );

        request.receiptHash =
            receiptHash;

        emit IQSToOSTConversionReceiptHashRecorded(
            requestId,
            receiptHash,
            block.timestamp
        );
    }

    // -------------------------------------------------------------------------
    // Getters
    // -------------------------------------------------------------------------

    function getIQSToOSTConversion(
        uint256 requestId
    )
        external
        view
        override
        returns (IQSToOSTConversion memory)
    {
        return conversions[requestId];
    }

    function getTransactionHistoryLengthIQStoOST()
        external
        view
        override
        returns (uint256)
    {
        return nextConversionRequestId;
    }
}