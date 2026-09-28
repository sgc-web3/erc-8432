# Backwards Compatibility

## Summary

This ERC is **purely additive**. It defines a new interface
(`IIPAssetRegistry`, inheriting `ITermsRegistry`); it does
**not** modify, deprecate, or require changes to any existing standard. No
migration is required for existing token-standard contracts, and ERC-721/ERC-1155
deployments keep working unchanged. A registry composes *over* existing token
standards rather than replacing them.

The ERC layers cleanly because of three deliberate choices:

- Registration never requires a token (R3) — the asset record, not a token, is
  the registration unit, so off-chain/onchain/hybrid works all fit.
- Tokenization is a small, closed enum (R4/R22) — the core only enumerates the
  token standards whose ownership semantics it can safely delegate to.
- Discovery is via ERC-165 (R33) and canonical string references (R2/R17/R19),
  so the ERC plugs into existing tooling instead of demanding new infra.

## Relationship to specific standards

### ERC-165 (Standard Interface Detection) — *required*

A conforming registry MUST implement `supportsInterface` and return `true` for
the ERC-165 id, the `IIPAssetRegistry` id `0x72117f80`, and the inherited
`ITermsRegistry` id `0x38c7f550` (R33). Catalogs, wallets, and extensions use
this to detect advertised interface support, not to establish behavioral
conformance, honest records, or legal authority.

### ERC-721 (Non-Fungible Token) — *first-class binding*

ERC-721 is the first-class onchain tokenization for both assets (R4) and
license agreements (R22). When `tokenization == ERC721`:

- `registry.ownerOf(assetId)` delegates to `IERC721(collection).ownerOf(tokenId)`
  with no caching (R5); the licensee of an `ERC721` agreement is the bound
  token holder (R22).
- An asset can bind to a **pre-existing** ERC-721 token; no re-mint is needed.
- Off-chain indexers MUST also watch the bound contract's `Transfer` events,
  because the registry is not in the transfer path (R5/R14, R22).

The ERC adds inspectable terms and agreement state alongside token holdings.
Neither a token holding nor a registry entry alone proves legal permission to
use the underlying work.

### ERC-1155 (Multi-Token) — *deliberately not a tokenization kind*

ERC-1155 is intentionally excluded from both the asset `AssetTokenization` enum
(R4) and the `AgreementTokenization` enum (R22). Multi-supply breaks
per-agreement revocation (all-or-nothing), makes `isAgreementActive` per-holder
ambiguous, and has no clean unassigned state. Existing ERC-1155 contracts are
unaffected; an ERC-1155-bound work registers with `tokenization == NONE` and
references the token in its metadata manifest. Editions are expressed as N
single-holder agreements; gas-efficient mass-fungible editions belong in a
future extension.

### ERC-6551 (Token-Bound Accounts) — *not a tokenization kind*

A token-bound account does not change *who owns* the underlying ERC-721, so
ERC-6551 is not a separate tokenization kind (R4). Implementers who want a TBA
set `tokenization == ERC721` and configure the account off the bound NFT via
the ERC-6551 registry. Fully compatible, no core support needed.

### ERC-3525, soulbound, and future token kinds — *via `NONE`*

Assets bound to ERC-3525, soulbound tokens, or any standard the core does not
enumerate register with `tokenization == NONE` (R3/R4); the registry records
the owner explicitly and the external token, if any, is referenced from the
metadata manifest. New first-class kinds are added only by revising this ERC,
because the R5 ownership invariant requires the core to understand the token's
ownership semantics.

### EIP-2981 (NFT Royalty Standard) — *optional royalty extension*

