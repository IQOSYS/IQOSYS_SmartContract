// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";

import "../src/AccessControl.sol";
import "../src/TokenManager.sol";
import "../src/OrderBookModule.sol";
import "../src/ConversionModule.sol";
import "../src/HashRegistry.sol";
import "../src/GovernanceRegistry.sol";
import "../src/IQOS.sol";

contract DeployIQOS is Script {
    function run() external {
        uint256 key = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(key);

        vm.startBroadcast(key);

        // ---------------------------------------------------------------------
        // Access control
        // ---------------------------------------------------------------------

        AccessControl ac =
            new AccessControl(
                deployerAddress
            );

        // ---------------------------------------------------------------------
        // Token layer
        // ---------------------------------------------------------------------

        TokenManager tm =
            new TokenManager(
                address(ac)
            );
        // Needed for wallet migration.
        // TokenManager must be allowed to whitelist the new wallet,
        // remove the old wallet from whitelist and freeze the old wallet.
        ac.addAdmin(address(tm));
        // ---------------------------------------------------------------------
        // Trading / settlement modules
        // ---------------------------------------------------------------------

        OrderBookModule ob =
            new OrderBookModule(
                address(ac),
                address(tm)
            );

        ConversionModule cm =
            new ConversionModule(
                address(ac),
                address(tm)
            );

        // ---------------------------------------------------------------------
        // Registry modules
        // ---------------------------------------------------------------------

        HashRegistry hr =
            new HashRegistry(
                deployerAddress,
                address(ac)
            );

        GovernanceRegistry gr =
            new GovernanceRegistry(
                address(ac)
            );

        // ---------------------------------------------------------------------
        // Core facade
        // ---------------------------------------------------------------------

        IQOS core =
            new IQOS(
                address(ac),
                address(tm),
                address(ob),
                address(cm),
                address(hr)
            );

        // ---------------------------------------------------------------------
        // Token operators
        // ---------------------------------------------------------------------

        tm.setTokenOperator(
            address(ob),
            true
        );

        tm.setTokenOperator(
            address(cm),
            true
        );
        // ---------------------------------------------------------------------
        // Initial IQS supply
        // ---------------------------------------------------------------------

        tm.mintIQS(
            1_000_000
        );

        // ---------------------------------------------------------------------
        // Deployment addresses
        // ---------------------------------------------------------------------

        console.log("------------------------------------------------");
        console.log("IQOS core deployed at          :", address(core));
        console.log("AccessControl deployed at      :", address(ac));
        console.log("TokenManager deployed at       :", address(tm));
        console.log("OrderBookModule deployed at    :", address(ob));
        console.log("ConversionModule deployed at   :", address(cm));
        console.log("HashRegistry deployed at       :", address(hr));
        console.log("GovernanceRegistry deployed at :", address(gr));
        console.log("------------------------------------------------");

        vm.stopBroadcast();
    }
}