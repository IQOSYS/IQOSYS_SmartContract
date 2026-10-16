// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./IEmergencyController.sol";
import "./IAccessControl.sol";
import "./IAdminMultisig.sol";

interface IEmergencyPausable {
    function pause() external;
    function unpause() external;
    function paused() external view returns (bool);
}

/// @title Emergency Controller
/// @notice Central controller for immediate admin pauses and multisig-approved resumes.
/// @dev No personal data is stored on-chain.
///      Only actions that resume operations require AdminMultisig approval.
contract EmergencyController is IEmergencyController {
    IAccessControl public accessControl;
    IAdminMultisig public adminMultisig;

    IEmergencyPausable public tokenManager;
    IEmergencyPausable public bsaRegistry;
    IEmergencyPausable public conversionModule;
    IEmergencyPausable public ostTransferModule;
    IEmergencyPausable public valuationAnchor;
    IEmergencyPausable public governanceRegistry;

    event EmergencyActionExecuted(
        EmergencyScope indexed scope,
        bool indexed shouldPause,
        bytes32 indexed actionHash,
        bytes32 referenceHash,
        address executedBy,
        uint256 timestamp
    );

    constructor(
        address _accessControl,
        address _adminMultisig,
        address _tokenManager,
        address _bsaRegistry,
        address _conversionModule,
        address _ostTransferModule,
        address _valuationAnchor,
        address _governanceRegistry
    ) {
        require(
            _accessControl != address(0),
            "Invalid access control"
        );

        require(
            _adminMultisig != address(0),
            "Invalid admin multisig"
        );

        require(
            _tokenManager != address(0),
            "Invalid token manager"
        );

        require(
            _bsaRegistry != address(0),
            "Invalid BSA registry"
        );

        require(
            _conversionModule != address(0),
            "Invalid conversion module"
        );

        require(
            _ostTransferModule != address(0),
            "Invalid OST transfer module"
        );

        require(
            _valuationAnchor != address(0),
            "Invalid valuation anchor"
        );

        require(
            _governanceRegistry != address(0),
            "Invalid governance registry"
        );

        accessControl =
            IAccessControl(_accessControl);

        adminMultisig =
            IAdminMultisig(_adminMultisig);

        tokenManager =
            IEmergencyPausable(_tokenManager);

        bsaRegistry =
            IEmergencyPausable(_bsaRegistry);

        conversionModule =
            IEmergencyPausable(_conversionModule);

        ostTransferModule =
            IEmergencyPausable(_ostTransferModule);

        valuationAnchor =
            IEmergencyPausable(_valuationAnchor);

        governanceRegistry =
            IEmergencyPausable(_governanceRegistry);
    }

    modifier onlyAdmin() {
        require(
            accessControl.isAdmin(msg.sender),
            "Caller is not an admin"
        );
        _;
    }

    function getEmergencyActionHash(
        EmergencyScope scope,
        bool shouldPause,
        bytes32 referenceHash
    )
        public
        view
        override
        returns (bytes32)
    {
        require(
            scope != EmergencyScope.None,
            "Invalid emergency scope"
        );

        require(
            referenceHash != bytes32(0),
            "Reference hash required"
        );

        return keccak256(
            abi.encode(
                address(this),
                block.chainid,
                "EMERGENCY_CONTROLLER",
                scope,
                shouldPause,
                referenceHash
            )
        );
    }

    function pauseAll(
        bytes32 referenceHash
    )
        external
        override
        onlyAdmin
    {
        _executeEmergencyAction(
            EmergencyScope.All,
            true,
            referenceHash
        );
    }

    function unpauseAll(
        bytes32 referenceHash
    )
        external
        override
        onlyAdmin
    {
        _executeEmergencyAction(
            EmergencyScope.All,
            false,
            referenceHash
        );
    }

    function pauseDistribution(
        bytes32 referenceHash
    )
        external
        override
        onlyAdmin
    {
        _executeEmergencyAction(
            EmergencyScope.Distribution,
            true,
            referenceHash
        );
    }

    function unpauseDistribution(
        bytes32 referenceHash
    )
        external
        override
        onlyAdmin
    {
        _executeEmergencyAction(
            EmergencyScope.Distribution,
            false,
            referenceHash
        );
    }

    function pauseConversions(
        bytes32 referenceHash
    )
        external
        override
        onlyAdmin
    {
        _executeEmergencyAction(
            EmergencyScope.Conversions,
            true,
            referenceHash
        );
    }

    function unpauseConversions(
        bytes32 referenceHash
    )
        external
        override
        onlyAdmin
    {
        _executeEmergencyAction(
            EmergencyScope.Conversions,
            false,
            referenceHash
        );
    }

    function pauseTransactions(
        bytes32 referenceHash
    )
        external
        override
        onlyAdmin
    {
        _executeEmergencyAction(
            EmergencyScope.Transactions,
            true,
            referenceHash
        );
    }

    function unpauseTransactions(
        bytes32 referenceHash
    )
        external
        override
        onlyAdmin
    {
        _executeEmergencyAction(
            EmergencyScope.Transactions,
            false,
            referenceHash
        );
    }

    function pauseValuation(
        bytes32 referenceHash
    )
        external
        override
        onlyAdmin
    {
        _executeEmergencyAction(
            EmergencyScope.Valuation,
            true,
            referenceHash
        );
    }

    function unpauseValuation(
        bytes32 referenceHash
    )
        external
        override
        onlyAdmin
    {
        _executeEmergencyAction(
            EmergencyScope.Valuation,
            false,
            referenceHash
        );
    }

    function pauseGovernance(
        bytes32 referenceHash
    )
        external
        override
        onlyAdmin
    {
        _executeEmergencyAction(
            EmergencyScope.Governance,
            true,
            referenceHash
        );
    }

    function unpauseGovernance(
        bytes32 referenceHash
    )
        external
        override
        onlyAdmin
    {
        _executeEmergencyAction(
            EmergencyScope.Governance,
            false,
            referenceHash
        );
    }

    function _executeEmergencyAction(
        EmergencyScope scope,
        bool shouldPause,
        bytes32 referenceHash
    )
        internal
    {
        require(
            scope != EmergencyScope.None,
            "Invalid emergency scope"
        );

        require(
            referenceHash != bytes32(0),
            "Reference hash required"
        );

        bytes32 actionHash =
            getEmergencyActionHash(
                scope,
                shouldPause,
                referenceHash
            );

        // Any admin can stop an incident immediately. Only a multisig-approved
        // controller action may resume operations.
        if (!shouldPause) {
            adminMultisig.consumeApprovedAction(actionHash);
        }

        if (scope == EmergencyScope.All) {
            _setAll(shouldPause);
        } else if (
            scope == EmergencyScope.Distribution
        ) {
            _setDistribution(shouldPause);
        } else if (
            scope == EmergencyScope.Conversions
        ) {
            _setConversions(shouldPause);
        } else if (
            scope == EmergencyScope.Transactions
        ) {
            _setTransactions(shouldPause);
        } else if (
            scope == EmergencyScope.Valuation
        ) {
            _setValuation(shouldPause);
        } else if (
            scope == EmergencyScope.Governance
        ) {
            _setGovernance(shouldPause);
        } else {
            revert(
                "Unsupported emergency scope"
            );
        }

        emit EmergencyActionExecuted(
            scope,
            shouldPause,
            actionHash,
            referenceHash,
            msg.sender,
            block.timestamp
        );
    }

    function _setAll(
        bool shouldPause
    )
        internal
    {
        if (shouldPause) {
            _setModule(
                bsaRegistry,
                true
            );

            _setModule(
                conversionModule,
                true
            );

            _setModule(
                ostTransferModule,
                true
            );

            _setModule(
                valuationAnchor,
                true
            );

            _setModule(
                governanceRegistry,
                true
            );

            _setModule(
                tokenManager,
                true
            );
        } else {
            _setModule(
                tokenManager,
                false
            );

            _setModule(
                bsaRegistry,
                false
            );

            _setModule(
                conversionModule,
                false
            );

            _setModule(
                ostTransferModule,
                false
            );

            _setModule(
                valuationAnchor,
                false
            );

            _setModule(
                governanceRegistry,
                false
            );
        }
    }

    function _setDistribution(
        bool shouldPause
    )
        internal
    {
        _setModule(
            bsaRegistry,
            shouldPause
        );
    }

    function _setConversions(
        bool shouldPause
    )
        internal
    {
        _setModule(
            conversionModule,
            shouldPause
        );
    }

    function _setTransactions(
        bool shouldPause
    )
        internal
    {
        _setModule(
            ostTransferModule,
            shouldPause
        );
    }

    function _setValuation(
        bool shouldPause
    )
        internal
    {
        _setModule(
            valuationAnchor,
            shouldPause
        );
    }

    function _setGovernance(
        bool shouldPause
    )
        internal
    {
        _setModule(
            governanceRegistry,
            shouldPause
        );
    }

    function _setModule(
        IEmergencyPausable module,
        bool shouldPause
    )
        internal
    {
        bool isPaused =
            module.paused();

        if (
            shouldPause &&
            !isPaused
        ) {
            module.pause();
        }

        if (
            !shouldPause &&
            isPaused
        ) {
            module.unpause();
        }
    }

    function getEmergencyStatus()
        external
        view
        override
        returns (
            EmergencyStatus memory
        )
    {
        return EmergencyStatus({
            tokenManagerPaused:
                tokenManager.paused(),
            bsaRegistryPaused:
                bsaRegistry.paused(),
            conversionModulePaused:
                conversionModule.paused(),
            ostTransferModulePaused:
                ostTransferModule.paused(),
            valuationAnchorPaused:
                valuationAnchor.paused(),
            governanceRegistryPaused:
                governanceRegistry.paused()
        });
    }
}
