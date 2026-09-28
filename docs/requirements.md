# ERC Requirements — Working Draft

> Status: work in progress. Requirements use RFC 2119 keywords (MUST / SHOULD / MAY)
> so they are testable against any candidate implementation.
> [erc-draft.md](erc-draft.md) is the authoritative, self-contained specification;
> this document expands its requirements and preserves stable R-number references.
>
> Groups:
> - **R0**      Permissionless registry deployment
> - **R1–R9**   Identity & Registration
> - **R10–R14** Authorship & Ownership   *(R12, R13 reserved)*
> - **R16–R22** Licensing                *(R15 reserved)*
> - **R23–R26** Derivation & Composition
> - **R27–R29** Discoverability & Events
> - **R30–R33** Extensibility & Hooks    *(R34 reserved)*
> - **R35–R37** Party Identity *(moved to extensions)*
>
> Status: R0, R1–R33, and R35–R37 are locked. Several requirements carry
> lettered sub-requirements (e.g. R2a–R2b, R6a–R6d, R16a–R16d, R27a) that
> refine a parent requirement without consuming a new top-level number.
> R2a, R16d, and R35–R37 no longer define core interfaces: the optional
> schema-registry, IPid-resolver, and party-identity interfaces were removed from
> the core and are left to extension ERCs.

## Reserved requirement numbers

R12, R13, R15, and R34 are **intentionally unallocated**. Their content was
merged into other requirements during the trim passes that tightened this
spec. The numbers are **reserved and never reused**: every R-number is a
*stable identifier* referenced from the Solidity NatSpec, the test suite
(`test/`), and the companion docs, so reshuffling live numbers to "close the
gaps" would silently invalidate those references. New requirements take the
next free top-level number or a lettered sub-number under their parent (e.g.
R27a); they never fill a reserved slot.

| Reserved | Disposition |
| --- | --- |
| R12, R13 | Former standalone role/authorship-distinction requirements, collapsed into R10 and the Design Philosophy "roles are independent" stance during the medium trim pass. |
| R15 | Collapsed in the same trim pass; the ownership-transfer surface settled as the one-step R14 (see the R14 rationale in `design_decisions.md`). |
| R34 | Never allocated; the Extensibility & Hooks group settled at R30–R33 and Party Identity (added later) resumes at R35. |

This is the same convention used for reserved fields and opcodes elsewhere in
Ethereum: a gap that is *documented as reserved* is unambiguous, whereas a
renumber breaks every prior reference.

---

## Design philosophy

