// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import "../src/IQOS.sol";
import "../src/AccessControl.sol";
import "../src/TokenManager.sol";
import "../src/OrderBookModule.sol";
import "../src/ConversionModule.sol";
import "../src/HashRegistry.sol";
import "../src/IOrderBookModule.sol";
import "../src/IConversionModule.sol";

contract IQOSTest is Test {
    IQOS public iqos;
    AccessControl public accessControl;
    TokenManager public tokenManager;
    OrderBookModule public orderBookModule;
    ConversionModule public conversionModule;
    HashRegistry public hashRegistry;

    address owner = address(0xABCD);
    address alice = address(0x1);
    address bob = address(0x2);
    address mallory = address(0x3);

    bytes32 constant SAMPLE_REF =
        keccak256("backend-order-reference");

    bytes32 constant SAMPLE_HASH =
        keccak256("document-hash");

    bytes32 constant SAMPLE_FIAT_REF =
        keccak256("fiat-transfer-reference");

    bytes32 constant SAMPLE_RECEIPT_HASH =
        keccak256("receipt-hash");

    function setUp() public {
        vm.startPrank(owner);

        accessControl =
            new AccessControl(owner);

        tokenManager =
            new TokenManager(address(accessControl));

        orderBookModule =
            new OrderBookModule(
                address(accessControl),
                address(tokenManager)
            );

        conversionModule =
            new ConversionModule(
                address(accessControl),
                address(tokenManager)
            );

        hashRegistry =
            new HashRegistry(
                owner,
                address(accessControl)
            );

        iqos =
            new IQOS(
                address(accessControl),
                address(tokenManager),
                address(orderBookModule),
                address(conversionModule),
                address(hashRegistry)
            );

        tokenManager.setTokenOperator(
            address(orderBookModule),
            true
        );

        tokenManager.setTokenOperator(
            address(conversionModule),
            true
        );

        vm.stopPrank();
    }

    function _makeValidUser(
        address user
    ) internal {
        vm.startPrank(owner);

        accessControl.addToWhiteList(user);
        accessControl.authorizeAddress(user);

        vm.stopPrank();
    }

    function _fundUserWithIQS(
        address user,
        uint256 amount
    ) internal {
        vm.startPrank(owner);

        tokenManager.mintIQS(amount);
        tokenManager.transferIQSfromAtoB(
            owner,
            user,
            amount
        );

        vm.stopPrank();
    }

    function _fundUserWithOST(
        address user,
        uint256 amount
    ) internal {
        vm.prank(owner);

        tokenManager.transferOSTfromAtoB(
            owner,
            user,
            amount
        );
    }

    function testInitialDeployment()
        public
        view
    {
        assertEq(
            accessControl.owner(),
            owner
        );

        assertTrue(
            accessControl.isAdmin(owner)
        );

        assertEq(
            tokenManager.balanceOfOST(owner),
            200_000
        );

        assertEq(
            tokenManager.totalSupplyOSTf(),
            200_000
        );

        assertEq(
            tokenManager.maxSupplyIQS(),
            1_000_000
        );
    }

    function testAuthorizeAndWhitelistUser()
        public
    {
        _makeValidUser(alice);

        assertTrue(
            accessControl.isWhiteListed(alice)
        );

        assertTrue(
            accessControl.isAuthorized(alice)
        );

        assertFalse(
            accessControl.isFrozen(alice)
        );
    }

    function testNonAdminCannotAuthorize()
        public
    {
        vm.prank(mallory);

        vm.expectRevert(
            "Caller is not an admin"
        );

        accessControl.authorizeAddress(
            mallory
        );
    }

    function testNonAdminCannotCreateSellOrder()
        public
    {
        _makeValidUser(alice);
        _fundUserWithIQS(alice, 100);

        vm.prank(mallory);

        vm.expectRevert(
            "Caller is not an admin"
        );

        orderBookModule.adminCreateSellOrder(
            alice,
            50,
            400,
            true,
            SAMPLE_REF
        );
    }

    function testAdminCreatesSellOrderAndMovesIQSToEscrow()
        public
    {
        _makeValidUser(alice);
        _fundUserWithIQS(alice, 100);

        address escrow =
            orderBookModule.escrowAddress();

        vm.prank(owner);

        uint256 orderId =
            orderBookModule.adminCreateSellOrder(
                alice,
                30,
                400,
                true,
                SAMPLE_REF
            );

        IOrderBookModule.SellOrder memory order =
            orderBookModule.sellOrdersf(orderId);

        assertEq(order.id, 0);
        assertEq(order.seller, alice);
        assertEq(order.amount, 30);
        assertEq(order.price, 400);
        assertTrue(order.isIQS);

        assertEq(
            uint256(order.status),
            uint256(IOrderBookModule.OrderStatus.Placed)
        );

        assertEq(
            tokenManager.balanceOfIQS(alice),
            70
        );

        assertEq(
            tokenManager.balanceOfIQS(escrow),
            30
        );

        assertEq(
            tokenManager.balanceOfIQS(owner),
            0
        );
    }

    function testAdminCancelSellOrderRefundsIQS()
        public
    {
        _makeValidUser(alice);
        _fundUserWithIQS(alice, 100);

        address escrow =
            orderBookModule.escrowAddress();

        vm.prank(owner);

        uint256 orderId =
            orderBookModule.adminCreateSellOrder(
                alice,
                30,
                400,
                true,
                SAMPLE_REF
            );

        assertEq(
            tokenManager.balanceOfIQS(escrow),
            30
        );

        vm.prank(owner);

        orderBookModule.adminCancelSellOrder(
            orderId
        );

        IOrderBookModule.SellOrder memory order =
            orderBookModule.sellOrdersf(orderId);

        assertEq(
            uint256(order.status),
            uint256(IOrderBookModule.OrderStatus.Cancelled)
        );

        assertEq(
            tokenManager.balanceOfIQS(alice),
            100
        );

        assertEq(
            tokenManager.balanceOfIQS(escrow),
            0
        );

        assertEq(
            tokenManager.balanceOfIQS(owner),
            0
        );
    }

    function testSellOrderFullSettlementFlow()
        public
    {
        _makeValidUser(alice);
        _fundUserWithIQS(alice, 100);

        address escrow =
            orderBookModule.escrowAddress();

        vm.prank(owner);

        uint256 orderId =
            orderBookModule.adminCreateSellOrder(
                alice,
                40,
                400,
                true,
                SAMPLE_REF
            );

        vm.prank(owner);

        orderBookModule.adminAcceptSellOrder(
            orderId
        );

        IOrderBookModule.SellOrder memory acceptedOrder =
            orderBookModule.sellOrdersf(orderId);

        assertEq(
            uint256(acceptedOrder.status),
            uint256(IOrderBookModule.OrderStatus.Accepted)
        );

        vm.prank(owner);

        orderBookModule.adminStartSellSettlement(
            orderId
        );

        IOrderBookModule.SellOrder memory settlementOrder =
            orderBookModule.sellOrdersf(orderId);

        assertEq(
            uint256(settlementOrder.status),
            uint256(IOrderBookModule.OrderStatus.SettlementInProgress)
        );

        vm.prank(owner);

        orderBookModule.adminCompleteSellOrder(
            orderId,
            SAMPLE_FIAT_REF
        );

        IOrderBookModule.SellOrder memory completedOrder =
            orderBookModule.sellOrdersf(orderId);

        assertEq(
            uint256(completedOrder.status),
            uint256(IOrderBookModule.OrderStatus.Completed)
        );

        assertEq(
            completedOrder.fiatReferenceHash,
            SAMPLE_FIAT_REF
        );

        assertEq(
            tokenManager.balanceOfIQS(alice),
            60
        );

        assertEq(
            tokenManager.balanceOfIQS(owner),
            40
        );

        assertEq(
            tokenManager.balanceOfIQS(escrow),
            0
        );
    }

    function testAdminRejectSellOrderRefundsIQS()
        public
    {
        _makeValidUser(alice);
        _fundUserWithIQS(alice, 100);

        address escrow =
            orderBookModule.escrowAddress();

        vm.prank(owner);

        uint256 orderId =
            orderBookModule.adminCreateSellOrder(
                alice,
                25,
                400,
                true,
                SAMPLE_REF
            );

        assertEq(
            tokenManager.balanceOfIQS(escrow),
            25
        );

        vm.prank(owner);

        orderBookModule.adminRejectSellOrder(
            orderId
        );

        IOrderBookModule.SellOrder memory order =
            orderBookModule.sellOrdersf(orderId);

        assertEq(
            uint256(order.status),
            uint256(IOrderBookModule.OrderStatus.Rejected)
        );

        assertEq(
            tokenManager.balanceOfIQS(alice),
            100
        );

        assertEq(
            tokenManager.balanceOfIQS(escrow),
            0
        );
    }

    function testAdminCreatesBuyOrderAndMovesTreasuryTokensToEscrow()
        public
    {
        _makeValidUser(bob);

        address escrow =
            orderBookModule.escrowAddress();

        uint256 ownerInitialBalance =
            tokenManager.balanceOfOST(owner);

        vm.prank(owner);

        uint256 orderId =
            orderBookModule.adminCreateBuyOrder(
                bob,
                20,
                400,
                false,
                SAMPLE_REF
            );

        IOrderBookModule.BuyOrder memory order =
            orderBookModule.buyOrdersf(orderId);

        assertEq(order.id, 0);
        assertEq(order.buyer, bob);
        assertEq(order.amount, 20);
        assertEq(order.price, 400);
        assertFalse(order.isIQS);

        assertEq(
            uint256(order.status),
            uint256(IOrderBookModule.OrderStatus.Placed)
        );

        assertEq(
            tokenManager.balanceOfOST(bob),
            0
        );

        assertEq(
            tokenManager.balanceOfOST(owner),
            ownerInitialBalance - 20
        );

        assertEq(
            tokenManager.balanceOfOST(escrow),
            20
        );
    }

    function testBuyOrderFullSettlementFlowReleasesOSTToBuyer()
        public
    {
        _makeValidUser(bob);

        address escrow =
            orderBookModule.escrowAddress();

        vm.prank(owner);

        uint256 orderId =
            orderBookModule.adminCreateBuyOrder(
                bob,
                20,
                400,
                false,
                SAMPLE_REF
            );

        vm.prank(owner);

        orderBookModule.adminAcceptBuyOrder(
            orderId
        );

        vm.prank(owner);

        orderBookModule.adminStartBuySettlement(
            orderId
        );

        vm.prank(owner);

        orderBookModule.adminCompleteBuyOrder(
            orderId,
            SAMPLE_FIAT_REF
        );

        IOrderBookModule.BuyOrder memory order =
            orderBookModule.buyOrdersf(orderId);

        assertEq(
            uint256(order.status),
            uint256(IOrderBookModule.OrderStatus.Completed)
        );

        assertEq(
            order.fiatReferenceHash,
            SAMPLE_FIAT_REF
        );

        assertEq(
            tokenManager.balanceOfOST(bob),
            20
        );

        assertEq(
            tokenManager.balanceOfOST(owner),
            199_980
        );

        assertEq(
            tokenManager.balanceOfOST(escrow),
            0
        );
    }

    function testAdminCancelBuyOrderRefundsTreasury()
        public
    {
        _makeValidUser(bob);

        address escrow =
            orderBookModule.escrowAddress();

        uint256 ownerInitialBalance =
            tokenManager.balanceOfOST(owner);

        vm.prank(owner);

        uint256 orderId =
            orderBookModule.adminCreateBuyOrder(
                bob,
                20,
                400,
                false,
                SAMPLE_REF
            );

        assertEq(
            tokenManager.balanceOfOST(escrow),
            20
        );

        vm.prank(owner);

        orderBookModule.adminCancelBuyOrder(
            orderId
        );

        IOrderBookModule.BuyOrder memory order =
            orderBookModule.buyOrdersf(orderId);

        assertEq(
            uint256(order.status),
            uint256(IOrderBookModule.OrderStatus.Cancelled)
        );

        assertEq(
            tokenManager.balanceOfOST(bob),
            0
        );

        assertEq(
            tokenManager.balanceOfOST(owner),
            ownerInitialBalance
        );

        assertEq(
            tokenManager.balanceOfOST(escrow),
            0
        );
    }

    function testAdminCreatesConversionRequestAfterUserAuthorization()
        public
    {
        _makeValidUser(alice);
        _fundUserWithIQS(alice, 50);

        vm.prank(owner);

        uint256 requestId =
            conversionModule.adminCreateIQSToOSTConversionRequest(
                alice,
                20,
                SAMPLE_REF
            );

        IConversionModule.IQSToOSTConversion memory request =
            conversionModule.getIQSToOSTConversion(
                requestId
            );

        assertEq(request.id, 0);
        assertEq(request.requester, alice);
        assertEq(request.amount, 20);
        assertEq(request.referenceHash, SAMPLE_REF);

        assertEq(
            uint256(request.status),
            uint256(IConversionModule.ConversionStatus.Requested)
        );

        assertEq(
            tokenManager.balanceOfIQS(alice),
            50
        );

        assertEq(
            tokenManager.balanceOfOST(alice),
            0
        );
    }

    function testApproveConversionBurnsIQSAndReleasesOST()
        public
    {
        _makeValidUser(alice);
        _fundUserWithIQS(alice, 50);

        vm.prank(owner);

        uint256 requestId =
            conversionModule.adminCreateIQSToOSTConversionRequest(
                alice,
                20,
                SAMPLE_REF
            );

        vm.prank(owner);

        conversionModule.approveIQSToOSTConversion(
            requestId
        );

        IConversionModule.IQSToOSTConversion memory request =
            conversionModule.getIQSToOSTConversion(
                requestId
            );

        assertEq(
            uint256(request.status),
            uint256(IConversionModule.ConversionStatus.Approved)
        );

        assertEq(
            tokenManager.balanceOfIQS(alice),
            30
        );

        assertEq(
            tokenManager.balanceOfOST(alice),
            20
        );

        assertEq(
            tokenManager.balanceOfOST(owner),
            199_980
        );

        assertEq(
            tokenManager.totalSupplyIQS(),
            30
        );
    }

    function testRejectConversionDoesNotMoveTokens()
        public
    {
        _makeValidUser(alice);
        _fundUserWithIQS(alice, 50);

        vm.prank(owner);

        uint256 requestId =
            conversionModule.adminCreateIQSToOSTConversionRequest(
                alice,
                20,
                SAMPLE_REF
            );

        vm.prank(owner);

        conversionModule.rejectIQSToOSTConversion(
            requestId
        );

        IConversionModule.IQSToOSTConversion memory request =
            conversionModule.getIQSToOSTConversion(
                requestId
            );

        assertEq(
            uint256(request.status),
            uint256(IConversionModule.ConversionStatus.Rejected)
        );

        assertEq(
            tokenManager.balanceOfIQS(alice),
            50
        );

        assertEq(
            tokenManager.balanceOfOST(alice),
            0
        );
    }

    function testRecordBuyReceiptHashAfterCompleted()
        public
    {
        _makeValidUser(bob);

        vm.prank(owner);

        uint256 orderId =
            orderBookModule.adminCreateBuyOrder(
                bob,
                20,
                400,
                false,
                SAMPLE_REF
            );

        vm.prank(owner);
        orderBookModule.adminAcceptBuyOrder(orderId);

        vm.prank(owner);
        orderBookModule.adminStartBuySettlement(orderId);

        vm.prank(owner);
        orderBookModule.adminCompleteBuyOrder(orderId);

        vm.prank(owner);
        orderBookModule.adminRecordBuyReceiptHash(
            orderId,
            SAMPLE_RECEIPT_HASH
        );

        IOrderBookModule.BuyOrder memory order =
            orderBookModule.buyOrdersf(orderId);

        assertEq(
            order.receiptHash,
            SAMPLE_RECEIPT_HASH
        );
    }

    function testCannotRecordBuyReceiptBeforeCompleted()
        public
    {
        _makeValidUser(bob);

        vm.prank(owner);

        uint256 orderId =
            orderBookModule.adminCreateBuyOrder(
                bob,
                20,
                400,
                false,
                SAMPLE_REF
            );

        vm.prank(owner);

        vm.expectRevert(
            "Order not completed"
        );

        orderBookModule.adminRecordBuyReceiptHash(
            orderId,
            SAMPLE_RECEIPT_HASH
        );
    }

    function testRecordConversionReceiptHashAfterApproval()
        public
    {
        _makeValidUser(alice);
        _fundUserWithIQS(alice, 50);

        vm.prank(owner);

        uint256 requestId =
            conversionModule.adminCreateIQSToOSTConversionRequest(
                alice,
                20,
                SAMPLE_REF
            );

        vm.prank(owner);

        conversionModule.approveIQSToOSTConversion(
            requestId
        );

        vm.prank(owner);

        conversionModule.adminRecordIQSToOSTConversionReceiptHash(
            requestId,
            SAMPLE_RECEIPT_HASH
        );

        IConversionModule.IQSToOSTConversion memory request =
            conversionModule.getIQSToOSTConversion(
                requestId
            );

        assertEq(
            request.receiptHash,
            SAMPLE_RECEIPT_HASH
        );
    }

    function testMintIQSWithinLimit()
        public
    {
        vm.prank(owner);

        tokenManager.mintIQS(
            50_000
        );

        assertEq(
            tokenManager.balanceOfIQS(owner),
            50_000
        );

        assertEq(
            tokenManager.totalSupplyIQS(),
            50_000
        );
    }

    function testCannotMintAboveMaxSupply()
        public
    {
        vm.prank(owner);

        tokenManager.mintIQS(
            1_000_000
        );

        vm.prank(owner);

        vm.expectRevert(
            "Exceeds max supply"
        );

        tokenManager.mintIQS(
            1
        );
    }

    function testBurnIQSByAdmin()
        public
    {
        _fundUserWithIQS(alice, 50);

        vm.prank(owner);

        tokenManager.burnIQS(
            15,
            alice
        );

        assertEq(
            tokenManager.balanceOfIQS(alice),
            35
        );

        assertEq(
            tokenManager.totalSupplyIQS(),
            35
        );
    }

    function testAddValidHash()
        public
    {
        vm.prank(owner);

        hashRegistry.addValidHash(
            SAMPLE_HASH
        );

        assertTrue(
            hashRegistry.isHashValid(SAMPLE_HASH)
        );
    }

    function testAnchorHashWithMetadata()
        public
    {
        vm.prank(owner);

        hashRegistry.anchorHash(
            SAMPLE_HASH,
            "TRADE_RECEIPT",
            1
        );

        (
            bool exists,
            address submitter,
            uint256 timestamp,
            string memory referenceType,
            uint256 referenceId
        ) =
            hashRegistry.getHashRecord(
                SAMPLE_HASH
            );

        assertTrue(exists);
        assertEq(submitter, owner);
        assertGt(timestamp, 0);
        assertEq(referenceType, "TRADE_RECEIPT");
        assertEq(referenceId, 1);
    }

    function testNonAdminCannotAddHash()
        public
    {
        vm.prank(mallory);

        vm.expectRevert(
            "Caller is not an admin"
        );

        hashRegistry.addValidHash(
            SAMPLE_HASH
        );
    }
}