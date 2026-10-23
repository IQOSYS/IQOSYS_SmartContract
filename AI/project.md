# IQOSYS smart-contract project

Last updated: 2026-10-20 (source `feat/amf-ready`, commit `dd07de0`; documentation branch / PR: *to confirm*)

## What the repository is for
`IQOSYS_SmartContract` contains the on-chain register and control modules for IQOSYS BSA warrants, IQS exercise rights and OST ordinary shares. It is public so the source can be compared with deployed bytecode. It does not contain the Laravel platform, bridge HTTP service, identity verification, bank processing or document-signing infrastructure.

The approved "IQS, BSA and OST" section of the platform's `AI/project.md` is the business authority. This file carries the rules needed to work in this repository. If the code differs, describe the implementation accurately and raise the alignment question; do not silently redefine the business rule.

## Instruments and eligibility
| Instrument | Meaning | Eligible holder |
|---|---|---|
| BSA | Share warrant signed by an Exec Partner's company, with its own allocation, strike, premium and expiry. Standard business duration is two years; the contract records the supplied expiry. | Exec Partners' companies |
| IQS | Whole, non-transferable exercise rights unlocked manually from gross margin generated and collected. One IQS gives the right to subscribe one OST at the BSA strike. IQS have no cash value of their own. | Exec Partners' companies |
| OST | Ordinary shares of IQOSYS SAS represented in the controlled shareholder ledger. One share class with ordinary rights, including voting. | Shareholders |

Consultants, researchers, IQosystem partners and clients do not receive IQS. The contracts validate wallets and permissions; legal-company eligibility and identity re-proofing are enforced off-chain.

## Business model
1. The company's BSA is signed and recorded. Signing/offer controls must keep the number of holders below 150.
2. The admin manually awards IQS as qualifying gross margin is collected. There is no automatic unlock. Unawarded BSA allocation and minted IQS are different quantities.
3. Exercise requires payment of the strike and the capital-confirmation process. Approved finalization burns IQS and issues an equal number of OST.
4. OST sales are bilateral and agreed between participants. IQOSYS approves and records them, including evidence of the buyer's bank payment. It does not run a market, order book or matching service.
5. IQOSYS does not buy back IQS. No general peer-to-peer IQS transfer, preference share class or third-party relayer is part of this model.

The theoretical OST value is the approved company valuation divided by issued OST + issued unexercised IQS + active unawarded BSA allocation. The admin publishes quarterly valuations; the contracts anchor evidence rather than independently valuing the company.

Governance votes can use IQS, OST or both. Signed ballots, the tally and legal interpretation are off-chain; the official result and ballot root are anchored on-chain. Planned IQS co-optation must not be described as already live.

## Stack and repository map
| Path | Contents |
|---|---|
| `src/` | Contract modules and their interfaces |
| `test/` | Foundry tests and regression cases |
| `script/Deploy.s.sol` | `DeployIQOS` deployment and bootstrap |
| `foundry.toml` | Solidity 0.8.20, Shanghai, optimizer 200 runs, via IR |
| `@openzeppelin/contracts/` | OpenZeppelin components used by the source |
| `lib/forge-std/` | Foundry script and test helpers |

Production targets Polygon PoS, chain ID 137; development/testing uses Amoy, chain ID 80002. The actual deployment, module addresses and ABI revision must be checked separately. There is no proxy upgrade mechanism.

## Authorities and safety rules
- The AccessControl owner Safe, admins, multisig signers, scoped roles and token operators are separate authorities. The deployment initializes three signers and a two-signature threshold.
- Sensitive operations bind approvals to exact intent. Proposal creation adds no approval. Consumption is restricted to the intended consumer and is single-use.
- The approved business policy requires two-admin control for issuance, sensitive configuration and wallet recovery, with a 48-hour delay and immediate email/SMS alerts for key/operator/holder rotations. In this source revision, the explicit on-chain delay belongs to holder migration; do not claim a universal delay on signer/operator functions.
- Migration Abort is a separate quorum action. With the default setup it needs two of three signatures. One admin can pause TokenManager during the migration window; one admin cannot execute Abort alone.
- Every equity operation requires application 2FA under platform policy. Solidity cannot verify an email/SMS/TOTP challenge; this belongs to the application.
- Names, identity documents and bank details stay off-chain. Reference hashes are commitments to private evidence, not proof that the source data is anonymous.

The system is designed around the French DEEP model and the platform's holder restrictions. Source comments, an audit approval or a 149-slot counter do not establish legal qualification, an exemption or regulatory approval.

## Review and audit status
Commit `dd07de0` was approved in the reported contract review after resolution of N-01 through N-05 and the remaining F-05 work. The reviewer reported 278 passing tests including independent checks. This is a revision-specific result, not a blanket approval of later commits, bridge code or deployment configuration.

Two non-blocking follow-ups were accepted: show the Abort quorum requirement in the admin UI, and review the immutable first receipt-hash write after reclaim after release. Do not change audited Solidity for those items without identifying the new commits for review.

Start a review with `AI/review.md`. The detailed functionality is in `AI/functionalities/iqs-bsa-ost.md`; Solidity rules are in `AI/smart_contract_review.md`.
