// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/AccessControl.sol";
import "../src/AdminMultisig.sol";
import "../src/TokenManager.sol";
import "../src/OSTTransferModule.sol";
import "../src/ConversionModule.sol";
import "../src/BSARegistry.sol";
import "../src/HashRegistry.sol";
import "../src/GovernanceRegistry.sol";
import "../src/ValuationAnchor.sol";
import "../src/EmergencyController.sol";
import "../src/HolderMigrationController.sol";
import "../src/TokenOperatorController.sol";
import "../src/IQOS.sol";

contract DeployIQOS is Script {
    function run() external {
        uint256 key = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(key);
        address safeOwner = vm.envAddress("OWNER_SAFE");
        address signer1 = vm.envAddress("ADMIN_SIGNER_1");
        address signer2 = vm.envAddress("ADMIN_SIGNER_2");
        address signer3 = vm.envAddress("ADMIN_SIGNER_3");

        require(safeOwner != address(0), "Invalid OWNER_SAFE");
        require(safeOwner != deployerAddress, "Safe owner must differ from deployer");
        require(signer1 != address(0), "Invalid ADMIN_SIGNER_1");
        require(signer2 != address(0), "Invalid ADMIN_SIGNER_2");
        require(signer3 != address(0), "Invalid ADMIN_SIGNER_3");
        require(signer1 != signer2, "Duplicate signer 1/2");
        require(signer1 != signer3, "Duplicate signer 1/3");
        require(signer2 != signer3, "Duplicate signer 2/3");

        // H-1: the deployment EOA must not remain a standing operational signer.
        require(signer1 != deployerAddress, "Signer 1 must differ from deployer");
        require(signer2 != deployerAddress, "Signer 2 must differ from deployer");
        require(signer3 != deployerAddress, "Signer 3 must differ from deployer");

        address[] memory signers = new address[](3);
        signers[0] = signer1;
        signers[1] = signer2;
        signers[2] = signer3;

        vm.startBroadcast(key);

        AccessControl ac = new AccessControl(deployerAddress);
        if (!ac.isAdmin(signer1)) {
            ac.addAdmin(signer1);
        }
        if (!ac.isAdmin(signer2)) {
            ac.addAdmin(signer2);
        }
        if (!ac.isAdmin(signer3)) {
            ac.addAdmin(signer3);
        }

        require(ac.isAdmin(signer1), "Signer 1 is not admin");
        require(ac.isAdmin(signer2), "Signer 2 is not admin");
        require(ac.isAdmin(signer3), "Signer 3 is not admin");

        AdminMultisig adminMultisig = new AdminMultisig(address(ac), signers, 2);

        // One-time binding: AdminMultisig becomes the only controller that can
        // atomically move admin rights during signer replacement.
        ac.setAdminSignerController(address(adminMultisig));
        require(ac.adminSignerController() == address(adminMultisig), "Admin signer controller missing");

        TokenManager tm = new TokenManager(address(ac));

        // TokenManager needs account-management calls during wallet migration, not blanket admin.
        ac.setRole(ac.ROLE_ACCOUNT_MANAGER(), address(tm), true);

        OSTTransferModule ostTransferModule = new OSTTransferModule(address(ac), address(tm), address(adminMultisig));

        BSARegistry bsaRegistry = new BSARegistry(address(ac), address(tm), address(adminMultisig));

        ConversionModule cm = new ConversionModule(
            address(ac),
            address(tm),
            address(adminMultisig),
            address(bsaRegistry)
        );

        HashRegistry hr = new HashRegistry(address(ac));

        ValuationAnchor valuationAnchor = new ValuationAnchor(address(ac), address(adminMultisig), address(hr));
        ac.setRole(ac.ROLE_ANCHOR(), address(valuationAnchor), true);

        GovernanceRegistry gr = new GovernanceRegistry(address(ac), address(hr), address(adminMultisig));
        ac.setRole(ac.ROLE_ANCHOR(), address(gr), true);

        EmergencyController emergencyController = new EmergencyController(
            address(ac),
            address(adminMultisig),
            address(tm),
            address(bsaRegistry),
            address(cm),
            address(ostTransferModule),
            address(valuationAnchor),
            address(gr)
        );
        ac.setRole(ac.ROLE_EMERGENCY(), address(emergencyController), true);

        HolderMigrationController holderMigrationController = new HolderMigrationController(
            address(ac),
            address(adminMultisig),
            address(tm),
            address(bsaRegistry)
        );

        // Dedicated controller allowlists in BSARegistry and TokenManager are enough.
        // HolderMigrationController does not need any generic AccessControl role.
        // H-7: the same holder migration controller moves BSA ownership and token balances.
        bsaRegistry.setHolderMigrationController(address(holderMigrationController));

        // C-1: one-time wallet migration controller bootstrap.
        tm.setWalletMigrationController(address(holderMigrationController));

        TokenOperatorController tokenOperatorController = new TokenOperatorController(
            address(ac),
            address(adminMultisig),
            address(tm)
        );

        // Bootstrap token operators before locking TokenManager behind TokenOperatorController.
        tm.setTokenOperator(address(ostTransferModule), true);

        // M-6 compatibility: bind custodial OST escrow before transfers can occur.
        tm.setOSTEscrowAddress(address(ostTransferModule));
        require(tm.ostEscrowAddress() == address(ostTransferModule), "OST escrow binding missing");
        tm.setTokenOperator(address(cm), true);
        tm.setTokenOperator(address(bsaRegistry), true);
        tm.setTokenOperatorController(address(tokenOperatorController));

        IQOS core = new IQOS(
            address(ac),
            address(tm),
            address(ostTransferModule),
            address(cm),
            address(hr),
            address(adminMultisig),
            address(bsaRegistry),
            address(valuationAnchor),
            address(gr),
            address(emergencyController),
            address(holderMigrationController),
            address(tokenOperatorController)
        );

        // Register every multisig action consumer before locking bootstrap.
        adminMultisig.setActionConsumer(address(tm), true);
        adminMultisig.setActionConsumer(address(bsaRegistry), true);
        adminMultisig.setActionConsumer(address(cm), true);
        adminMultisig.setActionConsumer(address(valuationAnchor), true);
        adminMultisig.setActionConsumer(address(gr), true);
        adminMultisig.setActionConsumer(address(holderMigrationController), true);
        adminMultisig.setActionConsumer(address(tokenOperatorController), true);
        adminMultisig.setActionConsumer(address(emergencyController), true);
        adminMultisig.setActionConsumer(address(ostTransferModule), true);
        bsaRegistry.setConversionModule(address(cm));
        adminMultisig.lockActionConsumerBootstrap();

        // H-1: remove deployment EOA operational privileges before proposing Safe ownership.
        if (ac.isAuthorized(deployerAddress)) {
            ac.revokeAuthorization(deployerAddress);
        }
        if (ac.isWhiteListed(deployerAddress)) {
            ac.removeFromWhiteList(deployerAddress);
        }
        if (ac.isAdmin(deployerAddress)) {
            ac.removeAdmin(deployerAddress);
        }
        require(!ac.isAdmin(address(tm)), "TokenManager must not be admin");
        require(!ac.isAdmin(address(valuationAnchor)), "ValuationAnchor must not be admin");
        require(!ac.isAdmin(address(gr)), "GovernanceRegistry must not be admin");
        require(!ac.isAdmin(address(emergencyController)), "EmergencyController must not be admin");
        require(!ac.isAdmin(address(holderMigrationController)), "HolderMigrationController must not be admin");
        require(ac.hasRole(ac.ROLE_ACCOUNT_MANAGER(), address(tm)), "TokenManager role missing");
        require(ac.hasRole(ac.ROLE_ANCHOR(), address(valuationAnchor)), "Valuation anchor role missing");
        require(ac.hasRole(ac.ROLE_ANCHOR(), address(gr)), "Governance anchor role missing");
        require(adminMultisig.isActionConsumer(address(gr)), "Governance action consumer missing");
        require(adminMultisig.isActionConsumer(address(tm)), "Genesis registration action consumer missing");
        require(ac.hasRole(ac.ROLE_EMERGENCY(), address(emergencyController)), "Emergency role missing");

        ac.transferOwnership(safeOwner);
        require(ac.pendingOwner() == safeOwner, "Safe ownership transfer not initiated");
        require(!ac.isAdmin(deployerAddress), "Deployer must not remain admin");
        require(!ac.isAuthorized(deployerAddress), "Deployer must not remain authorized");
        require(!ac.isWhiteListed(deployerAddress), "Deployer must not remain whitelisted");

        console.log("------------------------------------------------");
        console.log("IQOS core deployed at          :", address(core));
        console.log("AccessControl deployed at      :", address(ac));
        console.log("AdminMultisig deployed at      :", address(adminMultisig));
        console.log("TokenManager deployed at       :", address(tm));
        console.log("OSTTransferModule deployed at  :", address(ostTransferModule));
        console.log("ConversionModule deployed at   :", address(cm));
        console.log("BSARegistry deployed at        :", address(bsaRegistry));
        console.log("HashRegistry deployed at       :", address(hr));
        console.log("GovernanceRegistry deployed at :", address(gr));
        console.log("ValuationAnchor deployed at    :", address(valuationAnchor));
        console.log("EmergencyController deployed at:", address(emergencyController));
        console.log("HolderMigrationController at   :", address(holderMigrationController));
        console.log("TokenOperatorController at     :", address(tokenOperatorController));

        console.log("------------------------------------------------");
        console.log("Admin signer 1                 :", signer1);
        console.log("Admin signer 2                 :", signer2);
        console.log("Admin signer 3                 :", signer3);
        console.log("Required signatures            :", uint256(2));
        console.log("Pending AccessControl owner    :", safeOwner);

        console.log("------------------------------------------------");

        vm.stopBroadcast();
    }
}
