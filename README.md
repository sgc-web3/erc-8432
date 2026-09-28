# ERC for Onchain IP Licensing
Working repository for an Ethereum standard for onchain intellectual-property
licensing.

## Reading order
| Document                             | What it is                                    |
|--------------------------------------| --------------------------------------------- |
| `docs/erc_overview.md`               | **Start here.** High-level introduction, layer diagram, and basic flows |
| `docs/faq.md`                        | Short answers to recurring questions, each linking to the spec / rationale |
| `docs/terminology.md`                | Glossary of licensing, registry, and verification terminology |
| `docs/core_architecture.md`          | Developer-facing architecture, top-down       |
| `docs/key_interaction_flows.md`      | End-to-end worked example: registration, terms, agreements, and derivation |
| `docs/license_terms_explained.md`    | Picture-first guide to `LicenseTerms`: the four layers, what each `contentHash` hashes, and what `rightsData` is |
| `docs/requirements.md`               | Expanded R0-R33 and R35-R37 working requirements and traceability notes |
| `docs/erc-draft.md`                 | Authoritative, self-contained EIP/ERC publication draft |
| `docs/design_decisions.md`          | Design principles followed by technical decisions and rationale |
| `docs/security_considerations.md`    | Consolidated Security Considerations (EIP section), cross-referenced to R-numbers |
| `docs/backwards_compatibility.md`    | Consolidated Backwards Compatibility (EIP section): relationship to ERC-721/1155/6551/3643/5218, EIP-2981/712, identity systems |
| `docs/schemas/generic-license-v1.md` | Guide to the generic schema defined inline in the ERC draft |

New readers: start with `erc_overview.md` for the high-level shape (and
`faq.md` for quick "why" answers), then `core_architecture.md` for the
component-level architecture, then `key_interaction_flows.md` to see the pieces
compose in a concrete example. `erc-draft.md` is authoritative; `requirements.md`
expands it with stable R-number references. `design_decisions.md` starts with the
principles before explaining technical trade-offs. Use `terminology.md` for
unfamiliar terms and `license_terms_explained.md` for illustrations of the four
terms layers and their content hashes.

## Solidity surface
| File                                  | Purpose                                                |
| ------------------------------------- | ------------------------------------------------------ |
| `src/interfaces/IPAssetTypes.sol`     | Shared types, structs, enums, well-known constants     |
| `src/interfaces/IERC165.sol`          | Local, dependency-free ERC-165 interface               |
| `src/interfaces/IIPAssetRegistry.sol` | Canonical registry interface consolidating R0-R33      |
| `src/interfaces/ITermsRegistry.sol`   | Local content-addressed terms storage inherited by each asset registry |
| `src/IpRef.sol`                       | Parser/encoder for `ipid:` / `ipterms:` / `ipagreement:` |
| `src/IPid.sol`                        | Back-compat alias for the asset-specific surface       |
| `src/IPAssetRegistry.sol`             | **Reference implementation** of `IIPAssetRegistry` (spec-validation, not audited) |

A first reference implementation (`src/IPAssetRegistry.sol`) now accompanies
the interfaces. It is an intentionally un-optimized, dependency-free contract
whose purpose is to *validate the specification* - to prove every normative
requirement is simultaneously satisfiable and to surface design issues before
the ERC text freezes. It is **not audited** and **not production code**. All
Solidity compiles with **no external dependencies** (`IERC165` is declared
locally rather than imported from OpenZeppelin).

## Status
- **Locked:** R0, R1-R33, and R35-R37.
- **Pinned:** the `IIPAssetRegistry` ERC-165 id `0x72117f80` and the
  `TERMS_TYPE_GENERIC_V1` schema hash
  `0x497589298d23e3edf03354027567294825f845d9acccc3812cbb7b7b8dc3f5fa`
  (both locked by tests; re-pin only if the interface or schema changes).
- **Validated:** reference implementation (`src/IPAssetRegistry.sol`),
  exercised by a Foundry test suite. The spec-validation pass that produced it is
  complete; the decisions it surfaced are folded into the normative text and
  the design rationale (`design_decisions.md`).
- **Open:** Ethereum Magicians discussion and final EIP/ERC submission metadata.

## Build and test
This repository uses [Foundry](https://book.getfoundry.sh/). Install
Foundry, then:
```sh
forge build
forge test
```
The interfaces, reference library, and tests compile and run with **no
external dependencies** - no `forge install` step is required. The current
suite covers the `IpRef` encoder/decoder (round-trips, malformed-input
rejection, fuzzing), the ERC-165 interface ids, the `generic-license-v1`
schema hash, and the `IPAssetRegistry` reference implementation
(registration, ownership/licensee delegation and ERC-721 query safety,
terms attachment, agreement lifecycle, verification, pagination, freeze /
revoke, and EIP-712 derivation-attestation signatures). To print the
interface ids for pinning:
```sh
forge test --match-test test_RecordInterfaceIds -vvvv
```
## License
All Solidity files are `CC0-1.0`. Documentation is intended to be
incorporated into a Creative-Commons-licensed EIP submission.
