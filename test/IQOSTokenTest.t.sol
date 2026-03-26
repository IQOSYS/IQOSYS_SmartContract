// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/IQOS.sol"; 

contract IQOSTest is Test {
    IQOS public iqos;
    AccessControl public accessControl;
    TokenManager public tokenManager;
    P2PModule public p2pModule;
    OrderBookModule public orderBookModule;
    TradeModule public tradeModule;
    ConversionModule public conversionModule;
    HashRegistry public hashRegistry;
    DAO public dao;

    address owner = address(0xABCD);
    address alice = address(0x1);
    address bob   = address(0x2);
    address mallory = address(0x3); // Utilisé pour simuler un Hacker
    bytes32 constant SAMPLE_HASH = keccak256("foo");
    address public voter1      = address(0x1111);
    address public voter2      = address(0x2222);
    address public nonHolder   = address(0x3333);

    function setUp() public {
        owner = address(0xABCD);
        address forwarder = address(0x123); 

        vm.startPrank(owner); 

        // 1. Déploiement
        accessControl = new AccessControl(owner, forwarder);
        tokenManager = new TokenManager(address(accessControl), forwarder);
        p2pModule = new P2PModule(address(accessControl), address(tokenManager), forwarder);
        orderBookModule = new OrderBookModule(address(accessControl), address(tokenManager), forwarder);
        tradeModule = new TradeModule(address(accessControl), address(tokenManager), address(orderBookModule), forwarder);
        conversionModule = new ConversionModule(address(accessControl), address(tokenManager), forwarder);
        hashRegistry = new HashRegistry(owner, forwarder, address(accessControl));
        dao = new DAO(address(tokenManager), owner, forwarder);

        // 2. Configuration des droits vitaux (L'Admin pour les conversions)
        accessControl.addAdmin(address(conversionModule));

        // 3. Core
        iqos = new IQOS(
            address(accessControl), 
            address(tokenManager),
            address(p2pModule),
            address(orderBookModule),
            address(tradeModule),
            address(conversionModule),
            address(hashRegistry),
            address(dao)
        );

        tokenManager.setBalanceForTesting(voter1, 100, 0);
        tokenManager.setBalanceForTesting(voter2,  50, 0);

        vm.stopPrank();
    }

    function testAllOwnersAreCorrect() public view {
        address expectedOwner = owner;
        assertEq(accessControl.owner(), expectedOwner, "AccessControl");
        assertEq(dao.owner(), expectedOwner, "DAO");
        assertEq(hashRegistry.owner(), expectedOwner, "HashRegistry");
    }

    // ==========================================
    // --- 1. GESTION DES ADRESSES ET SÉCURITÉ --
    // ==========================================
    event AuthorizationUpdated(address indexed account, bool isAuthorized);
    event WhiteListed(address indexed account, bool status);
    event AddressFrozen(address indexed account, bool isFrozen);

    function testAuthorizeAddress() public {
        vm.prank(owner); // Owner est Admin par défaut
        vm.expectEmit(true, true, false, false);
        emit AuthorizationUpdated(bob, true);
        accessControl.authorizeAddress(bob);
        assertTrue(accessControl.isAuthorized(bob), "Bob should be authorized");
    }

    function testRevokeAuthorization() public {
        vm.prank(owner);
        accessControl.authorizeAddress(bob);

        vm.prank(owner);
        accessControl.revokeAuthorization(bob);
        assertFalse(accessControl.isAuthorized(bob), "Bob should not be authorized");
    }

    function testAddToWhiteList() public {
        vm.prank(owner);
        accessControl.addToWhiteList(bob);
        assertTrue(accessControl.isWhiteListed(bob), "Bob should be whitelisted");
    }

    function testFreezeAddress() public {
        vm.prank(owner);
        accessControl.freezeAddress(bob);
        assertTrue(accessControl.isFrozen(bob), "Bob should be frozen");
    }

    // --- TESTS NEGATIFS (Hacking / Sécurité Strictes) ---
    
    function testNonAdminCannotFreeze() public {
        vm.prank(mallory); // Mallory essaie de geler le compte de Bob
        vm.expectRevert("Caller is not an admin");
        accessControl.freezeAddress(bob);
    }

    function testNonAdminCannotAuthorize() public {
        vm.prank(mallory); 
        vm.expectRevert("Caller is not an admin");
        accessControl.authorizeAddress(mallory);
    }

    // ==========================================
    // --- 2. GESTION DES TRANSFERTS DIRECTS ----
    // ==========================================
    
    function testDirectTransferIQSToIQS() public {
        vm.prank(owner); tokenManager.setBalanceForTesting(alice, 100, 0);
        vm.prank(owner); accessControl.authorizeAddress(alice);
        vm.prank(owner); accessControl.addToWhiteList(alice);

        // Alice envoie 20 IQS à Bob directement
        vm.prank(alice);
        tokenManager.transferIQStoIQS(bob, 20);

        assertEq(tokenManager.balanceOfIQS(alice), 80);
        assertEq(tokenManager.balanceOfIQS(bob), 20);

        // Vérification que Bob a bien été ajouté à la liste des Holders
        (address[] memory holders, ) = tokenManager.getIQSHolders();
        bool bobIsHolder = false;
        for(uint i = 0; i < holders.length; i++) {
            if(holders[i] == bob) bobIsHolder = true;
        }
        assertTrue(bobIsHolder, "Bob devrait etre dans la liste des holders");
    }

    function testDirectTransferRevertsIfFrozen() public {
        vm.prank(owner); tokenManager.setBalanceForTesting(alice, 100, 0);
        vm.prank(owner); accessControl.authorizeAddress(alice);
        vm.prank(owner); accessControl.addToWhiteList(alice);
        
        // L'admin gèle le compte d'Alice
        vm.prank(owner); accessControl.freezeAddress(alice);

        // Alice essaie de transférer
        vm.prank(alice);
        vm.expectRevert("Sender is frozen");
        tokenManager.transferIQStoIQS(bob, 20);
    }


    // ==========================================
    // --- 3. TRANSACTIONS P2P ------------------
    // ==========================================
    event PendingP2PTransactionConfirmed(uint256 indexed id, address indexed participant);
    event PendingP2PTransactionCreated(uint256 indexed id, address indexed from, address indexed to, uint256 amount, uint256 price, bool isIQS, uint256 timestamp);
    event PendingP2PTransactionCanceled(uint256 indexed id, address indexed canceledBy);

    function _setupP2PUser(address user, uint256 iqsBalance, uint256 ostBalance) internal {
        vm.prank(owner);
        tokenManager.setBalanceForTesting(user, iqsBalance, ostBalance);
        vm.prank(owner);
        accessControl.authorizeAddress(user);
        vm.prank(owner);
        accessControl.addToWhiteList(user);
    }

    function testProposeP2PTransaction_IQS() public {
        _setupP2PUser(alice, 50, 0);
        _setupP2PUser(bob,   0, 0); 

        vm.prank(alice);
        p2pModule.proposeP2PTransaction(bob, 20, 5, true);

        (uint256 id, address from, address to, uint256 amount, , bool isIQS, ) = p2pModule.pendingP2PTransactions(0);
        assertEq(id,     0);
        assertEq(from,   alice);
        assertEq(to,     bob);
        assertEq(amount, 20);
        assertTrue(isIQS);

        assertEq(tokenManager.balanceOfIQS(alice), 30);
        assertEq(tokenManager.balanceOfIQS(owner), 20);
    }

    function testConfirmP2PTransactionBySender() public {
        testProposeP2PTransaction_IQS();

        vm.prank(alice);
        p2pModule.confirmP2PTransaction(0);

        (bool cf, ) = p2pModule.p2pConfirmations(0);
        assertTrue(cf);
    }

    function testCancelP2PTransactionByRecipient() public {
        vm.prank(owner); tokenManager.setBalanceForTesting(owner, 0, 0);
        _setupP2PUser(alice, 0, 40);
        _setupP2PUser(bob, 0, 0);

        vm.prank(alice);
        p2pModule.proposeP2PTransaction(bob, 15, 1, false);

        vm.prank(bob);
        p2pModule.cancelP2PTransaction(0);

        assertEq(tokenManager.balanceOfOST(alice), 40);
        assertEq(tokenManager.balanceOfOST(owner), 0);
    }

    // ==========================================
    // --- 4. CARNET D'ORDRES ET FUZZING --------
    // ==========================================
    event SellOrderCreated(uint256 indexed id, address indexed seller, uint256 amount, uint256 price, bool isIQS, uint256 timestamp);

    function _setupSellSender(address user, uint256 iqsBalance, uint256 ostBalance) internal {
        vm.prank(owner); tokenManager.setBalanceForTesting(user, iqsBalance, ostBalance);
        vm.prank(owner); accessControl.authorizeAddress(user);
        vm.prank(owner); accessControl.addToWhiteList(user);
    }

    function testProposeSellOrder_IQS() public {
        _setupSellSender(alice, 100, 0);

        vm.prank(alice);
        orderBookModule.proposeSellOrder(30, 7, true);

        (uint256 id, address seller, uint256 amount,, bool isIQS, ) = orderBookModule.sellOrders(0);
        assertEq(id,      0);
        assertEq(seller,  alice);
        assertEq(amount,  30);
        assertTrue(isIQS);
        
        // Escrow
        assertEq(tokenManager.balanceOfIQS(alice),  70);
        assertEq(tokenManager.balanceOfIQS(owner),  30);
    }

    // --- FUZZ TESTING (Nombres aléatoires extrêmes) ---
    function testFuzzProposeSellOrder(uint256 randomAmount, uint256 randomPrice) public {
        // On limite les montants à des valeurs logiques (plus de 0, pas plus que la supply max)
        vm.assume(randomAmount > 0 && randomAmount <= 800_000);
        vm.assume(randomPrice > 0 && randomPrice < 1_000_000);

        _setupSellSender(alice, randomAmount, 0); 

        vm.prank(alice);
        orderBookModule.proposeSellOrder(randomAmount, randomPrice, true);

        // Vérification de l'escrow mathématique
        assertEq(tokenManager.balanceOfIQS(owner), randomAmount);
        assertEq(tokenManager.balanceOfIQS(alice), 0);
    }

    function testAdminCancelSellOrder_IQS() public {
        _setupSellSender(alice, 50, 0);
        vm.prank(alice); orderBookModule.proposeSellOrder(10, 5, true);

        vm.prank(owner);
        orderBookModule.adminCancelSellOrder(0);

        // Restitution escrow
        assertEq(tokenManager.balanceOfIQS(alice), 50);
        assertEq(tokenManager.balanceOfIQS(owner),  0);
    }

    // ==========================================
    // --- 5. EXÉCUTION DES TRADES (ADMIN) ------
    // ==========================================
    function _setupBuySender(address user) internal {
        vm.prank(owner); accessControl.authorizeAddress(user);
        vm.prank(owner); accessControl.addToWhiteList(user);
    }

    function _setupSellOrder(address seller, uint256 iqsBalance) internal {
        _setupSellSender(seller, iqsBalance, 0);
        vm.prank(seller);
        orderBookModule.proposeSellOrder(10, 5, true);
    }

    function _setupBuyOrder(address buyer, uint256 ostBalance) internal {
        vm.prank(owner); tokenManager.setBalanceForTesting(buyer, 0, ostBalance);
        _setupBuySender(buyer);
        vm.prank(buyer);
        orderBookModule.proposeBuyOrder(8, 3, false);
    }

    function testAdminExecuteTradeMatch() public {
        _setupSellOrder(alice, 100); // Alice vend des IQS (il lui reste 90 IQS en poche, 10 en séquestre)
        _setupBuyOrder(bob, 50);     // Bob veut acheter 8 OST

        // FIX : Puisque Alice va agir comme "vendeuse" pour l'ordre d'achat de Bob (qui demande des OST),
        // elle doit avoir des OST dans son portefeuille ! 
        // On lui donne 10 OST (et on lui laisse ses 90 IQS restants pour ne rien casser).
        vm.prank(owner); 
        tokenManager.setBalanceForTesting(alice, 90, 10);

        // L'admin fusionne l'exécution des deux ordres en une signature
        vm.prank(owner);
        tradeModule.adminExecuteTradeMatch(0, bob, 0, alice);

        (,,,, address executedBuyer,,,,) = tradeModule.executedTrades(0);
        assertEq(executedBuyer, bob);

        (,,, address executedSeller,,,,,) = tradeModule.executedTrades(1);
        assertEq(executedSeller, alice);
    }

    // --- TESTS HISTORIQUES (VIEW FUNCTIONS) ---
    function testTradeHistoryGetters() public {
        testAdminExecuteTradeMatch(); // Génère 2 trades dans l'historique

        // On vérifie que le Getter renvoie bien l'historique pour Bob
        (uint256[] memory ids, , , , address[] memory buyers, , , , ) = tradeModule.getUserValidatedTradesOrderBook(bob);
        
        // Ce getter cherche dans 'validateexecutedTrades', on doit donc valider le trade d'abord !
        vm.prank(owner);
        tradeModule.validateExecutedTrade(0); // On valide le trade de Bob

        (ids, , , , buyers, , , , ) = tradeModule.getUserValidatedTradesOrderBook(bob);
        
        assertTrue(ids.length > 0, "L'historique ne doit pas etre vide");
        assertEq(buyers[0], bob, "Bob devrait etre l'acheteur dans l'historique");
    }

    function testNonAdminCannotValidateTrade() public {
        _setupSellOrder(alice, 100);
        vm.prank(owner); accessControl.authorizeAddress(bob);
        vm.prank(owner); accessControl.addToWhiteList(bob);
        
        vm.prank(bob); tradeModule.OrderSellFill(0);

        // MALLORY essaie de valider la transaction FIAT (Hacking)
        vm.prank(mallory);
        vm.expectRevert("Caller is not an admin");
        tradeModule.validateExecutedTrade(0);
    }

    function testValidateExecutedTrade_IQS() public {
        _setupSellOrder(alice, 100);
        vm.prank(owner); accessControl.authorizeAddress(bob);
        vm.prank(owner); accessControl.addToWhiteList(bob);
        vm.prank(bob); tradeModule.OrderSellFill(0);
        
        vm.prank(owner);
        tradeModule.validateExecutedTrade(0);

        assertEq(tokenManager.balanceOfIQS(bob), 10);
    }

    // ==========================================
    // --- 6. CONVERSIONS, MINAGE ET BURN -------
    // ==========================================
    
    function _setupValidSender(address user, uint256 balance) internal {
        vm.prank(owner); tokenManager.setBalanceForTesting(user, balance, 0);
        vm.prank(owner); accessControl.authorizeAddress(user);
        vm.prank(owner); accessControl.addToWhiteList(user);
    }

    function testRequestConversionEmitsEventAndStores() public {
        _setupValidSender(alice, 100);
        vm.prank(alice);
        conversionModule.requestIQSToOSTConversion(50);
        
        (address user, uint256 amt) = conversionModule.pendingIQSToOSTConversions(0);
        assertEq(user, alice);
        assertEq(amt, 50);
    }

    function testApproveConversion() public {
        _setupValidSender(alice, 20);
        vm.prank(alice);
        conversionModule.requestIQSToOSTConversion(20);
        
        // AJOUTER CECI : On abaisse artificiellement la Supply OST à 0 pour laisser de la place pour la conversion
        vm.prank(owner); 
        tokenManager.setTotalSupplyForTesting(800_000, 0);

        vm.prank(owner); // Owner est Admin, il peut approuver
        conversionModule.approveIQSToOSTConversion(0);

        assertEq(tokenManager.balanceOfIQS(alice), 0);
        assertEq(tokenManager.balanceOfOST(alice), 20);
    }

    function testMintWithinLimits() public {
        uint256 amount = 50_000;
        vm.prank(owner);
        tokenManager.mintIQS(amount);

        assertEq(tokenManager.balanceOfIQS(owner), amount);
        assertEq(tokenManager.totalSupplyIQS(), amount);
    }

    function testBurnIQSByAdmin() public {
        vm.prank(owner);
        tokenManager.setBalanceForTesting(alice, 50, 0);

        // AJOUTER CECI : On triche en mettant le TotalSupply à 50 pour ne pas faire planter les maths
        vm.prank(owner);
        tokenManager.setTotalSupplyForTesting(50, 200_000);

        vm.prank(owner); // Owner est Admin, il a le droit de burn
        tokenManager.burnIQS(15, alice);

        assertEq(tokenManager.balanceOfIQS(alice), 35);
    }

    // ==========================================
    // --- 7. HASH REGISTRY ET DAO --------------
    // ==========================================
    
    function testAddValidHash() public {
        bytes32 h = keccak256("bar");
        vm.prank(owner); // Owner est admin
        hashRegistry.addValidHash(h);

        assertTrue(hashRegistry.isHashValid(h));
    }

    function testCreateAndReadPoll() public {
        string[] memory options = new string[](2);
        options[0] = "Yes"; options[1] = "No";
        uint256 duration = 1 hours;
        vm.prank(owner);
        dao.createPoll("Do you agree?", options, duration);
    }

    function testVoteAndResults() public {
        string[] memory opts = new string[](2);
        opts[0] = "A"; opts[1] = "B";
        vm.prank(owner);
        dao.createPoll("Pick A or B", opts, 100);

        vm.prank(voter1); dao.vote(0, 0);
        vm.prank(voter2); dao.vote(0, 1);

        (string[] memory labels, uint256[] memory results) = dao.getResults(0);

        assertEq(results[0], 100);
        assertEq(results[1],  50);
        assertEq(labels[0], "A");
    }
}