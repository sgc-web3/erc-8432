# Terminology

A growing glossary for readers of [the ERC draft](erc-draft.md) who know
Ethereum, Solidity, and ERCs but may be new to intellectual-property licensing.
Definitions explain how the draft uses each term; they are non-normative and
do not replace the specification or provide legal advice.

## Works, rights, and roles

### Intellectual property (IP), work, and IP asset

Intellectual property refers to legally recognized rights in creations, such as
copyright in a song or patent rights in an invention. A **work** is the material
being identified or licensed. An **IP asset** is this registry's record for that
material, not the material itself or proof of legal ownership. Registering a
record does not establish that the material is legally protected or that the
registrant has rights to it.

### Authorship and author shares

Authorship identifies who is credited with creating a work. It is distinct from
who currently owns or administers rights: an author may have transferred rights
or appointed someone else to manage them. The draft records author shares as
exact fractions. These entries do not themselves establish legal entitlements
or distribute royalties.

### Administrative owner

The address that controls an asset's owner-authorized registry operations, such
as attaching terms or granting agreements. For `NONE`, the registry stores this
address; for `ERC721`, it resolves the current holder of the bound token.
Administrative control is not proof of ownership of the underlying IP rights.
Transferring that control is not, by itself, a legal transfer of those rights.

### Registrant

The caller that submits an asset registration. This role is distinct from the
author and administrative owner. Submitting the registration does not give the
registrant ongoing authority over the record.

### Licensor, licensee, and party

A **licensor** grants permission to use a work; a **licensee** receives it. The
draft records the asset's administrative owner at agreement creation as the
licensor, without proving that address's legal authority to grant rights.
The current licensee may later change through a permitted registry transfer or
an external transfer of a bound ERC-721. In agreement APIs, **party** denotes
the licensee being specified or queried, not necessarily the transaction caller.

### License, license terms, and license agreement

A **license** is permission to exercise specified rights without necessarily
acquiring ownership of them. **License terms** describe reusable permissions,
restrictions, and conditions. A **license agreement** is the registry record
binding one asset, one terms object, and a licensee. Many agreements can reuse
the same terms; registering terms alone grants nobody a license.

## Offers and licensing conditions

The related fields are defined in the draft's Specification, sections 1.4,
1.6, 6, and 7.

### Standing offer / standing acquisition authorization

Attaching terms to an asset publishes terms under which qualifying callers can
use `acquireAgreement` without a new owner transaction or signature for each
acquisition. This is continuing registry authorization, subject to current
policy and creation requirements, not a guarantee of legal contract formation.
Attachment itself grants no rights. Detachment stops future agreements under
that attachment but leaves existing agreements unchanged. Attachments persist
across administrative ownership changes until detached.

### Grant versus acquisition

A **grant** uses `createAgreement`: the owner or an authorized delegate creates
an agreement for a licensee. An **acquisition** uses `acquireAgreement`: the
caller takes up attached terms and becomes the licensee of a `NONE` agreement.
Both paths require attached local terms and policy approval. A grant record
alone does not demonstrate that the recipient accepted the legal terms.

### Commercial use

Use connected to direct or indirect revenue. For example, using a song in a
paid advertisement is commercial use. The precise boundaries depend on the
terms' legal text; the machine-readable flag is a summary, not a complete
definition of every possible use.

### Derivative work / derivation / composition

A derivative work draws on or adapts an existing work, such as a translation or
remix. Composition can combine several works into another asset. Whether a
particular use legally counts as a derivative depends on the material and
applicable law. The draft can record declared parent assets, but a parent
reference does not grant permission to use them.

### Attribution

Giving required credit to an author or source. `attributionRequired` states
whether credit is required; an attribution template describes how to render
it. Attribution is not a substitute for permission, payment, or compliance
with other conditions.

### Exclusivity and scope

An exclusive license precludes other grants within the same licensed scope.
Scope describes the boundaries of the permission, which may include the kind
of use, territory, and time period. Exclusivity therefore does not necessarily
mean exclusive rights to every use of the entire work. The core records
`exclusive` but does not detect overlapping grants or enforce exclusivity.

### Sublicensing versus transfer

**Sublicensing** means a licensee grants another party permission derived from
its own license. **Transfer** changes who holds an existing agreement. They
are not interchangeable. The draft records `sublicensable` but defines no core
sublicense operation or parent-child agreement lifecycle. For `NONE`, it
enforces the agreement's captured `transferable` flag; for `ERC721`, transfer
restrictions require enforcement by the token contract.

### Jurisdiction and jurisdiction scope

