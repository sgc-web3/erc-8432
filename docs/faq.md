# FAQ

Short answers for readers and implementers. The
[ERC draft](erc-draft.md) is the authoritative specification;
[requirements.md](requirements.md) provides expanded R-number references and
[design_decisions.md](design_decisions.md) explains the rationale. This FAQ is
non-normative.

## Purpose and design

### Why isn't an IP asset just an ERC-721?

Token ownership and rights to a work are different things. This ERC records
declared authorship, administrative ownership, terms, and agreements for
off-chain, onchain, and hybrid works. Registration does not require a token.
ERC-721 is an optional binding that supplies the current administrative owner
or licensee, not proof of the underlying legal rights.
See [Overview](erc-draft.md#overview); R3-R5.

### Why focus on AI agents?

Agents need to compare offers, inspect policy, acquire agreements, and check
their state without a different integration for every vendor. Machine-readable
terms, permissionless pre-flight hooks, self-service acquisition, and bounded
discovery provide that common surface. Humans and applications use it too.
An agent still needs to interpret applicable terms and assess trust; neither
ERC-8004 nor x402 is required.
See [Motivation](erc-draft.md#motivation) and
[design principles](design_decisions.md#design-principles).

### Why allow multiple vendors and permissionless registries?

A mandatory registry list or operator would make that gatekeeper control access
to the protocol. Instead, anyone may deploy a conforming registry with its own
eligibility and governance policies. Shared interfaces enable interoperability;
catalogs and integrators decide which implementations and records to trust.
Permissionless deployment does not mean every action in a deployment is
permissionless.
See [Motivation](erc-draft.md#motivation); R0, R31-R33.

### How are jurisdiction schemes pluggable?

`jurisdictionScope` records a scope indicator, conventionally worldwide or an
ISO country code. Hooks can combine it with claims, identity evidence, and
domain-specific terms to implement a deployment's policy. Optional extensions
may add jurisdiction modules, but the core requires no particular scheme and
does not enforce territorial restrictions or determine enforceability.
The scope field is not a complete choice-of-law or court-selection clause.
See [License terms](erc-draft.md#14-license-terms); R16a, R31, R35-R37.

### Is a particular identity system required?

No. The core defines no identity interface, and a conforming registry may
remain address-only. Hooks remain address-based; deployments that need
identity-aware policy (DID, ONCHAINID, ERC-8004, …) resolve identity inside
their hooks. Common identity abstractions are extension work. See
[Pre-flight hooks](erc-draft.md#10-pre-flight-hooks); R35-R37.

### Why is authorship immutable?

It gives consumers a stable record of the authorship declared at registration.
Corrections use a replacement asset rather than changing that history; authorized
administration can freeze the old asset to stop the specified future licensing
writes. A supersession claim may link the two records without misrepresenting a
clerical correction as creative derivation. Immutability does not prove that the
original declaration was true.
See [Authorship rationale](design_decisions.md#r10--r11---immutable-authorship-and-exact-fractional-shares);
R10-R11.

### Why is there no `LicenseAgreement` or `IPAsset` value struct?

The chosen interface separates raw record fields, live ownership or licensee
state, and computed activity through targeted views. A single aggregate could
return a snapshot, but would not remove those distinctions. Immutable value
components such as `LicenseTerms` and `AgreementEvidence` are structs;
`AgreementParams` and `RegistrationParams` are input bundles.
See [Asset reads](erc-draft.md#3-asset-read-paths) and
[agreement reads](erc-draft.md#7-license-agreements-and-activity); R19, R22, R27.

## References and registry trust

### How are records identified across chains and registries?

By `(chainId, registry, id)`, encoded as
`<prefix>:<chainId>:<registry>/<id>`. The prefixes are `ipid`, `ipterms`, and
`ipagreement`. The canonical string is parseable without a resolver contract;
the registry's nonzero EIP-155 chain id is captured at deployment and retained
for its lifetime.
See [Identity and registration](erc-draft.md#2-identity-and-registration); R1-R2, R28.

### Does a cross-chain reference verify remote state?

No. It names a record for resolution and indexing; it does not bridge records,
read a remote chain from the EVM, or prove a remote license exists. Consumers
need an appropriate off-chain or verification extension for those tasks.
Registries remain independent, even when their records reference each other.
See [Cross-chain references](erc-draft.md#cross-registry--cross-chain-references);
R28.

### Can an asset attach terms from another registry?

Only after the exact `LicenseTerms` tuple is registered locally. Content
addressing gives that copy the same `termsId`. The source `ipterms:` reference
remains useful for discovery, but attachment and agreement creation do not
depend on querying the source registry at runtime.
See [Terms and attachment](erc-draft.md#6-license-terms-and-attachment); R17-R18.

### How is duplicate registration of the same work prevented?

It is not prevented globally. Within a registry,
`assetId = keccak256(abi.encode(chainId, registry, registrant, salt))`, with
`registrant = msg.sender`, and duplicate ids are rejected. A deployment can
request `salt = contentHash` for per-registrant exact-content deduplication,
or different salts for distinct registrations. Another caller cannot take a
pending registrant's id by copying the salt; this does not prevent that caller
from registering the same work under their own id.
Across registries, catalogs and consumers assess authority and supersession.
Byte identity does not establish that two different files are the same creative
work.
See [Identity and registration](erc-draft.md#2-identity-and-registration); R0-R2.

### Should licensing rely only on trusted registries?

Consumers must choose which registries and licensors they trust, including for
entirely local agreements. Correct interface declarations do not prove correct
behavior, honest records, or that a licensor owns the necessary rights.
Cross-registry provenance adds source-registry and attestation-issuer trust
questions; those references are not automatically trusted.
`setTrustedIssuer` provides policy hints, not a global trust decision.
See [Registry trust and verification scope](erc-draft.md#registry-trust-and-verification-scope);
R0, R23, R30, R33.

## Terms and agreement state

### Why have both machine-readable terms and legal text?

The fixed frame and mandatory rights summary give agents and applications a
common comparison surface; typed `rightsData` adds domain detail. An optional
URI/hash pair identifies the authoritative legal instrument when one is supplied.
These layers must agree: consumers reject or flag contradictions instead of
choosing whichever representation is more favorable. The core does not interpret
legal prose or validate those semantic relationships.
See [License terms](erc-draft.md#14-license-terms); R16.

### Does attaching terms grant a license?

No. It publishes a standing acquisition authorization, subject to creation
invariants and current `canLicense` policy. An agreement must still be created.
Attachments persist across ownership changes until detached; the owner at
agreement creation is recorded as licensor. Detachment blocks future creation
under those terms without changing existing agreements.
See [Terms and attachment](erc-draft.md#6-license-terms-and-attachment); R18-R19.

### How do granting and acquiring an agreement differ?

`createAgreement` requires the asset owner or an explicit delegate and can grant
a registry-tracked or ERC-721-bound agreement. `acquireAgreement` uses the
standing attachment authorization to create a registry-tracked (`NONE`)
agreement for its caller. Both require locally registered, attached terms,
an observable nonzero owner, and current license policy approval.
See [License agreements](erc-draft.md#7-license-agreements-and-activity); R19, R22.

### What is a "witness," and what if I don't have one?

A witness is a supplied `agreementId` identifying a candidate agreement, not a
human witness, signature, or separate cryptographic proof.
`isActiveAgreementHolder(agreementId, assetId, party)` checks that candidate
without scanning the asset's agreements.

Without an id, use paginated `activeAgreementsOf`. Its `limit` caps records
examined, not matches returned. An empty page is not enough to establish
absence: complete the scan using `nextCursor` until it reaches
`agreementCountOf(assetId)`. For a consistent off-chain snapshot, query the
pages at the same block.
See [Asset reads](erc-draft.md#3-asset-read-paths); R20, R27a.

### Does an active agreement mean a particular use is permitted?

No. Activity means the agreement has a current licensee and is not expired,
revoked, or agreement-frozen in the queried registry. Consumers must inspect
that agreement's terms for the contemplated use and apply trust and off-chain
checks. Activity does not prove legal validity, the licensor's rights, payment,
KYC, acceptance, or permission for commercial use or derivation.
See [Agreement activity](erc-draft.md#7-license-agreements-and-activity); R20.

### Does a successful pre-flight hook guarantee the transaction will succeed?

No. State or policy can change before execution, and a write still enforces its
invariants and mandatory caller authorization. The matching write evaluates
current hook policy and reverts with `HookDenied(reason)` on denial. Even a
default-permissive hook cannot authorize an unrelated caller.
See [Hooks and administrative authorization](erc-draft.md#hooks-and-administrative-authorization);
R31.

### What is the difference between freezing an asset and an agreement?

Ordinary owner revocation requires the agreement's captured `revocable` flag
to be true, as well as hook approval. False does not prevent separately
authorized force revocation or freezing, and does not decide legal termination.

Asset freeze blocks new attachments, grants, and acquisitions; existing
agreements keep their own lifecycle. Agreement freeze makes that agreement
inactive until unfrozen, subject to its other lifecycle conditions.
Revocation is permanent rather than reversible. None of these paths deletes
the agreement record.
See [Revocation and administrative paths](erc-draft.md#8-revocation-and-administrative-paths);
R21, R32.

### Can the registry stop an ERC-721 license token from transferring?

Not for an arbitrary external token. The registry enforces transferability and
`canTransferAgreement` only for `NONE`; ERC-721 restrictions must be enforced by the
bound token. An unrestricted token can move despite `transferable == false`,
and activity follows its new holder without attesting transfer compliance.
Use a suitable restricted token or `NONE` when those controls are required.
See [License agreements](erc-draft.md#7-license-agreements-and-activity); R19, R22.

### Do agreement evidence and `acceptanceHash` prove acceptance or payment?

Not by themselves. `AgreementEvidence` records creation-time facts, including
the licensor, caller, initial licensee, creation mode, and parameter commitments.
An optional `acceptanceHash` can support an extension's evidence scheme, but
the core does not define or verify a universal acceptance proof or collect
payment. Live holder state is queried separately.
See [License agreements](erc-draft.md#7-license-agreements-and-activity); R19-R20.

### Are opaque terms or licensing parameters private?

No. `LicenseTerms`, including `rightsData`, is public in calldata and through
`getTerms`; transaction-supplied licensing parameters are also public.
"Opaque to the core" means the core does not decode domain semantics.
Sensitive material can remain off-chain, or use schema-defined commitments or
ciphertext with an appropriate extension. Encrypting a legal document does
not hide the public universal frame or rights summary.
See [Public data and confidentiality](erc-draft.md#public-data-and-confidentiality).

## Provenance and authorship

### Why is derivation an attestation rather than an asset claim?

It is an optional, immutable registration-time declaration of parents signed
by an issuer. Mutable asset claims instead support topic-keyed facts that can
be replaced or revoked. The different types make these lifecycles explicit.
The derivation signature authenticates the declaration, not its truth.
See [Derivation](erc-draft.md#13-derivation); R23-R26, R30.

### Does registering a derivative require a license?

Not as a core invariant. The core verifies a supplied attestation's signature,
but does not validate parent licensing. Deployments can enforce registration
eligibility through `canRegister`; `canDerive` exposes a pre-flight question.
Remote parent state requires additional evidence or a verification extension.
There is no core parent-agreement field or standardized agreement-link layout
inside the attestation's opaque metadata.
See [Derivation and composition](erc-draft.md#9-derivation-and-composition);
R23-R26.

### How does a verifier assess whether a derivation is legitimate?

For a contract issuer, ERC-1271 approval was checked at registration and may
change later; do not treat a later failed check as proof registration was invalid.
Verify the signature using ECDSA or ERC-1271 as appropriate, and assess issuer
trust; resolve and assess the
declared parent registries and records; inspect any authorizing agreements and
their applicable terms at the relevant time. Current activity alone cannot
establish historical authorization. Whether the declared inputs were actually
used remains an off-chain question requiring evidence such as content analysis
and trusted tool attestations.
See [Derivation signatures and provenance](erc-draft.md#derivation-signatures-and-provenance);
R23-R26.

### Can authors be concealed at registration and revealed later?

Identities can, but declared shares are public and immutable. Register
`address(0)` author entries if appropriate, then disclose identities through
additive asset claims or an extension view. The registry must not replace the
placeholder addresses in canonical `authorsOf`, and consumers must assess the
later disclosure claims rather than treating them as authenticated automatically.
See [Authorship](erc-draft.md#12-authorship) and
[asset claims](erc-draft.md#5-asset-claims); R10-R11, R30.

## Scope

### Where are royalties and payments?

Outside the core. Author shares, lifecycle fields, the amount-free `feeModel`,
and domain-specific `rightsData` can inform payment extensions. These are data,
not payment hooks or settlement operations. The core neither moves money nor
defines a beneficiary/payment record; a fee classification is not proof of
payment.
See [Core exclusions](erc-draft.md#what-this-erc-does-not-do); R11, R16.

### Why no ERC-1155 for assets or agreements?

The core models one administrative owner and one current licensee per
agreement. Multi-supply ownership makes those roles and per-agreement revocation
ambiguous. Editions can use multiple single-holder agreements; fungible
editions or revenue-share tokens need an extension. An external token reference
can still appear in metadata for a `NONE` record without delegating ownership.
See [Tokenization modes](erc-draft.md#11-tokenization-modes); R3-R5, R22.

### Why no `recoverAsset` or `freezeParty` in the core?

Recovery transfers administrative authority outside the ordinary owner path,
and its authorization and objection procedures vary by deployment and
jurisdiction. A core party-freeze switch would likewise prescribe broad policy.
Recovery can be an extension; per-action hooks can consult a deployment's
sanctions or eligibility rules, but cannot block arbitrary external NFT transfers.
See [Administrative rationale](design_decisions.md#r32---break-glass-authority-without-universal-recovery-or-party-freezing);
R32.

### Does `sublicensable` create an onchain sublicense mechanism?

No. It is a recorded legal/downstream assertion. `createAgreement` remains
owner/delegate-authorized; the core has no parent-agreement relationship or
licensee-as-grantor operation. An extension must define those relationships,
authority checks, lifecycle and terms constraints, and read/event surfaces.
A permissive hook cannot supply that missing model.
See [License terms](erc-draft.md#14-license-terms); R16a, R19.

## Further reading

- Publication specification: [ERC draft](erc-draft.md)
- Expanded clauses and stable R references: [Requirements](requirements.md)
- Principles, decisions, and trade-offs: [Design decisions](design_decisions.md)
- Terms illustrations: [License terms explained](license_terms_explained.md)
- Registration-to-verification example: [Key interaction flows](key_interaction_flows.md)
