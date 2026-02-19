// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IOrderBookModule.sol";
import "./IAccessControl.sol";
import "./ITokenManager.sol";
import "@openzeppelin/contracts/metatx/ERC2771Context.sol";

contract OrderBookModule is IOrderBookModule, ERC2771Context {
    IAccessControl public accessControl;
    ITokenManager public tokenManager;

    uint256 private nextSellId;
    uint256 private nextSellOrderId;
    uint256 private nextBuyId;
    uint256 private nextBuyOrderId;

    mapping(uint256 => PendingSellOrder) public PendingSellOrders;
    mapping(uint256 => SellOrder) public sellOrders;
    mapping(uint256 => PendingBuyOrder) public PendingBuyOrders;
    mapping(uint256 => BuyOrder) public buyOrders;

    event PendingSellOrderCreated(uint256 indexed id, address indexed seller, uint256 amount, uint256 price, bool isIQS, uint256 timestamp);
    event SellOrderValidated(uint256 indexed id, address indexed seller, uint256 amount, uint256 price, bool isIQS, uint256 timestamp);
    event PendingSellOrderRejected(uint256 indexed id, address indexed seller);
    event PendingSellOrderCanceled(uint256 indexed id, address indexed seller);
    event SellOrderCanceled(uint256 indexed id, address indexed seller);

    event PendingBuyOrderCreated(uint256 indexed id, address indexed buyer, uint256 amount, uint256 price, bool isIQS, uint256 timestamp);
    event BuyOrderValidated(uint256 indexed id, address indexed buyer, uint256 amount, uint256 price, bool isIQS, uint256 timestamp);
    event PendingBuyOrderRejected(uint256 indexed id, address indexed buyer);
    event PendingBuyOrderCanceled(uint256 indexed id, address indexed buyer);
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

    // --- Sell Orders ---
    function proposeSellOrder(uint256 amount, uint256 price, bool isIQS) external override onlyValidSender {
        address sender = _msgSender();

        require(amount > 0, "Amount must be > 0");
        require(price  > 0, "Price must be > 0");

        if (isIQS) {
            require(tokenManager.balanceOfIQS(sender) >= amount, "Insufficient IQS balance");
            tokenManager.transferIQSfromAtoB(sender, accessControl.owner(), amount); 
        } else {
            require(tokenManager.balanceOfOST(sender) >= amount, "Insufficient OST balance");
            tokenManager.transferOSTfromAtoB(sender, accessControl.owner(), amount);
        }

        uint256 id = nextSellId++;
        PendingSellOrders[id] = PendingSellOrder({
            id:        id,
            seller:    sender, 
            amount:    amount,
            price:     price,
            isIQS:     isIQS,
            timestamp: block.timestamp
        });

        emit PendingSellOrderCreated(id, sender, amount, price, isIQS, block.timestamp);
    }

    function validatePendingSellOrder(uint256 id) external override onlyAdmin {
        PendingSellOrder storage p = PendingSellOrders[id];
        require(p.seller != address(0), "No such pending order");

        sellOrders[nextSellOrderId] = SellOrder({
            id:        nextSellOrderId,
            seller:    p.seller,
            amount:    p.amount,
            price:     p.price,
            isIQS:     p.isIQS,
            timestamp: p.timestamp
        });
        emit SellOrderValidated(nextSellOrderId, p.seller, p.amount, p.price, p.isIQS, p.timestamp);
        nextSellOrderId++;

        delete PendingSellOrders[id];
    }

    function rejectPendingSellOrder(uint256 id) external override onlyAdmin {
        PendingSellOrder storage p = PendingSellOrders[id];
        require(p.seller != address(0), "No such pending order");

        if (p.isIQS) {
            require(tokenManager.balanceOfIQS(accessControl.owner()) >= p.amount, "Escrow IQS insufficient");
            tokenManager.transferIQSfromAtoB(accessControl.owner(), p.seller, p.amount);
        } else {
            require(tokenManager.balanceOfOST(accessControl.owner()) >= p.amount, "Escrow OST insufficient");
            tokenManager.transferOSTfromAtoB(accessControl.owner(), p.seller, p.amount);
        }

        emit PendingSellOrderRejected(id, p.seller);
        delete PendingSellOrders[id];
    }

    function cancelPendingSellOrder(uint256 id) external override onlyValidSender {
        address sender = _msgSender(); 
        PendingSellOrder storage p = PendingSellOrders[id];
        require(p.seller == sender, "Not your order");

        if (p.isIQS) {
            require(tokenManager.balanceOfIQS(accessControl.owner()) >= p.amount, "Escrow IQS insufficient");
            tokenManager.transferIQSfromAtoB(accessControl.owner(), sender, p.amount);
        } else {
            require(tokenManager.balanceOfOST(accessControl.owner()) >= p.amount, "Escrow OST insufficient");
            tokenManager.transferOSTfromAtoB(accessControl.owner(), sender, p.amount);
        }

        emit PendingSellOrderCanceled(id, sender);
        delete PendingSellOrders[id];
    }

    function cancelSellOrder(uint256 id) external override onlyValidSender {
        address sender = _msgSender(); 
        SellOrder storage o = sellOrders[id];
        require(o.seller == sender, "Not your order");

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

    // --- Buy Orders ---
    function proposeBuyOrder(uint256 amount, uint256 price, bool isIQS) external override onlyValidSender {
        address sender = _msgSender();

        require(amount > 0, "Amount must be > 0");
        require(price  > 0, "Price must be > 0");

        uint256 id = nextBuyId++;
        PendingBuyOrders[id] = PendingBuyOrder({
            id:        id,
            buyer:     sender,
            amount:    amount,
            price:     price,
            isIQS:     isIQS,
            timestamp: block.timestamp
        });

        emit PendingBuyOrderCreated(id, sender, amount, price, isIQS, block.timestamp);
    }

    function validatePendingBuyOrder(uint256 id) external override onlyAdmin {
        PendingBuyOrder storage p = PendingBuyOrders[id];
        require(p.buyer != address(0), "No such pending order");

        buyOrders[nextBuyOrderId] = BuyOrder({
            id:        nextBuyOrderId,
            buyer:     p.buyer,
            amount:    p.amount,
            price:     p.price,
            isIQS:     p.isIQS,
            timestamp: p.timestamp
        });

        emit BuyOrderValidated(nextBuyOrderId, p.buyer, p.amount, p.price, p.isIQS, p.timestamp);
        nextBuyOrderId++;
        delete PendingBuyOrders[id];
    }

    function rejectPendingBuyOrder(uint256 id) external override onlyAdmin {
        PendingBuyOrder storage p = PendingBuyOrders[id];
        require(p.buyer != address(0), "No such pending order");

        emit PendingBuyOrderRejected(id, p.buyer);
        delete PendingBuyOrders[id];
    }

    function cancelPendingBuyOrder(uint256 id) external override onlyValidSender {
        address sender = _msgSender();
        PendingBuyOrder storage p = PendingBuyOrders[id];
        require(p.buyer == sender, "Not your order");

        emit PendingBuyOrderCanceled(id, sender);
        delete PendingBuyOrders[id];
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
    function PendingSellOrdersf(uint256 id) external view override returns (PendingSellOrder memory) { return PendingSellOrders[id]; }
    function sellOrdersf(uint256 id) external view override returns (SellOrder memory) { return sellOrders[id]; }
    function nextSellIdf() external view override returns (uint256) { return nextSellId; }
    function nextSellOrderIdf() external view override returns (uint256) { return nextSellOrderId; }

    function PendingBuyOrdersf(uint256 id) external view override returns (PendingBuyOrder memory) { return PendingBuyOrders[id]; }
    function buyOrdersf(uint256 id) external view override returns (BuyOrder memory) { return buyOrders[id]; }
    function nextBuyIdf() external view override returns (uint256) { return nextBuyId; }
    function nextBuyOrderIdf() external view override returns (uint256) { return nextBuyOrderId; }

    function _msgSender() internal view override(ERC2771Context) returns (address) { return ERC2771Context._msgSender(); }
    function _msgData() internal view override(ERC2771Context) returns (bytes calldata) { return ERC2771Context._msgData(); }
    function _contextSuffixLength() internal view override(ERC2771Context) returns (uint256) { return ERC2771Context._contextSuffixLength(); }
}