A jurisdiction is a legal system or territory relevant to rights and their
enforcement. `jurisdictionScope` records a scope indicator, conventionally
`worldwide` or an ISO country code such as `JP`. It is not a complete
choice-of-law or court-selection clause, and the core does not enforce
territorial restrictions or establish enforceability there.

### Fee model, royalties, and settlement

A **fee model** classifies charges as free, one-time, recurring, usage-based,
external, or unspecified. It does not specify amounts or currencies.
**Royalties** are payments for exercising licensed rights, often tied to use
or revenue. **Settlement** is the actual payment or discharge of an obligation.
The core classifies fees but does not collect them, distribute royalties, or
prove payment. Royalty-stream tokenization, also outside the core, means
representing an entitlement to royalty payments with tokens.

## Expressing and identifying terms

### Machine-readable terms

Terms represented in structured fields that software can inspect without
interpreting legal prose. Here they combine a fixed universal frame,
`RightsSummary`, and optional schema-specific `rightsData`. Software can, for
example, compare whether two offers permit commercial use. Machine-readable
does not mean automatically enforced: the core records many assertions without
acting on them.

### Universal frame

The common fields for expiry, duration, transferability, revocability, sublicensing,
exclusivity, and jurisdiction scope. Every terms object has the same frame.
The registry applies its defined lifecycle rules, but some frame fields are
only recorded assertions for consumers to evaluate.

### Rights summary / comparison floor / unspecified

`RightsSummary` provides a common minimum vocabulary across different schemas:
commercial use, derivatives, attribution, and fee model. This **comparison
floor** lets software compare offers without decoding all domain-specific
details. `UNSPECIFIED` means no assertion, not permission or prohibition.
More detailed layers may fill gaps but cannot contradict explicit assertions.
The generic schema requires explicit, matching `YES` or `NO` values for its
three boolean rights dimensions.

### Rights schema and domain-specific rights

A schema defines how to decode and interpret `rightsData`; `termsType`
identifies that schema by content hash. A domain-specific schema can describe
rights particular to a kind of material or industry. `generic-license-v1` is
the draft's minimal asset-type-independent schema. The schema identifier
(`termsType`) names the format and meaning, whereas `termsId` identifies an
entire populated terms object.

### Opaque to the core

The registry stores or forwards a value without interpreting its internal
meaning. For example, consumers decode `rightsData` using its schema, and
hooks can interpret `licenseParams` or `attachmentParameters`. Opaque does
not mean encrypted or private: public transaction and registry data remain
visible.

### Legal wrapper / authoritative legal text / incorporation by reference

The optional `(uri, contentHash)` pair anchors a human-readable legal document.
An **instrument** is that legal document; **incorporation by reference** means
making it part of the terms by identifying it rather than reproducing its text
onchain. The wrapper supplies authoritative legal detail, but it cannot
override protocol behavior or contradict machine-readable assertions. The core
cannot detect such semantic conflicts; consumers must reject or flag them.
Anchoring a document does not establish its legal enforceability.

### Content-addressed terms and content anchors

Terms are **content-addressed** because `termsId` is the hash of the complete
canonical ABI-encoded terms object. Identical terms mirrored in another
registry retain that ID; changing a field requires a different ID.
Separately, an asset's `contentHash` anchors the original-work bytes, and a
terms object's `contentHash` anchors the legal-document bytes. Neither should
be confused with the salt-derived `assetId`. Byte identity does not prove
authorship, ownership, or semantic equivalence between differently encoded works.

## Discovery and verification

These distinctions explain the abstract and the read paths in Specification
sections 3 and 7.

### Machine-readable discovery

Finding relevant offers or agreements through structured registry queries
rather than manually searching documents or platform pages. A client can
inspect attached terms, retrieve their fields, and enumerate active agreements.
Discovery finds candidate records; it does not establish that a contemplated
use is legally permitted.

### Witness

In the draft's verification flow, a witness is a supplied `agreementId` pointing
to a candidate agreement. It is not a human witness, signature, or special
cryptographic proof. Supplying it lets the registry check that particular
agreement instead of searching for one.

### Constant-work agreement verification

`isActiveAgreementHolder` checks a supplied agreement against an asset and party
without scanning all agreements. The amount of work does not grow with the
asset's agreement count. This is not a promise of identical gas consumption:
ERC-721-bound holders, for example, require a bounded external query.
The result establishes registry activity and holder state, not legal validity.

### Bounded discovery

When no agreement witness is available, `activeAgreementsOf` searches the
asset's stable agreement index in pages. `limit` caps records **examined**, not
matches returned: examining ten expired agreements may produce an empty page
even when a later active agreement exists. To establish absence, continue from
`nextCursor` until it reaches `agreementCountOf(assetId)`. Each call is bounded;
the complete search can still grow with the asset's history. This guarantee
does not apply to every array-returning view.