These recurring stances inform every requirement and are stated once here so
that individual requirements stay focused on interface and behavior rather
than re-asserting the same philosophy. They reflect the authoritative ERC draft;
[design_decisions.md](design_decisions.md#design-principles) explains the
principles and their rationale.

1. **Permissionless protocol layer.** Anyone may deploy a registry. The core
   ERC defines no central authority or allow-list over registry deployment.
   Independent vendors and chains share canonical references (R2/R28), not
   automatically shared or verified state. Trust filtering is downstream
   (catalogs, integrators, reputation), not at the protocol layer.
2. **Hooks for extensible policy.** Eligibility and compliance decisions such
   as KYC, AML, and jurisdiction are exposed through hooks. Mandatory caller
   authorization remains separate: owner-controlled, issuer/governance, and
   administrative writes MUST reject unrelated callers under the deployment's
   documented authorization model. Hooks also serve as read-only pre-flight
   checks for AI agents.
3. **Onchain for decisions, off-chain for presentation.** Facts that hooks
   and compliance modules consume can be represented as onchain claims (R6d).
   Descriptive metadata lives off-chain at a mutable URI; the asset's immutable
   content hash anchors the original work, not necessarily that metadata
   document (R6a).
4. **Roles are independent.** Author, Owner, Licensee, and Beneficiary are
   orthogonal roles relating to an asset. The core distinguishes authorship,
   administrative ownership, and the licensee in its records and operations;
   the economic Beneficiary role belongs to extensions, not a core query or
   payment surface. The same address MAY hold multiple roles. These records
   do not by themselves establish underlying legal rights.
5. **Narrowest useful primitive.** The core ERC standardizes only what
   cross-implementation composability requires. Stances are documented once
   in this section; everything else either specifies an interface that
   implementers must produce, or is moved to an extension.

## Identity & Registration

### R0. Permissionless registry deployment

Anyone MUST be able to deploy a conforming `IPAssetRegistry` contract. The
core ERC MUST NOT define any gating, allow-listing, or central authority
over which registries are recognized. A deployment is conforming only if it
satisfies the ERC's required interfaces and normative behavior. Advertising
ERC-165 support does not prove that behavior, honest records, or legal authority.
Reputation and trust are external concerns handled by catalogs (extension) and
by integrators choosing which registries to read.

Consequences:

- The core ERC has no notion of a "blessed" registry. All registries are
  equally first-class at the protocol layer.
- Scam, low-quality, or non-compliant registries are filtered downstream
  (catalogs decline to index them, integrators decline to read them), the
  same pattern that operates today for ERC-721 collections.
- Every policy decision about what a registry accepts (KYC, asset types,
  jurisdictions, etc.) lives in that registry's `canRegister` hook (R9) and
  related hooks, not in the ERC.

### R1. Asset identifier

An IP Asset MUST be identified by a `bytes32 assetId` that is unique within its
issuing `IPAssetRegistry`. The `assetId` is opaque: arithmetic on it has no
defined meaning.

The `assetId` MUST be derived from a registrant-supplied `bytes32 salt`
(carried in `RegistrationParams`, R8) as:

```
assetId = keccak256(abi.encode(chainId, registry, registrant, salt))
```

`registrant` is the caller of `register` (`msg.sender`). Here and throughout
this ERC, `chainId` is the issuing registry's `chainId()`
value. A conforming registry MUST capture `block.chainid` at deployment, MUST
reject deployment if that value is zero, and MUST return the captured value
unchanged for its lifetime. It MUST NOT switch to a later live `block.chainid`
after a fork or chain-id change. The captured value is the registry's nonzero
EIP-155 namespace and MUST be used consistently for asset and agreement ids,
canonical references, and the EIP-712 domain in R23.

The registry MUST reject duplicate ids within itself. Deriving from a
caller-chosen `salt` (rather than from registry-internal state such as a
counter) is REQUIRED so that the `assetId` is **pre-computable before the
registration transaction** — a derivation attestation (R23) is signed by its
issuer over the `assetId` and supplied in the same `register` call (R24), so
the id must be knowable in advance.

Registries that want per-registrant content-addressed de-duplication instruct
registrants to set `salt = contentHash` (or a hash derived from it); a single
registrant can register the same work more than once (e.g. for territories or
the supersession remedy of R10/R24) using distinct salts. Deriving the id from a
caller-chosen salt rather than directly from `contentHash` also avoids
**identity-squatting** in a permissionless registry (R0): a work has no
single mandatory id slot. Binding the registrant prevents another caller from
front-running a pending registration to seize its precomputed id. Separate
registrants can still register the same work; downstream catalogs arbitrate
authority.

### R2. Canonical global identifier and IPid string form

The canonical global identifier of an IP Asset is the tuple
`(chainId, registry, assetId)`.

The core ERC defines a canonical string form ("IPid") for this tuple:

```
ipid:<chainId>:<registry>/<assetId>
```

where:

- `<chainId>` is the EIP-155 chain id encoded as a base-10 ASCII integer with
  no leading zeros (the value `0` is reserved and MUST NOT appear in a valid
  IPid),
- `<registry>` is the 20-byte address of the `IPAssetRegistry` contract,
  encoded as a `0x`-prefixed lowercase hex string of exactly 42 characters,
- `<assetId>` is the 32-byte asset identifier, encoded as a `0x`-prefixed
  lowercase hex string of exactly 66 characters.

The canonical form MUST be parseable without any onchain resolver. A
reference parser/encoder library is provided alongside the ERC
(`src/IpRef.sol`, with `src/IPid.sol` as a thin back-compat alias for the
asset-specific surface).

### R2a. Alternative IPid namespaces (extension)

Mapping alternative IPid namespaces (catalog-native, DID-based,
rights-society-native, etc.) to the canonical `(chainId, registry, assetId)`
tuple is an extension concern. The core ERC defines no resolver interface, and
the canonical form defined in R2 MUST always be usable without one.

### R2b. External (non-registered) references

External references to works that are not registered in any compatible
`IPAssetRegistry` MUST NOT use the IPid scheme. Such references MAY appear
inside claim payloads as opaque tagged URIs (e.g., `doi:…`, `jasrac:…`,
`urn:…`) but are not resolvable through the core IPid interface and are
treated by the ERC as opaque strings.

### R3. Onchain, off-chain, and hybrid assets

The ERC MUST support IP Assets whose underlying work is off-chain, onchain,
or hybrid. Registration MUST NOT require the existence of a token. The
registry record is the onchain source of truth for authorship, ownership,
terms, and metadata, regardless of where the work itself is stored.

The first-class onchain binding is ERC-721 (R4). Assets bound to other
token standards (ERC-1155, ERC-6551, soulbound, ERC-3525, future kinds)
are supported via `tokenization == NONE`: the registry records the owner
explicitly and the asset MAY reference the external token through its
metadata manifest (R6a). The R5 ownership-delegation invariant applies
only to `ERC721`.

The ERC does not support assets that have no `IPAssetRegistry` record on any
chain. Such "dangling" assets cannot answer any of the core queries (owner,
authorship, licensing, derivation) and are therefore out of scope.

### R4. Tokenization kind (fixed enum)

Each IP Asset MUST expose a `tokenization` value drawn from a fixed enum
defined by this ERC:

```solidity
enum AssetTokenization { NONE, ERC721 }
```

The enum is intentionally closed and intentionally small. New tokenization
kinds MUST be added by revising this ERC, not by external registration,
because the ownership invariant in R5 only holds when the core ERC knows what
"ownership" means for the given token kind — a semantic that cannot be safely
delegated to a third-party registry.

For `NONE`, the asset is off-chain, hybrid, or bound to a token standard that
the core ERC does not enumerate (e.g. ERC-1155, ERC-6551, soulbound, ERC-3525,
or a future standard); the registry records the owner explicitly. For
`ERC721`, the asset is bound to a specific token in an external ERC-721
contract and the registry MUST record that binding (collection address and
token id).

For `ERC721` registration, `RegistrationParams.owner` MUST be
`address(0)` because ownership comes only from the bound token. The collection
MUST be a non-zero address containing contract code, and registration MUST
perform R5's bounded canonical `ownerOf(tokenId)` query. A revert, over-budget
call, malformed result, or zero holder MUST reject registration. The resolved
non-zero holder is the initial owner emitted by `AssetRegistered`; it is not
cached.

ERC-1155 is deliberately excluded from the IPAsset tokenization enum: the
multi-supply ERC-1155 patterns that arise in IP licensing (fractional
revenue shares, gas-efficient mass editions) belong on payment-extension
tokens, not on the asset itself — and not on `LicenseAgreement` either,
which is single-holder (R22). ERC-6551 is
deliberately excluded because an ERC-6551 token-bound account does not
introduce a new ownership semantic at the asset level — the asset's owner is
still the holder of the underlying ERC-721 — so the existence of a TBA is an
asset-implementation detail, not a tokenization kind.

### R5. Ownership and the `ownerOf` invariant

Each IP Asset has exactly one owner address representing the *administrative*
role: the party authorized to update the asset's metadata, configure license
terms, and transfer ownership. Ownership is mutable, is
distinct from authorship (R10), and is distinct from any economic-beneficiary
or licensee role. The core ERC recognizes a single owner and does not define a
separate operator or delegate role in its ABI; any delegation of administrative
authority (an "operator" model) is implementer-defined and enforced through the
implementation's authorization policy and pre-flight hooks (R31).

The behavior of `registry.ownerOf(assetId)` depends on the asset's
`tokenization` value (R4):

- **`NONE`**: the registry stores the owner address. Ownership transfers go
  through the registry and MUST emit `OwnershipTransferred`.
- **`ERC721`**: `registry.ownerOf(assetId)` MUST delegate to
  `IERC721(collection).ownerOf(tokenId)` for the bound token. The registry
  MUST NOT cache the owner. The call MUST use a 100,000-gas stipend and accept
  exactly one canonical 32-byte ABI address word. If the bound token's `ownerOf`
  reverts, exhausts that stipend, returns any other length, or returns a word
  greater than `type(uint160).max`, `registry.ownerOf(assetId)`
  MUST treat the asset as currently ownerless and return `address(0)` rather
  than propagate the revert, so the non-revert guarantee of the R27 read
  paths holds. Off-chain indexers that need to observe
  ownership changes for `ERC721`-tokenized assets MUST listen to the bound
  token contract's `Transfer` events in addition to the registry's own
  events.

The owner, author, and licensee roles MUST remain distinct even when the same
address holds multiple roles. Core event obligations are those specified in R29,
not separate events for every role. Beneficiary and payment roles remain
extension concerns.

---

### R6. Metadata model

Metadata about an IP Asset is split across four layers, each with a different
writer, lifecycle, and onchain footprint. Only the *identifying* and
*pointer* layers live in the asset record; *descriptive* metadata lives
off-chain at the pointer; *compliance* metadata lives as onchain claims.

| Layer | Lives | Writer | Mutability |
| --- | --- | --- | --- |
| Identifying | Asset record (onchain) | Registrant | Set at registration |
| Pointer    | Asset record (onchain) | Owner | Mutable (URI), immutable (hash) |
| Descriptive | Manifest at pointer (off-chain) | Owner | Mutable; not necessarily covered by the work's `contentHash` (R6a) |
| Compliance | Claims registry (onchain, per R6d) | Named issuer or explicitly authorized delegate (R30); trust is a separate policy input | Replaceable/revocable per topic and issuer |

#### R6a. Pointer and integrity

Each IP Asset MUST expose:

- `metadataURI` — an opaque string URI pointing to an off-chain JSON manifest
  describing the asset. Mutable by the owner. The ERC does not constrain the
  URI scheme; consumers and catalogs are responsible for validating it.
- `contentHash` — a `bytes32` hash anchoring the *original* work the asset
  refers to. **Immutable** once set at registration.

`contentHash` MUST equal `keccak256(originalWorkBytes)`, where
`originalWorkBytes` is the exact canonical byte sequence selected by the
registrant as the original work representation. Consumers MUST NOT normalize,
transcode, reserialize, or otherwise transform that sequence before hashing.
For multi-file or structured works, the registrant first chooses a deterministic
byte representation, such as a canonical manifest containing component hashes.
The ERC does not prescribe packaging: equality proves byte identity, not that
two differently encoded representations are semantically the same work.

`metadataURI` describes the asset and MAY specify how to retrieve or reconstruct
`originalWorkBytes`. Its returned metadata document is not itself covered by
`contentHash` unless the registrant deliberately chose that document as the
original-work representation.

`contentHash` is REQUIRED at registration when `tokenization == NONE`, giving
the registry-tracked work an immutable byte commitment. It is OPTIONAL when
`tokenization == ERC721`, where consumers may use integrity mechanisms supplied
by the bound token. An ERC-721 binding or `tokenURI` alone does not guarantee
immutable or authentic content.

`contentHash` is a **registration-time anchor**: it is fixed in the same
`register` call that mints the asset and is immutable thereafter. There is no
later setter — an `ERC721` asset registered with no `contentHash` (`bytes32(0)`)
never acquires one. Consumers must assess any external integrity mechanism
separately.
Accordingly the initial `metadataURI` and `contentHash` are reported in the
`AssetRegistered` event (R29), while subsequent URI changes are reported in
`MetadataUpdated`, so that event-only indexers capture the complete state
without a view call.

The asset record stores **only the current pointer**. Historical versions are
not stored onchain. Because `contentHash` is immutable, the only metadata that
changes after registration is `metadataURI`; the full history of `metadataURI`
MUST be recoverable from the initial URI in `AssetRegistered` and the
`MetadataUpdated` event stream (see R29), which MUST include the old and new URI
plus a timestamp. The
`updateMetadata(assetId, newURI)` entry point moves only the URI and MUST NOT
provide any means of altering `contentHash`.
Its caller MUST be the asset's current administrative owner or an address
explicitly authorized to act for that owner under the registry's documented
delegation policy. This mandatory authorization is independent of
`canUpdateMetadata`; a permissive hook MUST NOT authorize an unrelated caller.

Versioning *within* an asset (remasters, translations, corrections) is a
manifest-internal concern. `contentHash` always anchors the *original* work
and MUST NOT be updated when the manifest publishes new versions. Onchain
versioned manifests (Merkle-rooted history, version arrays) are explicitly
out of scope for the core ERC and are left to extensions.

#### R6b. Metadata layer boundaries

The core ERC MUST NOT store free-form descriptive metadata in the asset
record. Descriptive metadata (title, synopsis, director, composer, sample
rate, dataset row count, etc.) lives in the off-chain manifest at
`metadataURI`.

Compliance facts (KYC status of the owner, age rating, sanctions hits,
training-data-inclusion flag, JASRAC administration status, etc.) MUST NOT
live in free-form metadata. They MUST be represented as onchain claims
(R6d) so that hooks and compliance modules consume a typed, signed,
auditable source rather than parsing an off-chain document.

#### R6c. Schema selection by asset type

The off-chain manifest at `metadataURI` SHOULD conform to a JSON schema
selected by the asset's `assetType` (R7). Schemas are content-addressed:
the canonical schema id is `keccak256` of the canonical schema document.

The core ERC defines the *mechanism* — content-addressed schema ids,
extension-defined discovery (R16d) — but ships no schemas of its own
in this group. Schema definitions are community / extension artifacts,
analogous to the ERC-721 metadata schema today.

Implementations MUST function without any schema registry: an unknown or
unparseable manifest does not invalidate the asset record.

#### R6d. Asset claims registry

Each IP Asset MUST expose a claims interface parallel to the identity-claims
model of ERC-3643. A claim about an asset is a tuple
`(topicId, issuer, data, signature)` where:

- `topicId` is a `bytes32` claim-topic identifier, drawn from an open set
  (same pattern as R7).
- `issuer` is the address (or identity contract) that attested the claim.
- `data` and `signature` follow the ERC-3643 claim shape.

Trusted issuers per topic are configured by the implementer, not by the core
ERC. Compliance modules consuming claims pick which issuers they trust. The
ERC defines the *mechanism* for storing, querying, and revoking claims about
assets, and for checking their status (existence, revocation, and
trusted-issuer status); it stores each claim's `signature` verbatim but does
**not** itself verify that signature onchain (unlike a derivation attestation,
R23/R25, whose signature the core does verify). It does not define *which*
claims must exist or *who* may issue them.

**The core ERC ships no well-known claim topic ids.** Authorship (R10)
and derivation (R23) are first-class structural fields on the asset
record, not claims. Compliance, KYC, sanctions, age ratings,
third-party attestations vouching for authorship or derivation, and
similar facts are entirely implementer-defined and the topic ids for
them are minted by the relevant extension or implementer using the
same `keccak256(<descriptive string>)` convention as R7.

The function ABI for this interface is specified in R30.

---

### R7. Asset type (open identifier with well-known set)

Each IP Asset MUST declare an `assetType` of type `bytes32`. The core ERC
defines a set of well-known type identifiers as `keccak256` hashes of short
descriptive strings:

| Constant | Preimage |
| --- | --- |
| `ASSET_TYPE_AUDIO`     | `"audio"` |
| `ASSET_TYPE_VIDEO`     | `"video"` |
| `ASSET_TYPE_IMAGE`     | `"image"` |
| `ASSET_TYPE_TEXT`      | `"text"` |
| `ASSET_TYPE_SOFTWARE`  | `"software"` |
| `ASSET_TYPE_DATASET`   | `"dataset"` |
| `ASSET_TYPE_MODEL`     | `"model"` |
| `ASSET_TYPE_PATENT`    | `"patent"` |
| `ASSET_TYPE_ALGORITHM` | `"algorithm"` |

Implementers MAY use any other `bytes32` value, conventionally
`keccak256(<lowercase ASCII descriptive string>)`. The core ERC does not
maintain an onchain registry of asset types: asset type is descriptive
metadata, not behavior, and no core function dispatches on it. Discovery and
human-readable labelling of non-well-known types is the role of catalogs
(extension layer).

The set of well-known constants MAY be extended by future revisions of this
ERC. Existing well-known values MUST NOT be renumbered or repurposed.

---

### R8. Registration: registrant, owner, and authors are distinct roles

The `register(...)` entry point of an `IPAssetRegistry` MUST accept, as
explicit parameters (typically bundled in a `RegistrationParams` struct):

- a `salt` (`bytes32`) from which the `assetId` is derived (R1). The salt
  fixes the `assetId` up front so it can be signed over by a derivation
  attestation (R23/R24) and so that the same work can be registered under
  distinct ids when required,
- an `owner` address (the administrative role per R5): non-zero and stored for
  `NONE`, canonically `address(0)` and not stored for `ERC721`,
- the `authors` array together with `sharesDenominator` (the moral-rights
  role per R10–R11),
- the initial identifying metadata: `assetType` (R7), `tokenization` (R4)
  and any associated token binding, `metadataURI` and `contentHash` (R6a), and
- an OPTIONAL `derivationAttestation` (R23). Absence has one canonical encoding:
  `issuer == address(0)`, empty `parents`, `signature`, and `metadata`, and
  `registrationHash == bytes32(0)`. A zero issuer accompanied by any nonempty
  or nonzero attestation field is malformed and registration MUST revert; those
  fields MUST NOT be silently ignored.

The transaction sender (`msg.sender`) is the **registrant**: the party
submitting the registration. The registrant MAY equal the owner, MAY equal
one of the authors, and MAY equal neither (e.g. a catalog operator
registering on behalf of an artist, a label registering on behalf of an
employee, a rights society batch-registering a back catalog, or an AI
agent's operator registering a derived work).

For `NONE`, token-binding inputs are ignored and their stored values MUST be
normalized to `address(0)` and `0`. For `ERC721`, the zero `owner` input remains
part of R23's signed registration payload, while `AssetRegistered.owner` MUST
emit the non-zero token holder resolved during registration.

The registrant role is **transient**: it exists only at the moment of the
registration transaction. The registrant identity MUST be recorded in the
`AssetRegistered` event for auditability, but MUST NOT be stored as a
persistent field on the asset record and MUST NOT confer any ongoing
authority over the asset after registration completes.

Any post-registration authority the registrant may need (the right to update
metadata, configure license terms, etc.) MUST derive from being (or becoming)
the asset's owner, or from an implementer-defined delegation ("operator") policy
enforced by the implementation — not from an implicit privilege of having
registered the asset. The core ERC itself defines no operator ABI; it enforces
owner-only administrative access, and any delegate model is layered on by the
implementation.

### R9. `canRegister` hook

Registries MUST expose a pre-flight check with the canonical signature

```solidity
function canRegister(address registrant, RegistrationParams calldata params)
    external view returns (bool ok, bytes32 reason);
```

and `register(...)` MUST refuse a registration when `canRegister` returns
`ok == false` (or its onchain enforcement equivalent reverts with
`HookDenied(reason)`, per R31). The
`RegistrationParams` struct bundles every input enumerated in R8 (owner,
authors, sharesDenominator, assetType, tokenization, token binding,
metadataURI, contentHash, derivationAttestation); the struct shape is the
canonical ABI and is repeated identically in R31's hook catalog.

The semantics of `canRegister` are entirely defined by the implementer.
Plausible policies include:

- KYC on the registrant or owner (delegated to an identity registry under
  R6d / ERC-3643);
- requiring a signed attestation from each declared author;
- restricting the asset types or tokenization kinds the registry accepts;
- catalog-specific allow-lists; or
- jurisdiction-module checks (extension).

The core ERC MUST NOT prescribe any of these policies. The hook exists so
that off-chain agents (in particular AI agents) can call it as a read-only
pre-flight before submitting the registration transaction, and so that
implementers can compose compliance modules without forking the registry.

A registry implementation MAY return true unconditionally; the existence of
the hook is mandatory, the policy behind it is not.

---

## Authorship & Ownership

### R10. Authorship is immutable, set at registration

The set of authors of an IP Asset MUST be fixed at the moment of registration
and MUST NOT be modifiable thereafter. Authors are the parties whose creative
contribution is declared in the asset, independent of who administers or licenses
it. This immutable record does not by itself establish authorship or moral
rights under applicable law.

The core ERC MUST NOT permit adding, removing, or reweighting authors after
registration. The remedy for incorrect authorship is to register a new asset
with a new `assetId` carrying the corrected authorship, freeze the original
(`freezeAsset`, per the administrative paths in R32) to block creation of new license
agreements, and optionally link the new asset to the original via an
implementer-defined asset claim (R6d/R30). This is a *supersession*
("replaces") relationship recorded as a claim, NOT a derivation
attestation (R23): an authorship correction is not a derived work, and
modeling it as a derivation edge would pollute the provenance graph that
graph extensions traverse. Pre-existing license agreements on a frozen asset
retain their own lifecycle; the asset freeze blocks the future writes specified
in R32, not their activity. The core ERC
MUST NOT prescribe who may freeze an asset (that is implementer-controlled
administrative authorization, not a hook).

The `authors` list MAY be empty (public-domain inputs, scraped NFT
collections of unknown provenance, anonymous-by-design works). Author
entries MAY use `address(0)` to record a share without naming any address,
and MAY use addresses with no associated identity claims (pseudonymous
authorship). The core ERC does not require onchain verification of author
consent at registration; whether and how consent is verified is a policy
decision under `canRegister` (R9).

An `Author.author` MAY also be a **contract** address rather than an
externally owned account. The core records that address and its declared share;
it does not resolve underlying human identities, delegate legal authorship to
code, or prescribe a royalty-routing policy. A single contract entry with share
`1/1` is one possible representation, not a required reduced form: other equal
positive numerator/denominator pairs also satisfy R11.

Extensions may resolve identities or route payments through such a contract.
Consumers must assess those mechanisms separately; contract code and public
state do not provide confidentiality merely because the author entry is a
contract. Any richer identity or payment breakdown is outside the canonical
author array, whose address and share remain immutable.

### R11. Author share precision: rational fractions with a per-asset denominator

Each author MUST be recorded with a share expressed as a non-negative integer
numerator over a per-asset denominator chosen at registration:

```solidity
struct Author {
    address author;          // may be address(0)
    uint256 shareNumerator;
}

// stored per asset, immutable:
uint256 sharesDenominator;   // chosen at registration, > 0 if any authors
Author[] authors;
```

Invariant: `sum_i authors[i].shareNumerator == sharesDenominator` when
`authors.length > 0`, and `sharesDenominator > 0` whenever
`authors.length > 0`. This rejects a meaningless non-empty all-zero share set
and keeps share helpers well-defined. When `authors.length == 0`, `sharesDenominator` is
unconstrained and SHOULD be zero.

Registries SHOULD provide a view helper exposing each author's share in
basis points (`numerator * 10000 / sharesDenominator`) for compatibility
with EIP-2981-style consumers, but the canonical onchain representation is
the exact rational fraction. Fractions such as one third and fine-grained
contribution shares cannot always be represented exactly in fixed basis points.
The per-asset denominator avoids imposing that rounding on the stored record.

### R12, R13. Reserved

Intentionally unallocated — see *Reserved requirement numbers* near the top of
this document. The original content was folded into R10 and the Design
Philosophy "roles are independent" stance. The numbers are not reused.

### R14. Ownership transfer

For `tokenization == NONE`, ownership is transferred via
`transferOwnership(assetId, newOwner)` on the registry. This call MUST emit
`OwnershipTransferred(assetId, from, to)` and MUST be subject to a
`canTransferAsset(assetId, from, to)` hook, where `from` is the current owner.
The caller MUST be the current owner or an address explicitly authorized to act
for that owner under the registry's documented delegation policy. This
authorization is mandatory independently of the hook result.

For `tokenization == ERC721`, ownership is transferred by transferring the
bound NFT in its own contract. `registry.ownerOf(assetId)` reflects the new
holder on the next read by virtue of the R5 delegation; no registry-level
call is required. `transferOwnership` MUST revert when called on an asset
with `tokenization == ERC721`, because the registry does not own the
ownership state.

Because the registry is not in the transfer path for `ERC721` assets, the
`canTransferAsset` hook (R31) cannot fire on those transfers. Implementers that
need transfer policy (KYC/AML, jurisdiction, allow-listed owners) on
`ERC721` asset ownership MUST enforce it inside a suitable restricted ERC-721 —
for example, one adopting ERC-3643-style identity/compliance checks. ERC-3643
conformance alone does not supply ERC-721 ownership semantics. Implementers
that require the *registry itself* to gate every
ownership transfer SHOULD use `tokenization == NONE`, where the registry is
in the path and `canTransferAsset` applies. This is symmetric with the
agreement layer (R22).

### R15. Reserved

Intentionally unallocated — see *Reserved requirement numbers* near the top of
this document. Collapsed in the same trim pass that settled ownership transfer
as the one-step R14. The number is not reused.

---

## Licensing

### R16. LicenseTerms structure

A `LicenseTerms` object MUST describe the terms under which an IP Asset
may be used, in a form that is simultaneously legible to AI agents, hooks,
compliance modules, and humans. The structure is split into four layers:

1. **Universal frame** — agreement-level properties that mean the same
   thing across every asset type and every jurisdiction.
2. **Mandatory rights summary** — a small, always-present, tri-state rights
   vector plus a coarse fee-model classifier, comparable across every
   `termsType` (R16e).
3. **Authoritative legal text** — an off-chain document, content-hashed.
4. **Domain-specific rights schema** — the rights actually granted,
   in a domain-specific structured form addressed by a content-addressed
   schema id.

```solidity
struct LicenseTerms {
    // 1. Universal frame
    uint64  expiry;            // absolute unix-seconds hard deadline; 0 = none
    uint64  duration;          // seconds from agreement creation; 0 = none
    bool    transferable;      // may the resulting LicenseAgreement be transferred
    bool    revocable;         // permits ordinary owner revocation; not force revocation
    bool    sublicensable;     // terms assert onward licensing is permitted;
                               // recorded only, with no core sublicense action
    bool    exclusive;         // does this grant preclude others on the same scope
    bytes32 jurisdictionScope; // well-known: keccak256("worldwide"),
                               //             keccak256("JP"), keccak256("US"), …
                               //             (ISO-3166-1 alpha-2 codes by convention)

    // 2. Mandatory rights summary (R16e)
    RightsSummary rights;

    // 3. Authoritative legal text
    string  uri;
    bytes32 contentHash;

    // 4. Domain-specific rights
    bytes32 termsType;         // content-addressed schema id (see R16d), or
                               // bytes32(0) when the summary is the full expression
    bytes   rightsData;        // ABI-encoded per termsType's schema
}

enum Ternary  { UNSPECIFIED, YES, NO }
enum FeeModel { UNSPECIFIED, FREE, ONE_TIME, RECURRING, USAGE_BASED, EXTERNAL }

struct RightsSummary {
    Ternary  commercialUse;       // YES = commercial use permitted
    Ternary  derivativesAllowed;  // YES = derivative works permitted
    Ternary  attributionRequired; // YES = attribution required
    FeeModel feeModel;            // coarse, amount-free classifier
}
```

#### R16a. Universal frame is invariant across asset types and jurisdictions

The seven universal-frame fields (`expiry`, `duration`, `transferable`, `revocable`, `sublicensable`,
`exclusive`, `jurisdictionScope`) MUST be interpreted identically regardless
of asset type or termsType. They describe *properties of the license
relationship*, not the rights being granted. Adding fields to the universal
frame is a core-ERC revision; implementers MUST NOT extend it locally.

The frame fields differ in **who enforces them**. The registry enforces `expiry`
and `duration` for every agreement, `revocable` on ordinary revocation for both
tokenization modes, and `transferable` only where the registry controls the
transfer path (`NONE`). For `ERC721`, transferability policy belongs to the
bound token contract. The other three fields are *recorded* faithfully by the
core for downstream consumers (hooks, payment / jurisdiction / asset-graph
extensions, agents, courts) to act on — exactly as `rightsData` is recorded but
never decoded by the core (R16c).

| Field | Core-enforced? | Mechanism |
| --- | --- | --- |
| `expiry` | **Yes** | Optional absolute Unix-seconds hard deadline shared by every agreement using the terms. Zero means no absolute deadline. |
| `duration` | **Yes** | Optional lifetime in seconds from each agreement's creation. Zero means no relative deadline. The agreement captures the earlier non-zero result of `expiry` and `createdAt + duration`; both zero means perpetual. |
| `transferable` | **Conditional** | For `NONE`, the registry MUST reject `transferAgreement` when false. For `ERC721`, the registry only captures and exposes the value; the bound token contract is the enforcement point and activity views do not attest compliance (R19/R22). |
| `revocable` | **Yes, for ordinary revocation** | If false, `revokeAgreement` MUST revert regardless of `canRevoke`, for both `NONE` and `ERC721`. The separately authorized `forceRevokeAgreement` remains available for exceptional intervention. This flag does not determine legal termination. |
| `sublicensable` | **No — recorded only** | The terms assert whether onward licensing is permitted, for legal interpretation and downstream consumers. The core defines no sublicense operation, grantor role for a licensee, or parent-agreement relationship. |
| `exclusive` | **No — recorded only** | The core does NOT prevent attaching or granting overlapping terms on the same scope. Exclusivity is enforced, if at all, by `canAttachTerms` / `canLicense` policy (R31) or a licensing extension. |
| `jurisdictionScope` | **No — recorded only** | A recorded scope indicator. Deployment-specific hooks and optional jurisdiction extensions may interpret it alongside claims and terms; the core does not enforce territorial restrictions or require a particular jurisdiction scheme. |

"Recorded only" is a deliberate stance, not an omission. Forcing the core to
adjudicate exclusivity or sublicensing would require it to understand the
domain-specific scope of each `termsType` — precisely the coupling that the
frame / `rightsData` split (R16c) exists to avoid (an "exclusive" music sync
license and an "exclusive" software field-of-use grant do not share a scope
the core could compare). Consumers that need these guarantees MUST enforce
them in hooks or extensions and MUST NOT assume the core has done so.

In particular, `sublicensable == true` does not authorize any caller to invoke
`createAgreement`: R19 still restricts that core entry point to the asset owner
or its authorized delegate. It also does not make a newly created agreement a
sublicense, because the core ABI records no parent agreement or sublicense
grantor. A protocol that represents sublicenses onchain MUST use an extension
that defines at least the parent `agreementId`, the licensee-as-grantor authority
check, the child agreement's relationship to the parent terms and lifecycle,
and corresponding read/event surfaces. Without such an extension, the flag is
only a machine-readable assertion for off-chain legal and policy evaluation.

#### R16b. Authoritative legal text

When present, `uri` MUST point to a human-readable legal document describing
the license terms. `contentHash` is `keccak256(documentBytes)`, where
`documentBytes` is the exact canonical byte sequence selected by the publisher
for that document, and is immutable once set. The pair `(uri, contentHash)` is
the authoritative legal artifact the terms refer to; the onchain structure is
the deterministic machine-readable protocol representation. R16b.1 defines
their complementary scope and prohibits conflicts.

`uri` MAY be empty and `contentHash` MAY be `bytes32(0)` if the implementer
does not publish a separate legal document (e.g. when relying entirely on
a well-known `termsType` whose schema is itself legally normative). The
core ERC does not constrain the URI scheme. The wrapper MUST be either wholly
absent (`uri == ""` and `contentHash == bytes32(0)`) or wholly present
(`uri != ""` and `contentHash != bytes32(0)`). Consumers MUST hash the canonical
document bytes without Unicode normalization, line-ending conversion,
reserialization, or other content transformation.

#### R16b.1. Layer consistency and precedence

The universal frame, rights summary, domain `rightsData`, and legal document
MUST describe one internally consistent terms object. Their responsibilities
are:

1. The universal frame is authoritative for protocol behavior in its seven
   dimensions. The registry MUST compute expiry and registry-controlled
   transfer behavior from it and MUST NOT parse legal prose for overrides.
2. Each non-`UNSPECIFIED` rights-summary value is the authoritative coarse
   machine-readable assertion for that dimension.
3. `rightsData` MAY refine the summary with narrower schema-defined detail but
   MUST NOT negate or broaden the frame or summary.
4. Legal text MAY define terminology, conditions, remedies, and matters not
   expressible onchain, including dimensions marked `UNSPECIFIED`, but MUST NOT
   contradict the machine-readable assertions.

The core treats `rightsData` and legal prose as opaque and cannot generally
validate this consistency at registration. A discovered conflict makes the
terms non-conforming. Conforming consumers MUST reject or prominently flag the
terms and MUST NOT select a preferred layer. The registry continues to apply
the universal frame because that is the only deterministic onchain behavior;
this ERC makes no claim about which conflicting statement is legally
enforceable in a particular jurisdiction.

Because terms and agreements are immutable, a conflict MUST be corrected by
registering a consistent `LicenseTerms` value with a new `termsId` and attaching
that replacement for future agreements. Existing terms and agreements MUST NOT
be rewritten or silently reinterpreted.

#### R16c. Domain-specific rights via content-addressed schemas

`termsType` MUST be a content-addressed schema id: `keccak256` of canonical
schema bytes describing the layout and semantics of `rightsData`. The generic
schema is fully defined inline in the ERC draft; other schemas may be published
separately.

The core ERC defines exactly one well-known `termsType`:

| Constant | Preimage / role |
| --- | --- |
| `TERMS_TYPE_GENERIC_V1` | `keccak256` of the exact single JSON line in [ERC draft §1.6](erc-draft.md#16-well-known-constants): UTF-8, without a BOM, fences, surrounding whitespace, or line terminator; no reserialization or normalization. Pinned value `0x497589298d23e3edf03354027567294825f845d9acccc3812cbb7b7b8dc3f5fa`. Its three booleans MUST match the summary; it adds `attributionTemplate`. Terms MAY instead set `termsType == bytes32(0)` and use the summary alone. |

For each boolean restated by `GenericLicenseV1Rights`, the mapping is exact:

| Summary value | Generic boolean | Conforming |
| --- | --- | --- |
| `YES` | `true` | Yes |
| `YES` | `false` | No |
| `NO` | `false` | Yes |
| `NO` | `true` | No |
| `UNSPECIFIED` | either | No |

Because the generic schema's booleans always assert a polarity, terms selecting
`TERMS_TYPE_GENERIC_V1` MUST use `YES` or `NO` for all three corresponding
summary dimensions. The core does not decode the payload at registration;
generic-schema consumers and policy hooks MUST reject invalid mappings.

Domain-specific schemas (e.g. `music-license-v1`, `software-license-v1`,
`visual-license-v1`, `dataset-license-v1`) are illustrative examples called
out in non-normative text of this ERC and SHOULD be developed as separate
ERC extensions. They are **not** part of this ERC's normative content.

Consumers (hooks, agents, compliance modules) decode `rightsData` according
to the schema selected by `termsType`. Implementations SHOULD reject
`(assetType, termsType)` pairings that are conventionally incompatible
(e.g. a music-license `termsType` on a patent asset), but the core ERC
does not enforce specific pairings: schemas evolve at extension cadence
and the core MUST NOT need revision to support new ones.

#### R16d. Schema discovery (extension)

The core ERC defines no schema-registry interface. Discovering the canonical
document for a content-addressed schema id, for metadata schemas (R6c) and
`termsType` schemas (R16c), is left to extensions. Whatever the discovery
mechanism, consumers MUST verify that the retrieved bytes hash to the requested
id; a pointer does not prove correct or available content. Consumers using only
the well-known schemas defined in this ERC can hard-code the canonical schema
text and need no lookup.

#### R16e. Mandatory rights summary

Every `LicenseTerms` MUST carry a `RightsSummary rights` (layer 2 of the R16
struct). It is present regardless of `termsType`, including when
`termsType == bytes32(0)`, and provides a guaranteed, cross-schema comparison
vocabulary so that an agent or hook can evaluate terms it has never seen before
without decoding a domain-specific `rightsData`. Together with the frame's
`expiry` (duration), `jurisdictionScope` (territory), and `sublicensable`
(sublicensing), the summary yields six comparable dimensions; the summary
contributes commercial use, derivatives, attribution, and a coarse fee model.

- **Tri-state dimensions.** `commercialUse`, `derivativesAllowed`, and
  `attributionRequired` are each `Ternary`. `UNSPECIFIED` means the terms make no
  machine-readable assertion on that dimension (the domain schema or legal text
  governs); `YES`/`NO` are affirmative assertions. Consumers MUST treat
  `UNSPECIFIED` as "unknown", not as a default of either polarity.
- **Fee model.** `feeModel` classifies how a fee, if any, is structured
  (`FREE`, `ONE_TIME`, `RECURRING`, `USAGE_BASED`, `EXTERNAL`, or `UNSPECIFIED`).
  It MUST NOT encode any amount, currency, token, or settlement logic — those are
  the payment extension's concern. It exists solely so agents can filter and
  cost-optimize offers.
- **Floor, not ceiling.** The summary does not replace the domain rights schema.
  `rightsData` (R16c) MAY refine any dimension with domain-specific nuance but
  MUST NOT contradict the summary. Where a well-known schema restates a summary
  dimension (e.g. `generic-license-v1`'s `commercialUse`), the two MUST agree,
  and the summary MUST NOT be `UNSPECIFIED` for a dimension the schema asserts.
- **No conflict override.** Neither `rightsData` nor legal text overrides a
  non-`UNSPECIFIED` summary value. A contradiction is non-conforming under
  R16b.1 rather than a precedence mechanism.
- **Core does not interpret it.** As with `rightsData` and the recorded-only
  frame fields, the core records the summary faithfully and acts on none of it;
  enforcement and comparison are consumer/hook/extension concerns.

The core does not adopt an existing rights expression language (ODRL, ccREL,
MPEG-21 REL) as its onchain encoding — those are designed for off-chain,
document-oriented processing, not gas-bounded onchain decode — but the summary's
dimensions are chosen to align with their well-established vocabulary so that
off-chain tooling can map between them.

---

### R17. LicenseTerms identification and reuse

A `LicenseTerms` object is identified by a content-addressed `termsId`:

```solidity
termsId = keccak256(abi.encode(terms))
```

The canonical encoding is the Solidity ABI encoding of `terms` as one
`LicenseTerms` tuple argument, with `rightsData` already encoded per its
`termsType`. Its canonical ABI type is
`(uint64,uint64,bool,bool,bool,bool,bytes32,(uint8,uint8,uint8,uint8),string,bytes32,bytes32,bytes)`;
the nested tuple is `RightsSummary`, and enums use their declared `uint8`
ordinals. Field order is exactly the R16 declaration order. `abi.encodePacked`,
textual encodings, field-by-field encoding, and implementation-defined
encodings are non-conforming. In particular, encoding the fields as separate
top-level arguments is not interchangeable with encoding the `LicenseTerms`
struct as one dynamic tuple argument. Implementations in other languages MUST
produce the same bytes as Solidity's `abi.encode(terms)`. The normative test
vectors are published in `erc-draft.md` §6.

Two registrants who submit identical terms produce the same `termsId` by construction.
Re-registration of an already-known `termsId` MUST succeed, return that id,
leave stored terms unchanged, and emit no event.

The canonical global identifier of a terms object is the tuple
`(chainId, registry, termsId)`. The string form mirrors IPid:

```
ipterms:<chainId>:<registry>/<termsId>
```

with the same syntax rules as IPid (R2) — lowercase hex, no leading zeros
in chainId, `0x`-prefixed 42-char registry, `0x`-prefixed 66-char termsId.
The same reference library (`src/IpRef.sol`) handles both forms.

`LicenseTerms` are reusable. Many IP Assets in one registry MAY reference the
same `termsId`. Attaching terms to an asset (R18) does not transfer or grant any
rights over the terms themselves.

`LicenseTerms` are immutable: their onchain representation is fixed by
content addressing. "Updating" terms means registering new terms (new
`termsId`) and re-attaching. Existing license agreements bound to an old
`termsId` continue to refer to the old terms — a feature, not a bug, since
agreed terms should never silently change under a licensee.

Terms used by an asset MUST be registered in the same registry as that asset.
The `ipterms:` form can identify a terms object in another registry for
off-chain discovery, but it is not an attachable onchain reference. Anyone may
mirror the exact `LicenseTerms` value into another registry before attachment;
content addressing gives the local copy the same `termsId`. This local-only
rule makes each agreement self-contained and removes runtime availability and
trust dependencies on another terms contract.

### R18. Attaching terms to an asset

The owner of an IP Asset attaches one or more locally registered `termsId`
values to the asset via:

```solidity
function attachTerms(
    bytes32 assetId,
    bytes32 termsId,
    bytes calldata attachmentParameters
) external;
```

Attaching publishes an asset-level standing offer and authorization for the
self-service acquisition path. While the `termsId` attachment remains active,
a caller may invoke `acquireAgreement` without a
contemporaneous transaction, signature, or approval from the asset owner,
provided all creation invariants hold and
`canLicense(assetId, termsId, caller, licenseParams, acceptanceHash)` returns
`ok == true`. The hook MAY consult the stored
`attachmentParameters` to enforce the deployment's eligibility, payment, or
other offer conditions.

An attachment is persistent asset state and remains effective across ownership
changes until the current owner or its authorized delegate detaches it.
Reattachment may update its conditions through `attachmentParameters`.
The current owner at acquisition time is captured as the resulting
agreement's `licensor`. Owners and prospective owners MUST therefore treat
active attachments as outstanding offers associated with the asset.

Attachment alone does not grant rights, create an agreement, or identify a
licensee. An agreement record is created by a successful owner-authorized
`createAgreement` grant or qualifying `acquireAgreement`; creation does not by
itself establish legal validity or enforceability (R20).

The caller of `attachTerms` or `detachTerms` MUST be the asset's current
administrative owner or an address explicitly authorized to act for that owner
under the registry's documented delegation policy. This authorization is a
mandatory invariant independent of the pre-flight hooks: a permissive
`canAttachTerms` or `canDetachTerms` result MUST NOT authorize an otherwise
unrelated caller.

Every attachment MUST identify a terms object already registered in the asset
registry. `attachTerms` MUST require `termsExists(termsId) == true`; an unknown
`termsId` MUST revert without creating or updating an attachment. `getTerms`
MUST revert for an unknown `termsId` rather than returning a zero-valued
`LicenseTerms`.

`attachmentParameters` is opaque to the core ERC and carries
implementer-specific configuration (who may call `acquireAgreement`, fee
receiver and amount for use by the payment extension, etc.). The core ERC
does not parse or enforce its contents.

Attachments MAY be detached by the owner via `detachTerms(assetId, termsId)`.
Detachment blocks the creation of new license
agreements under those terms but does NOT invalidate existing agreements
already bound to them. Existing agreements remain subject to their own
expiry and revocation rules.

Both operations MUST be subject to `canAttachTerms` / `canDetachTerms`
hooks and MUST emit
`TermsAttached(assetId, termsId, attachmentParameters)` and
`TermsDetached(assetId, termsId)` respectively.
`TermsAttached` MUST be emitted both for a new attachment and when reattachment
updates the stored parameters, carrying the complete new byte value.

### R19. LicenseAgreement structure

A `LicenseAgreement` represents a granted license. It binds:

- an asset by canonical tuple `(assetRegistry, assetId)`,
- terms by the locally registered `termsId` in that asset registry,
- a licensee — for `NONE` agreements the stored `party` (which MUST be
  non-zero); for `ERC721` agreements the holder of the bound token,
- an `agreementId` unique within the issuing registry.

Let `agreementIndex` be `agreementCountOf(assetId)` immediately before the new
agreement is appended to that asset's agreement set. Both creation paths MUST
derive the identifier as:

```solidity
agreementId = keccak256(
    abi.encode(chainId(), address(this), assetId, agreementIndex)
);
```

Here `chainId()` is the issuing registry's canonical chain identifier. The
encoded types are exactly `(uint256,address,bytes32,uint256)`. Packed,
textual, reordered, block-number-dependent, timestamp-dependent, or
implementation-defined encodings are non-conforming. `agreementId` MUST be
non-zero and MUST NOT already exist in the issuing registry. If either
condition occurs, creation MUST revert with
`AgreementIdCollision(agreementId)` and MUST NOT overwrite or reuse a record.
The asset's agreement indices and IDs are append-only and MUST NOT be reused
after revocation, expiry, freezing, or any other lifecycle change.

Both agreement-creation paths MUST require that the exact `termsId` is
currently attached to the asset and still registered locally before writing
the agreement. A detached or unknown terms reference MUST NOT produce an
agreement.

The canonical global identifier of a LicenseAgreement is
`(chainId, registry, agreementId)` — symmetric with assets and terms. Its
string form mirrors IPid and `ipterms:`:

```
ipagreement:<chainId>:<registry>/<agreementId>
```

with the same syntax rules as R2 (lowercase hex, no leading zeros in
chainId, `0x`-prefixed 42-char registry, `0x`-prefixed 66-char
agreementId). The same reference library (`src/IpRef.sol`) handles all
three forms.

Every LicenseAgreement has a licensee from the moment it is created. The
core ERC does NOT define an "unassigned" / pre-minted agreement state: a
license is always a grant *to someone*. Inventory-style "mint now, sell
later" is expressed without a registry-level unassigned state — either by
creating the agreement at the point of sale (`NONE`), or by minting and
later transferring the bound license token (`ERC721`).

For an `ERC721` agreement, `agreementCollection` MUST be non-zero and its
gas-bounded `ownerOf(agreementTokenId)` query MUST resolve to a non-zero holder
at creation. A reverting, over-budget, malformed, or zero ownership result MUST
reject creation. This is a core creation invariant, not optional `canLicense`
policy. Later token failure or burning follows R20 and makes the already-created
agreement inactive without deleting it.

At agreement creation, the registry MUST resolve the two terms-level time
constraints into one immutable absolute agreement deadline:

```solidity
relativeExpiry = duration == 0 ? 0 : createdAt + duration;
effectiveExpiry =
    expiry == 0 ? relativeExpiry
  : relativeExpiry == 0 ? expiry
  : min(expiry, relativeExpiry);
```

`createdAt` is the agreement's recorded creation timestamp. Both constraints
zero means perpetual. Overflow of `createdAt + duration` MUST revert with
`AgreementExpiryOverflow(termsId)`. A non-zero
`effectiveExpiry <= createdAt` MUST revert with
`TermsAlreadyExpired(termsId, effectiveExpiry)` so creation
cannot succeed with an already-inactive agreement. `agreementOf` and
`LicenseAgreementCreated` expose this captured `effectiveExpiry`. Reusing terms
with a non-zero `duration` computes a fresh relative deadline for each
agreement, while a non-zero absolute `expiry` remains a common hard cap.

Agreements are created through one of two entry points:

- `createAgreement(AgreementParams params)` — called by the asset owner or,
  under an implementer-defined delegation policy, a party explicitly authorized
  to act for that owner. The registry MUST enforce this grant authority
  independently of `canLicense`; an arbitrary caller MUST NOT create a grant
  carrying the current owner as `licensor`. For
  `NONE`, `params.party` MUST be non-zero; for `ERC721`, the licensee is the
  non-zero holder of the non-zero bound collection at creation.
- `acquireAgreement(assetId, termsId, licenseParams,
  acceptanceHash)` — called by a would-be licensee against attached terms
  (R18). It MUST always create a registry-tracked agreement with
  `agreementTokenization == AgreementTokenization.NONE`,
  `party == msg.sender`, `agreementCollection == address(0)`, and
  `agreementTokenId == 0`; it cannot create a token-bound agreement.
  The active attachment supplies standing owner authorization, so no
  contemporaneous owner transaction or signature is required. `acceptanceHash`
  MAY be zero when no separate acceptance evidence is asserted.

Both entry points MUST be subject to the
`canLicense(assetId, termsId, acquirer, licenseParams, acceptanceHash)` hook
(R31) and MUST emit `LicenseAgreementCreated` (R29). `canLicense` is therefore
the sale-time policy gate (KYC, eligibility, payment confirmation) for who may
receive a license. `licenseParams` is opaque to the core ERC and is forwarded
verbatim from the caller (`AgreementParams.licenseParams` for
`createAgreement`, the explicit argument for `acquireAgreement`) to the
`canLicense` hook, mirroring how `attachmentParameters` reaches `canAttachTerms`
(R18); the core retains `keccak256(licenseParams)` as evidence. The optional
`acceptanceHash` is also forwarded so policy can validate the commitment before
it is stored. These inputs let the policy receive caller-supplied verification data — e.g. a
rights-ratio confirmation, an off-chain legal-acceptance signature, or
parent-terms inheritance data — without the core decoding it.

For `createAgreement`, the record construction and hook arguments are
tokenization-dependent and exact:

- The asset and terms binding MUST equal `params.assetId` and `params.termsId`.
- The current non-zero administrative owner of `params.assetId` MUST be captured
  as `licensor`, even when an authorized delegate is `msg.sender`.
- For `AgreementTokenization.NONE`, `params.party` is the initial licensee and
  MUST be non-zero. `params.agreementCollection` and
  `params.agreementTokenId` are ignored; their stored values MUST be normalized
  to `address(0)` and `0`.
- For `AgreementTokenization.ERC721`, `params.party` is ignored and its stored
  value MUST be `address(0)`. The stored token binding is
  `(params.agreementCollection, params.agreementTokenId)`, and the bounded
  `ownerOf` result at creation is the non-zero initial licensee.
- `canLicense.acquirer` MUST be that effective initial licensee:
  `params.party` for `NONE`, or the resolved current token holder for `ERC721`.
  It MUST NOT be `msg.sender` merely because the owner or delegate submitted
  the grant.

The core MUST preserve immutable creation evidence for every agreement:

```solidity
enum AgreementCreationMode { GRANT, ACQUIRE }

struct AgreementEvidence {
    address licensor;
    address createdBy;
    address initialLicensee;
    uint64 createdAt;
    AgreementCreationMode creationMode;
    bytes32 licenseParamsHash;
    bytes32 acceptanceHash;
}
```

- `licensor` is the asset's administrative owner resolved at agreement creation.
  It is a historical authorization fact, not an assertion that the address held
  the underlying legal rights.
- `createdBy` is the actual `msg.sender`. It distinguishes an owner or delegated
  grant initiator from the licensee calling the self-service acquisition path.
- `initialLicensee` is the effective licensee at creation, including the bound
  token holder for `ERC721`; it remains immutable after transfers.
- `createdAt` is the creation `block.timestamp` captured as `uint64`.
- `creationMode` is `GRANT` for `createAgreement` and `ACQUIRE` for
  `acquireAgreement`.
- `licenseParamsHash` is `keccak256` of the exact bytes forwarded to
  `canLicense`. The bytes themselves need not be stored onchain; a party
  presenting them later can prove they match the creation input.
- `acceptanceHash` is the caller-supplied commitment carried by
  `AgreementParams.acceptanceHash` or the acquisition argument. It MAY commit to
  an acceptance signature or document, but the hash alone does not prove who
  signed or accepted it. Any required validation belongs in `canLicense` and the
  applicable terms schema.

For `createAgreement`, every evidence field is fixed as follows:

| Field | Required value |
| --- | --- |
| `licensor` | current non-zero administrative owner of `params.assetId`, resolved at creation |
| `createdBy` | `msg.sender` |
| `initialLicensee` | `params.party` for `NONE`, or the resolved bound-token holder for `ERC721` |
| `createdAt` | creation `block.timestamp`, represented as `uint64` |
| `creationMode` | `AgreementCreationMode.GRANT` |
| `licenseParamsHash` | `keccak256(params.licenseParams)` over the exact supplied bytes |
| `acceptanceHash` | the exact `params.acceptanceHash`, including zero |

Its effective `expiry` MUST be computed from the resolved terms and this
`createdAt`, and its captured `transferable` and `revocable` values MUST equal the resolved
terms' `transferable` field.

For `acquireAgreement`, these general evidence rules determine every field
exactly:

| Field | Required value |
| --- | --- |
| `licensor` | current non-zero administrative owner of `assetId`, resolved at creation |
| `createdBy` | `msg.sender` |
| `initialLicensee` | `msg.sender` |
| `createdAt` | creation `block.timestamp`, represented as `uint64` |
| `creationMode` | `AgreementCreationMode.ACQUIRE` |
| `licenseParamsHash` | `keccak256(licenseParams)` over the exact supplied bytes |
| `acceptanceHash` | the exact supplied argument, including zero |

The agreement's asset and terms fields MUST equal the supplied `assetId` and
`termsId`. Its effective `expiry` MUST be computed from the
resolved terms and this `createdAt`, and its captured `transferable` and `revocable` values MUST
equal the resolved terms' `transferable` field. The function MUST use the same
canonical agreement-ID derivation, append-only indexing, terms revalidation,
`LicenseAgreementCreated` event, and failure rules as `createAgreement`.

`agreementOf` MUST expose this evidence together with the immutable asset/terms
and tokenization binding, the exact effective absolute expiry derived from
`expiry`/`duration`, and the `transferable` and `revocable` values captured by the registry.
Historical evidence MUST NOT change when the current
licensee or asset owner changes. `acquireAgreement` MUST reject creation if the
asset has no observable current administrative owner, because no licensor can be
snapshotted.

Secondary transfer of an already-granted `NONE` agreement is governed by:

- mandatory caller authorization: the caller MUST be the current licensee or
  an address explicitly authorized to act for that licensee under the
  registry's documented delegation policy;
- the `transferable` field of the universal frame (R16a) — when false,
  `transferAgreement` MUST revert;
- the `canTransferAgreement` hook;

via `transferAgreement(agreementId, to)` (emitting
`LicenseAgreementTransferred`). For `ERC721` agreements the licensee changes by
transferring the bound token; the registry is not in that path and MUST NOT
claim to enforce `transferable` or `canTransferAgreement`. A deployment requiring those
restrictions MUST use a suitably restricted token contract (e.g. a soulbound
token for a non-transferable license) or use `NONE`.
Caller authorization is independent of `canTransferAgreement`: a permissive hook MUST
NOT authorize an unrelated caller to transfer a `NONE` agreement.
For the `NONE` path, the exact hook invocation is
`canTransferAgreement(agreementId, from, to)`, where `from` is the current licensee.

An ERC-721 transfer that conflicts with `transferable == false` is a
token-contract or off-chain terms violation; it does not automatically revoke,
freeze, expire, or deactivate the agreement. R20 activity views follow the
current token holder and attest only to registry lifecycle state, not whether
the transfer complied with the terms.

**Captured lifecycle fields.** An agreement captures the effective absolute
`expiry` calculated above from its terms and its own `createdAt`, plus the
terms' unchanged `transferable` value. The source `duration` remains in the terms,
not a separately exposed agreement field. Registries MUST treat an agreement as
expired when its captured `expiry > 0` and `block.timestamp >= expiry` (R20).
Identical or mirrored terms can produce different effective deadlines for
agreements created at different times, still subject to any absolute terms cap.

### R20. Agreement activity

The core ERC MUST expose four agreement-activity functions, all callable by
anyone and none relying on `msg.sender` to identify the party in question:

```solidity
function activeAgreementsOf(
    bytes32 assetId,
    uint256 cursor,
    uint256 limit
) external view returns (bytes32[] memory agreementIds, uint256 nextCursor);

function activeAgreementsOf(
    bytes32 assetId,
    address party,
    uint256 cursor,
    uint256 limit
) external view returns (bytes32[] memory agreementIds, uint256 nextCursor);

function isActiveAgreementHolder(
    bytes32 agreementId,
    bytes32 assetId,
    address party
) external view returns (bool);

function isAgreementActive(bytes32 agreementId)
    external view returns (bool);
```

Semantics:

- **`activeAgreementsOf(assetId, cursor, limit)`** is asset-wide discovery. It
  examines at most `limit` stable entries and returns every active agreement in
  that examined range, regardless of holder.
- **`activeAgreementsOf(assetId, party, cursor, limit)`** examines at most
  `limit` entries from the asset's stable, append-only agreement list beginning
  at `cursor`, and returns the active agreements currently held by `party` plus
  the next cursor. "Active" means only that the agreement has a current licensee,
  is not expired (R16a / R19), is not revoked (R21), and is not frozen (R32).
  `limit` bounds records examined, not records returned. An empty or short page
  does not prove absence; discovery is complete only when
  `nextCursor == agreementCountOf(assetId)`. When
  `cursor <= agreementCountOf(assetId)`, a zero `limit` examines nothing and
  returns the input `cursor` unchanged; an out-of-range cursor is clamped to the
  agreement count as described below.
- **`isActiveAgreementHolder(agreementId, assetId, party)`** returns true iff
  the identified agreement binds `assetId`, is active, and its current licensee
  is `party`. This is the constant-work witness path: a party or indexer supplies
  an `agreementId`, avoiding an asset-wide scan. It returns `false` for an
  unknown agreement or asset, or when `party == address(0)`.
- **`isAgreementActive(agreementId)`** returns true iff the agreement currently
  has a licensee and is not expired, revoked, or frozen. It returns `false` for
  an unknown agreement.

`agreementOf(unknownAgreementId)` MUST return the all-zero ABI tuple: zero
addresses, ids, token id, expiry, `transferable == false`, and `revocable == false`;
`agreementTokenization == NONE`; and every `AgreementEvidence` field at its zero
value (`creationMode == GRANT`). `getLicensee(unknownAgreementId)` MUST return
`address(0)`.

These functions report **onchain lifecycle state only**. They do not assert
that an agreement is legally valid or enforceable, that its licensor owned the
rights purportedly granted, or that it permits a contemplated use, territory,
commercial activity, or derivation. A consumer making an authorization decision
MUST obtain the relevant ids from a supplied witness or `activeAgreementsOf`,
read each agreement's own locally registered `termsId`, and evaluate that
agreement's complete terms and applicable off-chain conditions. A consumer MUST
NOT combine the active state of one agreement with rights read from another.

All four functions MUST be `view`, MUST be callable without permission, and
MUST NOT revert on unknown identifiers. Both `activeAgreementsOf` overloads MUST also be
non-reverting for out-of-range cursors and MUST avoid overflow for every
`cursor` and `limit`.

The core deliberately exposes no unbounded existential boolean and no
unpaginated per-party enumeration. Arbitrary ERC-721-bound
agreements can transfer without notifying the registry, so a reliable party
index cannot be required. A positive claim is cheaply verified by supplying an
`agreementId`; proving absence requires completing the bounded scan or relying
on an off-chain indexer. Implementations MAY expose indexed convenience queries
through a separate ERC-165 extension when their token model guarantees reliable
index maintenance.

The non-revert guarantee extends to **delegation failures**. For `ERC721`
agreements (and, symmetrically, `ERC721` asset ownership, R5), the external
token's `ownerOf` may revert, return malformed data, or consume all forwarded
gas. A conforming registry MUST use a 100,000-gas stipend for each delegated
`ownerOf` call, require exactly one canonical 32-byte address word, and treat a
reverting, over-budget, or
malformed call as **no current holder**. The agreement is then inactive and
omitted from paginated active sets. A delegated failure MUST NOT propagate out
of a view required to be non-reverting (R20, R27, R27a) or a hook (R31). The
gas and return-data limits are normative.

### R21. Revocation

LicenseAgreements MAY permit ordinary revocation and MUST support a separately
authorized exceptional path. The core ERC defines two paths:

```solidity
function revokeAgreement(bytes32 agreementId, bytes32 reason) external;
function forceRevokeAgreement(bytes32 agreementId, bytes32 reason) external;
```

- **`revokeAgreement`** is the ordinary owner-authorized path. Its caller MUST
  be the current administrative owner of the agreement's bound asset or an
  address explicitly authorized to act for that owner under the registry's
  documented delegation policy. This authorization is mandatory and independent
  of hook policy. When the agreement's captured `revocable` is false,
  `revokeAgreement` MUST revert regardless of hook approval; the flag does not
  determine whether legal rights terminate for other reasons. Otherwise the function MUST invoke
  `canRevoke(agreementId, msg.sender, reason)` against current state and MUST
  revert with `HookDenied(denialReason)` when the hook returns `ok == false`.
  The hook may enforce additional circumstances or cooldowns, but a permissive
  hook MUST NOT authorize an unrelated caller.
- **`forceRevokeAgreement`** is the separately authorized break-glass path for
  exceptional intervention such as court orders, sanctions, or takedowns. It
  MUST be restricted to the registry's documented administrative or governance
  authority and MUST NOT invoke or depend on `canRevoke` or `revocable`. Both paths MUST
  record the `reason` (opaque `bytes32`) so off-chain audit trails are complete.

Revocation MUST be observable:

- A revoked agreement MUST cause `isActiveAgreementHolder`, `activeAgreementsOf`, and
  `isAgreementActive` (R20) to behave as if the agreement no longer existed
  from the revocation block forward.
- Revocation MUST emit `LicenseAgreementRevoked(agreementId, by, reason)`.
- Revocation MUST NOT delete the agreement from storage. The record MUST
  be marked revoked so that off-chain indexers can observe both the
  original grant and its revocation, and so that future disputes have an
  onchain audit trail.

Revocation through either path is permanent. The core exposes no
un-revocation operation; temporary intervention uses `freezeAgreement`.

### R22. LicenseAgreement tokenization

A LicenseAgreement is either registry-tracked or bound to a single external
token. When bound, the registry's notion of the agreement's licensee is
delegated to the token holder, symmetric with R5's treatment of IP-asset
ownership. The core ERC defines a fixed enum, deliberately symmetric with
the IP-asset `AssetTokenization` enum (R4):

```solidity
enum AgreementTokenization { NONE, ERC721 }
```

Per-mode semantics:

- **NONE.** The registry stores the licensee (`party`) explicitly.
  Creation, transfer, and revocation go through the registry. `canTransferAgreement`
  applies on every secondary transfer; `transferable` (R16a) governs
  whether such transfers are permitted at all.
- **ERC721.** The agreement is bound to a specific ERC-721 token at
  creation. `getLicensee(agreementId)` MUST delegate to
  `IERC721(collection).ownerOf(tokenId)`; the registry MUST NOT cache the
  licensee. If that `ownerOf` reverts (burned or nonexistent token),
  `getLicensee` MUST return `address(0)` rather than revert, and the
  agreement MUST be treated as having no licensee for activity checks (R20).
  Transfer of the bound NFT transfers the licensee role automatically;
  `canTransferAgreement` on the registry does NOT apply because the registry is not in
  the transfer path. The registry records `transferable` but does not enforce
  or attest compliance with it for an ERC-721 transfer. Safety and policy —
  including implementing a soulbound license when `transferable == false` —
  are the responsibility of the bound token contract.

For `ERC721` bindings the registry MUST record the `(collection, tokenId)`
binding at agreement creation time. The binding is immutable for the
lifetime of the agreement — switching binding modes after the fact would
break licensee semantics.

`canTransferAgreement` on the registry applies only to `NONE` agreements.
Implementers requiring policy enforcement on tokenized-agreement transfers
MUST enforce it inside the bound token contract or use `NONE`. Registry
activity views MUST continue to follow the bound token's current holder and
MUST NOT be interpreted as evidence that a transfer complied with policy.

**Why no ERC-1155.** ERC-1155 was previously a third agreement mode for
multi-supply "editions". It was removed because the multi-holder model
breaks three core guarantees: (1) revocation (R21) is per-agreement, so a
single ERC-1155 agreement backing N holders could only be revoked for all N
  at once — individual takedowns become impossible; (2) `isAgreementActive`
(R20) has no single answer when activity is per-holder; (3) there is no
clean preminted/unassigned state. Editions are still expressible as N
single-holder agreements (`NONE` records or `ERC721` tokens), each
individually grantable, transferable, and revocable. Gas-efficient
mass-fungible editions, if ever needed, belong in a future extension, not
the core primitive — the same reasoning that keeps ERC-1155 out of the
IP-asset layer (R4).

---

## Derivation & Composition

### R23. Derivation attestation

An IP Asset MAY carry a **derivation attestation** declaring its provenance:
the set of parent assets it is derived from. The attestation is OPTIONAL.
Absence means *no onchain statement has been made* about derivation,
which is distinct from asserting "no parents".

Absence MUST be encoded as the completely empty struct: `issuer == address(0)`,
`parents.length == 0`, `signature.length == 0`, `metadata.length == 0`, and
`registrationHash == bytes32(0)`. A registry MUST revert with
`MalformedDerivationAttestation()` if `issuer == address(0)` while any other
field is nonempty or nonzero. Such fields MUST NOT be stored, emitted, or
silently ignored. Conversely, any present attestation MUST have a nonzero
issuer and satisfy the signature rules below. An empty `parents` array on a
present, validly signed attestation means an explicit "original work" statement,
not absence.

The attestation is structured as:

```solidity
struct ParentRef {
    uint256 chainId;
    address registry;
    bytes32 assetId;
}

struct DerivationAttestation {
    ParentRef[] parents;     // empty array = explicit "original work" attestation
    address     issuer;      // attestor
    bytes       signature;   // EOA ECDSA or contract issuer ERC-1271 signature
    bytes       metadata;    // optional, opaque: producing-software hash,
                             //   process hash, prompt hash, etc.
    bytes32     registrationHash; // commitment to registrant + registration payload
}
```

`issuer` MAY be the registrant themselves (self-attestation), a piece of
software signing that only listed inputs were used (e.g. a remix tool, an
AI training pipeline, a video compositor), or a third-party oracle /
certifying service. The legal weight of the claim depends entirely on who
the issuer is and what the consumer trusts; the core ERC does not assign
trust.

For an `issuer` with no code, `signature` MUST be a 65-byte `r || s || v`
signature over the exact EIP-712 digest below, with `v` equal to 27 or 28 and
low-`s` canonicalization per EIP-2. For an `issuer` with code, `signature` is
opaque and MUST be verified using ERC-1271 `isValidSignature(bytes32,bytes)`.
Hash names below denote the 32-byte result of `keccak256`.

```text
DOMAIN_TYPE =
  "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
AUTHOR_TYPE =
  "Author(address author,uint256 shareNumerator)"
PARENT_TYPE =
  "ParentRef(uint256 chainId,address registry,bytes32 assetId)"
ASSET_DATA_TYPE =
  "AssetData(bytes32 assetType,uint8 tokenization,address tokenCollection,uint256 tokenId,bytes32 contentHash)"
REGISTRATION_TYPE =
  "Registration(bytes32 salt,address registrant,address owner,bytes32 authorsHash,uint256 sharesDenominator,bytes32 assetDataHash,bytes32 metadataURIHash)"
DERIVATION_TYPE =
  "Derivation(uint256 chainId,address registry,bytes32 assetId,bytes32 registrationHash,bytes32 parentsHash,bytes32 metadataHash)"
```

Each type hash is `keccak256(bytes(<TYPE>))`. Array hashes preserve order:

```text
authorHashes[i] = keccak256(abi.encode(
  AUTHOR_TYPEHASH, authors[i].author, authors[i].shareNumerator
))
authorsHash = keccak256(abi.encodePacked(authorHashes))

parentHashes[i] = keccak256(abi.encode(
  PARENT_TYPEHASH, parents[i].chainId, parents[i].registry, parents[i].assetId
))
parentsHash = keccak256(abi.encodePacked(parentHashes))
```

The registration commitment MUST bind the exact values supplied to `register`,
including values ignored by a tokenization mode:

```text
assetDataHash = keccak256(abi.encode(
  ASSET_DATA_TYPEHASH,
  assetType,
  uint8(tokenization),
  tokenCollection,
  tokenId,
  contentHash
))

registrationHash = keccak256(abi.encode(
  REGISTRATION_TYPEHASH,
  salt,
  registrant,
  owner,
  authorsHash,
  sharesDenominator,
  assetDataHash,
  keccak256(bytes(metadataURI))
))
```

`registrant` is the address expected to call `register` (`msg.sender`). The
registry MUST require `DerivationAttestation.registrationHash` to equal this
computed value. The initial metadata URI is signed; a later authorized
`updateMetadata` does not retroactively invalidate the creation-time
attestation.

```text
structHash = keccak256(abi.encode(
  DERIVATION_TYPEHASH,
  chainId,
  registry,
  assetId,
  registrationHash,
  parentsHash,
  keccak256(metadata)
))

domainSeparator = keccak256(abi.encode(
  DOMAIN_TYPEHASH,
  keccak256(bytes("IPAssetRegistry")),
  keccak256(bytes("1")),
  chainId,
  registry
))

digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash))
```

The registry MUST recover a code-free `issuer` from `digest` and `signature`.
For an issuer with code, it MUST instead `staticcall` `isValidSignature(digest,
signature)` with at most 100,000 gas and accept only an exact canonical 32-byte
ABI encoding of `bytes4(0x1626ba7e)`; failure, malformed return data, or any
other value MUST reject registration. Contract signatures do not follow the
EOA length or `v`/`s` restrictions. Binding both
the complete registration payload and intended registrant prevents a copied
pending attestation from being replayed onto altered asset data or submitted by
a front-runner under the same salt-derived `assetId`.
An ERC-1271 approval is checked at registration, not rechecked afterward.

`metadata` is opaque to the core ERC and lets attestors include
software-version hashes, process descriptions, prompt hashes, or any
provenance information their attestation needs. The core ERC does not
parse or interpret it.

Some registries gate derivation on licensing: registering a derived asset
(e.g. a remix) requires the registrant to hold a qualifying LicenseAgreement
on each relevant parent. The core already supports the *enforcement* side of
this without any new field — `canRegister` (R9) receives the full
`derivationAttestation`, so a registry may resolve each `ParentRef`, check
`activeAgreementsOf(parent, registrant, cursor, limit)` (R20), evaluate each agreement's terms, and refuse registration
when the required standing is absent. To additionally *record* which
agreement authorized each parent edge (answering "given this derived asset,
what agreements were relied upon?"), implementers SHOULD encode an array of
`(ParentRef, agreementRef)` pairs — where `agreementRef` is the canonical
`(chainId, registry, agreementId)` tuple — inside this `metadata` field,
under a layout standardized by the relevant extension spec (e.g. the Asset
Graph / licensing extension). This keeps the record atomic, immutable, and
signed at registration (R24) with no change to the core struct, and keeps
provenance separate from licensing: the core neither parses nor verifies
these references. Consumers MUST treat a recorded `agreementRef` as a
*snapshot claim* at registration time, not a live license check — the
referenced agreement may since have expired, been revoked, or been
transferred (R20/R21), so current standing MUST still be verified against the
parent via `activeAgreementsOf` / `isAgreementActive` and re-evaluate its terms. Recording the
authorizing agreement is therefore deliberately NOT a dedicated field on
`DerivationAttestation`: it would re-couple provenance and licensing, muddy
the issuer's signature domain, and bloat a struct the Asset Graph extension
traverses by `parents` alone.

Exactly one derivation attestation MAY be associated with an asset. Multiple
attestations from different parties about the same asset are out of scope
for the core ERC and may be modeled by extensions.

> Naming note: this is a dedicated structural field on the asset record,
> NOT a generic asset-claim stored via the R6d/R30 claims interface.
> The struct is deliberately named `DerivationAttestation` (not
> `DerivationClaim`) to avoid confusion with claim-topic entries.

### R24. Derivation attestation is set at registration and immutable

The derivation attestation MUST be supplied (if at all) at registration time as
part of the `register(...)` call. The registry MUST NOT permit setting,
modifying, or revoking a derivation attestation after registration completes.

Rationale (provenance integrity and front-running prevention): if the
attestation were mutable, a registrant could publish an asset, observe its
commercial reception, then retroactively claim derivation from a popular
work to siphon royalty flow, or claim derivation from a public-domain
work to confuse provenance. Immutability at registration commits the
registrant to provenance before any market signal exists.

Atomic submission is not by itself front-running protection: pending calldata is
public. The R23 `registrationHash` and intended-registrant binding MUST be
checked before registration so copied calldata cannot authorize altered asset
data or a different caller.

Correction of an incorrect derivation attestation follows the same remedy as
incorrect authorship (R10): register a new asset with the correct attestation,
and freeze the original under R32's administrative authorization. An
extension-defined supersession claim MAY link the replacement to the original.
The original belongs in the new attestation's parent list only if genuine
creative derivation occurred, not merely to preserve a correction link.

Parent references MAY point to assets in other registries via the
canonical `(chainId, registry, assetId)` tuple. Same-chain cross-registry
references work natively; cross-chain references work for off-chain
consumers but cannot be read onchain by EVM hooks, the same limitation
that applies to cross-chain terms (R17). Implementations needing
onchain dispatch on cross-chain parents MAY mirror them locally.

### R25. Core scope: store and verify, do not validate or walk graphs

The core ERC's responsibilities for a derivation attestation are deliberately
narrow:

1. Store the attestation verbatim with the asset record.
2. Verify that `signature` is valid against the attesting `issuer` over the
   canonical encoding.
3. Emit `DerivationAttestationRegistered(assetId, issuer, parents, metadata,
   registrationHash)` so off-chain indexers and graph extensions can pick it up
   and reconstruct the signed commitment.

The core ERC MUST NOT:

- Validate that the listed parents actually were used in producing the
  asset (this is an off-chain fact the registry cannot verify).
- Walk derivation graphs, detect cycles, or aggregate royalties across
  ancestry — these belong to graph and royalty extensions.
- Enforce that parent assets' license terms actually permit derivation —
  this is deployment policy. `canDerive` exposes the pre-flight question (R26);
  `canRegister` applies registration policy (R9). A cross-chain reference alone
  cannot supply verified remote parent state.
- Treat the absence of a derivation attestation as evidence of either
  originality or non-originality.

### R26. `canDerive` pre-flight hook

The core ERC MUST expose a pre-flight check that lets agents and
implementers ask "may this party derive from this parent asset under
current state?":

```solidity
function canDerive(bytes32 parentAssetId, address deriver)
    external view returns (bool ok, bytes32 reason);
```

The hook is read-only, MUST NOT revert on unknown inputs, and is called
on the parent asset's registry. Its implementation is entirely the
registry's policy.

Typical implementations resolve `canDerive` by:

1. Locating LicenseAgreements where `deriver` is the party on
   `parentAssetId` (via R20's `activeAgreementsOf`).
2. For each, reading the universal frame (R16a) and decoding `rightsData`
   per the agreement's `termsType` (R16c) to determine whether derivation
   is permitted under those terms.
3. Returning `(true, bytes32(0))` iff at least one current agreement
   satisfies the derivation policy, else `(false, <reason>)`.

This logic is implementer-specific because the meaning of "derivation
permitted" depends on the `termsType` schema (a software fork is not a
music remix). The core ERC defines the *question* (the hook signature);
implementers decide how to answer it.

`canDerive` is independent of the registration flow. At actual
registration, the registry's `canRegister` hook (R9) receives the full
derivation attestation and applies whatever final policy is needed.
`canDerive` is the cheap pre-flight that agents call before they bother
preparing the derivation.

---

## Discoverability & Events

### R27. Required read paths

Given a `(registry, assetId)` pair, any caller MUST be able to retrieve
through permission-less `view` functions, in one or a small constant
number of calls each:

| Concept | Returns | Unknown-asset sentinel |
| --- | --- | --- |
| Existence           | `assetExists(assetId)` | `false` |
| Owner               | `address` (per R5 — delegated for `ERC721`, stored for `NONE`) | `address(0)` |
| Authors             | `(Author[] authors, uint256 sharesDenominator)` (per R10–R11) | `([], 0)` |
| Tokenization        | `AssetTokenization` plus `(collection, tokenId)` binding when applicable (per R4) | `(NONE, address(0), 0)` |
| Asset type          | `bytes32 assetType` (per R7) | `bytes32(0)` |
| Metadata pointer    | `(string metadataURI, bytes32 contentHash)` (per R6a) | `("", bytes32(0))` |
| Derivation attestation | `DerivationAttestation` (per R23) | empty `parents`, `signature`, and `metadata`; zero `issuer` and `registrationHash` |
| Attached terms      | arrays of ids and parameters (per R18) | two empty arrays |
| Agreement count     | append-only agreement count | `0` |
| Active agreements   | paginated active `agreementId`s (per R19–R21, R27a) | empty page with `nextCursor == 0` |
| Asset claims        | by topic id, per the R6d interface | R30 sentinels |

For a given `agreementId`, any caller MUST be able to retrieve the bound
asset and terms tuples, the licensee (the stored `party` for `NONE`, or the
bound token's current holder for `ERC721`), the tokenization binding (per
R22), and the activity flags exposed by R20.

For a given `termsId`, any caller MUST be able to retrieve the full
`LicenseTerms` struct including universal frame, legal-text pointer, and
the `(termsType, rightsData)` pair.

The "active agreements" view is a deliberate addition to the core: AI
agents need to discover active license agreements on an asset
onchain, not only via events. Because a popular asset MAY accumulate
thousands of agreements over its lifetime, this read path MUST be
paginated (R27a); an unbounded array-returning form is non-conforming
because it can exceed the block gas limit and become permanently
uncallable for large assets.

The asset and agreement view functions in this requirement MUST be callable
without permission, MUST be `view`, and MUST return the exact sentinels defined
here and in R20, R27a, and R30 rather than revert on unknown identifiers. This
rule does not apply to `ITermsRegistry.getTerms`, which MUST revert for an
unknown `termsId` as specified in R18; callers use `termsExists` first.

### R27a. Paginated agreement enumeration

The per-asset agreement set is **append-only**: revoked, expired, and
frozen agreements are never deleted (R21), so once an agreement is
created its position in the asset's agreement list never moves. This
makes index-based pagination stable and is the basis of the required
read path.

Conforming registries MUST expose:

```solidity
function agreementCountOf(bytes32 assetId)
    external view returns (uint256);

function agreementAtIndex(bytes32 assetId, uint256 index)
    external view returns (bytes32 agreementId);

function activeAgreementsOf(bytes32 assetId, uint256 cursor, uint256 limit)
    external view returns (bytes32[] memory agreementIds, uint256 nextCursor);
```

Semantics:

- **`agreementCountOf(assetId)`** returns the total number of agreements
  ever created on the asset (including revoked, expired, and frozen
  ones). Indices in `[0, agreementCountOf(assetId))` are stable.
- **`agreementAtIndex(assetId, index)`** returns the `agreementId` at a
  stable index. Together with `agreementCountOf` it enumerates the full
  history; callers filter activity per-id via `isAgreementActive` (R20). It
  MUST return `bytes32(0)` when the asset is unknown or
  `index >= agreementCountOf(assetId)`.
- **`activeAgreementsOf(assetId, cursor, limit)`** examines up to `limit`
  agreements starting at stable index `cursor` and returns the
  active subset (R20: has a licensee, not expired, not revoked,
  not frozen) together with `nextCursor`, the index at which to resume.
  `limit` bounds the number of records *examined*, not the number
  returned, so gas is bounded regardless of how many are active; a page
  MAY therefore contain fewer than `limit` ids — or none — while
  agreements still remain. Enumeration is complete once
  `nextCursor == agreementCountOf(assetId)`; callers MUST iterate on that
  condition, not on a short page. When
  `cursor <= agreementCountOf(assetId)`, a zero `limit` examines nothing and
  returns the input `cursor` unchanged; an out-of-range cursor is clamped to the
  agreement count.

All three MUST be `view`, callable without permission, and MUST NOT
revert on an unknown `assetId`, an out-of-range index, or an out-of-range
`cursor`. An unknown asset or exhausted range returns an empty page with
`nextCursor == agreementCountOf(assetId)` (i.e. `0` for an unknown
asset). The paginated triple above is the normative, gas-safe asset-wide read
path. The per-party overload in R20 uses the same cursor and examined-record
semantics; neither path has an unpaginated core form.

### R28. Cross-registry and cross-chain references via IPid

Cross-registry discovery is achieved through the canonical IPid form
defined in R2. The core ERC does NOT maintain a registry of registries,
a catalog of catalogs, or any central index — these are extension
concerns, as discussed in [design_decisions.md](design_decisions.md).

Every conforming `IPAssetRegistry` MUST make it possible for any caller
to construct the canonical IPid (`ipid:<chainId>:<registry>/<assetId>`)
for any asset it holds. In practice:

- `<chainId>` MUST be the nonzero deployment-frozen EIP-155 value returned by
  the registry's `chainId()` view, as defined in R1. This explicit view lets
  off-chain consumers query a registry without already knowing its namespace.
- `<registry>` is `address(this)` of the registry contract.
- `<assetId>` is the in-registry id.

The same construction MUST be possible for `termsId` (yielding the
`ipterms:` form defined in R17) and for `agreementId` (yielding the
`ipagreement:` form defined in R19). All three follow the same pattern.

Namespace translation from human-facing identifiers (catalog labels,
DOIs, JASRAC ids, DIDs, …) to canonical IPids is the role of
resolver and catalog extensions (R2a). The core ERC defines only the
canonical form; it does not define namespace mappings.

### R29. Canonical event catalog with indexing rules

Event emission is a conformance requirement. For every successful invocation,
a conforming registry MUST emit exactly one corresponding event as follows:

| Invocation | Required event |
| --- | --- |
| `register` | `AssetRegistered`; additionally `DerivationAttestationRegistered` iff a derivation attestation is present |
| `updateMetadata` | `MetadataUpdated` |
| `transferOwnership` for `NONE` | `OwnershipTransferred` |
| `addClaim` / `revokeClaim` | `AssetClaimAdded` / `AssetClaimRevoked` |
| `setTrustedIssuer` | `TrustedIssuerChanged` |
| first-time `registerTerms` | `TermsRegistered`; re-registration of an existing id MUST succeed without emitting any event |
| `attachTerms` / `detachTerms` | `TermsAttached` / `TermsDetached` |
| `createAgreement` / `acquireAgreement` | `LicenseAgreementCreated` |
| `transferAgreement` for `NONE` | `LicenseAgreementTransferred` |
| `revokeAgreement` / `forceRevokeAgreement` | `LicenseAgreementRevoked` |
| `freezeAsset` / `unfreezeAsset` | `AssetFrozen` / `AssetUnfrozen` |
| `freezeAgreement` / `unfreezeAgreement` | `LicenseAgreementFrozen` / `LicenseAgreementUnfrozen` |

The event arguments MUST be the exact input, prior-state, resulting-state,
actor, timestamp, and normalized tokenization-dependent values declared in the
standalone specification and signatures below. ERC-721 ownership and agreement
transfers occur outside the registry and are observed from the bound token's
events. A reverted invocation has no persistent event. Indexed parameters are
marked with `*` in the signatures; up to three indexed parameters per event,
chosen for off-chain searchability.

**Indexing rule:** identifiers (`assetId`, `agreementId`, `termsId`,
`topicId`) MUST be `indexed` whenever they appear. Addresses that
represent a *role* relevant to filtering (registrant, owner, licensee,
issuer, the actor performing the action) MUST be `indexed` when there is
room. Free-form payload (URIs, content hashes, struct arrays, enums,
opaque reason codes) MUST NOT be `indexed`.

**Asset lifecycle**

```solidity
event AssetRegistered(
    bytes32 *assetId, address *registrant, address *owner,
    bytes32 assetType, uint8 tokenization, string metadataURI, bytes32 contentHash
);
event MetadataUpdated(
    bytes32 *assetId, address *updatedBy,
    string oldURI, string newURI, uint64 timestamp
);  // contentHash is immutable (R6a) and carried by AssetRegistered, not here
event OwnershipTransferred(
    bytes32 *assetId, address *from, address *to
);  // emitted only for tokenization == NONE; ERC721 transfers via the bound NFT contract
event AssetFrozen(bytes32 *assetId, address *by, bytes32 reason);
event AssetUnfrozen(bytes32 *assetId, address *by, bytes32 reason);
event DerivationAttestationRegistered(
    bytes32 *assetId, address *issuer,
    ParentRef[] parents, bytes metadata, bytes32 registrationHash
);
```

**Asset claims (R6d general claims)**

```solidity
event AssetClaimAdded(
    bytes32 *assetId, bytes32 *topicId, address *issuer, bytes data
);
event AssetClaimRevoked(
    bytes32 *assetId, bytes32 *topicId, address *issuer
);
event TrustedIssuerChanged(
    bytes32 *topicId, address *issuer, bool trusted, address *changedBy
);
```

**Terms lifecycle**

```solidity
event TermsRegistered(
    bytes32 *termsId, address *registrant, bytes32 *termsType
);
event TermsAttached(
    bytes32 *assetId, bytes32 *termsId, bytes attachmentParameters
);
event TermsDetached(
    bytes32 *assetId, bytes32 *termsId
);
```

**Agreement lifecycle**

```solidity
event LicenseAgreementCreated(
    bytes32 *agreementId, bytes32 *assetId, bytes32 *termsId,
    AgreementEvidence evidence, AgreementTokenization agreementTokenization,
    address agreementCollection, uint256 agreementTokenId,
    uint64 expiry, bool transferable, bool revocable
);
event LicenseAgreementTransferred(
    bytes32 *agreementId, address *from, address *to
);  // emitted only for tokenization == NONE; tokenized transfers go via the bound token contract
event LicenseAgreementRevoked(
    bytes32 *agreementId, address *by, bytes32 reason
);
event LicenseAgreementFrozen(
    bytes32 *agreementId, address *by, bytes32 reason
);
event LicenseAgreementUnfrozen(
    bytes32 *agreementId, address *by, bytes32 reason
);
```

Indexers reconstruct lifecycle history from the events above and bound tokens'
`Transfer` events. For ERC-721 assets, first obtain the collection/token-id binding
through `tokenizationOf`: `AssetRegistered` does not emit it. Agreement creation
events already contain their token binding. Historical reads may also be needed
to establish delegated holder state that an external token's events do not
fully describe; events alone do not prove an external token's behavior.

`LicenseAgreementCreated` MUST contain the complete immutable agreement state at
creation: binding, creation evidence, token binding, and captured lifecycle
frame. In particular, indexers MUST NOT need historical transaction calldata to
recover the licensor, creator, initial licensee, creation time, evidence hashes,
or token binding. The event's `AgreementEvidence` tuple has the same semantics
as R19.

---

## Extensibility & Hooks

### R30. Asset claims interface

The function ABI for the asset claims mechanism described in R6d. The
core ERC MUST expose, on every conforming `IPAssetRegistry`:

```solidity
function addClaim(
    bytes32 assetId,
    bytes32 topicId,
    address issuer,
    bytes calldata data,
    bytes calldata signature
) external;

function revokeClaim(
    bytes32 assetId,
    bytes32 topicId,
    address issuer
) external;

function getClaim(
    bytes32 assetId,
    bytes32 topicId,
    address issuer
) external view returns (
    bytes memory data,
    bytes memory signature,
    uint64 timestamp,
    bool revoked
);

function getClaimIssuers(
    bytes32 assetId,
    bytes32 topicId
) external view returns (address[] memory);

function setTrustedIssuer(
    bytes32 topicId,
    address issuer,
    bool trusted
) external;

function isTrustedIssuer(
    bytes32 topicId,
    address issuer
) external view returns (bool);
```

Semantics and rules:

- **Authorization for `addClaim` and `revokeClaim`** is the implementer's
  policy, but enforcement is mandatory. An arbitrary caller MUST NOT be able to
  create, replace, or revoke a claim under another address's `issuer` identity.
  The caller MUST be the named issuer or an address explicitly authorized to
  act for it by the registry's documented policy. Plausible models include
  issuer-only writes, trusted-issuer roles, issuer delegates, or an
  administrator able to revoke any claim. The core ERC defines the ABI rather
  than one universal role system.
- **`setTrustedIssuer` authorization** is also implementation-controlled but
  MUST be restricted to the registry's documented governance authority. The
  trusted-issuer registry is a hint consumed by hooks and downstream
  extensions; the core ERC does not itself dispatch on `isTrustedIssuer`.
- Every successful `setTrustedIssuer(topicId, issuer, trusted)` call MUST emit
  `TrustedIssuerChanged(topicId, issuer, trusted, msg.sender)`. Indexers MUST be
  able to reconstruct additions and removals without tracing transaction input.
- A conforming registry MUST document both authorization policies. Interface
  conformance proves neither that governance is trustworthy nor that a stored
  claim signature is valid. Authorization to store on an issuer's behalf MUST
  NOT be interpreted as signature verification; consumers still verify the
  stored signature and choose trusted issuers.
- **Signature handling.** The `signature` passed to `addClaim` is stored
  verbatim and returned by `getClaim`; the core ERC does **not** verify it
  onchain. The core defines no digest, domain, or byte encoding for claim
  signatures: they are opaque and issuer-scheme-specific. A consumer MUST know
  the issuer's declared signing scheme before attempting verification and MUST
  NOT infer validity from the signature's presence. This contrasts with the
  derivation attestation (R23/R25), whose exact signature scheme the core
  defines and verifies at registration.
- **Multiple claims per `(assetId, topicId)`** are permitted, one per
  distinct issuer.
- **Unknown-read sentinels.** For an absent claim, including any query against
  an unknown asset, `getClaim` MUST return empty `data`, empty `signature`,
  `timestamp == 0`, and `revoked == false`. `getClaimIssuers` MUST return an
  empty array for an unknown asset or topic. `isTrustedIssuer` MUST return
  `false` for an unknown topic/issuer pair. These reads MUST NOT revert.
- **`revoked` semantics.** Revoked claims MUST remain queryable through
  `getClaim` (with `revoked == true`) so that audit trails remain
  reconstructable. They MUST be excluded from `getClaimIssuers` and
  from any consumer treating "issuer attests topic for asset" as true.
- **Events** (`AssetClaimAdded`, `AssetClaimRevoked`,
  `TrustedIssuerChanged`) are defined in R29.
- **Well-known topic ids: none in core** (per R6d). All topic ids in this
  interface are implementer- or extension-defined.

The derivation attestation (R23) is NOT carried through this interface. It
is a dedicated, immutable, registration-time field with structural typing
(`ParentRef[]`) — the struct is named `DerivationAttestation` precisely to
avoid being mistaken for a claim-topic entry under this interface.
Authorship (R10) is similarly a dedicated field, not a claim. The two are
structurally first-class and the claims interface is for everything else.

### R31. Hook catalog

Every conforming registry MUST expose the following pre-flight hooks.
All are `view`, all are permissionless to call, and all MUST NOT revert
on unknown inputs. Each returns `(bool ok, bytes32 reason)`: `ok == false`
denies (rather than reverting on policy denial), and `reason` is an
implementer-defined, machine-readable code explaining a denial (e.g.
`"kyc-required"`, `"not-authorized"`). When `ok == true`, `reason` MUST be
`bytes32(0)`; when `ok == false`, `reason` SHOULD be a non-zero code.
Returning `(false, <code>)` for nonexistent identifiers is acceptable.
This mirrors the `bytes32 reason` convention already used by revocation and
freeze (R21, R32). The matching state-changing function MUST revert with
`HookDenied(bytes32 reason)` carrying the same code, so callers learn *why*
a write was rejected (mapped to a human message off-chain) — not merely
that it was.

```solidity
function canRegister(
    address registrant,
    RegistrationParams calldata params
) external view returns (bool ok, bytes32 reason);

function canUpdateMetadata(
    bytes32 assetId,
    string calldata newURI
) external view returns (bool ok, bytes32 reason);

function canTransferAsset(
    bytes32 assetId,
    address from,
    address to
) external view returns (bool ok, bytes32 reason);

function canTransferAgreement(
    bytes32 agreementId,
    address from,
    address to
) external view returns (bool ok, bytes32 reason);

function canAttachTerms(
    bytes32 assetId,
    bytes32 termsId,
    bytes calldata attachmentParameters
) external view returns (bool ok, bytes32 reason);

function canDetachTerms(
    bytes32 assetId,
    bytes32 termsId
) external view returns (bool ok, bytes32 reason);

function canLicense(
    bytes32 assetId,
    bytes32 termsId,
    address acquirer,
    bytes calldata licenseParams,
    bytes32 acceptanceHash
) external view returns (bool ok, bytes32 reason);

function canRevoke(
    bytes32 agreementId,
    address caller,
    bytes32 reason        // the caller-supplied revocation reason (R21)
) external view returns (bool ok, bytes32 denialReason);

function canDerive(
    bytes32 parentAssetId,
    address deriver
) external view returns (bool ok, bytes32 reason);
```

Common rules:

- **Pre-flight, not gate.** Each hook is a *read-only* pre-flight check
  that AI agents and integrators can call before submitting a
  state-changing transaction. The corresponding state-changing function
  MUST also enforce the equivalent check at write time; agents observing
  `(true, bytes32(0))` from a hook get no guarantee that the actual write
  will succeed if state changes between blocks, but they get a cheap signal
  of intent-feasibility, and a `reason` code to display when it is not.
- **Default-permissive is allowed.** A registry MAY return
  `(true, bytes32(0))` unconditionally from any hook. The *existence* of the
  hook is normative; the *policy* (and any `reason` codes) is not.
- **Implementer-controlled policy.** Plausible implementations consult
  the claims registry (R30), an external KYC service, jurisdiction
  modules (extension), licensing rights decoded from `termsType` schemas
  (R16c), the freeze state (R32), or any combination.
- **`canTransferAsset` applies to R14 administrative ownership transfers;
  `canTransferAgreement` applies to R19/R22 licensee transfers**, both for
  `NONE`-tokenization records. For
  tokenization-bound subjects (`ERC721` asset ownership, `ERC721`
  agreement licensee), the bound token contract is in the
  transfer path, not the registry, and neither registry transfer hook applies.
  Implementers requiring transfer policy on tokenized subjects MUST
  enforce it in a suitable restricted ERC-721, potentially using ERC-3643-style
  compliance checks, or use `NONE` to keep the registry in the path. An
  ERC-3643 token alone does not provide the required ERC-721 holder interface.
- `transferOwnership` MUST enforce `canTransferAsset` with the asset ID, current
  owner, and recipient. `transferAgreement` MUST enforce `canTransferAgreement`
  with the agreement ID, current licensee, and recipient. Each hook interprets
  its ID in its own namespace, even if an asset and agreement share identical
  ID bytes; implementations MUST NOT infer record kind by probing both ID maps.

### R32. Administrative paths: freeze and force-revoke

The core ERC defines five administrative functions used to interrupt
normal asset and agreement lifecycles. Authorization for these
functions is entirely the implementer's policy; the core ERC defines
their signatures, their observable consequences, and their events
(R29).

```solidity
function freezeAsset(bytes32 assetId, bytes32 reason) external;
function unfreezeAsset(bytes32 assetId, bytes32 reason) external;

function freezeAgreement(bytes32 agreementId, bytes32 reason) external;
function unfreezeAgreement(bytes32 agreementId, bytes32 reason) external;

function forceRevokeAgreement(bytes32 agreementId, bytes32 reason) external;
```

Observable consequences:

- **Frozen asset.** A frozen asset MUST refuse new `attachTerms` calls
  and both agreement-creation paths (`createAgreement` and `acquireAgreement`).
  It MUST NOT revoke, freeze, deactivate, or otherwise alter existing
  agreements, which retain their own expiry, current-licensee, revocation,
  and agreement-freeze state. Ownership transfer and terms detachment MAY
  each be allowed or refused per implementer policy. `unfreezeAsset` restores
  the blocked creation paths.
- **Frozen agreement.** A frozen agreement MUST cause `isActiveAgreementHolder`,
  `activeAgreementsOf`, and `isAgreementActive` (R20) to behave as if the
  agreement no longer existed, identical to revocation for activity checks
  purposes. The agreement record is NOT deleted; freezing is reversible
  via `unfreezeAgreement`. Revocation is terminal under R21.
- **`forceRevokeAgreement`** is the irreversible administrative revocation
  path described in R21; it is included here for grouping.

**Out of scope (deliberately):**

- **`freezeParty`** is NOT in the core. Per-action `canX` hooks (R31)
  let implementers consult sanctions lists at decision time without
  carrying a global "this address is frozen everywhere" flag, which
  would be a kind of central authority the core ERC avoids.
- **`recoverAsset`** is NOT in the core. Recovery of admin authority
  for lost-key scenarios is implementer-defined policy; see the
  [design rationale](design_decisions.md) for guidance on how
  a registry MAY support it and the security considerations involved.

Authorization for freeze, unfreeze, and force-revoke is implementer-
controlled but MUST be restricted to the registry's documented administrative
or governance authority. Plausible models include multisig, time-locked
governance, DAO vote, jurisdiction-module dispatch, or owner-only. The core ERC
neither prescribes a model nor exposes a hook for these paths — they
are deliberately administrative, intended for break-glass scenarios
(takedowns, sanctions, DMCA, jurisdiction orders).

### R33. ERC-165 interface support

Every conforming `IPAssetRegistry` MUST implement ERC-165's
`supportsInterface(bytes4 interfaceId) returns (bool)` and MUST return
`true` for at least:

- the ERC-165 interface id itself,
- the `IIPAssetRegistry` interface id defined by this ERC: **`0x72117f80`**, and
- the inherited `ITermsRegistry` interface id: **`0x38c7f550`**.
  Each is the XOR of that interface's own function selectors (excluding the
  inherited `supportsInterface`), computed from `src/interfaces/` and locked by
  `test/InterfaceId.t.sol`. They are re-pinned only if the interface surface
  changes.

ERC-165 support is mandatory because without it, downstream consumers
(catalogs, wallets, payment extensions, asset-graph extensions) have
no onchain way to detect that a contract claims to be a conforming
registry. Trial-and-error calls are unacceptable as a discovery
mechanism at scale.

### R34. Reserved

Intentionally unallocated — see *Reserved requirement numbers* near the top of
this document. Never allocated; Extensibility & Hooks settled at R30–R33 and
Party Identity resumes at R35. The number is not reused.

---

## Party Identity (moved to extensions)

R35–R37 originally defined optional `IIPPartyIdentity` and
`IIPPartyIdentityRegistry` interfaces. They were removed from the core
(2026-09-25) because they had no normative semantics in the ERC and their
`setTrustedIssuer`/`isTrustedIssuer` signatures collided with the core
asset-claims surface (R30). The numbers stay reserved for traceability.

### R35. Abstract party-identity model (extension)

Party-identity abstractions (ONCHAINID, DID+VC, ERC-8004, smart accounts, …)
are defined by extensions, not by the core.

### R36. Party identity registry (extension)

Resolving party addresses to identities, and any associated trusted-issuer
policy, is defined by extensions.

### R37. Integration model: hooks remain address-based

Hook signatures in R31 remain address-based. A registry MAY consult any
identity system inside its hook implementations (`canRegister`, `canLicense`,
`canRevoke`, etc.) to enforce identity-aware policy (KYC/AML, sanctions,
jurisdiction, role gating, agent-vs-human constraints). Identity claims are a
policy input, not a replacement for the Author, Owner, and Licensee roles.

---
