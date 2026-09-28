# Security Considerations

This document expands the security considerations in `erc-draft.md`. The
referenced requirements are normative in `requirements.md`.

## Derivation signatures and provenance

EIP-712 provides domain separation but does not by itself prevent replay. The
R23 digest binds the intended registrant and every registration field in
addition to the `chainId`, registry, `assetId`, parents, and attestation
metadata. Implementations MUST use R23's exact type strings and hash procedure,
reject a mismatched `registrationHash`, and reject an existing `assetId` (R1).
A copied pending attestation therefore cannot be submitted by a different
caller or attached to altered owner, authorship, asset, token, content, or
initial metadata. The registrant-bound `assetId` also prevents a different
caller from occupying the intended id with the same salt, although it does not
prevent that caller from registering the same work under their own id.

For contract issuers, ERC-1271 approval is checked only at registration; their
signature policy may subsequently change. The 100,000-gas `staticcall` and
exact 32-byte magic-value check reject reverting, gas-griefing, and malformed
issuers without allowing unbounded returndata copying.

The EIP-712 domain and deterministic identifiers use the registry's nonzero
EIP-155 `chainId()`, captured from `block.chainid` at deployment and frozen for
the registry's lifetime (R1). Implementations MUST NOT recompute these values
from a changed live `block.chainid`; doing so after a fork would rename the
registry namespace and invalidate precomputed identifiers and signatures.

An absent derivation attestation is the completely empty struct, not merely a
zero issuer (R23). Registries MUST reject a zero issuer combined with populated
parents, signature, metadata, or registration hash. Silently ignoring such data
would create different transaction payloads with indistinguishable stored state
and could mislead submitters or off-chain auditors about what was attested.

A valid signature proves only that the issuer signed the attestation. It does
not prove that the issuer is trustworthy, that the declared parents were used,
or that the derivation was authorized. Consumers MUST apply their own issuer
trust, parent-license, and content-forensics checks (R25).

The same limitation applies to asset claims. Consumers MUST reject revoked
claims and decide which claim issuers they trust; the registry does not make
those trust decisions (R30).

## External calls and reentrancy

A delegated ERC-721 `ownerOf` call may revert, return malformed data, or consume
all forwarded gas. Implementations MUST use a 100,000-gas stipend and accept exactly
one canonical 32-byte address word
as specified by R5, R20, and R22: failure means the current holder is
`address(0)` and a corresponding agreement is inactive. A hostile token MUST
NOT make bounded registry views or hooks permanently uncallable.

Implementations or extensions that add state-changing external calls MUST
apply checks-effects-interactions, an appropriate reentrancy guard, or both.
For ERC-721-bound records, transfer-time restrictions must be enforced by the
token contract because the registry is not in the transfer path. In particular,
the registry cannot enforce an agreement's `transferable == false` value against
an unrestricted bound token. Activity views follow the token's current holder
and do not prove that a transfer complied with the terms. Deployments requiring
registry-enforced transferability MUST use `NONE`.

## Hooks and administrative authorization

`revocable == false` blocks ordinary owner revocation in either tokenization
mode, even if `canRevoke` approves. It does not block authorized force revocation,
agreement freeze, expiry, or legal termination. Licensees must assess the
registry's administrative authority independently of this captured flag.

A prior `canX` result is only a pre-flight result. Ownership, claims, or freeze
status may change before the transaction executes. The corresponding write
MUST evaluate and enforce the current policy; callers MUST NOT treat a
successful pre-flight result as a promise that a later write will succeed
(R31).

A default-permissive hook does not demonstrate that any policy was applied.
Integrators MUST assess the registry's actual hook implementation before
relying on it.

Claim writes and trusted-issuer configuration are separate authorization
surfaces, not default-permissive hooks. Implementations MUST prevent arbitrary
callers from adding or revoking claims under another issuer and MUST restrict
trusted-issuer changes to their documented governance authority. Administrative
authorization to store a claim does not validate its signature; consumers MUST
verify signatures independently.

`freezeAsset`, `unfreezeAsset`, `freezeAgreement`, `unfreezeAgreement`, and
`forceRevokeAgreement` are not hook-gated. Implementations MUST protect these
administrative paths according to their declared authorization model and emit
the required events (R29, R32). Integrators should assess that model before
relying on a registry.

Consumers MUST distinguish the two freeze scopes. Asset freeze blocks future
attachments and agreement creation but does not invalidate existing agreements.
Only agreement freeze changes agreement activity, and it affects only the named
agreement. Treating asset freeze as retroactive revocation would incorrectly
erase previously granted rights from activity queries.

## Registry trust and verification scope

Anyone may deploy a registry. ERC-165 conformance proves only that a contract
exposes an interface; it does not establish that the registry, its issuers, or
its records are honest (R0, R33). Integrators MUST choose which registries to
trust.

