# Design decisions for implementers

The [ERC draft](erc-draft.md) defines the behavior. This guide explains why
several constraints exist and the trade-offs they create when building a
registry, token adapter, indexer, or policy module.

## Why one registry holds assets, terms, and agreements

An asset identifies a work and its administrative role; terms describe a
reusable offer; an agreement records a grant to a licensee. Separate records
allow many offers per asset and many agreements per offer without changing an
agreement when a later offer is updated. Terms must be available **locally**
before attachment and creation: a grant cannot depend on a remote terms
registry staying available or honest. Identical terms can still be mirrored
between registries because their IDs hash the same canonical tuple.

The registry is a policy and trust boundary, not a globally privileged
authority. Anyone can deploy one. ERC-165 and canonical references simplify
integration, while consumers decide which registries and issuers to trust.
The `(chainId, registry, id)` reference form can identify records across
chains but cannot bridge or verify their state.

## Why asset IDs use a registrant-chosen salt

`assetId = keccak256(abi.encode(chainId, registry, registrant, salt))`, where
`registrant` is the caller of `register`. This makes an ID computable before a
transaction: the issuer can sign a derivation attestation over the intended
asset ID and complete registration payload. Including the caller prevents
someone copying a pending salt to occupy **that caller's** ID. It does not
prevent another registrant from making a different record for the same work.
The chain ID is captured at deployment so a later fork does not silently
rename records or alter the signing domain. Discovery and trust decisions for
duplicate works remain outside the core.

## Why only `NONE` and `ERC721` delegate holders

`NONE` stores one administrative owner or licensee. `ERC721` binds to one
external token and reads its live holder. An open tokenization enum would
pretend the registry understood arbitrary standards' ownership semantics;
ERC-1155 balances, for example, cannot supply one unambiguous current licensee
for each agreement. Unsupported tokens can be described in metadata while the
registry tracks a `NONE` owner.

For ERC-721, caching holders would go stale on transfers outside the registry.
The live read has a 100,000-gas budget, checks the exact ABI result, and treats
failure as no holder. The cost is that registry hooks cannot police external
transfers. A deployment needing enforceable transfer restrictions uses `NONE`
or a cooperating ERC-721 contract; a captured `transferable` value alone is
not an NFT transfer gate.

## Why terms mix a fixed frame and typed payloads

The universal frame gives every agreement the same lifecycle semantics.
The mandatory tri-state rights summary makes common dimensions comparable
without knowing a music, software, or dataset schema. Domain-specific
`rightsData` can then express details the common frame cannot. A nonzero
`termsType` pins a schema by its exact bytes; changing its meaning needs a new
ID. Legal prose can supply detail but must not contradict the machine-readable
frame and summary. The core cannot check semantic contradictions in opaque
payloads or documents; schema-aware consumers must reject or flag them.

Terms hash the full ABI encoding of **one** `LicenseTerms` tuple, including
dynamic fields and its top-level offset. This makes identical terms reusable
and corrections explicit new objects. The draft includes encoding vectors
and the canonical `generic-license-v1` schema preimage so implementations in
other languages can reproduce the IDs.

## Why attachment is authorization, not an agreement

Only an owner or delegate may attach local terms. An attachment is a standing
offer: a qualifying caller can invoke `acquireAgreement` without another owner
signature. Actual creation still checks `canLicense`, records the current
owner as licensor, and produces a specific agreement. Owner-granted
`createAgreement` uses the same attached terms but permits an ERC-721-bound
agreement. Both paths bind the grant to immutable terms; detaching the offer
does not rewrite or deactivate prior grants. Attachment parameters are public
opaque input for deployment-specific policy, not secret payment data.

## Why verification takes an agreement ID

`isActiveAgreementHolder` checks one supplied agreement in constant work with
respect to the asset's agreement count. A universal party index would become
stale when bound ERC-721 tokens transfer outside the registry. Instead,
`activeAgreementsOf` scans stable append-only indices in bounded pages. This
keeps any *one* call bounded, but a complete absence proof can require scanning
the entire history. Indexers can build application-specific search indices
off-chain. Activity verifies registry holder and lifecycle state only; an
application must inspect **that** agreement's terms and other evidence.

## Why policy checks and authority are separate

Permissionless `canX` hooks let a user or agent preview eligibility. They
cannot prove the caller is the asset owner, current licensee, claim issuer, or
administrator. State can also change between the preview and the write.
Each protected write therefore enforces its own authorization and current
policy; exceptional freeze and force-revoke paths use documented governance
authority instead of the ordinary hooks. The core specifies effects while
deployments choose identity, jurisdiction, delegate, and governance rules.

Authorship and signed derivation are immutable registration-time declarations;
mutable asset claims handle later issuer-specific evidence. Neither a signature
nor an active agreement is a legal adjudication of title or permitted use.
See [integration patterns](integration_guide.md) for the practical implications.
