# IQOSYS Smart Contracts

Solidity contracts for BSA subscription warrants, IQS subscription rights and the OST ordinary-share ledger.

IQOSYS manages the lifecycle from warrant registration and rights allocation to share issuance and controlled transfers. The system combines a custom ledger, administrative multisig approvals, escrow settlement and on-chain evidence registries.

**Solidity 0.8.20 · Foundry · OpenZeppelin Contracts 5.1.0 · Polygon Amoy**

[Overview](#overview) · [Getting started](#getting-started) · [Architecture](#architecture) · [Workflows](#workflows) · [Security model](#security-model) · [Deployments](#deployments)

## Overview

| Instrument | Purpose |
| --- | --- |
| **BSA** | Subscription warrant recording the holder, contractual terms, strike price, maximum allocation and expiry. |
| **IQS** | Whole, non-transferable subscription rights awarded under a BSA. Exercise burns IQS and issues an equal quantity of OST. |
| **OST** | On-chain representation of ordinary shares, held in a controlled ledger and transferred through the settlement module. |

The custom ledger does not implement the general-purpose ERC-20 interface. OST supply starts at zero. Existing shares can be registered once through the approved genesis import; subsequent issuance follows the approved exercise process.

The contracts record authorized actions and evidence references. Eligibility checks, signed agreements, bank payments and company-law formalities take place off-chain. Their completion cannot be inferred from an on-chain record alone.

## Getting started

Install [Foundry](https://getfoundry.sh/) and use a local checkout with the repository's recorded dependencies, including `forge-std` and OpenZeppelin Contracts.

If the checkout uses Git submodules, initialize them first:

```sh
git submodule update --init --recursive
```

Build and run the test suite from the repository root:

```sh
forge build
forge test
forge build --sizes
```

Compiler settings are defined in [foundry.toml](foundry.toml):

| Setting | Value |
| --- | --- |
| Solidity | `0.8.20` |
| EVM target | `shanghai` |
| Optimizer | Enabled, `200` runs |
| Via IR | Enabled |

Keep dependency versions and compiler settings consistent when verifying deployed bytecode.

## Architecture

The system uses dedicated contracts for authorization, accounting, settlement and evidence. [IQOS](src/IQOS.sol) holds references to the module set; each module executes its own business logic.

| Contract | Responsibility |
| --- | --- |
| [AccessControl](src/AccessControl.sol) | Ownership, administrators, scoped roles, whitelist and freeze controls. |
| [AdminMultisig](src/AdminMultisig.sol) | Proposals, signer approvals, execution authorization and proposal recovery. |
| [TokenManager](src/TokenManager.sol) | IQS/OST balances, supply, holder slots and operator bindings. |
| [BSARegistry](src/BSARegistry.sol) | Warrant terms, rights allocation, awards, expiry and exercise accounting. |
| [ConversionModule](src/ConversionModule.sol) | IQS exercise, capital confirmation and OST issuance. |
| [OSTTransferModule](src/OSTTransferModule.sol) | Transfer requests, escrow, payment evidence, settlement and dispute handling. |
| [HashRegistry](src/HashRegistry.sol) | Module-scoped evidence hashes and document supersession. |
| [GovernanceRegistry](src/GovernanceRegistry.sol) | Official voting outcomes and ballot roots. |
| [ValuationAnchor](src/ValuationAnchor.sol) | Valuation publications and linked corrections. |
| [EmergencyController](src/EmergencyController.sol) | Scoped pause and approved resume operations. |
| [HolderMigrationController](src/HolderMigrationController.sol) | Delayed holder-wallet recovery and migration cancellation. |
| [TokenOperatorController](src/TokenOperatorController.sol) | Approved changes to token operators. |

### Repository layout

| Path | Contents |
| --- | --- |
| [src/](src/) | Solidity contracts and supporting interfaces. |
| [test/](test/) | Foundry tests and regression cases. |
| [script/](script/) | Deployment scripts. |
| [foundry.toml](foundry.toml) | Build, compiler and network configuration. |

## Workflows

### BSA registration and IQS awards

Approved registration records the warrant's terms and maximum allocation. Subsequent approved awards credit IQS to the holder and reduce the unawarded allocation. Registration does not mint the full allocation; expiry and cancellation update the remaining rights.

### Existing-share registration

Before any OST is issued, administrators can register all existing shares and their current holders in a single transaction. The approval binds the complete address/quantity list, declared total and SHA-256 of the signed off-chain register extract. Registration requires the configured quorum (at least two of three signers), a 48-hour delay, and compliance with the shared permanent 149-holder cap. A separate quorum can abort before execution. Successful registration permanently locks this import path.

See [Initial share registration](docs/initial-share-registration.md) for the approval workflow, canonical-address checks and platform alert integration.

### IQS exercise and OST issuance

A holder requests exercise against an eligible BSA and available IQS. After approval and capital confirmation, finalization burns the exercised IQS, updates the BSA record and issues the same number of OST in one transaction.

### OST transfer and settlement

1. A transfer request identifies the participants, quantity, price and agreement evidence.
2. Acceptance locks the seller's OST in escrow.
3. Buyer payment evidence is recorded.
4. A quorum-approved settlement confirms the seller's receipt of payment and releases the OST to the buyer atomically.

The combined `adminConfirmSellerPaymentAndRelease` action binds the transfer and both receipt hashes. If release fails, payment confirmation and approval consumption revert with it. Dispute, resolution and timeout-reclaim paths depend on the transfer state and deadlines.

Escrow holds already-issued OST. Token release and reclaim do not execute or reverse bank payments.

## Security model

IQOSYS uses permissioned administration. Ownership, multisig signer membership, scoped roles and token operators are separate authorities.

| Control | Behavior |
| --- | --- |
| **Administrative quorum** | The deployment script configures three signers with two required approvals. Operations use the applicable live threshold. |
| **Bound approvals** | A proposal binds its consumer, function selector, calldata hash and deadline. Proposal creation does not count as an approval. |
| **Single consumption** | Only the bound consumer can consume an approved action, once. Approvals also depend on signer epoch and proposal lifecycle. |
| **Emergency controls** | An administrator can pause an allowed scope immediately. Resuming requires the corresponding quorum-approved controller action. |
| **Existing shares** | Genesis-only registration binds the complete register, verifies its declared total and executes atomically after quorum plus 48 hours. A separate quorum can abort, including while paused. |
| **Wallet recovery** | Migration requires at least two approvals, honors a higher configured threshold and enforces a 48-hour delay from effective quorum. Open transfers block migration. |
| **Evidence integrity** | Terminal exercise and transfer receipt hashes are write-once. Document corrections preserve prior evidence through linked supersession where applicable. |

IQS and OST share a **149-slot holder register**. Slots remain allocated after balances reach zero and can move through authorized wallet migration. This is a wallet-level restriction, not a count of verified individuals or a regulatory exemption.

The owner Safe and `AdminMultisig` have independently configured thresholds. Contracts are deployed directly without upgrade proxies. Module replacement requires redeployment and a reviewed migration plan; several bindings are one-time setters.

## Accounting

IQS and OST quantities are whole units. Contractual monetary values use integer EUR cents.

| Field | Unit | Example |
| --- | --- | --- |
| `strikePrice` | EUR cents per OST | `185` = EUR 1.85 |
| `pricePerOST` | EUR cents per OST | `200` = EUR 2.00 |
| `premiumPaid` | Total EUR cents for the BSA | `15000` = EUR 150.00 |
| `capitalDue` | Total EUR cents | `10 × 185 = 1850` = EUR 18.50 |

The valuation denominator combines issued OST, minted unexercised IQS and unawarded allocation from active, unexpired BSAs:

```solidity
TokenManager.totalSupplyOSTf()
    + TokenManager.totalSupplyIQS()
    + BSARegistry.totalIQSInEscrow()
```

OST in transfer escrow remains part of issued supply. Read all quantities at the same block and use a consistent currency scale with the approved off-chain valuation. The contracts do not appraise the company.

## Testing

The [Foundry suite](test/) covers authorization, multisig lifecycle, warrant accounting, exercise, transfer settlement, expiry and wallet recovery. Regression suites include [AtomicOSTSettlement.t.sol](test/AtomicOSTSettlement.t.sol) and [Reaudit20261016.t.sol](test/Reaudit20261016.t.sol).

The [initial registration regression suite](test/InitialShareRegistration.t.sol) covers complete imports, declared totals, eligibility, the holder cap, delay, Abort and approval invalidation.

Run tests against the exact revision being reviewed.

## Deployments

### Polygon Amoy

**Chain ID:** `80002` · **Deployment block:** `50548536`

Recorded testnet module addresses:

| Contract | Address |
| --- | --- |
| IQOS | [`0x8581275778dfBe580efD260CB82E4d8BA3779B9F`](https://amoy.polygonscan.com/address/0x8581275778dfBe580efD260CB82E4d8BA3779B9F) |
| AccessControl | [`0xC4739d784488d84bD8c84475A851FCA8D6A0fC77`](https://amoy.polygonscan.com/address/0xC4739d784488d84bD8c84475A851FCA8D6A0fC77) |
| AdminMultisig | [`0xb9f85a46a025Ff9170a074d8f1dB8ed5c1d2FFd8`](https://amoy.polygonscan.com/address/0xb9f85a46a025Ff9170a074d8f1dB8ed5c1d2FFd8) |
| TokenManager | [`0xC6E8b1D5C8667A43985ddBeFc7e859F50f29C9D0`](https://amoy.polygonscan.com/address/0xC6E8b1D5C8667A43985ddBeFc7e859F50f29C9D0) |
| BSARegistry | [`0x3869dAc57Ae037285f1F934AE12BccDDf2167da3`](https://amoy.polygonscan.com/address/0x3869dAc57Ae037285f1F934AE12BccDDf2167da3) |
| ConversionModule | [`0x55C62DBAB6a60BeCd338853388aa87153d41090d`](https://amoy.polygonscan.com/address/0x55C62DBAB6a60BeCd338853388aa87153d41090d) |
| OSTTransferModule | [`0x081F59A62347E3eecf9B575E746fEE1567592fDc`](https://amoy.polygonscan.com/address/0x081F59A62347E3eecf9B575E746fEE1567592fDc) |
| HashRegistry | [`0x1e766B58335C1Df844396e3FBc12741C3B5E8865`](https://amoy.polygonscan.com/address/0x1e766B58335C1Df844396e3FBc12741C3B5E8865) |
| GovernanceRegistry | [`0x025595CeC5481Fc1ce0aE4A72668274451BB3d31`](https://amoy.polygonscan.com/address/0x025595CeC5481Fc1ce0aE4A72668274451BB3d31) |
| ValuationAnchor | [`0x9Ea8d4e05B83E4092a9C0F9d88C4e514702dC579`](https://amoy.polygonscan.com/address/0x9Ea8d4e05B83E4092a9C0F9d88C4e514702dC579) |
| EmergencyController | [`0x75E3DBFf70cc0488ED5010911d7E6455040CA1fB`](https://amoy.polygonscan.com/address/0x75E3DBFf70cc0488ED5010911d7E6455040CA1fB) |
| HolderMigrationController | [`0x96bcFC9B740563B78CF02674833D2620a14240bA`](https://amoy.polygonscan.com/address/0x96bcFC9B740563B78CF02674833D2620a14240bA) |
| TokenOperatorController | [`0xCea51DEbE0e878e8692CbB2b5E117CCe9646a866`](https://amoy.polygonscan.com/address/0xCea51DEbE0e878e8692CbB2b5E117CCe9646a866) |

### Deploying the contracts

The entry point is [DeployIQOS](script/Deploy.s.sol). It deploys the modules, configures permissions and initiates ownership transfer.

Configure deployment values locally:

| Variable | Purpose |
| --- | --- |
| `PRIVATE_KEY` | Deployment signer. |
| `OWNER_SAFE` | Intended AccessControl owner. |
| `ADMIN_SIGNER_1`, `ADMIN_SIGNER_2`, `ADMIN_SIGNER_3` | Distinct initial signers, each different from the deployer. |
| `POLYGON_AMOY_RPC_URL` | RPC endpoint for the `amoy` alias. |
| `POLYGON_MAINNET_RPC_URL` | RPC endpoint for the `polygon` alias, if used. |
| `POLYGONSCAN_API_KEY` | Explorer verification credential, if used. |

Keep private keys and credential-bearing RPC URLs out of version control.

Simulate deployment:

```sh
forge script script/Deploy.s.sol:DeployIQOS --rpc-url amoy -vv
```

After reviewing the simulation and target configuration, broadcast:

```sh
forge script script/Deploy.s.sol:DeployIQOS --rpc-url amoy --broadcast -vv
```

Deployment spans multiple transactions. Inspect every receipt and resolve failed steps. Verify bytecode, module bindings, permissions and bootstrap locks against the reviewed revision.

The designated Safe must execute `acceptOwnership()` on AccessControl. Confirm the final owner, cleared pending owner and removal of the deployer's operational privileges.

## Integration notes

Use module-specific interfaces and the live configuration. Preserve integer precision and distinguish currency units from gas fees. If application synchronization fails after a successful transaction, reconcile its original receipt before considering another transaction.

## Contributing

Describe the effect of changes on contract state and permissions. Include tests for successful execution and relevant failure paths, then run `forge build` and `forge test` before submitting a pull request.


## License

Licensed under the MIT License. Third-party dependencies are subject to their respective licenses.
