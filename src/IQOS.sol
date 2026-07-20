// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./AccessControl.sol";
import "./TokenManager.sol";
import "./OrderBookModule.sol";
import "./ConversionModule.sol";
import "./HashRegistry.sol";

/// @title IQOS Core
/// @notice Main aggregator contract referencing the deployed IQOS modules
contract IQOS {
    AccessControl public accessControl;
    TokenManager public tokenManager;
    OrderBookModule public orderBookModule;
    ConversionModule public conversionModule;
    HashRegistry public hashRegistry;

    constructor(
        address _accessControl,
        address _tokenManager,
        address _orderBookModule,
        address _conversionModule,
        address _hashRegistry
    ) {
        require(_accessControl != address(0), "Invalid access control");
        require(_tokenManager != address(0), "Invalid token manager");
        require(_orderBookModule != address(0), "Invalid order book");
        require(_conversionModule != address(0), "Invalid conversion module");
        require(_hashRegistry != address(0), "Invalid hash registry");

        accessControl = AccessControl(_accessControl);
        tokenManager = TokenManager(_tokenManager);
        orderBookModule = OrderBookModule(_orderBookModule);
        conversionModule = ConversionModule(_conversionModule);
        hashRegistry = HashRegistry(_hashRegistry);
    }
}