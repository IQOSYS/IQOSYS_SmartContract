// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./AccessControl.sol";
import "./TokenManager.sol";
import "./OSTTransferModule.sol";
import "./ConversionModule.sol";
import "./HashRegistry.sol";
import "./AdminMultisig.sol";
import "./BSARegistry.sol";
import "./ValuationAnchor.sol";
import "./GovernanceRegistry.sol";
import "./EmergencyController.sol";
import "./HolderMigrationController.sol";
import "./TokenOperatorController.sol";

/// @title IQOS Core
/// @notice Main aggregator contract referencing the deployed IQOS AMF modules.
/// @dev This contract does not execute business logic. It is a registry/entry point for deployed modules.
contract IQOS {
    AccessControl public accessControl;
    TokenManager public tokenManager;
    OSTTransferModule public ostTransferModule;
    ConversionModule public conversionModule;
    HashRegistry public hashRegistry;
    AdminMultisig public adminMultisig;
    BSARegistry public bsaRegistry;
    ValuationAnchor public valuationAnchor;
    GovernanceRegistry public governanceRegistry;
    EmergencyController public emergencyController;
    HolderMigrationController public holderMigrationController;
    TokenOperatorController public tokenOperatorController;

    constructor(
        address _accessControl,
        address _tokenManager,
        address _ostTransferModule,
        address _conversionModule,
        address _hashRegistry,
        address _adminMultisig,
        address _bsaRegistry,
        address _valuationAnchor,
        address _governanceRegistry,
        address _emergencyController,
        address _holderMigrationController,
        address _tokenOperatorController
    ) {
        require(_accessControl != address(0), "Invalid access control");
        require(_tokenManager != address(0), "Invalid token manager");
        require(_ostTransferModule != address(0), "Invalid OST transfer module");
        require(_conversionModule != address(0), "Invalid conversion module");
        require(_hashRegistry != address(0), "Invalid hash registry");
        require(_adminMultisig != address(0), "Invalid admin multisig");
        require(_bsaRegistry != address(0), "Invalid BSA registry");
        require(_valuationAnchor != address(0), "Invalid valuation anchor");
        require(_governanceRegistry != address(0), "Invalid governance registry");
        require(_emergencyController != address(0), "Invalid emergency controller");
        require(_holderMigrationController != address(0), "Invalid holder migration controller");
        require(_tokenOperatorController != address(0), "Invalid token operator controller");

        accessControl = AccessControl(_accessControl);
        tokenManager = TokenManager(_tokenManager);
        ostTransferModule = OSTTransferModule(_ostTransferModule);
        conversionModule = ConversionModule(_conversionModule);
        hashRegistry = HashRegistry(_hashRegistry);
        adminMultisig = AdminMultisig(_adminMultisig);
        bsaRegistry = BSARegistry(_bsaRegistry);
        valuationAnchor = ValuationAnchor(_valuationAnchor);
        governanceRegistry = GovernanceRegistry(_governanceRegistry);
        emergencyController = EmergencyController(_emergencyController);
        holderMigrationController = HolderMigrationController(_holderMigrationController);
        tokenOperatorController = TokenOperatorController(_tokenOperatorController);
    }
}