`isActiveAgreementHolder`, `isAgreementActive`, and related views report only the current
onchain agreement state in the queried registry. They do not establish legal
validity, the licensor's underlying rights, permission for a contemplated use or
territory, payment, KYC, or acceptance of off-chain terms. Consumers MUST inspect
each active agreement's own terms and perform the relevant off-chain checks. They
MUST NOT combine one agreement's active state with another agreement's rights.

`AgreementEvidence.licensor` records the asset's administrative owner at
creation; it does not prove underlying legal title. `acceptanceHash` and
`licenseParamsHash` are commitments, not proof of signature validity, payment,
or informed acceptance. Consumers must obtain the preimages, verify any claimed
signatures, and apply the terms and registry policy that define their meaning.

`LicenseTerms.sublicensable` is a recorded legal/policy assertion, not core
grant authority. The core has no sublicense action or parent-agreement field,
and `createAgreement` remains asset-owner-authorized. Integrators MUST NOT infer
an onchain sublicense relationship from this flag without an extension that
defines and verifies that relationship and its lifecycle.

Cross-chain references are identifiers for off-chain resolution. They MUST NOT
be treated as onchain verification of remote state. A deployment that mirrors
remote data locally must account for stale or dishonest mirrors.

`IPAsset.contentHash` anchors the exact original-work representation chosen at
registration, not automatically the metadata document at `metadataURI`.
Consumers MUST use the metadata to resolve that representation and verify its
`keccak256`. Consumers resolving `LicenseTerms.uri` MUST verify the exact legal
document bytes against `LicenseTerms.contentHash`. Normalization,
reserialization, or format conversion before hashing invalidates either check.
An unavailable URI does not invalidate the onchain record, but it may make the
referenced content unusable.

Machine-readable fields and legal text MUST be reviewed for semantic
consistency before terms are attached or accepted. The core cannot inspect
opaque schemas or prose. A malicious publisher can therefore create
content-addressed but contradictory terms. Consumers MUST reject or flag a
conflict rather than choosing the favorable representation. Registry behavior
continues to follow the universal frame; legal enforceability of contradictory
prose is outside the protocol.

## Denial of service and pagination

Callers of either `activeAgreementsOf` overload MUST advance `nextCursor` until
it equals `agreementCountOf(assetId)`. Its `limit` bounds records examined, not
records returned (R20, R27a). An empty page is not proof of absence. Consumers
with an `agreementId` SHOULD prefer the constant-work
`isActiveAgreementHolder` witness check.

Other array-returning views, including `attachedTermsOf` and `getClaimIssuers`,
have no protocol-enforced size bound. Implementations
expecting large collections SHOULD provide pagination, and onchain consumers
SHOULD avoid depending on unbounded results.

Schema registries may return incorrect or unavailable pointers. Content
addressing detects mismatched bytes; it does not guarantee honest registries.
Consumers MUST verify `keccak256(canonical schema bytes) == schemaId` (R16d).
For `generic-license-v1`, hash the exact single JSON line in
[ERC draft §1.6](erc-draft.md#16-well-known-constants) as UTF-8, without fences,
a BOM, surrounding whitespace, or its line terminator. Do not normalize,
reserialize, or hash the enclosing Markdown document.

## Public data and confidentiality

The complete `LicenseTerms` tuple is public and permanent: `registerTerms`
exposes it in transaction calldata and `getTerms` returns it, including the
universal frame, rights summary, `termsType`, and `rightsData`. "Opaque to the
core" means the core does not interpret `rightsData`; it does not make those
bytes confidential. Asset claims, derivation metadata, events, and other
transaction inputs are likewise public. Sensitive values MUST NOT be placed in
these fields with an expectation of secrecy.

Supplementary legal, pricing, personal, or KYC content MAY be encrypted or
access-controlled off-chain and referenced by the public `LicenseTerms.uri`.
Consumers receiving it MUST verify it against `LicenseTerms.contentHash`. This
does not conceal values encoded directly in `LicenseTerms`. Private
domain-specific values require a schema-defined commitment or ciphertext in
`rightsData` and an off-chain or proof-aware extension; the universal frame and
mandatory rights summary remain public.

## Extension assumptions

Extensions that settle from off-chain facts, such as usage or play counts,
inherit the trust and manipulation risks of their oracle. This ERC provides no
oracle or dispute-resolution guarantee. Extension authors MUST document the
oracle and dispute assumptions on which settlement depends.

The core does not collect transfer or resale fees. Such fees are enforceable
only when the transfer or settlement path enforces them. Integrators MUST NOT
assume that recording a fee obligation causes payment.

Recovery mechanisms added by extensions can override ownership authority.
Extension authors SHOULD require delayed, multi-party authorization and MUST
NOT permit recovery to rewrite immutable authorship or derivation data.
