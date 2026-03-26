// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./IConversionModule.sol";
import "./IAccessControl.sol";
import "./ITokenManager.sol";
import "@openzeppelin/contracts/metatx/ERC2771Context.sol";

/// @title Conversion Module
/// @notice Manages conversion requests from IQS to OST, approvals, rejections, and history
contract ConversionModule is IConversionModule, ERC2771Context {
    IAccessControl public accessControl;
    ITokenManager public tokenManager;

    mapping(uint256 => PendingIQSToOSTConversion) public pendingIQSToOSTConversions; 
    uint256 public iqstoostConversionRequestCount = 0;

    mapping(uint256 => PendingIQSToOSTConversion) public historyIQSToOSTConversions; 
    uint256 public historyIQSToOSTConversionCount = 0;

    event IQSToOSTConversionRequested(uint256 indexed requestId, address indexed user, uint256 amount);
    event IQSToOSTConversionApproved(uint256 indexed requestId, address indexed user, uint256 amount);
    event IQSToOSTConversionRejected(uint256 indexed requestId, address indexed user);
    event IQSToOSTConversionCancelled(uint256 indexed requestId, address indexed user);

    

    /// @param _accessControl Address of AccessControl module
    /// @param _tokenManager Address of TokenManager module
    /// @param forwarder Address of the Trusted Forwarder (ERC2771)
    constructor(
        address _accessControl, 
        address _tokenManager, 
        address forwarder
    ) ERC2771Context(forwarder) {
        accessControl = IAccessControl(_accessControl);
        tokenManager = ITokenManager(_tokenManager);
    }

    // CHANGEMENT : Utilise désormais isAdmin() au lieu de owner()
    modifier onlyAdmin() {
        require(accessControl.isAdmin(_msgSender()), "Caller is not an admin");
        _;
    }

    /// @inheritdoc IConversionModule
    function requestIQSToOSTConversion(uint256 amount) external override {
        // CHANGEMENT : on récupère le vrai sender via _msgSender()
        address sender = _msgSender();

        accessControl.onlyValidSender(sender); 
        require(amount > 0, "Amount must be greater than zero");
        require(tokenManager.balanceOfIQS(sender) >= amount, "Insufficient IQS balance");

        uint256 requestId = iqstoostConversionRequestCount++;
        pendingIQSToOSTConversions[requestId] = PendingIQSToOSTConversion({
            requester: sender,
            amount: amount
        });
        emit IQSToOSTConversionRequested(requestId, sender, amount);
    }

    /// @inheritdoc IConversionModule
    function approveIQSToOSTConversion(uint256 requestId) external onlyAdmin override {
        
        PendingIQSToOSTConversion storage request = pendingIQSToOSTConversions[requestId];
        require(request.requester != address(0), "Conversion request not found");
        require(tokenManager.balanceOfIQS(request.requester) >= request.amount, "Insufficient IQS balance at approval");
        require(tokenManager.totalSupplyOSTf() + request.amount <= tokenManager.maxSupplyOSTf(), "Exceeds max OST supply");

        tokenManager.burnIQS(request.amount, request.requester); 
        tokenManager.transferOSTfromAtoB(accessControl.owner(), request.requester, request.amount);
        tokenManager._addIQSHolder(request.requester);
        tokenManager._addOSTHolder(request.requester);

        uint256 histId = historyIQSToOSTConversionCount++;
        historyIQSToOSTConversions[histId] = PendingIQSToOSTConversion({
            requester: request.requester,
            amount:    request.amount
        });

        delete pendingIQSToOSTConversions[requestId];
        emit IQSToOSTConversionApproved(requestId, request.requester, request.amount);  
    }

    /// @inheritdoc IConversionModule
    function rejectIQSToOSTConversion(uint256 requestId) external onlyAdmin override {   
        PendingIQSToOSTConversion storage request = pendingIQSToOSTConversions[requestId];
        require(request.requester != address(0), "Conversion request not found");   
        address user = request.requester;
        delete pendingIQSToOSTConversions[requestId]; 
        emit IQSToOSTConversionRejected(requestId, user);
    }

    /// @inheritdoc IConversionModule
    function cancelIQSToOSTConversion(uint256 requestId) external override {
        // CHANGEMENT : _msgSender()
        address sender = _msgSender();

        PendingIQSToOSTConversion storage request = pendingIQSToOSTConversions[requestId];
        require(request.requester != address(0), "Conversion request not found");
        require(request.requester == sender, "Only requester can cancel");
        
        delete pendingIQSToOSTConversions[requestId]; 
        emit IQSToOSTConversionCancelled(requestId, sender);
    }

    // --- VIEW FUNCTIONS (Pas de changement nécessaire sur la logique, sauf overrides) ---

    /// @inheritdoc IConversionModule
    function getIQSToOSTConversionHistory()
        external
        view
        returns (
            address[] memory requesters,
            uint256[] memory amounts
        )
    {
        uint256 total = historyIQSToOSTConversionCount;
        requesters = new address[](total);
        amounts    = new uint256[](total);

        for (uint256 i = 0; i < total; i++) {
            PendingIQSToOSTConversion storage entry = historyIQSToOSTConversions[i];
            requesters[i] = entry.requester;
            amounts[i]    = entry.amount;
        }
    }

    /// @inheritdoc IConversionModule
    function getUserIQSToOSTConversionHistory(address user)
        external
        view
        returns (
            uint256[] memory requestIds,
            uint256[] memory amounts
        )
    {
        uint256 total = historyIQSToOSTConversionCount;
        uint256 count = 0;
        for (uint256 i = 0; i < total; i++) {
            if (historyIQSToOSTConversions[i].requester == user) {
                count++;
            }
        }

        requestIds = new uint256[](count);
        amounts    = new uint256[](count);

        uint256 idx = 0;
        for (uint256 i = 0; i < total; i++) {
            PendingIQSToOSTConversion storage entry = historyIQSToOSTConversions[i];
            if (entry.requester == user) {
                requestIds[idx] = i;
                amounts[idx]    = entry.amount;
                idx++;
            }
        }
    }

    function getTransactionHistoryLengthIQStoOST() public view returns (uint256) {
        return historyIQSToOSTConversionCount; 
    }

    // --- RÉSOLUTION DES CONFLITS D'HÉRITAGE (ERC2771Context) ---

    function _msgSender() internal view override(ERC2771Context) returns (address) {
        return ERC2771Context._msgSender();
    }

    function _msgData() internal view override(ERC2771Context) returns (bytes calldata) {
        return ERC2771Context._msgData();
    }

    function _contextSuffixLength() internal view override(ERC2771Context) returns (uint256) {
        return ERC2771Context._contextSuffixLength();
    }
}