[EIP-2981](https://eips.ethereum.org/EIPS/eip-2981) specifies
`royaltyInfo(uint256,uint256)`, returning `(address receiver, uint256 royaltyAmount)`
for a token id and sale price. The amount must be a percentage of the sale price
in the same unit of exchange; the standard prescribes neither basis-point
storage nor a fixed denominator. It reports royalty information, not payment.

Author shares here are exact rational fractions over a per-asset denominator
(R11). R11 recommends a basis-points view for consumers using that convention,
but neither shares nor that view implements EIP-2981. An optional extension
could use shares as inputs to a royalty/splitting policy; it must separately
provide the royalty interface and define any payment integration.

### ERC-3643 (T-REX / permissioned tokens) — *pattern reuse, optional integration*

[ERC-3643](https://ercs.ethereum.org/ERCS/erc-3643) requires ERC-20 compatibility
and an onchain identity system; conformance alone does not provide ERC-721's
`ownerOf(tokenId)` semantics. Its token cannot be used directly as an `ERC721`
binding merely because it conforms to ERC-3643.

The asset-claims interface (R6d/R30) reuses its claim pattern (typed, signed
claims; trusted-issuer hints). Transfer restrictions on
`ERC721` assets/agreements require a suitable ERC-721-compatible token or adapter,
potentially adopting ERC-3643-style identity/compliance checks. The bound token,
not the registry, must enforce that transfer policy (R5/R14, R22).
Use `NONE` when the registry itself must gate transfers. Neither ERC-3643 nor
identity integration is a dependency of this draft.

### ERC-5218 (NFT Rights Management) — *distinct registry model*

[ERC-5218](https://ercs.ethereum.org/ERCS/erc-5218) extends ERC-721. Its root
license is tied to the underlying NFT and follows its holder; sublicenses are
address-held `License` records associated with that NFT, not separate NFTs.
`transferSublicense` changes a sublicense's holder. License URIs may point to
legal text, human-readable summaries, or machine-readable metadata. A license's
`revoker` may be a programmable contract, allowing conditional revocation.

This draft does not inherit `IERC5218` because its core represents assets and
agreements independently of tokens. Its registry-level surfaces differ:

- **Optional token binding.** Assets and agreements can independently use
  `NONE` or `ERC721`; registering a work or agreement need not mint a token
  (R1/R19/R22).
- **Scoped references.** Alongside local ids, the draft defines canonical
  `(chainId, registry, id)` references with `ipid:`, `ipterms:`, and
  `ipagreement:` forms (R2/R17/R19/R28). These identify records; they do not
  prove work uniqueness or remote state.
- **Work provenance.** An optional signed `DerivationAttestation` (EIP-712,
  R23/R24) records an issuer's explicit "original work" or parent-asset statement,
  without requiring tokenized derivatives. Signature verification does not
  establish originality or legal authority. This differs from ERC-5218's
  license-parent tree; the draft does not define a core sublicense operation.
- **Onchain terms and queries.** Reusable, content-addressed `LicenseTerms`
  records expose a mandatory rights summary and domain-specific data (R16/R17),
  rather than relying only on URI retrieval. The permissionless, non-reverting
  `isActiveAgreementHolder(agreementId, assetId, party)` witness and bounded
  per-party discovery report agreement/holder state, not legal permission (R20).

These choices do not prevent extensions to either standard. An opt-in adapter
could map compatible token-bound cases; implementing one interface does not
automatically implement the other.

### ERC-5554 (COALA — legal use, repurposing, remixing) — *token-centered integration*

[ERC-5554](https://ercs.ethereum.org/ERCS/erc-5554) inherits `IERC5218` and adds
token-id-based copyright-owner lookup (`getCopyrightOwner`) and usage logging
(`logCommercialExploitation`, `logDerivative`, `logReproduction`). Derivative
and reproduction targets are identified by collection address and token id.
Its Rationale targets rights that follow the token, rather than personal
exclusive licenses or sublicensing.

This draft does not inherit that token-centered interface: its assets,
agreements, and parent-asset references need not be tokenized. Commercial-use
and derivative assertions belong in the mandatory `RightsSummary`, with other
terms in the universal frame, optional legal wrapper, and domain-specific
`rightsData` (R16/R16a–R16e), rather than requiring token-scoped usage logging.
An optional adapter can support overlapping token-bound use cases without
changing either standard; no automatic interface compatibility is implied.

### EIP-712 (Typed structured data) — *mandatory for derivation attestations*

Derivation-attestation signatures MUST use R23's exact EIP-712 type strings and
hash procedure so registration fields and the intended caller cannot be
substituted. Asset/identity claims remain issuer-defined opaque signatures under
R6d/R30; they do not inherit the derivation signature format.

### Identity systems (DID, ONCHAINID/ERC-734+735, ERC-725/LSP6, ERC-4337, ERC-8004) — *via hooks and extensions*

The core defines no identity interface; identity abstractions and adapters for
any of these systems are extension artifacts (R35–R37). Hooks stay
address-based, so a registry can integrate any identity scheme (or none)
without changing the core ABI.

## Interface stability and the pinned id

The `IIPAssetRegistry` ERC-165 id `0x72117f80` and the inherited
`ITermsRegistry` id `0x38c7f550` are computed from each interface's
function selectors and locked by `test/InterfaceId.t.sol`. Function-signature
changes require recomputing the relevant id; event or semantic changes can also
break compatibility without changing that id. The well-known
`TERMS_TYPE_GENERIC_V1` (`0x4975…c3f5fa`) identifies the canonical JSON line
embedded in [ERC draft §1.6](erc-draft.md#16-well-known-constants), excluding its
Markdown wrapper and line terminator. A revised schema needs a new `termsType`;
existing identifiers must not be silently redefined.

This draft revision replaces the generic transfer-policy entry point with
`canTransferAsset` and `canTransferAgreement`, without a compatibility wrapper.
Consumers of earlier draft ABIs must update; compatibility with existing token
standards is unchanged.

## No required changes to existing deployments

Because the ERC introduces new contracts and interfaces and never alters the
semantics of existing standards, there are no backwards-incompatible changes
for current ERC-721/1155/6551 deployments, indexers, wallets, or marketplaces.
Adoption is opt-in per registry (R0) and per integrator.
