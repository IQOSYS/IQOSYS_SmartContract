// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IP2PModule.sol";
import "./IAccessControl.sol";
import "./ITokenManager.sol";
import "@openzeppelin/contracts/metatx/ERC2771Context.sol"; 

/// @title P2P Transactions Module
/// @notice Manages peer-to-peer token transactions with escrow and administrative validation
contract P2PModule is IP2PModule, ERC2771Context {
    IAccessControl public accessControl;
    ITokenManager public tokenManager;

    uint256 private nextValidatedP2PId;
    uint256 public nextP2PId;

    mapping(uint256 => PendingP2PTransaction) public pendingP2PTransactions;
    mapping(uint256 => PendingP2PTransaction) public validatedP2PTransactions;
    mapping(uint256 => P2PConfirmations) public p2pConfirmations;

    struct P2PConfirmations {
        bool fromConfirmed;
        bool toConfirmed;
    }

    event PendingP2PTransactionCreated(
        uint256 indexed id,
        address indexed from,
        address indexed to,
        uint256 amount,
        uint256 price,
        bool isIQS,
        uint256 timestamp
    );
    event PendingP2PTransactionConfirmed(uint256 indexed id, address indexed participant);
    event PendingP2PTransactionCanceled(uint256 indexed id, address indexed canceledBy);
    event PendingP2PTransactionValidated(
        uint256 indexed id,
        address indexed from,
        address indexed to,
        uint256 amount,
        uint256 price,
        bool isIQS,
        uint256 timestamp
    );
    event PendingP2PTransactionRejected(uint256 indexed id, address indexed from);

    /// @param _accessControl Address of AccessControl module
    /// @param _tokenManager Address of TokenManager module
    /// @param forwarder Address of the Trusted Forwarder
    constructor(
        address _accessControl, 
        address _tokenManager, 
        address forwarder
    ) ERC2771Context(forwarder) {
        accessControl = IAccessControl(_accessControl);
        tokenManager = ITokenManager(_tokenManager);
    }

    // --- MODIFIERS ---

    modifier onlyValidSender() {
        address sender = _msgSender();
        require(accessControl.isWhiteListed(sender), "Sender not whitelisted");
        require(accessControl.isAuthorized(sender), "Sender not authorized");
        require(!accessControl.isFrozen(sender), "Sender is frozen");
        _;
    }

    // CHANGEMENT : Utilise désormais isAdmin() au lieu de owner()
    modifier onlyAdmin() {
        require(accessControl.isAdmin(_msgSender()), "Caller is not an admin");
        _;
    }

    // --- CORE FUNCTIONS ---

    /// @inheritdoc IP2PModule
    function proposeP2PTransaction(address to, uint256 amount, uint256 price, bool isIQS) external override onlyValidSender {
        address sender = _msgSender();

        require(to != address(0), "Invalid recipient");
        require(amount > 0 && price > 0, "Amount and price > 0");

        if (isIQS) {
            tokenManager.transferIQSfromAtoB(sender, accessControl.owner(), amount);
        } else {
            tokenManager.transferOSTfromAtoB(sender, accessControl.owner(), amount);
        }

        uint256 id = nextP2PId++;
        pendingP2PTransactions[id] = PendingP2PTransaction({
            id:        id,
            from:      sender,
            to:        to,
            amount:    amount,
            price:     price,
            isIQS:     isIQS,
            timestamp: block.timestamp
        });

        emit PendingP2PTransactionCreated(id, sender, to, amount, price, isIQS, block.timestamp);
    }

    /// @inheritdoc IP2PModule
    function confirmP2PTransaction(uint256 id) external override onlyValidSender {
        address sender = _msgSender(); 

        PendingP2PTransaction storage txp = pendingP2PTransactions[id];
        require(txp.from != address(0), "No such P2P transaction");
        P2PConfirmations storage c = p2pConfirmations[id];

        if (sender == txp.from) {
            require(!c.fromConfirmed, "Already confirmed by sender");
            c.fromConfirmed = true;
        } else if (sender == txp.to) {
            require(!c.toConfirmed, "Already confirmed by recipient");
            c.toConfirmed = true;
        } else {
            revert("Not a participant");
        }

        emit PendingP2PTransactionConfirmed(id, sender);
    }

    /// @inheritdoc IP2PModule
    function cancelP2PTransaction(uint256 id) external override onlyValidSender {
        address sender = _msgSender(); 

        PendingP2PTransaction storage txp = pendingP2PTransactions[id];
        require(txp.from != address(0), "No such P2P transaction");
        require(sender == txp.from || sender == txp.to, "Not a participant");

        if (txp.isIQS) {
            tokenManager.transferIQSfromAtoB(accessControl.owner(), txp.from, txp.amount);
        } else {
            tokenManager.transferOSTfromAtoB(accessControl.owner(), txp.from, txp.amount);
        }

        emit PendingP2PTransactionCanceled(id, sender);
        delete pendingP2PTransactions[id];
    }

    /// @inheritdoc IP2PModule
    /// @dev Validation standard (les deux parties doivent avoir confirmé)
    function validateP2PTransaction(uint256 id) external override {
        PendingP2PTransaction storage txp = pendingP2PTransactions[id];
        require(txp.from != address(0), "No such P2P transaction");

        P2PConfirmations storage c = p2pConfirmations[id];
        require(c.fromConfirmed && c.toConfirmed, "Both must confirm first");

        _executeTransferAndCleanup(id, txp);
    }


    /// @dev Helper interne pour le transfert et l'archivage
    function _executeTransferAndCleanup(uint256 id, PendingP2PTransaction storage txp) internal {
        if (txp.isIQS) {
            require(tokenManager.balanceOfIQS(accessControl.owner()) >= txp.amount, "Escrow IQS insufficient");
            tokenManager.transferIQSfromAtoB(accessControl.owner(), txp.to, txp.amount);
            tokenManager._addIQSHolder(txp.to);
        } else {
            require(tokenManager.balanceOfOST(accessControl.owner()) >= txp.amount, "Escrow OST insufficient");
            tokenManager.transferOSTfromAtoB(accessControl.owner(), txp.to, txp.amount);
            tokenManager._addOSTHolder(txp.to);
        }

        // Archive 
        validatedP2PTransactions[nextValidatedP2PId] = PendingP2PTransaction({
            id:        nextValidatedP2PId,
            from:      txp.from,
            to:        txp.to,
            amount:    txp.amount,
            price:     txp.price,
            isIQS:     txp.isIQS,
            timestamp: txp.timestamp
        });
        
        emit PendingP2PTransactionValidated(nextValidatedP2PId, txp.from, txp.to, txp.amount, txp.price, txp.isIQS, txp.timestamp);
        nextValidatedP2PId++;

        // Cleanup
        delete pendingP2PTransactions[id];
        delete p2pConfirmations[id];
    }

    /// @inheritdoc IP2PModule
    function rejectP2PTransaction(uint256 id) external override {
        PendingP2PTransaction storage txp = pendingP2PTransactions[id];
        require(txp.from != address(0), "No such P2P transaction");

        if (txp.isIQS) {
            require(tokenManager.balanceOfIQS(accessControl.owner()) >= txp.amount, "Escrow IQS insufficient");
            tokenManager.transferIQSfromAtoB(accessControl.owner(), txp.from, txp.amount);
        } else {
            require(tokenManager.balanceOfOST(accessControl.owner()) >= txp.amount, "Escrow OST insufficient");
            tokenManager.transferOSTfromAtoB(accessControl.owner(), txp.from, txp.amount);
        }

        emit PendingP2PTransactionRejected(id, txp.from);
        delete pendingP2PTransactions[id];
    }

    // --- VIEW FUNCTIONS ---

    function getValidatedP2PTransactions() external view returns (uint256[] memory ids, address[] memory froms, address[] memory tos, uint256[] memory amounts, uint256[] memory prices, bool[] memory isIQSFlags, uint256[] memory timestamps) {
        uint256 total = nextValidatedP2PId;
        ids = new uint256[](total); froms = new address[](total); tos = new address[](total); amounts = new uint256[](total); prices = new uint256[](total); isIQSFlags = new bool[](total); timestamps = new uint256[](total);
        for (uint256 i = 0; i < total; i++) {
            PendingP2PTransaction storage txp = validatedP2PTransactions[i];
            ids[i] = txp.id; froms[i] = txp.from; tos[i] = txp.to; amounts[i] = txp.amount; prices[i] = txp.price; isIQSFlags[i] = txp.isIQS; timestamps[i] = txp.timestamp;
        }
    }

    function getUserValidatedP2PTransactions(address user) external view returns (uint256[] memory ids, address[] memory froms, address[] memory tos, uint256[] memory amounts, uint256[] memory prices, bool[] memory isIQSFlags, uint256[] memory timestamps) {
        uint256 total = nextValidatedP2PId; uint256 count = 0;
        for (uint256 i = 0; i < total; i++) { if (validatedP2PTransactions[i].from == user || validatedP2PTransactions[i].to == user) count++; }
        ids = new uint256[](count); froms = new address[](count); tos = new address[](count); amounts = new uint256[](count); prices = new uint256[](count); isIQSFlags = new bool[](count); timestamps = new uint256[](count);
        uint256 idx = 0;
        for (uint256 i = 0; i < total; i++) {
            PendingP2PTransaction storage txp = validatedP2PTransactions[i];
            if (txp.from == user || txp.to == user) {
                ids[idx] = txp.id; froms[idx] = txp.from; tos[idx] = txp.to; amounts[idx] = txp.amount; prices[idx] = txp.price; isIQSFlags[idx] = txp.isIQS; timestamps[idx] = txp.timestamp; idx++;
            }
        }
    }

    function getTransactionHistoryLengthP2P() public view returns (uint256) {
        return nextValidatedP2PId > 0 ? nextValidatedP2PId - 1 : 0; 
    }

    // --- ERC2771 OVERRIDES ---

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