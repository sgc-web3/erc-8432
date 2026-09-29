# ERC-8432 Integration Guide

This guide follows a record from publication to verification. It explains
integration decisions rather than restating the [normative specification](erc-8432.md).
The [getting-started example](getting_started.md) shows how to publish a first
asset and offer.

## Records and read paths

| Need | Calls | Watch out for |
| --- | --- | --- |
| Identify a work | `assetExists`, `assetTypeOf`, `metadataOf`, `authorsOf` | A recorded owner or author is a declaration, not proof of legal title. |
| Resolve an offer | `attachedTermsOf`, `getTerms` | `getTerms` reverts on unknown IDs; attachment parameters are public and opaque to the core. |
| Inspect a grant | `agreementOf`, `getLicensee` | `agreementOf.party` is zero for ERC-721-bound agreements; use `getLicensee` for the live holder. |
| Check a supplied witness | `isActiveAgreementHolder(agreementId, assetId, party)` | Activity includes binding, holder, expiry, revocation, and agreement freeze, but not permission for a use. |
| Discover candidates | `activeAgreementsOf(assetId, party, cursor, limit)` | `limit` counts examined records, not matches. |

Asset and agreement reads return defined sentinels for unknown IDs rather than
reverting; `getTerms` is the notable exception. `agreementOf` exposes the terms
binding and immutable creation evidence, including initial licensor/licensee,
creation mode, and optional acceptance commitment. For an ERC-721 binding,
subsequent token transfers change the effective holder without updating that
creation snapshot.

## Verify a license for a use

1. Select a registry whose behavior and governance your application trusts.
2. Obtain the `agreementId` supplied by the user or discovered in the registry.
3. Check `isActiveAgreementHolder(agreementId, assetId, user)`. Use the *same*
   agreement's `agreementOf` result to find its `termsId`.
4. Load `getTerms(termsId)`. Interpret the universal frame, rights summary,
   optional schema-specific `rightsData`, and legal text together for the
   intended use and territory. Reject or flag contradictory layers.
5. Apply your application's off-chain checks (e.g., identity, payment, legal
   acceptance, work authenticity). The registry does not attest those facts.

Do not combine an active result from one agreement with more favorable terms
from another. An `acceptanceHash` or `licenseParamsHash` is a commitment, not a
validated signature or payment receipt. `canLicense` is a policy preview; its
approval can go stale and does not bypass caller authorization.

## Discover agreements without a witness

Use the party overload of `activeAgreementsOf`. Its cursor follows the
append-only per-asset agreement index even when earlier records expire or are
revoked. For example, examining indices `0..9` can yield an empty result and a
cursor of `10` while a matching agreement exists at index `12`. Continue until
`nextCursor == agreementCountOf(assetId)`; use a positive `limit` so the cursor
can advance. Off-chain clients should query every page against a consistent
block state when they need a snapshot. Onchain consumers should prefer a known
agreement ID to a full scan.

## Terms and content integrity

There are three distinct commitments:

| Field or ID | Exact preimage | What it does *not* prove |
| --- | --- | --- |
| Asset `contentHash` | `keccak256(originalWorkBytes)` for the chosen representation | That `metadataURI` itself is hashed, or that the registrant holds rights. |
| Terms `contentHash` | `keccak256(documentBytes)` for the legal text at `uri` | That the instrument is available or enforceable. |
| `termsId` | `keccak256(abi.encode(terms))` as **one** `LicenseTerms` tuple | That independently hosted terms text is consistent with its onchain assertions. |

Hash the exact selected bytes without normalizing text, line endings, or JSON.
Terms are registered locally before attachment. Mirroring the same tuple into
another registry reproduces the same `termsId`; changing any field creates a
new ID. Detaching terms prevents future agreements under that attachment but
does not invalidate existing ones.

The mandatory `RightsSummary` is comparable across schemas: three tri-state
rights (`UNSPECIFIED`, `YES`, `NO`) and an amount-free `FeeModel`. A zero
`termsType` means the summary is the complete machine-readable rights
expression. The one standardized nonzero schema is
[`generic-license-v1`](erc-8432.md#16-well-known-constants): ABI-encode
`(bool commercialUse, bool derivativesAllowed, bool attributionRequired,
string attributionTemplate)` as a single struct. Each boolean must match an
explicit `YES` or `NO` in the summary; `UNSPECIFIED` is invalid for those
dimensions. The core stores `rightsData` without decoding it, so clients and
policy hooks must validate its encoding and consistency. The draft pins the
schema's **single-line JSON preimage**; do not hash the enclosing Markdown.
The legal wrapper is either fully absent (`uri == ""`, zero `contentHash`) or
fully present (nonempty URI and nonzero hash).

## Token bindings, lifecycle, and indexing

For `NONE`, the registry stores administrative ownership or the licensee and
applies its transfer hooks. For `ERC721`, `ownerOf` / `getLicensee` query the
bound token on every read. Failed, over-budget, or malformed `ownerOf` responses
read as `address(0)`; an agreement with no observable holder is inactive.
The registry cannot restrict external NFT transfers. If an ERC-721 agreement
moves despite `transferable == false`, the activity views still follow its
current holder; use a suitable restricted token or `NONE` when that matters.

An agreement captures an effective expiry when created: the earlier nonzero
value of the absolute `expiry` and `createdAt + duration`; both zero means no
time-based expiry. Ordinary revocation requires owner authority, captured
`revocable == true`, and `canRevoke` approval. Administrative force revocation
bypasses that hook but requires its own documented authority. Agreement freeze
makes one agreement inactive until unfrozen; asset freeze blocks new attachment
and creation but does **not** deactivate existing agreements.

For historical indexing, follow `AssetRegistered`, `MetadataUpdated`,
`TermsAttached` / `TermsDetached`, `LicenseAgreementCreated` and lifecycle
events. Also follow the bound ERC-721 contracts' `Transfer` logs; a registry
does not emit its own transfer for external token movements. For historical
rights checks, reconstruct state at the relevant time, not from today's
activity view. External token behavior can change without a transfer event,
so logs alone may not establish every historical holder state.

## Provenance across registries

The canonical references `ipid:`, `ipterms:`, and `ipagreement:` include the
deployment-captured EIP-155 `chainId`, registry address, and local ID. They
name records; they do not verify remote chain state. A derivation attestation
is signed at asset registration and can contain `ParentRef` values for other
registries/chains. It is distinct from mutable asset claims. Its signature
authenticates the issuer's statement, not actual use of a parent or an
authorizing license. Consult the [ERC-8432 EIP-712 encoding](erc-8432.md#13-derivation)
before generating or verifying an attestation; the intended registrant and
complete registration payload are part of the commitment.
