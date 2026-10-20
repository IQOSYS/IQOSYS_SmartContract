# Functionality documentation

Last updated: 2026-10-20 (documentation branch / PR: *to confirm*)

One Markdown file per functionality describes the current contracts: actors, flows, rules, entry points, storage, integrations and security. `AI/project.md` sets business context; `AI/smart_contract_review.md` sets review rules.

## Rules
1. Write from the implementation and interfaces at the reviewed commit. Mark missing off-chain/deployment facts *to confirm*.
2. Describe current behavior. History belongs in git. Separate approved business policy from what Solidity enforces.
3. Use English, short sentences, endpoint/rule tables and numbered flows. Keep the section headings below, writing "None" where appropriate.
4. Use repository-relative source paths. Do not invent a private platform file, test result, HTTP endpoint or deployed address.
5. No secrets, production evidence, real identities or bank data in examples. Wallet-linked evidence can still be personal data.
6. Update the date and reviewed source/branch or PR whenever behavior changes. Update the index when adding or renaming a file.
7. Feature and behavior changes require documentation. A bugfix that restores the already documented behavior does not; path-only refactors update references.

## Template
```markdown
# <Functionality>

Last updated: YYYY-MM-DD (source commit / documentation branch / PR)

## Summary
## Who can use it
## How it works
## Business rules
## API endpoints
## Data
## Frontend
## Background jobs and notifications
## External services
## Configuration
## Security and GDPR
## Tests
## Known limitations and open issues
```

Under "API endpoints", say that Solidity has no HTTP endpoints and list relevant contract methods. Off-chain responsibilities belong in the corresponding sections, not under invented on-chain guarantees.

## Index
| Functionality | File | Area |
|---|---|---|
| BSA allocation, IQS exercise, OST settlement and administrative controls | [iqs-bsa-ost.md](iqs-bsa-ost.md) | On-chain register |
