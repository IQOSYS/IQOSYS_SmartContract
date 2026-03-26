// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./IOrderBookModule.sol";
import "./IAccessControl.sol";
import "./ITokenManager.sol";
import "@openzeppelin/contracts/metatx/ERC2771Context.sol";

contract OrderBookModule is IOrderBookModule, ERC2771Context {
    IAccessControl public accessControl;
    ITokenManager public tokenManager;

    uint256 private nextSellOrderId;
    uint256 private nextBuyOrderId;

    mapping(uint256 => SellOrder) public sellOrders;
    mapping(uint256 => BuyOrder) public buyOrders;

    // Événements simplifiés
    event SellOrderCreated(uint256 indexed id, address indexed seller, uint256 amount, uint256 price, bool isIQS, uint256 timestamp);
    event SellOrderCanceled(uint256 indexed id, address indexed seller);

    event BuyOrderCreated(uint256 indexed id, address indexed buyer, uint256 amount, uint256 price, bool isIQS, uint256 timestamp);
    event BuyOrderCanceled(uint256 indexed id, address indexed buyer);

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
        address forwarder
    ) ERC2771Context(forwarder) {
        accessControl = IAccessControl(_accessControl);
        tokenManager = ITokenManager(_tokenManager);
    }

    // --- SELL ORDERS ---

    function proposeSellOrder(uint256 amount, uint256 price, bool isIQS) external override onlyValidSender {
        address sender = _msgSender();

        require(amount > 0, "Amount must be > 0");
        require(price  > 0, "Price must be > 0");

        // 🔒 SÉQUESTRE (Escrow) : Maintenu pour la sécurité
        if (isIQS) {
            require(tokenManager.balanceOfIQS(sender) >= amount, "Insufficient IQS balance");
            tokenManager.transferIQSfromAtoB(sender, accessControl.owner(), amount); 
        } else {
            require(tokenManager.balanceOfOST(sender) >= amount, "Insufficient OST balance");
            tokenManager.transferOSTfromAtoB(sender, accessControl.owner(), amount);
        }

        uint256 id = nextSellOrderId++;
        
        // Entrée directe dans le carnet public
        sellOrders[id] = SellOrder({
            id:        id,
            seller:    sender, 
            amount:    amount,
            price:     price,
            isIQS:     isIQS,
            timestamp: block.timestamp
        });

        emit SellOrderCreated(id, sender, amount, price, isIQS, block.timestamp);
    }

    function cancelSellOrder(uint256 id) external override onlyValidSender {
        address sender = _msgSender(); 
        SellOrder storage o = sellOrders[id];
        require(o.seller == sender, "Not your order");

        // Remboursement du séquestre
        if (o.isIQS) {
            require(tokenManager.balanceOfIQS(accessControl.owner()) >= o.amount, "Escrow IQS insufficient");
            tokenManager.transferIQSfromAtoB(accessControl.owner(), sender, o.amount);
        } else {
            require(tokenManager.balanceOfOST(accessControl.owner()) >= o.amount, "Escrow OST insufficient");
            tokenManager.transferOSTfromAtoB(accessControl.owner(), sender, o.amount);
        }

        emit SellOrderCanceled(id, sender);
        delete sellOrders[id];
    }

    function adminCancelSellOrder(uint256 id) external override onlyAdmin {
        SellOrder storage o = sellOrders[id];
        require(o.seller != address(0), "No such order");

        // Remboursement du séquestre au vendeur
        if (o.isIQS) {
            require(tokenManager.balanceOfIQS(accessControl.owner()) >= o.amount, "Escrow IQS insufficient");
            tokenManager.transferIQSfromAtoB(accessControl.owner(), o.seller, o.amount);
        } else {
            require(tokenManager.balanceOfOST(accessControl.owner()) >= o.amount, "Escrow OST insufficient");
            tokenManager.transferOSTfromAtoB(accessControl.owner(), o.seller, o.amount);
        }

        emit SellOrderCanceled(id, o.seller);
        delete sellOrders[id];
    }

    function deleteSellOrder(uint256 id) external override {
        delete sellOrders[id];
    }

    // --- BUY ORDERS ---

    function proposeBuyOrder(uint256 amount, uint256 price, bool isIQS) external override onlyValidSender {
        address sender = _msgSender();

        require(amount > 0, "Amount must be > 0");
        require(price  > 0, "Price must be > 0");

        uint256 id = nextBuyOrderId++;
        
        // Entrée directe dans le carnet public
        buyOrders[id] = BuyOrder({
            id:        id,
            buyer:     sender,
            amount:    amount,
            price:     price,
            isIQS:     isIQS,
            timestamp: block.timestamp
        });

        emit BuyOrderCreated(id, sender, amount, price, isIQS, block.timestamp);
    }

    function cancelBuyOrder(uint256 id) external override onlyValidSender {
        address sender = _msgSender();
        BuyOrder storage o = buyOrders[id];
        require(o.buyer == sender, "Not your order");
        
        emit BuyOrderCanceled(id, sender);
        delete buyOrders[id];
    }

    function adminCancelBuyOrder(uint256 id) external override onlyAdmin {
        BuyOrder storage o = buyOrders[id];
        require(o.buyer != address(0), "No such order");
        
        emit BuyOrderCanceled(id, o.buyer);
        delete buyOrders[id];
    }

    function deleteBuyOrder(uint256 id) external override {
        delete buyOrders[id];
    }

    // --- GETTERS ---

    function sellOrdersf(uint256 id) external view override returns (SellOrder memory) { return sellOrders[id]; }
    function nextSellOrderIdf() external view override returns (uint256) { return nextSellOrderId; }

    function buyOrdersf(uint256 id) external view override returns (BuyOrder memory) { return buyOrders[id]; }
    function nextBuyOrderIdf() external view override returns (uint256) { return nextBuyOrderId; }

    // --- ERC2771 OVERRIDES ---
    function _msgSender() internal view override(ERC2771Context) returns (address) { return ERC2771Context._msgSender(); }
    function _msgData() internal view override(ERC2771Context) returns (bytes calldata) { return ERC2771Context._msgData(); }
    function _contextSuffixLength() internal view override(ERC2771Context) returns (uint256) { return ERC2771Context._contextSuffixLength(); }
}