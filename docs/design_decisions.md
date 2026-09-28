# Key Design Decisions

This document explains the principles and technical choices behind the ERC.
It is non-normative: [erc-draft.md](erc-draft.md) is the authoritative
specification, and [requirements.md](requirements.md) expands it using stable
R-number references. The decisions below describe the current design, not every
intermediate proposal.

## Design principles

### Multi-chain and cross-registry by design

Assets, terms, and agreements are identified within independent registries on
EIP-155 chains. Their globally scoped references include the chain, registry
address, and record id, so applications can name records without depending on
one network or registry.

This is interoperability through common interfaces and references, not a
shared cross-chain state machine. A reference does not bridge an asset, verify
remote state onchain, or establish which of two registrations is authoritative.
Resolution, indexing, and cross-chain verification belong to consumers and
extensions.

### Multiple vendors without a privileged registry

Anyone may deploy a conforming registry. Institutional operators, independent
platforms, and permissionless services can implement the same interface with
different policies; the core does not select a vendor or maintain a blessed
registry list.

A common interface makes integration reusable without making every deployment
trustworthy. Catalogs and consumers choose which registries, issuers, and records
to rely on. Interface detection, behavioral conformance, and trust are separate
questions.

### Pluggable jurisdiction and identity policy

Different legal systems and markets need different eligibility, identity, and
administrative rules. The ERC preserves a common terms structure while leaving
those rules to deployment-specific hooks, claims, documented authorization
models, and extensions.

`jurisdictionScope` records a scope indicator, conventionally worldwide or an
ISO country code. It is not a complete choice-of-law clause or a core-enforced
jurisdiction scheme. Optional identity adapters and domain-specific rights
schemas let vendors integrate their own systems without changing the core ABI.
No particular jurisdiction module, identity provider, or legal regime is
required.

### AI agents as first-class consumers

Autonomous software needs to inspect offers, compare rights, discover
agreements, and evaluate policy before submitting transactions. Machine-readable
terms, permissionless pre-flight hooks, self-service acquisition, constant-work
verification of a supplied agreement, and bounded discovery support that flow.
Humans, wallets, and applications use the same interface.

These mechanisms reduce reliance on platform-specific APIs; they do not remove
the need for legal interpretation, schema decoding, or trust decisions.
ERC-8004 identity and x402 payment mechanisms may compose through the extension
surfaces, but neither is a dependency.

### Mechanism, not policy

The core standardizes records, lifecycle rules, read paths, and policy questions,
not the deployment's answers to every eligibility question. Hooks expose those
answers through a predictable interface.

Policy approval is not caller authorization. Owner-controlled, issuer-controlled,
governance, and administrative writes must still reject unrelated callers.
Pre-flight results are advisory snapshots: the write enforces current policy,
and approval does not establish legal permission for a contemplated use.

### Separate works, roles, offers, and grants

The underlying work can be off-chain, onchain, or hybrid, and need not be an
NFT. Its registry record is distinct from reusable license terms and from an
agreement granting a particular licensee rights under those terms.

Author, administrative owner, and licensee are independent roles, even when one
address holds several. A beneficiary is an independent economic role for
extensions, not a fourth core record or query surface. Neither administrative
ownership nor a token balance establishes ownership of the underlying legal
rights.

### Verified evidence, not legal adjudication

Content commitments, signed provenance, and agreement state provide inspectable
evidence. They do not prove authorship, that declared parents were actually used,
that the licensor held the necessary rights, or that an agreement is legally
enforceable.

Consumers must combine registry state with the applicable terms, issuer and
registry trust, and any required off-chain evidence. Keeping these boundaries
explicit avoids turning a narrow technical result into an unsupported legal
guarantee.

### The narrowest useful interoperable core

The core includes what independent implementations need to exchange records and
query their state consistently. Payments, royalty distribution, revenue-share
tokenization, graph traversal, dispute resolution, concrete identity schemes,
and jurisdiction handlers remain extension concerns.

