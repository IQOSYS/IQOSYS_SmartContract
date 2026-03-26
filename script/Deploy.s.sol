// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
// 1. Import du MinimalForwarder d'OpenZeppelin
import "@openzeppelin/contracts/metatx/ERC2771Forwarder.sol";

import "../src/AccessControl.sol";
import "../src/TokenManager.sol";
import "../src/P2PModule.sol";
import "../src/OrderBookModule.sol";
import "../src/TradeModule.sol";
import "../src/ConversionModule.sol";
import "../src/HashRegistry.sol";
import "../src/DAO.sol";
import "../src/IQOS.sol";

contract DeployIQOS is Script {
    function run() external {

        uint256 key = vm.envUint("PRIVATE_KEY");
        // On récupère l'adresse associée à la clé privée pour l'utiliser comme owner initial
        address deployerAddress = vm.addr(key);
        
        vm.startBroadcast(key);

        // 0) Déployer le Trusted Forwarder
        ERC2771Forwarder forwarder = new ERC2771Forwarder("IQOSTrustedForwarder");
        console.log("Trusted Forwarder deployed at:", address(forwarder));

        // 1) Déploiement modulaire (avec l'adresse du forwarder ajoutée à la fin)

        // AccessControl(initialOwner, forwarder)
        AccessControl ac = new AccessControl(deployerAddress, address(forwarder));
        
        // TokenManager(accessControl, forwarder)
        TokenManager tm  = new TokenManager(address(ac), address(forwarder));
        
        // P2PModule(accessControl, tokenManager, forwarder)
        P2PModule p2p = new P2PModule(address(ac), address(tm), address(forwarder));
        
        // OrderBookModule(accessControl, tokenManager, forwarder)
        OrderBookModule ob  = new OrderBookModule(address(ac), address(tm), address(forwarder));
        
        // TradeModule(accessControl, tokenManager, orderBook, forwarder)
        TradeModule tr  = new TradeModule(address(ac), address(tm), address(ob), address(forwarder));
        
        // ConversionModule(accessControl, tokenManager, forwarder)
        ConversionModule cm  = new ConversionModule(address(ac), address(tm), address(forwarder));
        ac.addAdmin(address(cm)); // Permet au module de conversion d'être admin pour gérer les conversions
        
        // HashRegistry(initialOwner, forwarder, accessControl)
        HashRegistry hr  = new HashRegistry(deployerAddress, address(forwarder), address(ac)); // HashRegistry a besoin d'être admin pour gérer les hashes valides
        
        // DAO(tokenManager, initialOwner, forwarder)
        DAO dao = new DAO(address(tm), deployerAddress, address(forwarder));

        // 2) Core « léger » (Pas de changement ici, il prend juste les adresses)
        IQOS core = new IQOS(
            address(ac),
            address(tm),
            address(p2p),
            address(ob),
            address(tr),
            address(cm),
            address(hr),
            address(dao)
        );

        console.log("Trusted Forwarder deployed at:", address(forwarder));
        console.log("------------------------------------------------");
        console.log("IQOS core deployed at      :", address(core));
        console.log("AccessControl deployed at  :", address(ac));
        console.log("TokenManager deployed at   :", address(tm));
        console.log("P2PModule deployed at      :", address(p2p));
        console.log("OrderBookModule deployed at:", address(ob));
        console.log("TradeModule deployed at    :", address(tr));
        console.log("ConversionModule deployed a:", address(cm));
        console.log("HashRegistry deployed at   :", address(hr));
        console.log("DAO deployed at            :", address(dao));
        console.log("------------------------------------------------");

        vm.stopBroadcast();
    }
}