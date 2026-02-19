// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/IQOS.sol"; // ou le bon chemin vers ton contrat IQOS

contract IQOSTest is Test {
    IQOS public iqos;
    AccessControl public accessControl;
    TokenManager public tokenManager;
    ProfileManager public profileManager;
    P2PModule public p2pModule;
    OrderBookModule public orderBookModule;
    TradeModule public tradeModule;
    ConversionModule public conversionModule;
    HashRegistry public hashRegistry;
    DAO public dao;



    address owner = address(0xABCD);
    address alice = address(0x1);
    address bob   = address(0x2);
    address mallory = address(0x3);
    bytes32 constant SAMPLE_HASH = keccak256("foo");
    address    public voter1      = address(0x1111);
    address    public voter2      = address(0x2222);
    address    public nonHolder   = address(0x3333);

    function setUp() public {
        owner = address(0xABCD);
        
        // On définit une adresse fictive pour le forwarder (suffisant pour que les tests compilent)
        address forwarder = address(0x123); 

        vm.startPrank(owner); // Utilise startPrank pour éviter de répéter vm.prank à chaque ligne

        // Ajout de 'forwarder' à la fin de chaque déploiement :
        accessControl = new AccessControl(owner, forwarder);
        
        tokenManager = new TokenManager(address(accessControl), forwarder);
        
        profileManager = new ProfileManager(owner, forwarder);
        
        p2pModule = new P2PModule(address(accessControl), address(tokenManager), forwarder);
        
        orderBookModule = new OrderBookModule(address(accessControl), address(tokenManager), forwarder);
        
        tradeModule = new TradeModule(address(accessControl), address(tokenManager), address(orderBookModule), forwarder);
        
        conversionModule = new ConversionModule(address(accessControl), address(tokenManager), forwarder);
        
        hashRegistry = new HashRegistry(owner, forwarder);
        
        dao = new DAO(address(tokenManager), owner, forwarder);

        // Le Core ne change pas
        iqos = new IQOS(
            address(accessControl), // Attention: J'ai inversé ici pour matcher l'ordre habituel, vérifie ton constructeur IQOS
            address(tokenManager),
            address(profileManager),
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
        assertEq(profileManager.owner(), expectedOwner, "ProfileManager");
        assertEq(accessControl.owner(), expectedOwner, "AccessControl");
        assertEq(dao.owner(), expectedOwner, "DAO");
        assertEq(hashRegistry.owner(), expectedOwner, "HashRegistry");
    }


    // --- Gestion des identités ---
    event UserProfileUpdated(address indexed user,string email,string firstName,string lastName);

    function testDeleteUserProfile() public {
        // Setup: owner sets profile
        vm.prank(owner);
        profileManager.setUserProfile(alice, "a@b.com", "A", "B");

        // Delete profile
        vm.prank(owner);
        profileManager.deleteUserProfile(alice);

        // After deletion, fields should be empty strings
        (string memory email, string memory firstName, string memory lastName) = profileManager.getUserProfile(alice);
        assertEq(email, "");
        assertEq(firstName, "");
        assertEq(lastName, "");
    }

     function testSetAndGetUserProfile() public {
        // Owner sets profile for Alice
        vm.prank(owner);
        vm.expectEmit(true, true, false, false);
        emit UserProfileUpdated(alice, "alice@example.com", "Alice", "Liddell");
        profileManager.setUserProfile(alice, "alice@example.com", "Alice", "Liddell");

        // Retrieve profile
        (string memory email, string memory firstName, string memory lastName) = profileManager.getUserProfile(alice);
        assertEq(email, "alice@example.com");
        assertEq(firstName, "Alice");
        assertEq(lastName, "Liddell");
    }





    // --- Gestion des adresses ---
    event AuthorizationUpdated(address indexed account, bool isAuthorized);
    event WhiteListed(address indexed account, bool status);
    event AddressFrozen(address indexed account, bool isFrozen);

    function testAuthorizeAddress() public {
        vm.prank(owner);
        vm.expectEmit(true, true, false, false);
        emit AuthorizationUpdated(bob, true);
        accessControl.authorizeAddress(bob);

        assertTrue(accessControl.isAuthorized(bob), "Bob should be authorized");
    }

    function testAuthorizeTwiceReverts() public {
        vm.prank(owner);
        accessControl.authorizeAddress(bob);

        vm.prank(owner);
        vm.expectRevert("Address already authorized");
        accessControl.authorizeAddress(bob);
    }

    function testRevokeAuthorization() public {
        vm.prank(owner);
        accessControl.authorizeAddress(bob);

        vm.prank(owner);
        vm.expectEmit(true, true, false, false);
        emit AuthorizationUpdated(bob, false);
        accessControl.revokeAuthorization(bob);

        assertFalse(accessControl.isAuthorized(bob), "Bob should not be authorized");
    }

    function testRevokeUnauthorizedReverts() public {
        vm.prank(owner);
        vm.expectRevert("Address not authorized");
        accessControl.revokeAuthorization(bob);
    }

    function testAddToWhiteList() public {
        vm.prank(owner);
        vm.expectEmit(true, true, false, false);
        emit WhiteListed(bob, true);
        accessControl.addToWhiteList(bob);

        assertTrue(accessControl.isWhiteListed(bob), "Bob should be whitelisted");
    }

    function testAddToWhiteListTwiceReverts() public {
        vm.prank(owner);
        accessControl.addToWhiteList(bob);

        vm.prank(owner);
        vm.expectRevert("Account already white-listed");
        accessControl.addToWhiteList(bob);
    }

    function testRemoveFromWhiteList() public {
        vm.prank(owner);
        accessControl.addToWhiteList(bob);

        vm.prank(owner);
        vm.expectEmit(true, true, false, false);
        emit WhiteListed(bob, false);
        accessControl.removeFromWhiteList(bob);

        assertFalse(accessControl.isWhiteListed(bob), "Bob should not be whitelisted");
    }

    function testRemoveFromWhiteListRevertsIfNotListed() public {
        vm.prank(owner);
        vm.expectRevert("Account not in white-list");
        accessControl.removeFromWhiteList(bob);
    }

    function testFreezeAddress() public {
        vm.prank(owner);
        vm.expectEmit(true, true, false, false);
        emit AddressFrozen(bob, true);
        accessControl.freezeAddress(bob);

        assertTrue(accessControl.isFrozen(bob), "Bob should be frozen");
    }

    function testFreezeTwiceReverts() public {
        vm.prank(owner);
        accessControl.freezeAddress(bob);

        vm.prank(owner);
        vm.expectRevert("Address already frozen");
        accessControl.freezeAddress(bob);
    }

    function testUnfreezeAddress() public {
        vm.prank(owner);
        accessControl.freezeAddress(bob);

        vm.prank(owner);
        vm.expectEmit(true, true, false, false);
        emit AddressFrozen(bob, false);
        accessControl.unfreezeAddress(bob);

        assertFalse(accessControl.isFrozen(bob), "Bob should not be frozen");
    }

    function testUnfreezeRevertsIfNotFrozen() public {
        vm.prank(owner);
        vm.expectRevert("Address not frozen");
        accessControl.unfreezeAddress(bob);
    }



    // --- Transactions P2P ---
    event PendingP2PTransactionConfirmed(uint256 indexed id, address indexed participant);
    event PendingP2PTransactionCreated(
        uint256 indexed id,
        address indexed from,
        address indexed to,
        uint256 amount,
        uint256 price,
        bool    isIQS,
        uint256 timestamp
    );
    event PendingP2PTransactionCanceled(
        uint256 indexed id,
        address indexed canceledBy
    );


    function _setupP2PUser(address user, uint256 iqsBalance, uint256 ostBalance) internal {
        // Donne du solde pour escrowing
        vm.prank(owner);
        tokenManager.setBalanceForTesting(user, iqsBalance, ostBalance);
        // whitelist & auth
        vm.prank(owner);
        accessControl.authorizeAddress(user);
        vm.prank(owner);
        accessControl.addToWhiteList(user);
    }

    function testProposeP2PTransaction_IQS() public {
        _setupP2PUser(alice, 50, 0);
        _setupP2PUser(bob,   0, 0); // Bob doit juste pouvoir confirmer

        vm.prank(alice);
        vm.expectEmit(true, true, true, false);
        emit PendingP2PTransactionCreated(
            0,
            alice,
            bob,
            20,
            5,
            true,
            block.timestamp
        );
        p2pModule.proposeP2PTransaction(bob, 20, 5, true);

        // vérifie mapping et escrow
        (uint256 id, address from, address to, uint256 amount, uint256 price, bool isIQS, uint256 ts) =
        p2pModule.pendingP2PTransactions(0);
        assertEq(id,     0);
        assertEq(from,   alice);
        assertEq(to,     bob);
        assertEq(amount, 20);
        assertEq(price,  5);
        assertTrue(isIQS);
        assertEq(ts,     block.timestamp);

        // Escrow: alice perd 20 IQS, owner gagne 20
        assertEq(tokenManager.balanceOfIQS(alice), 30);
        assertEq(tokenManager.balanceOfIQS(owner), 20);
    }

    function testProposeP2PTransaction_OST() public {
        _setupP2PUser(alice, 0, 40);
        _setupP2PUser(bob,   0, 0);

        vm.prank(alice);
        vm.expectEmit(true, true, true, false);
        emit PendingP2PTransactionCreated(0, alice, bob, 15, 2, false, block.timestamp);
        p2pModule.proposeP2PTransaction(bob, 15, 2, false);

        (, , , uint256 amt, uint256 pr, bool isIQS,) = p2pModule.pendingP2PTransactions(0);
        assertEq(amt, 15);
        assertEq(pr,  2);
        assertFalse(isIQS);

        // Escrow OST
        assertEq(tokenManager.balanceOfOST(alice), 25);
        assertEq(tokenManager.balanceOfOST(owner), 200015);
    }

    function testProposeP2PTransactionReverts() public {
        _setupP2PUser(alice, 10, 0);

        // invalid recipient
        vm.prank(alice);
        vm.expectRevert("Invalid recipient");
        p2pModule.proposeP2PTransaction(address(0), 1, 1, true);

        // zero amount
        vm.prank(alice);
        vm.expectRevert("Amount and price > 0");
        p2pModule.proposeP2PTransaction(bob, 0, 1, true);

        // zero price
        vm.prank(alice);
        vm.expectRevert("Amount and price > 0");
        p2pModule.proposeP2PTransaction(bob, 1, 0, true);

        // insufficient bal
        vm.prank(alice);
        vm.expectRevert("Insufficient IQS balance");
        p2pModule.proposeP2PTransaction(bob, 11, 1, true);

        // not whitelisted/auth
        vm.prank(mallory);
        vm.expectRevert();
        p2pModule.proposeP2PTransaction(bob, 1, 1, true);
    }

    // --- confirmP2PTransaction ---
    function testConfirmP2PTransactionBySender() public {
        testProposeP2PTransaction_IQS();

        vm.prank(alice);
        vm.expectEmit(true, true, false, false);
        emit PendingP2PTransactionConfirmed(0, alice);
        p2pModule.confirmP2PTransaction(0);

        // mapping confirmations
        (bool cf, ) = p2pModule.p2pConfirmations(0);
        assertTrue(cf);

        // re-confirm sender reverts
        vm.prank(alice);
        vm.expectRevert("Already confirmed by sender");
        p2pModule.confirmP2PTransaction(0);
    }

    function testConfirmP2PTransactionRevertsIfNotWhiteList() public {
        testProposeP2PTransaction_IQS();
        vm.prank(mallory);
        vm.expectRevert("Sender not whitelisted");
        p2pModule.confirmP2PTransaction(0);
    }

    // --- cancelP2PTransaction ---
    function testCancelP2PTransactionByRecipient() public {
        // 1) Réinitialiser le solde du owner pour isoler le test
        vm.prank(owner);
        tokenManager.setBalanceForTesting(owner, 0, 0);

        // 2) Préparer Alice avec 40 OST, et Bob avec 0 OST
        vm.prank(owner);
        tokenManager.setBalanceForTesting(alice, 0, 40);
        vm.prank(owner);
        accessControl.authorizeAddress(alice);
        vm.prank(owner);
        accessControl.addToWhiteList(alice);

        vm.prank(owner);
        tokenManager.setBalanceForTesting(bob, 0, 0);
        vm.prank(owner);
        accessControl.authorizeAddress(bob);
        vm.prank(owner);
        accessControl.addToWhiteList(bob);

        // 3) Alice propose une transaction P2P d’OST vers Bob
        vm.prank(alice);
        vm.expectEmit(true, true, false, false);
        emit PendingP2PTransactionCreated(0, alice, bob, 15, 1, false, block.timestamp);
        p2pModule.proposeP2PTransaction(bob, 15, 1, false);

        // Vérifier l’escrow : Alice a perdu 15 OST, owner en a gagné 15
        assertEq(tokenManager.balanceOfOST(alice), 25);
        assertEq(tokenManager.balanceOfOST(owner), 15);

        // 4) Bob annule la transaction
        vm.prank(bob);
        vm.expectEmit(true, true, false, false);
        emit PendingP2PTransactionCanceled(0, bob);
        p2pModule.cancelP2PTransaction(0);

        // 5) Vérifications finales
        // - Alice récupère bien ses 15 OST
        assertEq(tokenManager.balanceOfOST(alice), 40);
        // - Le owner redescend à 0 OST
        assertEq(tokenManager.balanceOfOST(owner), 0);
        // - La transaction en attente est bien supprimée
        (, address from, address to,, , bool isIQS,) = p2pModule.pendingP2PTransactions(0);
        assertEq(from, address(0));
        assertEq(to,   address(0));
        assertFalse(isIQS);
    }

    function testCancelP2PTransactionRevertsIfNotParticipant() public {
        address charlie = address(0x3);

        // 1) Préparation des rôles et soldes
        // Alice (seller) détient 40 OST
        vm.prank(owner);
        tokenManager.setBalanceForTesting(alice, 0, 40);
        vm.prank(owner); accessControl.authorizeAddress(alice);
        vm.prank(owner); accessControl.addToWhiteList(alice);

        // Bob (buyer) n'a pas besoin de solde pour proposer, mais doit être whitelisté pour être participant
        vm.prank(owner);
        accessControl.authorizeAddress(bob);
        vm.prank(owner);
        accessControl.addToWhiteList(bob);

        // Charlie (tiers) : on l'autorise et whitelist pour passer onlyValidSender
        vm.prank(owner);
        accessControl.authorizeAddress(charlie);
        vm.prank(owner);
        accessControl.addToWhiteList(charlie);

        // 2) Alice propose une transaction P2P vers Bob
        vm.prank(alice);
        p2pModule.proposeP2PTransaction(bob, 15, 1, false);

        // 3) Charlie tente d'annuler — il est whitelisté, mais n'est ni 'from' ni 'to'
        vm.prank(charlie);
        vm.expectRevert("Not a participant");
        p2pModule.cancelP2PTransaction(0);
    }

    // --- P2PTransaction History ---
    function _createAndValidateP2P(address from, address to, uint256 amount, uint256 price, bool isIQS) internal {
        // Prépare les balances et permissions
        _setupP2PSender(from, isIQS ? amount : 0, isIQS ? 0 : amount);
        _setupP2PSender(to, 0, 0);

        // propose
        vm.prank(from);
        p2pModule.proposeP2PTransaction(to, amount, price, isIQS);

        // confirm both
        vm.prank(from);
        p2pModule.confirmP2PTransaction(0);
        vm.prank(to);
        p2pModule.confirmP2PTransaction(0);

        // validate by admin
        vm.prank(owner);
        p2pModule.validateP2PTransaction(0);
    }

    function _setupP2PSender(address user, uint256 iqsBalance, uint256 ostBalance) internal {
        vm.prank(owner);
        tokenManager.setBalanceForTesting(user, iqsBalance, ostBalance);
        vm.prank(owner);
        accessControl.authorizeAddress(user);
        vm.prank(owner);
        accessControl.addToWhiteList(user);
    }

    function testPendingP2PCostRevertsIfNotFound() public {
        vm.prank(alice);
        vm.expectRevert("No such pending P2P");
        p2pModule.pendingP2PCost(42);
    }

    function testGetValidatedP2PTransactions() public {
        _createAndValidateP2P(alice, bob, 7, 4, true);

        // Alice (whitelistée) récupère la liste complète
        vm.prank(alice);
        (
            uint256[] memory ids,
            address[] memory froms,
            address[] memory tos,
            uint256[] memory amounts,
            uint256[] memory prices,
            bool[]    memory isIQSFlags,
            uint256[] memory timestamps
        ) = p2pModule.getValidatedP2PTransactions();

        assertEq(ids.length,        1);
        assertEq(ids[0],            0);
        assertEq(froms[0],          alice);
        assertEq(tos[0],            bob);
        assertEq(amounts[0],        7);
        assertEq(prices[0],         4);
        assertTrue(isIQSFlags[0]);
        assertEq(timestamps[0],     block.timestamp);
    }

    function testGetUserValidatedP2PTransactionsFilters() public {
        // Un seul trade validé alice→bob
        _createAndValidateP2P(alice, bob, 7, 4, true);

        // Alice voit 1
        vm.prank(alice);
        (uint256[] memory aIds,,,,,,) = p2pModule.getUserValidatedP2PTransactions(alice);
        assertEq(aIds.length, 1);
        assertEq(aIds[0],     0);

        // Bob voit 1
        vm.prank(bob);
        (uint256[] memory bIds,,,,,,) = p2pModule.getUserValidatedP2PTransactions(bob);
        assertEq(bIds.length, 1);
        assertEq(bIds[0],     0);

        // Charlie voit 0
        address charlie = address(0x3);
        vm.prank(owner);
        accessControl.authorizeAddress(charlie);
        vm.prank(owner); accessControl.addToWhiteList(charlie);
        vm.prank(charlie);
        (uint256[] memory cIds,,,,,,) = p2pModule.getUserValidatedP2PTransactions(charlie);
        assertEq(cIds.length, 0);
    }

    function testPendingP2PCostCorrect() public {
        // Alice propose un P2P sans le valider
        _setupP2PSender(alice, 0, 15);
        vm.prank(alice);
        p2pModule.proposeP2PTransaction(bob, 5, 3, false);

        // appel en tant qu’Alice (whitelistée)
        vm.prank(alice);
        uint256 cost = p2pModule.pendingP2PCost(0);
        // base = 5*3 = 15; pct = (15*2)/100 = 0; total = 15 + 0 + 10 = 25
        assertEq(cost, 25);
    }
    



  


    
    

    // --- Gestion du carnet d'ordres ---

    event PendingSellOrderCreated(uint256 indexed id, address indexed seller, uint256 amount, uint256 price, bool isIQS, uint256 timestamp);
    event SellOrderValidated(      uint256 indexed id, address indexed seller, uint256 amount, uint256 price, bool isIQS, uint256 timestamp);
    event PendingSellOrderRejected(uint256 indexed id, address indexed seller);
    event PendingSellOrderCanceled(uint256 indexed id, address indexed seller);
    event SellOrderCanceled(uint256 indexed id, address indexed seller);

    // --- Helpers pour le carnet d’ordres de vente ---
    function _setupSellSender(address user, uint256 iqsBalance, uint256 ostBalance) internal {
        // Donne d’abord des IQS et OST pour couvrir les deux cas
        vm.prank(owner);
        tokenManager.setBalanceForTesting(user, iqsBalance, ostBalance);
        vm.prank(owner);
        accessControl.authorizeAddress(user);
        vm.prank(owner);
        accessControl.addToWhiteList(user);
    }

    function testProposeSellOrder_IQS() public {
        _setupSellSender(alice, 100, 0);

        vm.prank(alice);
        vm.expectEmit(true, true, false, false);
        emit PendingSellOrderCreated(0, alice, 30, 7, true, block.timestamp);
        orderBookModule.proposeSellOrder(30, 7, true);

        // Vérifie que le mapping pending a bien été rempli
        (uint256 id, address seller, uint256 amount, uint256 price, bool isIQS, ) = orderBookModule.PendingSellOrders(0);
        assertEq(id,      0);
        assertEq(seller,  alice);
        assertEq(amount,  30);
        assertEq(price,   7);
        assertTrue(isIQS);
        // Escrow : alice perd 30 IQS, owner en gagne 30
        assertEq(tokenManager.balanceOfIQS(alice),  70);
        assertEq(tokenManager.balanceOfIQS(owner),  30);
    }

    function testProposeSellOrder_OST() public {
        _setupSellSender(bob, 0, 50);

        vm.prank(bob);
        vm.expectEmit(true, true, false, false);
        emit PendingSellOrderCreated(0, bob, 20, 3, false, block.timestamp);
        orderBookModule.proposeSellOrder(20, 3, false);

        (,,uint256 amount, uint256 price, bool isIQS,) = orderBookModule.PendingSellOrders(0);
        assertEq(amount, 20);
        assertEq(price,  3);
        assertFalse(isIQS);
        // Escrow OST
        assertEq(tokenManager.balanceOfOST(bob),   30);
        assertEq(tokenManager.balanceOfOST(owner), 200020);
    }

    function testProposeSellOrderRevertsOnZero() public {
        _setupSellSender(alice, 10, 0);

        vm.prank(alice);
        vm.expectRevert("Amount must be > 0");
        orderBookModule.proposeSellOrder(0, 5, true);

        vm.prank(alice);
        vm.expectRevert("Price must be > 0");
        orderBookModule.proposeSellOrder(5, 0, true);
    }

    function testValidatePendingSellOrder() public {
        _setupSellSender(alice, 40, 0);
        vm.prank(alice); orderBookModule.proposeSellOrder(15, 2, true);

        vm.prank(owner);
        vm.expectEmit(true, true, false, false);
        emit SellOrderValidated(0, alice, 15, 2, true, block.timestamp);
        orderBookModule.validatePendingSellOrder(0);

        // Le sellOrder doit exister
        (uint256 id, address s, uint256 amt,, bool isIQS,) = orderBookModule.sellOrders(0);
        assertEq(id,     0);
        assertEq(s,      alice);
        assertEq(amt,    15);
        assertTrue(isIQS);

        // Le pending doit avoir été supprimé
        (, address pendingSeller,,,,) = orderBookModule.PendingSellOrders(0);
        assertEq(pendingSeller, address(0));
    }

    function testValidatePendingSellOrderRevertsIfNotFound() public {
        vm.prank(owner);
        vm.expectRevert("No such pending order");
        orderBookModule.validatePendingSellOrder(123);
    }

    function testRejectPendingSellOrder_IQS() public {
        _setupSellSender(alice, 25, 0);
        vm.prank(alice); orderBookModule.proposeSellOrder(10, 1, true);

        vm.prank(owner);
        vm.expectEmit(true, true, false, false);
        emit PendingSellOrderRejected(0, alice);
        orderBookModule.rejectPendingSellOrder(0);

        // Restitution escrow
        assertEq(tokenManager.balanceOfIQS(alice), 25);
        assertEq(tokenManager.balanceOfIQS(owner),  0);

        // Mapping pending vidé
        (,address pendingSeller,,,,) = orderBookModule.PendingSellOrders(0);
        assertEq(pendingSeller, address(0));
    }

    function testRejectPendingSellOrderRevertsIfNotFound() public {
        vm.prank(owner);
        vm.expectRevert("No such pending order");
        orderBookModule.rejectPendingSellOrder(99);
    }

    function testCancelPendingSellOrderBySeller() public {
        _setupSellSender(alice, 30, 0);
        vm.prank(alice); orderBookModule.proposeSellOrder(5, 2, true);

        vm.prank(alice);
        vm.expectEmit(true, true, false, false);
        emit PendingSellOrderCanceled(0, alice);
        orderBookModule.cancelPendingSellOrder(0);

        // Restitution escrow
        assertEq(tokenManager.balanceOfIQS(alice), 30);
        assertEq(tokenManager.balanceOfIQS(owner),  0);
        // Pending vidé
        (,address pendingSeller,,,,) = orderBookModule.PendingSellOrders(0);
        assertEq(pendingSeller, address(0));
    }

    function testCancelSellOrderBySeller() public {
        _setupSellSender(alice, 20, 0);
        vm.prank(alice); orderBookModule.proposeSellOrder(4, 1, true);
        vm.prank(owner); orderBookModule.validatePendingSellOrder(0);

        vm.prank(alice);
        vm.expectEmit(true, true, false, false);
        emit SellOrderCanceled(0, alice);
        orderBookModule.cancelSellOrder(0);

        // Restitution escrow
        assertEq(tokenManager.balanceOfIQS(alice), 20);
        assertEq(tokenManager.balanceOfIQS(owner),  0);
        // SellOrders vidé
        (, address sellerAfter,,,,) = orderBookModule.sellOrders(0);
        assertEq(sellerAfter, address(0));
    }

    function testAdminCancelSellOrder_IQS() public {
        _setupSellSender(alice, 50, 0);
        vm.prank(alice); orderBookModule.proposeSellOrder(10, 5, true);
        vm.prank(owner); orderBookModule.validatePendingSellOrder(0);

        vm.prank(owner);
        vm.expectEmit(true, true, false, false);
        emit SellOrderCanceled(0, alice);
        orderBookModule.adminCancelSellOrder(0);

        // Restitution escrow
        assertEq(tokenManager.balanceOfIQS(alice), 50);
        assertEq(tokenManager.balanceOfIQS(owner),  0);
        // SellOrders vidé
        (,address sellerAfter,,,,) = orderBookModule.sellOrders(0);
        assertEq(sellerAfter, address(0));
    }

    function testAdminCancelSellOrder_OST() public {
        _setupSellSender(alice, 0, 60);
        vm.prank(alice); orderBookModule.proposeSellOrder(15, 2, false);
        vm.prank(owner); orderBookModule.validatePendingSellOrder(0);

        vm.prank(owner);
        vm.expectEmit(true, true, false, false);
        emit SellOrderCanceled(0, alice);
        orderBookModule.adminCancelSellOrder(0);

        // Restitution escrow OST
        assertEq(tokenManager.balanceOfOST(alice), 60);
        assertEq(tokenManager.balanceOfOST(owner),  200000);
    }

    event PendingBuyOrderCreated(uint256 indexed id, address indexed buyer, uint256 amount, uint256 price, bool isIQS, uint256 timestamp);
    event BuyOrderValidated(        uint256 indexed id, address indexed buyer, uint256 amount, uint256 price, bool isIQS, uint256 timestamp);
    event PendingBuyOrderRejected(  uint256 indexed id, address indexed buyer);
    event PendingBuyOrderCanceled(  uint256 indexed id, address indexed buyer);
    event BuyOrderCanceled(uint256 indexed id, address indexed buyer);

    // --- Helper pour le carnet d’ordres d’achat ---
    function _setupBuySender(address user) internal {
        vm.prank(owner);
        accessControl.authorizeAddress(user);
        vm.prank(owner);
        accessControl.addToWhiteList(user);
    }

    function testProposeBuyOrder_IQS() public {
        _setupBuySender(alice);

        vm.prank(alice);
        vm.expectEmit(true, true, false, false);
        emit PendingBuyOrderCreated(0, alice, 12, 4, true, block.timestamp);
        orderBookModule.proposeBuyOrder(12, 4, true);

        (uint256 id, address buyer, uint256 amount, uint256 price, bool isIQS, ) =
            orderBookModule.PendingBuyOrders(0);
        assertEq(id,      0);
        assertEq(buyer,   alice);
        assertEq(amount,  12);
        assertEq(price,   4);
        assertTrue(isIQS);
    }

    function testProposeBuyOrder_OST() public {
        _setupBuySender(bob);

        vm.prank(bob);
        vm.expectEmit(true, true, false, false);
        emit PendingBuyOrderCreated(0, bob, 25, 6, false, block.timestamp);
        orderBookModule.proposeBuyOrder(25, 6, false);

        (, address buyer, uint256 amount, uint256 price, bool isIQS,) =
            orderBookModule.PendingBuyOrders(0);
        assertEq(buyer,  bob);
        assertEq(amount, 25);
        assertEq(price,  6);
        assertFalse(isIQS);
    }

    function testProposeBuyOrderRevertsOnZero() public {
        _setupBuySender(alice);

        vm.prank(alice);
        vm.expectRevert("Amount must be > 0");
        orderBookModule.proposeBuyOrder(0, 5, true);

        vm.prank(alice);
        vm.expectRevert("Price must be > 0");
        orderBookModule.proposeBuyOrder(5, 0, true);
    }

    function testValidatePendingBuyOrder() public {
        _setupBuySender(alice);
        vm.prank(alice); orderBookModule.proposeBuyOrder(8, 2, true);

        vm.prank(owner);
        vm.expectEmit(true, true, false, false);
        emit BuyOrderValidated(0, alice, 8, 2, true, block.timestamp);
        orderBookModule.validatePendingBuyOrder(0);

        (uint256 id, address b, uint256 amt, uint256 p, bool isIQS, ) =
            orderBookModule.buyOrders(0);
        assertEq(id,     0);
        assertEq(b,      alice);
        assertEq(amt,    8);
        assertEq(p,      2);
        assertTrue(isIQS);

        (, address pendingBuyer, , , ,) = orderBookModule.PendingBuyOrders(0);
        assertEq(pendingBuyer, address(0));
    }

    function testValidatePendingBuyOrderRevertsIfNotFound() public {
        vm.prank(owner);
        vm.expectRevert("No such pending order");
        orderBookModule.validatePendingBuyOrder(42);
    }

    function testRejectPendingBuyOrder() public {
        _setupBuySender(bob);
        vm.prank(bob); orderBookModule.proposeBuyOrder(5, 3, false);

        vm.prank(owner);
        vm.expectEmit(true, true, false, false);
        emit PendingBuyOrderRejected(0, bob);
        orderBookModule.rejectPendingBuyOrder(0);

        (, address pendingBuyer, , , ,) = orderBookModule.PendingBuyOrders(0);
        assertEq(pendingBuyer, address(0));
    }

    function testRejectPendingBuyOrderRevertsIfNotFound() public {
        vm.prank(owner);
        vm.expectRevert("No such pending order");
        orderBookModule.rejectPendingBuyOrder(99);
    }

    function testCancelPendingBuyOrderByBuyer() public {
        _setupBuySender(alice);
        vm.prank(alice); orderBookModule.proposeBuyOrder(7, 1, true);

        vm.prank(alice);
        vm.expectEmit(true, true, false, false);
        emit PendingBuyOrderCanceled(0, alice);
        orderBookModule.cancelPendingBuyOrder(0);

        (, address pendingBuyer, , , ,) = orderBookModule.PendingBuyOrders(0);
        assertEq(pendingBuyer, address(0));
    }

    function testCancelBuyOrderByBuyer() public {
        _setupBuySender(bob);
        vm.prank(bob); orderBookModule.proposeBuyOrder(9, 4, false);
        vm.prank(owner); orderBookModule.validatePendingBuyOrder(0);

        vm.prank(bob);
        vm.expectEmit(true, true, false, false);
        emit BuyOrderCanceled(0, bob);
        orderBookModule.cancelBuyOrder(0);

        (, address buyerAfter, , , ,) = orderBookModule.buyOrders(0);
        assertEq(buyerAfter, address(0));
    }

    function testAdminCancelBuyOrder() public {
        _setupBuySender(alice);
        vm.prank(alice); orderBookModule.proposeBuyOrder(6, 3, true);
        vm.prank(owner); orderBookModule.validatePendingBuyOrder(0);

        vm.prank(owner);
        vm.expectEmit(true, true, false, false);
        emit BuyOrderCanceled(0, alice);
        orderBookModule.adminCancelBuyOrder(0);

        (, address buyerAfter, ,,,) = orderBookModule.buyOrders(0);
        assertEq(buyerAfter, address(0));
    }

    function testAdminCancelBuyOrderRevertsIfNotFound() public {
        vm.prank(owner);
        vm.expectRevert("No such order");
        orderBookModule.adminCancelBuyOrder(123);
    }

        // --- Helpers pour exécuter les trades ---
    function _setupSellOrder(address seller, uint256 iqsBalance) internal {
        // Prépare un ordre de vente validé
        _setupSellSender(seller, iqsBalance, 0);
        vm.prank(seller);
        orderBookModule.proposeSellOrder(10, 5, true);
        vm.prank(owner);
        orderBookModule.validatePendingSellOrder(0);
    }

    function _setupBuyOrder(address buyer, uint256 ostBalance) internal {
        // Prépare un ordre d’achat validé
        vm.prank(owner);
        tokenManager.setBalanceForTesting(buyer, 0, ostBalance);
        _setupBuySender(buyer);
        vm.prank(buyer);
        orderBookModule.proposeBuyOrder(8, 3, false);
        vm.prank(owner);
        orderBookModule.validatePendingBuyOrder(0);
    }

    // --- Tests pour OrderSellFill ---
    event TradeExecuted(uint256 indexed id, uint256 indexed sellOrderId, uint256 indexed buyOrderId,
                       address seller, address buyer, uint256 amount, uint256 price, bool isIQS, uint256 timestamp);

    function testOrderSellFillCreatesExecutedTrade() public {
        // 1) Prépare un ordre de vente validé de Alice
        _setupSellOrder(alice, 100);

        // 2) Autorise & whitelist Bob pour qu’il puisse remplir l’ordre
        vm.prank(owner);
        accessControl.authorizeAddress(bob);
        vm.prank(owner);
        accessControl.addToWhiteList(bob);

        // 3) On définit l'événement attendu (pas de prank ici !)
        vm.expectEmit(true, true, false, false);
        emit TradeExecuted(
            0,      // id
            0,      // sellOrderId
            0,      // buyOrderId
            alice,  // seller
            bob,    // buyer
            10,     // amount (tel que proposeSellOrder)
            5,      // price  (tel que proposeSellOrder)
            true,   // isIQS
            block.timestamp
        );

        // 4) Enfin, Bob exécute l’ordre
        vm.prank(bob);
        tradeModule.OrderSellFill(0);

        // 5) Vérifications post-fill
        // - escrows
        assertEq(tokenManager.balanceOfIQS(alice),  90, unicode"Alice a débité 10 IQS");
        assertEq(tokenManager.balanceOfIQS(owner),  10, unicode"Owner détient 10 IQS en escrow");

        // - mapping executedTrades
        (
        uint256 id,
        uint256 sellId,
        uint256 buyId,
        address seller,
        address buyer,
        uint256 amount,
        uint256 price,
        bool    isIQS,
        uint256 ts
        ) = tradeModule.executedTrades(0);

        assertEq(id,       0);
        assertEq(sellId,   0);
        assertEq(buyId,    0);
        assertEq(seller,   alice);
        assertEq(buyer,    bob);
        assertEq(amount,   10);
        assertEq(price,    5);
        assertTrue(isIQS);
        assertEq(ts,       block.timestamp);
    }

    function testOrderSellFillRevertsIfNoOrder() public {
        _setupSellSender(bob, 0, 0);
        vm.prank(bob);
        vm.expectRevert("No such sell order");
        tradeModule.OrderSellFill(999);
    }


    function testOrderSellFillRevertsOnSelfBuy() public {
        _setupSellOrder(alice, 100);
        vm.prank(alice);
        vm.expectRevert("Cannot buy your own order");
        tradeModule.OrderSellFill(0);
    }
    
    function testOrderBuyFillCreatesExecutedTrade_IQS() public {
        // 1) Prépare l’ordre d’achat validé de Bob (isIQS = true)
        vm.prank(owner);
        tokenManager.setBalanceForTesting(bob, 50, 0);
        vm.prank(owner);
        accessControl.authorizeAddress(bob);
        vm.prank(owner);
        accessControl.addToWhiteList(bob);

        vm.prank(bob);
        orderBookModule.proposeBuyOrder(7, 2, true);
        vm.prank(owner);
        orderBookModule.validatePendingBuyOrder(0);

        // 2) Donne à Alice les IQS pour qu’elle puisse remplir l’ordre
        vm.prank(owner);
        tokenManager.setBalanceForTesting(alice, 7, 0);
        vm.prank(owner);
        accessControl.authorizeAddress(alice);
        vm.prank(owner);
        accessControl.addToWhiteList(alice);

        // 3) Prépare l’événement attendu (pas de prank ici !)
        vm.expectEmit(true, true, false, false);
        emit TradeExecuted(
            0,      // id
            0,      // sellOrderId
            0,      // buyOrderId
            alice,  // seller
            bob,    // buyer
            7,      // amount
            2,      // price
            true,   // isIQS
            block.timestamp
        );

        // 4) Enfin, simule Alice qui exécute l’ordre
        vm.prank(alice);
        tradeModule.OrderBuyFill(0);

        // 5) Vérifie l’escrow et le mapping
        assertEq(tokenManager.balanceOfIQS(alice), 0, unicode"Alice doit avoir débité ses IQS");
        assertEq(tokenManager.balanceOfIQS(owner), 7, unicode"Owner doit détenir l’escrow");

        (uint256 id,,,,, uint256 amt, uint256 pr, bool flag,) = tradeModule.executedTrades(0);
        assertEq(id,     0);
        assertEq(amt,    7);
        assertEq(pr,     2);
        assertTrue(flag);
    }

    function testOrderBuyFillRevertsIfNoOrder() public {
        _setupBuySender(alice);
        vm.prank(alice);
        vm.expectRevert("No such buy order");
        tradeModule.OrderBuyFill(42);
    }

    function testOrderBuyFillRevertsOnSelfSell() public {
        _setupBuyOrder(alice, 20);
        vm.prank(alice);
        vm.expectRevert("Cannot sell your own order");
        tradeModule.OrderBuyFill(0);
    }

    function testCalculateTotalCost() public {
        _setupSellOrder(alice, 100);
        _setupSellSender(bob, 0, 0);
        
        vm.prank(bob); tradeModule.OrderSellFill(0);

        // amount=10, price=5, default feeRate=2%, feeBase=10 → 10*5 + 10 = 60
        uint256 total = tradeModule.calculateTotalCost(0);
        assertEq(total, (10 * 5)* (1.02) + 10);
    }

    function testCalculateTotalCostRevertsIfNotFound() public {
        vm.prank(owner);
        vm.expectRevert("No such executed trade");
        tradeModule.calculateTotalCost(123);
    }

    // --- Helpers pour exécuter un sell fill et un buy fill validés ---
    event ExecutedTradeValidated(
        uint256 indexed id,
        uint256 indexed sellOrderId,
        uint256 indexed buyOrderId,
        address seller,
        address buyer,
        uint256 amount,
        uint256 price,
        bool    isIQS,
        uint256 timestamp
    );
    
    event ExecutedTradeRejected(
            uint256 indexed id,
            uint256 indexed sellOrderId,
            uint256 indexed buyOrderId,
            address seller,
            address buyer,
            bool    isIQS,
            uint256 timestamp
        );

    function testValidateExecutedTrade_IQS() public {
        // 1) Prépare un ordre de vente validé puis exécuté (Alice vend 10 IQS à Bob)
        _setupSellOrder(alice, 100);
        // autorise & whitelist Bob pour qu’il puisse remplir
        vm.prank(owner);
        accessControl.authorizeAddress(bob);
        vm.prank(owner);
        accessControl.addToWhiteList(bob);
        // Bob remplit l’ordre
        vm.prank(bob);
        tradeModule.OrderSellFill(0);
        // À ce stade, le contrat détient en escrow 10 IQS
        assertEq(tokenManager.balanceOfIQS(owner), 10);

        // 2) L’admin valide l’exécution
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit ExecutedTradeValidated(
            0,    // id dans validateexecutedTrades
            0,    // sellOrderId
            0,    // buyOrderId
            alice,
            bob,
            10,
            5,
            true,
            block.timestamp
        );
        tradeModule.validateExecutedTrade(0);

        // 3) Vérifie que Bob a bien reçu ses 10 IQS
        assertEq(tokenManager.balanceOfIQS(bob), 10);

        // 4) Vérifie que l’entrée dans executedTrades a été supprimée
        (, , , address clearedSeller, address clearedBuyer, , , , ) =
            tradeModule.executedTrades(0);
        assertEq(clearedSeller, address(0));
        assertEq(clearedBuyer,  address(0));

        // 5) Vérifie que la tranche validée est bien archivées
        (
            uint256 vid,
            uint256 vsellId,
            uint256 vbuyId,
            address vseller,
            address vbuyer,
            uint256 vamount,
            uint256 vprice,
            bool    visIQS,
            uint256 vts
        ) = tradeModule.validateexecutedTrades(0);
        assertEq(vid,       0);
        assertEq(vsellId,   0);
        assertEq(vbuyId,    0);
        assertEq(vseller,   alice);
        assertEq(vbuyer,    bob);
        assertEq(vamount,   10);
        assertEq(vprice,    5);
        assertTrue(visIQS);
        assertEq(vts,       block.timestamp);
    }

    function testValidateExecutedTradeRevertsIfNotFound() public {
        vm.prank(owner);
        vm.expectRevert("No such executed trade");
        tradeModule.validateExecutedTrade(123);
    }

    function testRejectExecutedTrade_IQS() public {
        // 1) Prépare et exécute un trade IQS :
        //    Alice propose un sell order puis Bob l'exécute
        _setupSellOrder(alice, 100);
        vm.prank(owner);
        accessControl.authorizeAddress(bob);
        vm.prank(owner);
        accessControl.addToWhiteList(bob);
        vm.prank(bob);
        tradeModule.OrderSellFill(0);
        // À ce stade, le ownerAddress a 10 IQS en escrow
        assertEq(tokenManager.balanceOfIQS(owner), 10);

        // 2) L’admin rejette l’exécution
        vm.prank(owner);
        vm.expectEmit(true, true, false, false);
        emit ExecutedTradeRejected(
            0,    // executedTradeId
            0,    // sellOrderId
            0,    // buyOrderId
            alice,
            bob,
            true,
            block.timestamp
        );
        tradeModule.rejectExecutedTrade(0);

        // 3) Vérifie que l’escrow est restitué à Alice
        assertEq(tokenManager.balanceOfIQS(alice), 100);

        // 4) La structure executedTrades[0] doit avoir été supprimée
        (
            uint256 id,
            ,
            ,
            address sellerAfter,
            address buyerAfter,
            ,
            ,
            ,
            
        ) = tradeModule.executedTrades(0);

        // seller et buyer doivent être à l’adresse zero
        assertEq(sellerAfter, address(0));
        assertEq(buyerAfter,  address(0));
        // les autres champs ne sont plus définis, mais on peut quand même vérifier id==0
        assertEq(id, 0);
    }

    function testRejectExecutedTradeRevertsIfNotFound() public {
        vm.prank(owner);
        vm.expectRevert("No such executed trade");
        tradeModule.rejectExecutedTrade(123);
    }

    function testGetValidatedP2PTransactions_Empty() public view{
        // owner est déjà validé dans le constructeur, pas besoin de ré-appeler authorize/whitelist
        (
            uint256[] memory ids,
            address[] memory froms,
            address[] memory tos,
            uint256[] memory amounts,
            uint256[] memory prices,
            bool[]    memory flags,
            uint256[] memory times
        ) = p2pModule.getValidatedP2PTransactions();

        assertEq(ids.length,     0);
        assertEq(froms.length,   0);
        assertEq(tos.length,     0);
        assertEq(amounts.length, 0);
        assertEq(prices.length,  0);
        assertEq(flags.length,   0);
        assertEq(times.length,   0);
    }

    function testPendingP2PCost_RevertsIfNotFound() public {
        // pendingP2PCost n'a pas de modifier, pas d'authorize/whitelist nécessaire
        vm.expectRevert("No such pending P2P");
        p2pModule.pendingP2PCost(999);
    }

    
    
    
    
    // --- Conversion des IQS en OST ---
    event IQSToOSTConversionRequested(uint256 requestId, address indexed user, uint256 amount);
    event IQSToOSTConversionApproved(uint256 requestId, address indexed user, uint256 amount);
    event IQSToOSTConversionRejected(uint256 requestId, address indexed user);
    event IQSToOSTConversionCancelled(uint256 requestId, address indexed user);

    function _setupValidSender(address user, uint256 balance) internal {
        vm.prank(owner);
        tokenManager.setBalanceForTesting(user, balance, 0);
        vm.prank(owner);
        accessControl.authorizeAddress(user);
        vm.prank(owner);
        accessControl.addToWhiteList(user);
    }

    function testRequestConversionEmitsEventAndStores() public {
        _setupValidSender(alice, 100);
        vm.prank(alice);
        vm.expectEmit(true, true, false, false);
        emit IQSToOSTConversionRequested(0, alice, 50);
        conversionModule.requestIQSToOSTConversion(50);
        (address user, uint256 amt) = conversionModule.pendingIQSToOSTConversions(0);
        assertEq(user, alice);
        assertEq(amt, 50);
        assertEq(conversionModule.iqstoostConversionRequestCount(), 1);
    }

    function testRequestConversionRevertsZeroAmount() public {
        _setupValidSender(alice, 100);
        vm.prank(alice);
        vm.expectRevert("Amount must be greater than zero");
        conversionModule.requestIQSToOSTConversion(0);
    }

    function testRequestConversionRevertsInsufficientBalance() public {
        _setupValidSender(alice, 10);
        vm.prank(alice);
        vm.expectRevert("Insufficient IQS balance");
        conversionModule.requestIQSToOSTConversion(20);
    }

    function testRequestConversionRevertsIfNotValidSender() public {
        // alice not authorized/whitelisted
        vm.prank(alice);
        vm.expectRevert(); // onlyValidSender revert (either whitelist or auth)
        conversionModule.requestIQSToOSTConversion(1);
    }

    function testApproveConversionRevertsIfRequestNotFound() public {
        vm.prank(owner);
        vm.expectRevert("Conversion request not found");
        conversionModule.approveIQSToOSTConversion(123);
    }

    function testApproveConversionRevertsOnInsufficientAtApproval() public {
        _setupValidSender(alice, 20);
        vm.prank(alice);
        conversionModule.requestIQSToOSTConversion(20);
        // Deplete alice balance
        vm.prank(owner);
        tokenManager.setBalanceForTesting(alice, 10, 0);

        vm.prank(owner);
        vm.expectRevert("Insufficient IQS balance at approval");
        conversionModule.approveIQSToOSTConversion(0);
    }

    function testRejectConversionEmitsAndDeletes() public {
        _setupValidSender(alice, 50);
        vm.prank(alice);
        conversionModule.requestIQSToOSTConversion(20);

        vm.prank(owner);
        vm.expectEmit(true, true, false, false);
        emit IQSToOSTConversionRejected(0, alice);
        conversionModule.rejectIQSToOSTConversion(0);

        (address p, ) = conversionModule.pendingIQSToOSTConversions(0);
        assertEq(p, address(0));
    }

    function testRejectConversionRevertsIfNotFound() public {
        vm.prank(owner);
        vm.expectRevert("Conversion request not found");
        conversionModule.rejectIQSToOSTConversion(1);
    }

    function testCancelConversionEmitsAndDeletes() public {
        _setupValidSender(alice, 40);
        vm.prank(alice);
        conversionModule.requestIQSToOSTConversion(15);

        vm.prank(alice);
        vm.expectEmit(true, true, false, false);
        emit IQSToOSTConversionCancelled(0, alice);
        conversionModule.cancelIQSToOSTConversion(0);

        (address p, ) = conversionModule.pendingIQSToOSTConversions(0);
        assertEq(p, address(0));
    }


    function testCancelConversionRevertsIfNotRequester() public {
        _setupValidSender(alice, 40);
        vm.prank(alice);
        conversionModule.requestIQSToOSTConversion(15);

        vm.prank(bob);
        vm.expectRevert("Only requester can cancel");
        conversionModule.cancelIQSToOSTConversion(0);
    }

    function testCancelConversionRevertsIfNotFound() public {
        vm.prank(alice);
        vm.expectRevert("Conversion request not found");
        conversionModule.cancelIQSToOSTConversion(5);
    }




    // --- Minage des IQS ---
    function testMintZeroAmountReverts() public {
        vm.prank(owner);
        vm.expectRevert("Amount must be greater than zero");
        tokenManager.mintIQS(0);
    }

    function testMintExceedsMaxSupplyReverts() public {
        uint256 tooMuch = tokenManager.maxSupplyIQS() + 1;
        vm.prank(owner);
        vm.expectRevert("Exceeds max supply");
        tokenManager.mintIQS(tooMuch);
    }

    function testMintExceedsTreasuryLimitReverts() public {
        // La limite de trésorerie est maxSupplyIQS/10
        uint256 limit = tokenManager.iqosysTreasuryShareLimit();
        vm.prank(owner);
        vm.expectRevert("Exceeds treasury limit");
        tokenManager.mintIQS(limit + 1);
    }

    function testMintWithinLimits() public {
        uint256 amount = 50_000;
        // Sanity-check de la limite
        assertLt(amount, tokenManager.iqosysTreasuryShareLimit());

        vm.prank(owner);
        tokenManager.mintIQS(amount);

        // Le owner doit avoir reçu `amount`
        assertEq(tokenManager.balanceOfIQS(owner), amount, "Owner IQS balance incorrect");
        // totalSupplyIQS doit être exactement `amount`
        assertEq(tokenManager.totalSupplyIQS(), amount, "TotalSupplyIQS incorrect");
    }




     // --- Changement des taux par le owner du smart contract ---
    event TransactionFeeRateUpdated(uint256 newRate);
    event TransactionFeeUpdated(uint256 newFee);

    function testSetConversionRateUpdatesValue() public {
        uint256 newRate = 42;
        vm.prank(owner);
        tokenManager.setConversionRate(newRate);
        assertEq(tokenManager.conversionRateGasToEuros(), newRate, "conversionRate not updated");
    }

    function testSetTransactionFeeRateExceedsReverts() public {
        vm.prank(owner);
        vm.expectRevert("Fee rate cannot exceed 10%");
        tokenManager.setTransactionFeeRate(11);
    }

    function testSetTransactionFeeRateEmitsAndUpdates() public {
        uint256 newRate = 8;
        vm.prank(owner);
        vm.expectEmit(/* topic1 */ false, /* topic2 */ false, /* topic3 */ false, /* data */ true);
        emit TransactionFeeRateUpdated(newRate);
        tokenManager.setTransactionFeeRate(newRate);

        assertEq(tokenManager.transactionFeeRate(), newRate, "transactionFeeRate not updated");
    }

    function testSetTransactionFeeZeroReverts() public {
        vm.prank(owner);
        vm.expectRevert("Transaction fee must be greater than zero");
        tokenManager.setTransactionFee(0);
    }

    function testSetTransactionFeeEmitsAndUpdates() public {
        uint256 newFee = 25;
        vm.prank(owner);
        vm.expectEmit(false, false, false, true);
        emit TransactionFeeUpdated(newFee);
        tokenManager.setTransactionFee(newFee);

        assertEq(tokenManager.transactionFee(), newFee, "transactionFee not updated");
    }




    // --- Sécurité : création d'un hash et vérification ---
    event HashAdded(bytes32 indexed hash);

    function testAddValidHashEmitsAndSets() public {
        bytes32 h = keccak256("bar");
        vm.prank(owner);
        vm.expectEmit(/* topic1 */ true, /* topic2 */ false, /* topic3 */ false, /* data */ false);
        emit HashAdded(h);
        hashRegistry.addValidHash(h);

        assertTrue(hashRegistry.isHashValid(h), "Hash should be marked valid");
    }

    function testAddSameHashReverts() public {
        bytes32 h = keccak256("baz");
        vm.prank(owner);
        hashRegistry.addValidHash(h);

        vm.prank(owner);
        vm.expectRevert("Hash already added");
        hashRegistry.addValidHash(h);
    }

    function testRemoveValidHashClearsFlag() public {
        bytes32 h = keccak256("quux");
        vm.prank(owner);
        hashRegistry.addValidHash(h);

        vm.prank(owner);
        hashRegistry.removeValidHash(h);
        assertFalse(hashRegistry.isHashValid(h), "Hash should no longer be valid");
    }

    function testRemoveNonexistentHashReverts() public {
        bytes32 h = keccak256("corge");
        vm.prank(owner);
        vm.expectRevert("Hash not found");
        hashRegistry.removeValidHash(h);
    }

    function testIsHashValidView() public {
        bytes32 h1 = keccak256("grault");
        bytes32 h2 = keccak256("garply");
        // h1 non ajouté -> false
        assertFalse(hashRegistry.isHashValid(h1));
        // on ajoute h2
        vm.prank(owner);
        hashRegistry.addValidHash(h2);
        assertTrue(hashRegistry.isHashValid(h2));
    }


    // --- DAO ---
    function testCreateAndReadPoll() public {
        // Prépare les options
        string[] memory options = new string[](2);
        options[0] = "Yes";
        options[1] = "No";

        uint256 duration = 1 hours;
        // uint256 beforeTs = block.timestamp;
        // Le owner (address(this)) crée un sondage
        vm.prank(owner);
        dao.createPoll("Do you agree?", options, duration);

    }

    function testCreatePoll_NotOwnerReverts() public {
        // Essayer de créer un sondage avec un compte non-owner
        vm.prank(voter1);
        vm.expectRevert();
        string[] memory options = new string[](0);
        dao.createPoll("Q", options, 100);
    }

    function testVoteAndResults() public {
        // On crée un poll
        string[] memory opts = new string[](2);
        opts[0] = "A"; opts[1] = "B";
        vm.prank(owner);

        dao.createPoll("Pick A or B", opts, 100);

        // voter1 vote pour A (optionIndex = 0)
        vm.prank(voter1);
        dao.vote(0, 0);
        // voter2 vote pour B (optionIndex = 1)
        vm.prank(voter2);
        dao.vote(0, 1);

        // On récupère les résultats
        (string[] memory labels, uint256[] memory results) = dao.getResults(0);

        // voter1 a 100 IQS, voter2 en a 50
        assertEq(results[0], 100, "Option A doit avoir 100 voix");
        assertEq(results[1],  50, "Option B doit avoir 50 voix");
        assertEq(labels.length, 2);
        assertEq(labels[0], "A");
        assertEq(labels[1], "B");
    }

    function testVote_NotHolderReverts() public {
        // On crée un poll
        string[] memory opts = new string[](2);
        opts[0] = "X"; opts[1] = "Y";
        vm.prank(owner);

        dao.createPoll("X vs Y", opts, 100);

        // nonHolder n'a pas de IQS
        vm.prank(nonHolder);
        vm.expectRevert("Must hold >0 IQS to vote");
        dao.vote(0, 0);
    }

    function testVote_TwiceReverts() public {
        // On crée un poll
        string[] memory opts = new string[](2);
        opts[0] = "1"; opts[1] = "2";
        vm.prank(owner);
        dao.createPoll("1 or 2?", opts, 100);

        // voter1 vote une première fois
        vm.prank(voter1);
        dao.vote(0, 1);

        // Essai de revote
        vm.prank(voter1);
        vm.expectRevert("Already voted");
        dao.vote(0, 0);
    }

    function testVote_InvalidOptionReverts() public {
        // On crée un poll
        string[] memory opts = new string[](2);
        opts[0] = "foo"; opts[1] = "bar";
        vm.prank(owner);
        dao.createPoll("foo vs bar", opts, 100);

        // voter2 tente d'utiliser un index hors limite
        vm.prank(voter2);
        vm.expectRevert("Invalid option");
        dao.vote(0, 2);
    }

    function testVote_PollNotStartedReverts() public {
        // 1) Avance le time pour éviter un sous-flow initial
        vm.warp(100);

        // 2) Prépare et crée le sondage (startTime = 100)
        string[] memory options = new string[](2);
        options[0] = "f";
        options[1] = "t";
        vm.prank(owner);
        dao.createPoll("ft?", options, 1);

        // 3) Récupère le startTime via le getter public polls()
        (
            ,             // question
            uint256 startTime,
            ,             // endTime
            bool     exists
        ) = dao.polls(0);
        assertTrue(exists, "Le poll n'existe pas");

        // 4) Warp juste avant le démarrage
        vm.warp(startTime - 1);

        // 5) On devrait revert avec "Poll not started"
        vm.prank(voter1);
        vm.expectRevert("Poll not started");
        dao.vote(0, 0);
    }

    function testVote_PollEndedReverts() public {
        // On crée un poll
        string[] memory opts = new string[](2);
        opts[0] = "up"; opts[1] = "down";
        vm.prank(owner);
        dao.createPoll("up/down", opts, 1);
        // On warp au-delà de endTime
        vm.warp(block.timestamp + 2);
        vm.prank(voter1);
        vm.expectRevert("Poll ended");
        dao.vote(0, 0);
    }

    function testGetResults_NonexistentPollReverts() public {
        vm.expectRevert("Poll does not exist");
        dao.getResults(42);
    }

    // --- NOUVEAUX TESTS : FLUX FIAT (ADMIN) ---

    function testAdminValidateP2PTransaction() public {
        _setupP2PUser(alice, 50, 0); // Alice a 50 IQS
        _setupP2PUser(bob, 0, 0);

        // Alice propose 20 IQS à Bob
        vm.prank(alice);
        p2pModule.proposeP2PTransaction(bob, 20, 5, true);

        // L'Admin valide DIRECTEMENT sans attendre que Bob confirme
        vm.prank(owner);
        p2pModule.adminValidateP2PTransaction(0);

        // Vérification : Bob a bien reçu les tokens
        assertEq(tokenManager.balanceOfIQS(bob), 20, unicode"Bob aurait dû recevoir les 20 IQS via l'Admin");
        assertEq(tokenManager.balanceOfIQS(owner), 0, unicode"L'escrow devrait être vide");
    }

    function testAdminOrderSellFill() public {
        _setupSellOrder(alice, 100); // Alice vend 10 IQS (prix 5)
        
        // Setup Bob (l'acheteur FIAT)
        vm.prank(owner); accessControl.authorizeAddress(bob);
        vm.prank(owner); accessControl.addToWhiteList(bob);

        // L'admin execute le Fill AU NOM de Bob
        vm.prank(owner);
        tradeModule.adminOrderSellFill(0, bob);

        // Vérification : L'ordre a été exécuté avec Bob comme acheteur (et non l'admin)
        (,,,, address executedBuyer,,,,) = tradeModule.executedTrades(0);
        assertEq(executedBuyer, bob, unicode"L'acheteur enregistré doit être Bob, pas l'Admin");
    }

    function testAdminOrderBuyFill() public {
        _setupBuyOrder(bob, 50); // Bob veut acheter (Escrow de 50 OST)
        
        // Setup Alice (le vendeur FIAT)
        vm.prank(owner); tokenManager.setBalanceForTesting(alice, 0, 10);
        vm.prank(owner); accessControl.authorizeAddress(alice);
        vm.prank(owner); accessControl.addToWhiteList(alice);

        // L'admin execute le Fill AU NOM d'Alice
        vm.prank(owner);
        tradeModule.adminOrderBuyFill(0, alice);

        // Vérification : L'ordre a été exécuté avec Alice comme vendeur
        (,,, address executedSeller,,,,,) = tradeModule.executedTrades(0);
        assertEq(executedSeller, alice, unicode"Le vendeur enregistré doit être Alice, pas l'Admin");
    }
    

    

}