Extensibility does not mean changing the meaning of core fields at runtime.
The ABI and enforced invariants stay fixed; open identifiers, typed payloads,
claims, and hooks carry additional meaning and policy.

## Technical decisions and rationale

### R0 / R2 / R28 - Global references without a central resolver

**Decision.** Name records using `(chainId, registry, id)` and the canonical
`ipid:`, `ipterms:`, and `ipagreement:` string forms. The canonical form needs
no resolver contract. Resolvers for alternative namespaces are extension
work.

**Reasoning.** A common foreign-reference encoding prevents each catalog or
graph extension from inventing an incompatible one. Embedding the namespace
also permits independent vendors and chains without a central registry of
registries. CAIP and interoperable-address mappings remain useful at the edges,
but a token-only identifier cannot represent every non-tokenized record or
32-byte registry id.

References identify records, not truth. Duplicate registrations across
registries are allowed, and catalogs decide which to recognize. An unregistered
work has no canonical IPid; external identifiers such as DOI can instead appear
as opaque metadata or extension-defined claims.

See [Specification §2](erc-draft.md#2-identity-and-registration) and
[Rationale](erc-draft.md#rationale).

### R1 - Precomputable asset ids from caller-chosen salts

**Decision.** Derive `assetId` as
`keccak256(abi.encode(chainId, registry, registrant, salt))`, with
`registrant = msg.sender`, and reject duplicate ids.

**Reasoning.** A registration-time derivation signature must bind the new
asset id before the transaction executes. A registry counter or transaction
ordering cannot provide that property. A caller-chosen salt also avoids making
the content hash a work's only, squattable registration slot.

A deployment can request `salt = contentHash` for exact-content deduplication,
or use distinct salts for different rights holders, territories, or replacement
records. This de-duplicates only per registrant; a different caller cannot
front-run and seize the intended id using the same salt. Salts do not prove
rights or eliminate all transaction races; the signed registration payload
separately binds the intended registrant and asset data.

### R1 / R28 - A deployment-captured chain namespace

**Decision.** `chainId()` returns the nonzero `block.chainid` captured at
deployment, unchanged for the registry's lifetime. Id derivation, canonical
references, and the EIP-712 domain all use that value.

**Reasoning.** A later chain-id change must not silently rename existing
records or change their signing domain. The view exposes this namespace to
clients already connected to the registry; it does not discover a network
endpoint from an address alone.

An existing deployment retains its namespace on both sides of a fork. This
stability does not itself distinguish fork histories or make cross-chain state
verification possible.

### R3-R5 / R22 - Closed tokenization modes with one current holder

**Decision.** Assets and agreements support only `NONE` and `ERC721`.
`NONE` stores the administrative owner or licensee; `ERC721` delegates that role
to one bound token.

**Reasoning.** Delegated ownership is safe to standardize only when the core
defines the token kind's ownership semantics. An open type id or `OTHER` mode
would require implementations to agree on semantics the ERC had never specified.
New tokenization kinds therefore need an extension or superseding ERC, not a
governance update to an enum.

ERC-1155's multi-holder model does not provide a single administrative owner or
licensee. At the agreement layer, it also makes per-agreement revocation and
holder-specific activity ambiguous. Editions can use multiple single-holder
agreements; mass-fungible editions and revenue shares belong in extensions.
Other token references may be recorded with `NONE` without delegating ownership.

ERC-6551 adds an account to an NFT rather than redefining that NFT's owner.
A registry may bind the underlying ERC-721 and configure its token-bound
account separately; no distinct `ERC6551` tokenization mode is needed.

See [Specification §1.1](erc-draft.md#11-tokenization-modes).

### R5 / R22 - Delegate live holder reads instead of caching them

**Decision.** Resolve ERC-721 ownership and licensees from the bound token on
each read. Use a gas-capped, success-checked `staticcall` with the prescribed
100,000-gas stipend and canonical 32-byte address result. Failure reads as no
current holder, not as a reverting registry view.

**Reasoning.** NFTs can transfer without notifying the registry. Caching would
introduce synchronization calls, stale ownership, and races. Direct delegation
removes that cache, while bounded reads stop a burned or hostile token from
breaking registry discovery.

Registration and agreement creation require an observable nonzero holder where
applicable. A later failed token query makes the role read as `address(0)` and
an affected agreement inactive without deleting the record. This is a defined
failure interpretation, not proof that the token contract is honest.

For `NONE`, the registry stores the role and emits its own transfer events.
For `ERC721`, indexers correlate the binding with the token's `Transfer` events.
Owner-keyed asset enumeration remains an indexer concern.

See [Specification §3](erc-draft.md#3-asset-read-paths).

### R5 / R14 / R22 - Enforce transfers where the ownership state lives

**Decision.** Registry transfers and their `canTransferAsset` and
`canTransferAgreement` hooks apply only to `NONE`.
ERC-721 transfers happen in the token contract; the registry cannot promise to
enforce their transferability or eligibility policy.

**Reasoning.** A registration-time check cannot constrain every future
transfer of an arbitrary external NFT. Deployments needing restricted NFT
ownership can combine a token-level policy callback with a `canRegister` policy
that accepts only suitable collections. Registry actions can additionally
reject ineligible current owners, but that gates their powers rather than
preventing the NFT transfer.

If every transfer must pass registry policy without token cooperation, use
`NONE`. For agreements, an unrestricted ERC-721 can transfer even when captured
terms say `transferable == false`; activity follows its current holder and does
not attest transfer compliance.

### R14 - One-step ownership transfer for registry-tracked assets

**Decision.** Transfer `NONE` ownership in one owner-authorized, hook-gated
operation. Registry `transferOwnership` rejects ERC-721-bound assets.

**Reasoning.** A core propose/accept workflow would add pending-recipient
storage, cancellation, extra events, and another lifecycle, while remaining
asymmetric with external NFT transfers. Wallets, multisigs, or extensions can
add confirmation workflows where needed.

The trade-off is that the core does not require recipient acceptance. Mandatory
caller authorization and current `canTransferAsset` policy still apply.

### R6 - Immutable work commitment, mutable metadata location

**Decision.** Keep identifying fields and an original-work content commitment
onchain, descriptive metadata at `metadataURI`, and mutable policy facts in
claims. Owners may update the metadata URI, not the original-work hash.

**Reasoning.** Rich descriptive metadata varies by domain and changes too
quickly for a fixed onchain structure. A mutable pointer supports hosting
migrations without silently replacing the work the record identifies.
An additional current-version hash or onchain pointer-history array would add
state and ambiguity; pointer history is available from events.

The asset hash is `keccak256(originalWorkBytes)`, not automatically the hash of
the document at `metadataURI`. Structured works need a deterministic selected
representation. Consumers hash exact bytes without normalization or
reserialization. The hash is mandatory for `NONE` and may be omitted for
`ERC721`; a token binding is not itself a guarantee of immutable token metadata.

Version descriptions can live in a manifest, but cannot change what the
registration-time hash commits to. `AssetRegistered` carries the initial
pointer and hash; `MetadataUpdated` carries the old and new URI and timestamp.

See [Specification §§2-4](erc-draft.md#2-identity-and-registration).

### R7 - Open asset types, not an onchain type authority

**Decision.** Use open `bytes32` asset-type ids with a small well-known set
such as audio, text, software, dataset, and model.

**Reasoning.** Asset type is descriptive; no core function dispatches on it.
An onchain authority for adding types would restrict an open-ended vocabulary
without adding an enforced invariant. Metadata schemas and domain-specific
labels can evolve outside the ERC.

The distinction is deliberate: closed enums describe core-enforced semantics;
open ids describe extensible meaning; registries of behavior handlers, such as
jurisdiction modules, are extension designs rather than core requirements.

### R8 / R9 - Registrant, owner, and authors are separate

**Decision.** The registrant submits the transaction and is recorded in
`AssetRegistered`, but receives no implicit ongoing authority. `canRegister`
evaluates registration policy over the supplied parameters.

**Reasoning.** A catalog operator or AI agent may register a work authored by
an artist and administered by a label. Conflating these parties excludes that
workflow. Persisting registrant-based powers would also create a second
administrative role without an explicit delegation decision.

Deployment policy may require author consent, identity evidence, or permitted
asset types. Those checks do not replace the core's registration invariants or
its exact derivation-signature verification.

### R10 / R11 - Immutable authorship and exact fractional shares

**Decision.** Fix the authors and their numerator/denominator shares at
registration. Authorship is a structural record, not a mutable asset claim.

**Reasoning.** Downstream consumers need a stable declared provenance anchor.
Append-only authorship corrections would handle an omitted author but not an
incorrectly included one. The chosen remedy is a replacement registration,
with the old asset frozen by authorized administration where appropriate.
A supersession claim can link the records; a clerical correction should not
be represented as a creative derivation edge.

Freezing the old asset blocks the specified future licensing writes, not the
activity of existing agreements. Those agreements retain their own lifecycle.
Recorded authorship is evidence, not a determination of moral or economic
rights under every jurisdiction.

Exact fractions avoid the rounding of fixed basis points, including ordinary
splits such as one third and fine-grained contribution shares. For a nonempty
author list, numerators sum to the positive per-asset denominator. Derived
basis-point helpers are recommended, not a required stored representation.

Empty authorship and anonymous `address(0)` entries are allowed. Later identity
disclosure can use additive claims or an extension view; it must not replace
addresses in the immutable author array. Declared shares remain public.

### R16 - Four layers of terms, not prose-only or an exhaustive rights vector

**Decision.** Every terms object has a fixed universal frame, a mandatory
rights summary, an optional legal-text anchor, and a domain payload identified
by `termsType`.

**Reasoning.** Prose-only terms require every consumer to retrieve and interpret
a document before comparing even basic rights. A fully exhaustive fixed rights
structure would instead overfit particular domains and jurisdictions. Music,
software, datasets, and patents need different details.

The hybrid keeps a small comparison floor while allowing typed `rightsData`
to express those differences. The mandatory summary does not reverse the
decision against an exhaustive global rights vector: its three rights
dimensions are tri-state, and `feeModel` classifies fees without amounts,
currencies, or settlement.

Claims were also rejected as the primary terms representation. Mutable,
issuer-keyed attestations suit facts about assets; an immutable, reusable terms
artifact does not need that lifecycle.

See [Specification §1.4](erc-draft.md#14-license-terms).

### R16a - Recorded terms are not all core-enforced

**Decision.** The universal frame stays identical across domains and
deployments. The core derives agreement expiry from `expiry` and `duration`,
and enforces `transferable` for `NONE` and `revocable` for ordinary revocation
in both tokenization modes. It records `sublicensable`, `exclusive`,
and `jurisdictionScope` for consumers.

**Reasoning.** Enforcing exclusivity would require comparing domain-specific
scopes. Interpreting every jurisdiction would require choosing legal policy.
Neither belongs in a neutral lifecycle mechanism. Hooks and extensions can
supply deployment-specific behavior without changing the common frame.

`sublicensable == true` does not authorize a licensee to call the owner-only
grant path. An onchain sublicensing extension needs a parent-agreement
relationship, licensee grant authority, child lifecycle and terms constraints,
and corresponding read/event surfaces. A hook alone does not add those missing
relationships.

### R16a / R21 - Captured ordinary revocability

The `revocable` frame value is captured at agreement creation and exposed in
the read tuple and creation event. False prevents ordinary owner revocation
even with a permissive hook; separately authorized force revocation and freeze
remain possible. This distinguishes a commitment against unilateral revocation
from expiry, legal termination, and exceptional governance intervention.

### R16b / R16e - Consistent layers and an optional exact-byte legal anchor

**Decision.** Legal text is optional but, when present, uses a paired URI and
nonzero `keccak256(documentBytes)` commitment. The frame, rights summary,
domain payload, and legal text must not contradict one another.

**Reasoning.** A legal wrapper links machine-readable terms to an identified
instrument without requiring every deployment to host legal prose. Exact-byte
hashing makes the commitment reproducible; normalization, line-ending
conversion, and reserialization would identify different content.

Protocol behavior follows the universal frame. Legal prose and `rightsData`
may supply detail or fill an `UNSPECIFIED` dimension, but cannot negate or
broaden an explicit machine-readable assertion. Consumers reject or flag
conflicts rather than selecting the most favorable layer. The core checks the
wrapper's presence pairing, not retrieved content or semantic consistency.
Correction requires new terms, not rewriting existing agreements.

### R16c / R16d - Content-addressed schemas with optional discovery

**Decision.** A nonzero `termsType` identifies a rights schema by content.
The ERC supplies one well-known schema, `generic-license-v1`; other schemas
are extension-defined. With `termsType == bytes32(0)`, the rights summary is
the complete machine-readable rights expression.

**Reasoning.** Schema identity must not depend on a vendor's mutable label or
central allocation process. Content addressing allows independent publishers
and revisions without silently changing a known schema's meaning.

Schema discovery is left to extensions; consumers with known schemas need
none. A discovery pointer is not proof of correct content or availability:
consumers retrieve the schema and verify its content-addressed identity.

The generic schema's booleans must match explicit `YES`/`NO` summary values;
`UNSPECIFIED` is not valid for its duplicated dimensions. Schema-aware
consumers enforce this rule because the core stores `rightsData` opaquely.
The pinned generic schema id and its byte-preimage rule are specified in the
draft, not redefined here. Its exact single-line JSON preimage contains the ABI
and semantics, so the draft is self-contained and editorial changes outside
that block do not change the id. This replaces the unpublished file-prefix
hash; the id was re-derived rather than retaining a repository dependency.

### R17 - Immutable local terms with exact mirroring

**Decision.** Compute `termsId = keccak256(abi.encode(terms))`, encoding one
complete `LicenseTerms` tuple in its canonical field order. Terms used by an
asset must be registered in that asset's registry. Re-registration MUST return
the existing id without changing storage or emitting an event.

**Reasoning.** Content addressing gives identical terms the same id and makes
updates explicit new objects. Local storage removes runtime dependencies on a
remote terms registry while preserving reuse: another registry can mirror the
exact tuple and obtain the same id. Idempotent registration lets callers ensure
local availability without needing to check whether the terms were registered.

Encoding separate fields, packed data, or text is not interchangeable with
encoding the single dynamic tuple. Canonical vectors in the draft provide
cross-language compatibility. Changing the struct changes content identity;
a deployment cannot silently redefine the encoding.

An `ipterms:` reference can locate the source copy off-chain, but attachment
uses a local `termsId`. Existing agreements stay bound to their original
terms when a new offer is published.

See [Specification §6](erc-draft.md#6-license-terms-and-attachment).

### R18 / R19 - Attachment is a standing offer, not a grant

**Decision.** Owners or explicit delegates attach locally registered terms.
While attached, qualifying callers may acquire agreements without a separate
owner transaction. Both grant and acquisition require the terms to remain
attached.

**Reasoning.** Separating publication of an offer from each agreement supports
self-service users and AI agents without requiring the owner to co-sign every
acquisition. Owner authorization and attachment policy protect the offer;
`canLicense` evaluates the particular acquisition.

Attachments persist through asset ownership changes; the current owner at
agreement creation is recorded as licensor. Reattachment replaces opaque
attachment parameters in place and emits their complete new value. Detachment
stops future grants and acquisitions under that attachment, but neither creates
rights nor invalidates already-created agreements.

### R19 / R22 - Separate grant and acquisition paths, no unassigned inventory

**Decision.** `createAgreement` is an owner/delegate grant to a named `NONE`
licensee or an observable ERC-721 holder. `acquireAgreement` creates a `NONE`
agreement for `msg.sender` under standing attachment authorization.

**Reasoning.** These are different authority and evidence flows. Both evaluate
`canLicense` for the effective initial licensee, not an owner or operator merely
because that address submitted a grant.

Every agreement has a licensee at creation. Preminted "unassigned" agreements
would add assignment operations and special cases while providing no consistent
meaning for token-bound custody: whoever holds a bearer token is already the
observable licensee. A marketplace may custody a tokenized agreement, but it is
not an unlicensed inventory state.

See [Specification §7](erc-draft.md#7-license-agreements-and-activity).

### R19 / R27 - Stable agreement identity and immutable creation evidence

**Decision.** Derive agreement ids from the captured chain id, registry,
asset id, and append-only per-asset agreement index. Preserve immutable
`AgreementEvidence`: licensor, actual caller, initial licensee, creation time,
grant/acquisition mode, license-parameter hash, and optional acceptance hash.

**Reasoning.** Stable indices keep discovery resumable and ids unambiguous
after revocation, expiry, or freeze. Creation snapshots distinguish who acted
and under which flow from whoever holds the agreement later.

The optional acceptance commitment is evidence supplied to policy, not built-in
proof of a licensee signature, legal acceptance, or payment. The creation event
carries the complete immutable creation state so reconstructing that evidence
does not require historical transaction calldata.

### R16a / R19 / R20 - Capture one effective expiry per agreement

**Decision.** At creation, convert the terms' absolute deadline and relative
duration into the earlier nonzero deadline. Both zero means perpetual. Reject
overflow and deadlines that would create an already-expired agreement.

**Reasoning.** A reusable offer can give each licensee a lifetime from
acquisition while still imposing a shared final deadline. Capturing one absolute
expiry makes later activity checks deterministic without reinterpreting the
original offer. Reusing the terms computes a fresh relative deadline for the
new agreement, still capped by the absolute expiry.

### R20 / R27a - A supplied agreement witness and bounded discovery

**Decision.** `isActiveAgreementHolder(agreementId, assetId, party)` checks one
candidate agreement in constant work relative to the agreement count.
The witness is simply the supplied `agreementId`, not a separate signature or
cryptographic proof. `isAgreementActive` checks one agreement's lifecycle.

**Reasoning.** A positive claim has a cheap candidate to check. Without that
id, `activeAgreementsOf` scans the stable per-asset index in pages, optionally
filtering by party. An always-current party index cannot be assumed because
ERC-721 agreements transfer outside the registry.

`limit` bounds records examined, not matches returned. An empty or short page
does not establish absence; callers must complete the scan using `nextCursor`
and `agreementCountOf`. Off-chain callers needing a coherent snapshot should
query pages against the same block state. Full discovery still grows with
history, and the append-only index consumes growing storage; pagination bounds
individual calls, not total storage or total search work.

These views report the current holder and lifecycle in the queried registry.
They do not attest permission for a specific use, territory, payment,
acceptance, or legal validity.

### R19 / R22 / R27 - Targeted reads rather than a single asset/agreement value

**Decision.** Read assets and agreements through focused functions instead of
a public `IPAsset` or `LicenseAgreement` value struct. Keep immutable components
such as `LicenseTerms` and `AgreementEvidence` as structs; parameter structs
bundle inputs.

**Reasoning.** A raw binding, a live token-derived holder, and computed activity
answer different questions. `agreementOf`, `getLicensee`, and activity views
make that distinction explicit. A returned aggregate could compute a snapshot,
but would not remove the need to distinguish stored and live values; caching
those live values would introduce synchronization problems.

Permissionless asset/agreement reads have defined unknown-id sentinels.
This is not a universal promise that every lookup succeeds: `getTerms`
deliberately rejects an unknown terms id.

### R21 / R32 - Revocation, agreement freeze, and asset freeze are different

**Decision.** Ordinary revocation requires the current asset owner or explicit
delegate, captured `revocable == true`, and current `canRevoke` approval. Administrative force revocation
bypasses that hook, not authorization. Both paths are permanent and retain the
agreement record.

**Reasoning.** Ordinary policy and exceptional intervention need distinct
authority paths. Temporary intervention instead freezes an agreement;
unfreezing removes that freeze but does not undo revocation or expiry.

An asset freeze blocks new attachments and both agreement-creation paths.
It does not revoke or deactivate existing agreements, which retain their own
expiry, current-holder, revocation, and agreement-freeze state. Ownership
transfer and terms detachment while the asset is frozen are deployment policy.

See [Specification §8](erc-draft.md#8-revocation-and-administrative-paths).

### R23-R26 - One immutable, signed derivation attestation at registration

**Decision.** An asset may include one issuer-signed `DerivationAttestation`,
fixed at registration. It is separate from mutable claims. The canonical absent
encoding is all empty/zero; a present attestation with no parents is an explicit
signed "original work" assertion.

**Reasoning.** A creator or tool can sign its declared inputs, creating
attributable provenance without requiring the registry to determine whether the
declaration is true. One structural attestation avoids choosing between
competing mutable parent lists. Further corroboration can use extensions.
Corrections require a new record rather than rewriting the recorded lineage.

The mandatory EIP-712 construction binds the full registration payload and
intended registrant as well as the asset, parents, and metadata. Signing only
the asset id would allow copied attestations to accompany altered registration
data. Exact signature rules and a recomputed `registrationHash` make that
binding interoperable.

EOA issuers use canonical 65-byte low-`s` ECDSA signatures; contract issuers
use ERC-1271 over the same digest so multisigs and institutional wallets can
attest. Verification uses a bounded `staticcall` and requires the canonical
magic response. Contract approval is a registration-time fact, not a promise
that the issuer will continue to approve the signature.

The registry verifies the signature, not actual use of parents, parent licenses,
graph validity, or legal authorization. `canDerive` exposes a local pre-flight
question; `canRegister` is the registration policy entry point. A cross-chain
parent cannot be read natively by following a reference: remote policy evidence
requires an appropriate off-chain or verification extension.

An authorizing-agreement link can be encoded in extension-defined attestation
metadata or a separate claim. The core defines no such byte layout or
parent-agreement field. Provenance and licensing are different relationships,
and a historical authorization reference must be assessed at the relevant
time, not inferred from an agreement's activity today.

See [Specification §1.3](erc-draft.md#13-derivation) and
[§9](erc-draft.md#9-derivation-and-composition).

### R27-R29 - Views for current state, events for lifecycle history

**Decision.** Provide the required live read surface and mandatory lifecycle
events with canonical fields and indexing. Retain agreement records and their
stable indices rather than deleting inactive entries.

**Reasoning.** Agents need current answers without reconstructing all history;
indexers need evidence of transitions rather than only the latest state.
Events also avoid storing a separate onchain history of every metadata pointer
or attachment-parameter update. The distinction does not make registry storage
bounded: agreement enumeration still includes retained historical records.

Canonical indexing prioritizes record identifiers, then role addresses within
the topic limit; variable payload remains event data. Successful core mutations
emit their required events, including parameter replacements and trust changes.
External ERC-721 transfers are observed from the token contract instead.

See [Specification §11](erc-draft.md#11-events).

### R6d / R30 - Mutable claims without prescribed topics or issuer schemes

**Decision.** Store one current claim per asset/topic/issuer, with replacement
and revocation, but define no well-known claim topics or universal claim
signature encoding. Issuers or authorized delegates control their claims;
governance controls registry trust hints.

**Reasoning.** Compliance, ratings, jurisdiction status, industry identifiers,
and identity-disclosure evidence need different issuers and update lifecycles.
They should not change immutable authorship or structural derivation.
Extension-defined topics provide a common mechanism without imposing those
policies on every vendor.

The registry stores claim signatures verbatim; consumers must know the issuer's
scheme and verify it. Trust hints are policy input, not automatic validation.
Revocation retains the current record with a flag, and issuer enumeration omits
revoked entries. This is not a complete stored history of every replaced claim.

See [Specification §5](erc-draft.md#5-asset-claims).

### R31 - Permissionless pre-flight hooks, separate mandatory authorization

**Decision.** Hooks are permissionless `view` calls returning
`(bool ok, bytes32 reason)`. They deny policy with a result, not a revert, and
must not revert on unknown ids. Default-permissive policy is allowed.

**Reasoning.** Agents and integrators need a common way to ask whether policy
permits an operation before spending gas. Machine-readable denial reasons make
that interaction usable across implementations.

The matching write must enforce current policy and use `HookDenied(reason)`
when denied. A prior approval may become stale, and even current approval cannot
authorize an unrelated caller. Administrative paths have separate authority
checks rather than hooks. `canDerive` is a pre-flight surface, not a mandatory
remote-parent traversal during registration.

Separate `canTransferAsset` and `canTransferAgreement` hooks distinguish
administrative ownership from licensee transfers. Their names identify the ID
namespace even if an asset and agreement have identical ID bytes, removing the
need for a public discriminator. The extra function declaration makes the
interface clearer and permits independent policies; implementations can still
share common policy internally.

See [Specification §10](erc-draft.md#10-pre-flight-hooks).

### R32 - Break-glass authority without universal recovery or party freezing

**Decision.** Standardize administrative freeze/unfreeze and force-revoke
effects, but leave their protected authorization model to deployments.
Do not include `freezeParty` or `recoverAsset` in the core.

**Reasoning.** Emergency intervention may use multisigs, timelocks, governance,
or jurisdiction-specific processes. A hook is not a substitute for that
authority. Likewise, a universal party-freeze flag would prescribe broad policy
when individual action hooks can consult a deployment's own sanctions rules.
Such hooks still cannot block arbitrary external ERC-721 transfers.

Recovery is especially sensitive: it transfers administrative power without
the current owner's ordinary authorization. Lost-key, inheritance, and court
order workflows differ too much for one mandatory recovery model.

An extension that offers recovery should consider an objection window,
multi-party authorization, and public proposal/finalization events. Recovery
must not rewrite authorship or derivation. For `ERC721`, it must operate through
the bound token's own authority model; the registry cannot recover external
token ownership by changing a cached field. Legal-process modules are one
possible deployment policy, not a universally safest or required choice.

### R33 / R35-R37 - Required interface detection, no companion interfaces

**Decision.** Require ERC-165 support for the core registry and inherited
local terms-storage interfaces. The core defines no optional companion
interfaces; schema discovery, IPid resolution, and party identity are
extension work.

**Reasoning.** Standard interface discovery is more reliable for integration
than guessing from successful calls. The pinned ids are defined in the draft
and checked by the existing interface-id tests. Advertising an interface does
not prove correct implementation, honest records, or legal authority.

Earlier drafts declared `ISchemaRegistry`, `IIPidResolver`,
`IIPPartyIdentity`, and `IIPPartyIdentityRegistry` as optional companions.
They were removed (2026-09-25) because the draft gave them no normative
semantics, which invites incompatible implementations, and because
`IIPPartyIdentityRegistry.setTrustedIssuer`/`isTrustedIssuer` had the same
signatures as the core asset-claims functions, so one contract implementing
both would merge two meanings into one function. Removing them also shortens
the draft. Hooks remain address-based; deployments that need identity look it
up within policy, and a registry may remain address-only.

See [Specification §§12-13](erc-draft.md#12-erc-165).

### R16 / R19 - Public machine-readable state, optional external evidence

**Decision.** Treat terms, their domain payload, and transaction-supplied
parameters as public onchain data. Opaque payloads are extensible, not secret.

**Reasoning.** Registry queries and agent comparison require observable
machine-readable state. An optional acceptance hash or encrypted legal document
does not hide values already submitted in calldata or stored in terms.

Sensitive supplementary material can remain encrypted or access-controlled
off-chain. Private domain values need schema-defined commitments or ciphertext
and an appropriate proof-aware or off-chain extension; the universal frame and
mandatory summary remain public. Neither a commitment nor an activity check
proves payment or compliance with the committed material.

See [Public data and confidentiality](erc-draft.md#public-data-and-confidentiality).
