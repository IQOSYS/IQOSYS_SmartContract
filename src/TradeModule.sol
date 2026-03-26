// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./ITradeModule.sol";
import "./IAccessControl.sol";
import "./ITokenManager.sol";
import "./IOrderBookModule.sol";
import "@openzeppelin/contracts/metatx/ERC2771Context.sol"; 

/// @title Trade Module
/// @notice Executes and validates trades by matching orders from the order book
contract TradeModule is ITradeModule, ERC2771Context {
    IAccessControl public accessControl;
    ITokenManager public tokenManager;
    IOrderBookModule public orderBook;

    uint256 private nextExecutedTradeId;
    uint256 private nextValidateExecutedTradeId;
    
    mapping(uint256 => ExecutedTrade) public executedTrades;
    mapping(uint256 => ValidateExecutedTrade) public validateexecutedTrades;

    event TradeExecuted(
        uint256 indexed id, uint256 indexed sellOrderId, uint256 indexed buyOrderId,
        address seller, address buyer, uint256 amount, uint256 price, bool isIQS, uint256 timestamp
    );
    event ExecutedTradeValidated(
        uint256 indexed id, uint256 indexed sellOrderId, uint256 indexed buyOrderId,
        address seller, address buyer, uint256 amount, uint256 price, bool isIQS, uint256 timestamp
    );
    event ExecutedTradeRejected(
        uint256 indexed id, uint256 indexed sellOrderId, uint256 indexed buyOrderId,
        address seller, address buyer, bool isIQS, uint256 timestamp
    );

    // --- MODIFIERS ---
    modifier onlyValidSender() {
        address sender = _msgSender();
        require(accessControl.isWhiteListed(sender), "Sender not whitelisted");
        require(accessControl.isAuthorized(sender), "Sender not authorized");
        require(!accessControl.isFrozen(sender), "Sender is frozen");
        _;
    }

    modifier onlyAdmin() {
        require(accessControl.isAdmin(_msgSender()), "Caller is not an admin");
        _;
    }

    constructor(
        address _accessControl, 
        address _tokenManager, 
        address _orderBook, 
        address forwarder
    ) ERC2771Context(forwarder) {
        accessControl = IAccessControl(_accessControl);
        tokenManager = ITokenManager(_tokenManager);
        orderBook = IOrderBookModule(_orderBook);
    }

    // --- EXECUTION DES ORDRES (Standard / On-chain) ---

    /// @inheritdoc ITradeModule
    function OrderSellFill(uint256 sellOrderId) external override onlyValidSender {
        address sender = _msgSender(); 
        _executeSellFill(sellOrderId, sender);
    }

    /// @inheritdoc ITradeModule
    function OrderBuyFill(uint256 buyOrderId) external override onlyValidSender {
        address sender = _msgSender(); 
        _executeBuyFill(buyOrderId, sender);
    }

    // --- EXECUTION DES ORDRES (Administrative / Flux FIAT) ---

    /**
     * @notice Permet à l'Admin d'exécuter un ordre de vente au nom d'un acheteur spécifique (Post-FIAT)
     * @param sellOrderId L'ID de l'ordre de vente
     * @param intendedBuyer L'adresse de l'utilisateur qui a payé en FIAT
     */
    function adminOrderSellFill(uint256 sellOrderId, address intendedBuyer) external onlyAdmin {
        _executeSellFill(sellOrderId, intendedBuyer);
    }

    /**
     * @notice Permet à l'Admin d'exécuter un ordre d'achat au nom d'un vendeur spécifique
     * @param buyOrderId L'ID de l'ordre d'achat
     * @param intendedSeller L'adresse de l'utilisateur qui vend
     */
    function adminOrderBuyFill(uint256 buyOrderId, address intendedSeller) external onlyAdmin {
        _executeBuyFill(buyOrderId, intendedSeller);
    }

    
    function adminExecuteTradeMatch(uint256 sellOrderId, address intendedBuyer, uint256 buyOrderId, address intendedSeller) external onlyAdmin {
        _executeSellFill(sellOrderId, intendedBuyer);
        _executeBuyFill(buyOrderId, intendedSeller);
    }

    // --- LOGIQUE INTERNE MUTUALISÉE ---

    function _executeSellFill(uint256 sellOrderId, address buyer) internal {
        IOrderBookModule.SellOrder memory o = orderBook.sellOrdersf(sellOrderId);
        require(o.seller != address(0), "No such sell order");
        require(o.seller != buyer, "Cannot buy your own order");

        executedTrades[nextExecutedTradeId] = ExecutedTrade({
            id:            nextExecutedTradeId,
            sellOrderId:   sellOrderId,
            buyOrderId:    0,
            seller:        o.seller,
            buyer:         buyer, // L'acheteur est bien l'utilisateur, pas l'admin
            amount:        o.amount,
            price:         o.price,
            isIQS:         o.isIQS,
            timestamp:     block.timestamp
        });

        emit TradeExecuted(nextExecutedTradeId, sellOrderId, 0, o.seller, buyer, o.amount, o.price, o.isIQS, block.timestamp);
        nextExecutedTradeId++;
        orderBook.deleteSellOrder(sellOrderId);
    }

    function _executeBuyFill(uint256 buyOrderId, address seller) internal {
        IOrderBookModule.BuyOrder memory o = orderBook.buyOrdersf(buyOrderId);
        require(o.buyer != address(0), "No such buy order");
        require(o.buyer != seller, "Cannot sell your own order");

        if (o.isIQS) {
            tokenManager.transferIQSfromAtoB(seller, accessControl.owner(), o.amount); 
        } else {
            tokenManager.transferOSTfromAtoB(seller, accessControl.owner(), o.amount);
        }

        executedTrades[nextExecutedTradeId] = ExecutedTrade({
            id:            nextExecutedTradeId,
            sellOrderId:   0,
            buyOrderId:    buyOrderId,
            seller:        seller, // Le vendeur est bien l'utilisateur, pas l'admin
            buyer:         o.buyer,
            amount:        o.amount,
            price:         o.price,
            isIQS:         o.isIQS,
            timestamp:     block.timestamp
        });

        emit TradeExecuted(nextExecutedTradeId, 0, buyOrderId, seller, o.buyer, o.amount, o.price, o.isIQS, block.timestamp);
        nextExecutedTradeId++;
        orderBook.deleteBuyOrder(buyOrderId);
    }

    // --- VALIDATION & REJET (Par l'Admin) ---

    /// @inheritdoc ITradeModule
    function validateExecutedTrade(uint256 executedTradeId) external override onlyAdmin {
        ExecutedTrade storage et = executedTrades[executedTradeId];
        require(et.seller != address(0), "No such executed trade");

        if (et.isIQS) {
            require(tokenManager.balanceOfIQS(accessControl.owner()) >= et.amount, "Insufficient IQS balance in owner address");
            tokenManager.transferIQSfromAtoB(accessControl.owner(), et.buyer, et.amount);
            tokenManager._addIQSHolder(et.buyer);
        } else {
            require(tokenManager.balanceOfOST(accessControl.owner()) >= et.amount, "Insufficient OST balance in owner address");
            tokenManager.transferOSTfromAtoB(accessControl.owner(), et.buyer, et.amount);
            tokenManager._addOSTHolder(et.buyer);
        }

        validateexecutedTrades[nextValidateExecutedTradeId] = ValidateExecutedTrade({
            id:            nextValidateExecutedTradeId,
            sellOrderId:   et.sellOrderId,
            buyOrderId:    et.buyOrderId,
            seller:        et.seller,
            buyer:         et.buyer,
            amount:        et.amount,
            price:         et.price,
            isIQS:         et.isIQS,
            timestamp:     et.timestamp
        });

        emit ExecutedTradeValidated(nextValidateExecutedTradeId, et.sellOrderId, et.buyOrderId, et.seller, et.buyer, et.amount, et.price, et.isIQS, et.timestamp);
        nextValidateExecutedTradeId++;
        delete executedTrades[executedTradeId];
    }

    /// @inheritdoc ITradeModule
    function rejectExecutedTrade(uint256 executedTradeId) external override onlyAdmin {
        ExecutedTrade storage et = executedTrades[executedTradeId];
        require(et.seller != address(0), "No such executed trade");

        if (et.isIQS) {
            require(tokenManager.balanceOfIQS(accessControl.owner()) >= et.amount, "Insufficient IQS balance in owner address");
            tokenManager.transferIQSfromAtoB(accessControl.owner(), et.seller, et.amount);
        } else {
            require(tokenManager.balanceOfOST(accessControl.owner()) >= et.amount, "Insufficient OST balance in owner address");
            tokenManager.transferOSTfromAtoB(accessControl.owner(), et.seller, et.amount);
        }

        emit ExecutedTradeRejected(executedTradeId, et.sellOrderId, et.buyOrderId, et.seller, et.buyer, et.isIQS, et.timestamp);
        delete executedTrades[executedTradeId];
    }

    // --- GETTERS ---

    function executedTradesf(uint256 id) external view override returns (ExecutedTrade memory) { return executedTrades[id]; }

    function validateexecutedTradesf(uint256 id) external view override returns (ExecutedTrade memory) {
        ValidateExecutedTrade storage vTrade = validateexecutedTrades[id];
        return ExecutedTrade({
            id: vTrade.id, sellOrderId: vTrade.sellOrderId, buyOrderId: vTrade.buyOrderId,
            seller: vTrade.seller, buyer: vTrade.buyer, amount: vTrade.amount, price: vTrade.price,
            isIQS: vTrade.isIQS, timestamp: vTrade.timestamp
        });
    }

    function nextExecutedTradeIdf() external view override returns (uint256) { return nextExecutedTradeId; }
    function nextValidateExecutedTradeIdf() external view returns (uint256) { return nextValidateExecutedTradeId; }


    function getUserValidatedTradesOrderBook(address user) external view returns (uint256[] memory ids, uint256[] memory sellOrderIds, uint256[] memory buyOrderIds, address[] memory sellers, address[] memory buyers, uint256[] memory amounts, uint256[] memory prices, bool[] memory isIQSFlags, uint256[] memory timestamps) {
        uint256 total = nextValidateExecutedTradeId; uint256 count = 0;
        for (uint256 i = 0; i < total; i++) { if (validateexecutedTrades[i].seller == user || validateexecutedTrades[i].buyer == user) count++; }
        ids = new uint256[](count); sellOrderIds = new uint256[](count); buyOrderIds = new uint256[](count); sellers = new address[](count); buyers = new address[](count); amounts = new uint256[](count); prices = new uint256[](count); isIQSFlags = new bool[](count); timestamps = new uint256[](count);
        uint256 idx = 0;
        for (uint256 i = 0; i < total; i++) {
            ValidateExecutedTrade storage t = validateexecutedTrades[i];
            if (t.seller == user || t.buyer == user) {
                ids[idx] = t.id; sellOrderIds[idx] = t.sellOrderId; buyOrderIds[idx] = t.buyOrderId; sellers[idx] = t.seller; buyers[idx] = t.buyer; amounts[idx] = t.amount; prices[idx] = t.price; isIQSFlags[idx] = t.isIQS; timestamps[idx] = t.timestamp; idx++;
            }
        }
    }

    function getUserIQSTradesOrderBook(address user) external view returns (uint256[] memory ids, uint256[] memory sellOrderIds, uint256[] memory buyOrderIds, address[] memory sellers, address[] memory buyers, uint256[] memory amounts, uint256[] memory prices, uint256[] memory timestamps) {
        uint256 total = nextValidateExecutedTradeId; uint256 count = 0;
        for (uint256 i = 0; i < total; i++) { if (validateexecutedTrades[i].isIQS && (validateexecutedTrades[i].seller == user || validateexecutedTrades[i].buyer == user)) count++; }
        ids = new uint256[](count); sellOrderIds = new uint256[](count); buyOrderIds = new uint256[](count); sellers = new address[](count); buyers = new address[](count); amounts = new uint256[](count); prices = new uint256[](count); timestamps = new uint256[](count);
        uint256 idx = 0;
        for (uint256 i = 0; i < total; i++) {
            ValidateExecutedTrade storage t = validateexecutedTrades[i];
            if (t.isIQS && (t.seller == user || t.buyer == user)) {
                ids[idx] = t.id; sellOrderIds[idx] = t.sellOrderId; buyOrderIds[idx] = t.buyOrderId; sellers[idx] = t.seller; buyers[idx] = t.buyer; amounts[idx] = t.amount; prices[idx] = t.price; timestamps[idx] = t.timestamp; idx++;
            }
        }
    }

    function getAllValidatedTrades() external view returns (uint256[] memory ids, uint256[] memory sellOrderIds, uint256[] memory buyOrderIds, address[] memory sellers, address[] memory buyers, uint256[] memory amounts, uint256[] memory prices, bool[] memory isIQSFlags, uint256[] memory timestamps) {
        uint256 total = nextValidateExecutedTradeId;
        ids = new uint256[](total); sellOrderIds = new uint256[](total); buyOrderIds = new uint256[](total); sellers = new address[](total); buyers = new address[](total); amounts = new uint256[](total); prices = new uint256[](total); isIQSFlags = new bool[](total); timestamps = new uint256[](total);
        for (uint256 i = 0; i < total; i++) {
            ValidateExecutedTrade storage t = validateexecutedTrades[i];
            ids[i] = t.id; sellOrderIds[i] = t.sellOrderId; buyOrderIds[i] = t.buyOrderId; sellers[i] = t.seller; buyers[i] = t.buyer; amounts[i] = t.amount; prices[i] = t.price; isIQSFlags[i] = t.isIQS; timestamps[i] = t.timestamp;
        }
    }

    function getTransactionHistoryLengthOrderBook() external view returns (uint256) {
        return nextValidateExecutedTradeId > 0 ? nextValidateExecutedTradeId - 1 : 0; 
    }

    // --- ERC2771 OVERRIDES ---
    function _msgSender() internal view override(ERC2771Context) returns (address) { return ERC2771Context._msgSender(); }
    function _msgData() internal view override(ERC2771Context) returns (bytes calldata) { return ERC2771Context._msgData(); }
    function _contextSuffixLength() internal view override(ERC2771Context) returns (uint256) { return ERC2771Context._contextSuffixLength(); }
}