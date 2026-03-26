// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./AccessControl.sol";
import "./TokenManager.sol";
import "./P2PModule.sol";
import "./OrderBookModule.sol";
import "./TradeModule.sol";
import "./ConversionModule.sol";
import "./HashRegistry.sol";
import "./DAO.sol";

/// @title IQOS Core
/// @notice Contrat principal qui référence tous les modules déployés séparément
contract IQOS {
    AccessControl   public accessControl;
    TokenManager    public tokenManager;
    P2PModule       public p2pModule;
    OrderBookModule public orderBookModule;
    TradeModule     public tradeModule;
    ConversionModule public conversionModule;
    HashRegistry    public hashRegistry;
    DAO             public dao;

    /// @notice Initialise le core avec les adresses des modules externes
    /// @param _accessControl Adresse du contrat AccessControl
    /// @param _tokenManager Adresse du contrat TokenManager
    /// @param _p2pModule Adresse du contrat P2PModule
    /// @param _orderBookModule Adresse du contrat OrderBookModule
    /// @param _tradeModule Adresse du contrat TradeModule
    /// @param _conversionModule Adresse du contrat ConversionModule
    /// @param _hashRegistry Adresse du contrat HashRegistry
    /// @param _dao Adresse du contrat DAO
    constructor(
        address _accessControl,
        address _tokenManager,
        address _p2pModule,
        address _orderBookModule,
        address _tradeModule,
        address _conversionModule,
        address _hashRegistry,
        address _dao
    ) {
        accessControl     = AccessControl(_accessControl);
        tokenManager      = TokenManager(_tokenManager);
        p2pModule         = P2PModule(_p2pModule);
        orderBookModule   = OrderBookModule(_orderBookModule);
        tradeModule       = TradeModule(_tradeModule);
        conversionModule  = ConversionModule(_conversionModule);
        hashRegistry      = HashRegistry(_hashRegistry);
        dao               = DAO(_dao);
    }
}
