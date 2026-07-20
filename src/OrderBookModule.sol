// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

import "./IOrderBookModule.sol";
import "./IAccessControl.sol";
import "./ITokenManager.sol";

/// @title Order Book Module
/// @notice Admin-mediated IQS/OST order book with staged fiat-gated settlement.
contract OrderBookModule is
    IOrderBookModule,
    ReentrancyGuard,
    Pausable
{
    IAccessControl public accessControl;
    ITokenManager public tokenManager;

    address public immutable override escrowAddress;

    uint256 private nextSellOrderId;
    uint256 private nextBuyOrderId;

    mapping(uint256 => SellOrder) private sellOrders;
    mapping(uint256 => BuyOrder) private buyOrders;

    event SellOrderCreated(
        uint256 indexed id,
        address indexed seller,
        uint256 amount,
        uint256 price,
        bool isIQS,
        bytes32 indexed referenceHash,
        uint256 timestamp
    );

    event BuyOrderCreated(
        uint256 indexed id,
        address indexed buyer,
        uint256 amount,
        uint256 price,
        bool isIQS,
        bytes32 indexed referenceHash,
        uint256 timestamp
    );

    event SellOrderStatusChanged(
        uint256 indexed id,
        OrderStatus status,
        uint256 timestamp
    );

    event BuyOrderStatusChanged(
        uint256 indexed id,
        OrderStatus status,
        uint256 timestamp
    );

    event SellOrderCompleted(
        uint256 indexed id,
        address indexed seller,
        uint256 amount,
        bool isIQS,
        bytes32 indexed fiatReferenceHash,
        uint256 timestamp
    );

    event BuyOrderCompleted(
        uint256 indexed id,
        address indexed buyer,
        uint256 amount,
        bool isIQS,
        bytes32 indexed fiatReferenceHash,
        uint256 timestamp
    );

    event SellOrderReceiptHashRecorded(
        uint256 indexed id,
        bytes32 indexed receiptHash,
        uint256 timestamp
    );

    event BuyOrderReceiptHashRecorded(
        uint256 indexed id,
        bytes32 indexed receiptHash,
        uint256 timestamp
    );

    event OrderBookPaused(
        address indexed admin,
        uint256 timestamp
    );

    event OrderBookUnpaused(
        address indexed admin,
        uint256 timestamp
    );

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

        escrowAddress =
            address(this);
    }

    modifier onlyAdmin() {
        require(
            accessControl.isAdmin(msg.sender),
            "Caller is not an admin"
        );
        _;
    }

    modifier sellOrderExists(
        uint256 id
    ) {
        require(
            sellOrders[id].seller != address(0),
            "Sell order not found"
        );
        _;
    }

    modifier buyOrderExists(
        uint256 id
    ) {
        require(
            buyOrders[id].buyer != address(0),
            "Buy order not found"
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

        emit OrderBookPaused(
            msg.sender,
            block.timestamp
        );
    }

    function unpause()
        external
        onlyAdmin
    {
        _unpause();

        emit OrderBookUnpaused(
            msg.sender,
            block.timestamp
        );
    }

    // -------------------------------------------------------------------------
    // Sell orders
    // -------------------------------------------------------------------------

    /// @notice Admin creates an on-chain sell order after user 2FA/backend authorization.
    /// @dev Seller's instrument is moved into module escrow immediately.
    /// @param price Unit price in EUR cents.
    function adminCreateSellOrder(
        address seller,
        uint256 amount,
        uint256 price,
        bool isIQS,
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
            seller != address(0),
            "Invalid seller"
        );

        require(
            amount > 0,
            "Amount must be > 0"
        );

        require(
            price > 0,
            "Price must be > 0"
        );

        require(
            referenceHash != bytes32(0),
            "Reference hash required"
        );
        require(
            accessControl.isWhiteListed(seller),
            "Seller not white-listed"
        );

        if (isIQS) {
            require(
                tokenManager.balanceOfIQS(seller) >= amount,
                "Insufficient IQS balance"
            );

            tokenManager.transferIQSfromAtoB(
                seller,
                escrowAddress,
                amount
            );
        } else {
            require(
                tokenManager.balanceOfOST(seller) >= amount,
                "Insufficient OST balance"
            );

            tokenManager.transferOSTfromAtoB(
                seller,
                escrowAddress,
                amount
            );
        }

        uint256 id =
            nextSellOrderId++;

        sellOrders[id] =
            SellOrder({
                id: id,
                seller: seller,
                amount: amount,
                price: price,
                isIQS: isIQS,
                timestamp: block.timestamp,
                completedAt: 0,
                status: OrderStatus.Placed,
                referenceHash: referenceHash,
                fiatReferenceHash: bytes32(0),
                receiptHash: bytes32(0)
            });

        emit SellOrderCreated(
            id,
            seller,
            amount,
            price,
            isIQS,
            referenceHash,
            block.timestamp
        );

        emit SellOrderStatusChanged(
            id,
            OrderStatus.Placed,
            block.timestamp
        );

        return id;
    }

    function adminAcceptSellOrder(
        uint256 id
    )
        external
        override
        onlyAdmin
        whenNotPaused
        sellOrderExists(id)
    {
        SellOrder storage order =
            sellOrders[id];

        require(
            order.status == OrderStatus.Placed,
            "Invalid status"
        );

        order.status =
            OrderStatus.Accepted;

        emit SellOrderStatusChanged(
            id,
            OrderStatus.Accepted,
            block.timestamp
        );
    }

    function adminStartSellSettlement(
        uint256 id
    )
        external
        override
        onlyAdmin
        whenNotPaused
        sellOrderExists(id)
    {
        SellOrder storage order =
            sellOrders[id];

        require(
            order.status == OrderStatus.Accepted,
            "Invalid status"
        );

        order.status =
            OrderStatus.SettlementInProgress;

        emit SellOrderStatusChanged(
            id,
            OrderStatus.SettlementInProgress,
            block.timestamp
        );
    }

    function adminCompleteSellOrder(
        uint256 id
    )
        external
        override
    {
        _completeSellOrder(
            id,
            bytes32(0)
        );
    }

    function adminCompleteSellOrder(
        uint256 id,
        bytes32 fiatReferenceHash
    )
        external
        override
    {
        _completeSellOrder(
            id,
            fiatReferenceHash
        );
    }

    function adminCancelSellOrder(
        uint256 id
    )
        external
        override
        onlyAdmin
        whenNotPaused
        nonReentrant
        sellOrderExists(id)
    {
        SellOrder storage order =
            sellOrders[id];

        require(
            order.status == OrderStatus.Placed ||
                order.status == OrderStatus.Accepted ||
                order.status == OrderStatus.SettlementInProgress,
            "Cannot cancel"
        );

        order.status =
            OrderStatus.Cancelled;

        _refundSellOrder(
            order
        );

        emit SellOrderStatusChanged(
            id,
            OrderStatus.Cancelled,
            block.timestamp
        );
    }

    function adminRejectSellOrder(
        uint256 id
    )
        external
        override
        onlyAdmin
        whenNotPaused
        nonReentrant
        sellOrderExists(id)
    {
        SellOrder storage order =
            sellOrders[id];

        require(
            order.status == OrderStatus.Placed ||
                order.status == OrderStatus.Accepted ||
                order.status == OrderStatus.SettlementInProgress,
            "Cannot reject"
        );

        order.status =
            OrderStatus.Rejected;

        _refundSellOrder(
            order
        );

        emit SellOrderStatusChanged(
            id,
            OrderStatus.Rejected,
            block.timestamp
        );
    }

    function adminRecordSellReceiptHash(
        uint256 id,
        bytes32 receiptHash
    )
        external
        override
        onlyAdmin
        whenNotPaused
        sellOrderExists(id)
    {
        SellOrder storage order =
            sellOrders[id];

        require(
            order.status == OrderStatus.Completed,
            "Order not completed"
        );

        require(
            receiptHash != bytes32(0),
            "Invalid receipt hash"
        );

        require(
            order.receiptHash == bytes32(0),
            "Receipt already recorded"
        );

        order.receiptHash =
            receiptHash;

        emit SellOrderReceiptHashRecorded(
            id,
            receiptHash,
            block.timestamp
        );
    }

    // -------------------------------------------------------------------------
    // Buy orders
    // -------------------------------------------------------------------------

    /// @notice Admin creates an on-chain buy order after user 2FA/backend authorization.
    /// @dev Treasury instrument is moved into module escrow immediately.
    /// @param price Unit price in EUR cents.
    function adminCreateBuyOrder(
        address buyer,
        uint256 amount,
        uint256 price,
        bool isIQS,
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
            buyer != address(0),
            "Invalid buyer"
        );

        require(
            amount > 0,
            "Amount must be > 0"
        );

        require(
            price > 0,
            "Price must be > 0"
        );

        require(
            referenceHash != bytes32(0),
            "Reference hash required"
        );

        require(
            accessControl.isWhiteListed(buyer),
            "Buyer not white-listed"
        );

        address treasury =
            accessControl.owner();

        if (isIQS) {
            require(
                tokenManager.balanceOfIQS(treasury) >= amount,
                "Treasury IQS insufficient"
            );

            tokenManager.transferIQSfromAtoB(
                treasury,
                escrowAddress,
                amount
            );
        } else {
            require(
                tokenManager.balanceOfOST(treasury) >= amount,
                "Treasury OST insufficient"
            );

            tokenManager.transferOSTfromAtoB(
                treasury,
                escrowAddress,
                amount
            );
        }

        uint256 id =
            nextBuyOrderId++;

        buyOrders[id] =
            BuyOrder({
                id: id,
                buyer: buyer,
                amount: amount,
                price: price,
                isIQS: isIQS,
                timestamp: block.timestamp,
                completedAt: 0,
                status: OrderStatus.Placed,
                referenceHash: referenceHash,
                fiatReferenceHash: bytes32(0),
                receiptHash: bytes32(0)
            });

        emit BuyOrderCreated(
            id,
            buyer,
            amount,
            price,
            isIQS,
            referenceHash,
            block.timestamp
        );

        emit BuyOrderStatusChanged(
            id,
            OrderStatus.Placed,
            block.timestamp
        );

        return id;
    }

    function adminAcceptBuyOrder(
        uint256 id
    )
        external
        override
        onlyAdmin
        whenNotPaused
        buyOrderExists(id)
    {
        BuyOrder storage order =
            buyOrders[id];

        require(
            order.status == OrderStatus.Placed,
            "Invalid status"
        );

        order.status =
            OrderStatus.Accepted;

        emit BuyOrderStatusChanged(
            id,
            OrderStatus.Accepted,
            block.timestamp
        );
    }

    function adminStartBuySettlement(
        uint256 id
    )
        external
        override
        onlyAdmin
        whenNotPaused
        buyOrderExists(id)
    {
        BuyOrder storage order =
            buyOrders[id];

        require(
            order.status == OrderStatus.Accepted,
            "Invalid status"
        );

        order.status =
            OrderStatus.SettlementInProgress;

        emit BuyOrderStatusChanged(
            id,
            OrderStatus.SettlementInProgress,
            block.timestamp
        );
    }

    function adminCompleteBuyOrder(
        uint256 id
    )
        external
        override
    {
        _completeBuyOrder(
            id,
            bytes32(0)
        );
    }

    function adminCompleteBuyOrder(
        uint256 id,
        bytes32 fiatReferenceHash
    )
        external
        override
    {
        _completeBuyOrder(
            id,
            fiatReferenceHash
        );
    }

    function adminCancelBuyOrder(
        uint256 id
    )
        external
        override
        onlyAdmin
        whenNotPaused
        nonReentrant
        buyOrderExists(id)
    {
        BuyOrder storage order =
            buyOrders[id];

        require(
            order.status == OrderStatus.Placed ||
                order.status == OrderStatus.Accepted ||
                order.status == OrderStatus.SettlementInProgress,
            "Cannot cancel"
        );

        order.status =
            OrderStatus.Cancelled;

        _refundBuyOrder(
            order
        );

        emit BuyOrderStatusChanged(
            id,
            OrderStatus.Cancelled,
            block.timestamp
        );
    }

    function adminRejectBuyOrder(
        uint256 id
    )
        external
        override
        onlyAdmin
        whenNotPaused
        nonReentrant
        buyOrderExists(id)
    {
        BuyOrder storage order =
            buyOrders[id];

        require(
            order.status == OrderStatus.Placed ||
                order.status == OrderStatus.Accepted ||
                order.status == OrderStatus.SettlementInProgress,
            "Cannot reject"
        );

        order.status =
            OrderStatus.Rejected;

        _refundBuyOrder(
            order
        );

        emit BuyOrderStatusChanged(
            id,
            OrderStatus.Rejected,
            block.timestamp
        );
    }

    function adminRecordBuyReceiptHash(
        uint256 id,
        bytes32 receiptHash
    )
        external
        override
        onlyAdmin
        whenNotPaused
        buyOrderExists(id)
    {
        BuyOrder storage order =
            buyOrders[id];

        require(
            order.status == OrderStatus.Completed,
            "Order not completed"
        );

        require(
            receiptHash != bytes32(0),
            "Invalid receipt hash"
        );

        require(
            order.receiptHash == bytes32(0),
            "Receipt already recorded"
        );

        order.receiptHash =
            receiptHash;

        emit BuyOrderReceiptHashRecorded(
            id,
            receiptHash,
            block.timestamp
        );
    }

    // -------------------------------------------------------------------------
    // Internal settlement helpers
    // -------------------------------------------------------------------------

    function _completeSellOrder(
        uint256 id,
        bytes32 fiatReferenceHash
    )
        internal
        onlyAdmin
        whenNotPaused
        nonReentrant
        sellOrderExists(id)
    {
        SellOrder storage order =
            sellOrders[id];

        require(
            order.status == OrderStatus.SettlementInProgress,
            "Invalid status"
        );

        address treasury =
            accessControl.owner();

        order.status =
            OrderStatus.Completed;

        order.completedAt =
            block.timestamp;

        order.fiatReferenceHash =
            fiatReferenceHash;

        if (order.isIQS) {
            require(
                tokenManager.balanceOfIQS(escrowAddress) >= order.amount,
                "Escrow IQS insufficient"
            );

            tokenManager.transferIQSfromAtoB(
                escrowAddress,
                treasury,
                order.amount
            );
        } else {
            require(
                tokenManager.balanceOfOST(escrowAddress) >= order.amount,
                "Escrow OST insufficient"
            );

            tokenManager.transferOSTfromAtoB(
                escrowAddress,
                treasury,
                order.amount
            );
        }

        emit SellOrderStatusChanged(
            id,
            OrderStatus.Completed,
            block.timestamp
        );

        emit SellOrderCompleted(
            id,
            order.seller,
            order.amount,
            order.isIQS,
            fiatReferenceHash,
            block.timestamp
        );
    }

    function _completeBuyOrder(
        uint256 id,
        bytes32 fiatReferenceHash
    )
        internal
        onlyAdmin
        whenNotPaused
        nonReentrant
        buyOrderExists(id)
    {
        BuyOrder storage order =
            buyOrders[id];

        require(
            order.status == OrderStatus.SettlementInProgress,
            "Invalid status"
        );

        order.status =
            OrderStatus.Completed;

        order.completedAt =
            block.timestamp;

        order.fiatReferenceHash =
            fiatReferenceHash;

        if (order.isIQS) {
            require(
                tokenManager.balanceOfIQS(escrowAddress) >= order.amount,
                "Escrow IQS insufficient"
            );

            tokenManager.transferIQSfromAtoB(
                escrowAddress,
                order.buyer,
                order.amount
            );
        } else {
            require(
                tokenManager.balanceOfOST(escrowAddress) >= order.amount,
                "Escrow OST insufficient"
            );

            tokenManager.transferOSTfromAtoB(
                escrowAddress,
                order.buyer,
                order.amount
            );
        }

        emit BuyOrderStatusChanged(
            id,
            OrderStatus.Completed,
            block.timestamp
        );

        emit BuyOrderCompleted(
            id,
            order.buyer,
            order.amount,
            order.isIQS,
            fiatReferenceHash,
            block.timestamp
        );
    }

    function _refundSellOrder(
        SellOrder storage order
    )
        internal
    {
        if (order.isIQS) {
            require(
                tokenManager.balanceOfIQS(escrowAddress) >= order.amount,
                "Escrow IQS insufficient"
            );

            tokenManager.transferIQSfromAtoB(
                escrowAddress,
                order.seller,
                order.amount
            );
        } else {
            require(
                tokenManager.balanceOfOST(escrowAddress) >= order.amount,
                "Escrow OST insufficient"
            );

            tokenManager.transferOSTfromAtoB(
                escrowAddress,
                order.seller,
                order.amount
            );
        }
    }

    function _refundBuyOrder(
        BuyOrder storage order
    )
        internal
    {
        address treasury =
            accessControl.owner();

        if (order.isIQS) {
            require(
                tokenManager.balanceOfIQS(escrowAddress) >= order.amount,
                "Escrow IQS insufficient"
            );

            tokenManager.transferIQSfromAtoB(
                escrowAddress,
                treasury,
                order.amount
            );
        } else {
            require(
                tokenManager.balanceOfOST(escrowAddress) >= order.amount,
                "Escrow OST insufficient"
            );

            tokenManager.transferOSTfromAtoB(
                escrowAddress,
                treasury,
                order.amount
            );
        }
    }

    // -------------------------------------------------------------------------
    // Getters
    // -------------------------------------------------------------------------

    function sellOrdersf(
        uint256 id
    )
        external
        view
        override
        returns (SellOrder memory)
    {
        return sellOrders[id];
    }

    function buyOrdersf(
        uint256 id
    )
        external
        view
        override
        returns (BuyOrder memory)
    {
        return buyOrders[id];
    }

    function nextSellOrderIdf()
        external
        view
        override
        returns (uint256)
    {
        return nextSellOrderId;
    }

    function nextBuyOrderIdf()
        external
        view
        override
        returns (uint256)
    {
        return nextBuyOrderId;
    }
}