### Globally scoped references and resolution

The `ipid:`, `ipterms:`, and `ipagreement:` forms name a record together with
its chain and registry. **Resolution** means using that information to locate
and read the record. A cross-chain reference identifies remote state; it does
not verify that state on the querying chain or provide a bridge.

## Provenance, evidence, and trust

### Signed provenance / derivation attestation

**Provenance** describes a work's declared origin and relationships to earlier
works. A derivation attestation is an issuer's signed statement binding the
registration details, intended registrant, parent references, and metadata.
The core verifies the signature and retains the immutable statement. It does
not prove that the origin story is true or that parent material was licensed.
A present attestation with no parents asserts "original work"; no attestation
makes no such assertion.

### Provenance graph and event-sourced provenance

A provenance graph connects derived assets to their declared parents.
**Event-sourced provenance** means off-chain indexers can build those
relationships from registry events rather than requiring the core to maintain
or traverse a graph. Traversal follows parent links, potentially across
registries and chains. Reconstructing the graph does not validate its claims.

### Asset claim, issuer, and trusted issuer

An asset claim is a statement about an asset under a topic, attributed to an
**issuer**. It could associate the asset with an industry identifier.
Generic claims differ from derivation attestations: their signature schemes
are extension-defined and verified off-chain, not standardized and verified
by the core. A **trusted issuer** is one marked trusted for a topic under
registry governance. That label is a trust decision, not proof that its claims
are true, and the core does not automatically act on it.

### Industry identifiers

These identifiers connect registry records with established external catalogs.
The draft leaves their claim topics to extensions.

| Term | Meaning |
| --- | --- |
| ISWC | International Standard Musical Work Code; identifies a musical work, distinct from a recording of it. |
| ISRC | International Standard Recording Code; identifies a sound recording or music video recording. |
| ISNI | International Standard Name Identifier; identifies public identities of contributors such as creators and organizations. |
| ISBN | International Standard Book Number; identifies a particular book edition and publication format. |
| DOI | Digital Object Identifier; provides a persistent identifier for an object such as a scholarly publication or dataset. |

### Agreement evidence and acceptance commitment

`AgreementEvidence` preserves creation-time facts such as the recorded licensor,
caller, initial licensee, and creation mode. `acceptanceHash` is an optional
commitment to acceptance-related evidence; the core does not prescribe or
verify that evidence. Recording a hash does not prove that anyone read,
accepted, or became legally bound by the terms. A zero hash means it is absent.

### Verified evidence, not adjudication

The registry can verify specified signatures and report recorded state.
**Adjudication** means deciding a dispute, such as who actually owns rights or
whether a license is enforceable. The ERC does not make those decisions.
**Legal validity** concerns whether a license has legal effect;
**enforceability** concerns whether its obligations or rights can be enforced
under applicable law. Neither follows merely from an active onchain record.

## Policy and lifecycle

### Mechanism, not policy / pre-flight hooks

**Mechanism** is the standardized record structure and operation behavior.
**Policy** determines deployment-specific eligibility and restrictions, such
as permitted jurisdictions or identity requirements. Permissionless `canX`
hooks expose policy decisions before a transaction; relevant writes enforce
current policy when executed. A successful pre-flight result is not a
reservation and cannot replace required caller authorization.

### KYC

Know Your Customer: identity-verification procedures used by some regulated
services. A deployment may apply such requirements through policy or
extensions. The ERC neither mandates KYC nor makes an active agreement proof
that those procedures occurred.

### Active agreement

An agreement with a current licensee that is not expired, revoked, or frozen.
"Active" is a registry-state predicate, not blanket permission to use the
asset. A consumer still needs to inspect that agreement's terms and applicable
off-chain conditions.

### Effective expiry and perpetual agreements

The effective expiry is the earlier applicable deadline from an absolute
terms expiry and a duration measured from agreement creation. For example,
"30 days from creation, but no later than December 31" ends at whichever comes
first. Both fields being zero means **perpetual**: no time-based expiry, not
immunity from revocation or freezing.

### Revocation, freeze, and break-glass authority

**Revocation** permanently deactivates an agreement without deleting its
history. An **agreement freeze** is reversible. An **asset freeze** instead
blocks new attachments and agreements without deactivating existing agreements.
**Break-glass** describes the exceptional administrative force-revocation
path: it bypasses the ordinary revocation hook but still requires the
deployment's documented administrative or governance authorization.
