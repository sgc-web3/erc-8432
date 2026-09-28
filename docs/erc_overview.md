# Onchain IP Asset and License Registry

This is a non-normative introduction. The [ERC draft](erc-draft.md) defines the
interface and required behavior.

## What it records

| Record | Purpose |
| --- | --- |
| IP asset | Identifies a work, its declared authors, administrative owner, metadata pointer, and optional signed derivation attestation. |
| License terms | Immutable, reusable conditions identified by `termsId = keccak256(abi.encode(terms))`. |
| License agreement | A grant binding one asset, one locally registered terms record, and a licensee. |

Works may be off-chain, onchain, or hybrid. Assets and agreements can be
registry-tracked (`NONE`) or bound to an ERC-721 token (`ERC721`). For a bound
record, the current token holder supplies the owner or licensee; token ownership
alone does not prove legal rights in the work. The registry's owner is an
administrative role, distinct from declared authors and licensees.

Each record has a globally scoped reference:

```text
ipid:<chainId>:<registry>/<assetId>
ipterms:<chainId>:<registry>/<termsId>
ipagreement:<chainId>:<registry>/<agreementId>
```

These strings name records across registries and chains; they do not verify
remote state or establish which registry is trustworthy. Terms must be
registered locally before they can be attached to an asset, though identical
terms can be mirrored to another registry under the same `termsId`.

## Licensing in five steps

1. Register an asset with `register(RegistrationParams)`. A nonzero
   `contentHash` commits to the chosen original-work bytes (required for
   `NONE`, optional for `ERC721`); `metadataURI` is a mutable descriptive
   pointer, not necessarily the hashed content.
2. Register `LicenseTerms` and attach the returned `termsId` to the asset.
   Attachment publishes a standing acquisition offer; it grants no rights by
   itself. Terms contain a lifecycle frame, mandatory rights summary, optional
   URI/hash anchor for legal text, and optional schema-specific `rightsData`. The
   `generic-license-v1` schema and its exact hash preimage are in the
   [draft](erc-draft.md#16-well-known-constants).
3. The owner or an authorized delegate grants an agreement with
   `createAgreement`, or an eligible caller obtains a `NONE` agreement under
   attached terms with `acquireAgreement`. Both paths check current
   `canLicense` policy. Payment and legal acceptance are not established by
   creation alone.
4. Given an `agreementId`, check
   `isActiveAgreementHolder(agreementId, assetId, party)` without scanning other
   agreements. Without an ID, use paginated `activeAgreementsOf`; `limit`
   bounds records examined, not matches, so an empty page may not end the scan.
5. Read **that agreement's** terms to assess the proposed use. An active result
   reports current registry state (holder, expiry, revocation, freeze), not
   legal validity, payment, or permission for a particular use.

## Policy and provenance

Permissionless `canX` views expose deployment-specific policy before a
transaction. A favorable result is advisory: writes also enforce current policy
and mandatory caller authorization. Deployments document their delegation and
administrative authority; ERC-165 support alone does not establish their
trustworthiness.

An asset can include an immutable derivation attestation at registration. Its
signature authenticates the issuer's declaration and may name parent assets in
other registries or chains; it does not prove that those works were used or
licensed. Asset claims are separate, mutable issuer-attributed records.

The core does not distribute royalties, collect fees, enforce legal rights,
traverse derivation graphs, or verify cross-chain state. For ABI, schema bytes,
lifecycle rules, rationale, backwards compatibility, and security considerations,
consult the [ERC draft](erc-draft.md).

To build against the interface, start with the [implementer walkthrough](getting_started.md).
For verification and indexing, see the [integration guide](integration_guide.md);
for technical trade-offs, see [design decisions](design_decisions.md).
