# Implementer FAQ

For exact requirements, consult the [ERC draft](erc-draft.md). For example
calls, see [getting started](getting_started.md) and the
[integration guide](integration_guide.md).

### Does `registerTerms` or `attachTerms` grant a license?

No. Registration stores an immutable terms object; attachment publishes a
standing acquisition offer. A grant exists only after successful
`createAgreement` (owner/delegate) or `acquireAgreement` (caller under attached
terms). Both creation paths require local attached terms and current
`canLicense` approval.

### Why does my ERC-721 registration require `owner == address(0)`?

The administrative owner comes from the bound token's live `ownerOf`, not an
independent registry field. Supply a deployed collection with an observable
nonzero token holder. For `NONE`, instead supply a nonzero stored owner and a
nonzero original-work `contentHash`. See [tokenization choices](design_decisions.md#why-only-none-and-erc721-delegate-holders).

### Can `canLicense` authorize an unrelated caller to grant an agreement?

No. Policy approval never replaces owner or delegate authorization on
`createAgreement`. For `acquireAgreement`, the caller becomes the licensee
under the owner's standing attachment authorization. Pre-flight results can
also become stale before the write.

### Why do I get an empty discovery page when agreements still exist?

The `limit` in `activeAgreementsOf` bounds *records examined*. None of the
examined records may be active for that party. Keep the returned `nextCursor`
and continue until it reaches `agreementCountOf(assetId)`. Use a nonzero limit
and the same block state across pages for a coherent snapshot.

### Does `isActiveAgreementHolder` mean a user may use the work?

No. It verifies the supplied agreement's asset binding, current holder, and
lifecycle in the queried registry. Read that agreement's terms and decide
whether they cover the proposed use; separately assess the licensor's rights,
registry trust, payment, acceptance, and any off-chain conditions. Current
activity does not establish historical authorization.

### Why is `getLicensee` zero when I know the agreement's token ID?

For an ERC-721-bound agreement, a burned token, reverting/over-budget
`ownerOf`, or malformed result reads as no observable licensee. The record
still exists; it is inactive while there is no current holder. Raw
`agreementOf.party` is intentionally zero for this mode.

### Which bytes does each `contentHash` cover?

Asset `contentHash` covers the chosen original-work representation, not
necessarily the metadata document. `LicenseTerms.contentHash` covers the
optional legal document at `uri`. Hash exact bytes without normalization.
`termsId` is different again: it hashes the entire ABI-encoded `LicenseTerms`
tuple. See [terms and content integrity](integration_guide.md#terms-and-content-integrity).

### Can I update terms or correct the registered authors?

Terms and declared authorship are immutable. Publish corrected terms under a
new `termsId` and attach them for future agreements; existing agreements keep
the old terms. For an authorship correction, register a replacement asset;
authorized administration may freeze the earlier one against future licensing
without deactivating its existing agreements.

### Does `sublicensable` let a licensee call `createAgreement`?

No. The flag is recorded for downstream interpretation. The core has no
licensee-as-grantor action or parent/child sublicense relation; onchain
sublicensing needs an extension that defines those checks and lifecycle.

### Can a cross-chain `ParentRef` prove the parent license is valid?

No. It identifies a parent for off-chain resolution. The core verifies the
derivation issuer's signed registration statement, not parent usage, remote
state, legal permission, or cross-chain finality. `canDerive` is an advisory
policy query, not a mandatory child-registration gate.

### Are `rightsData`, attachment parameters, or claim signatures private?

No. Opaque means the core does not interpret their semantics; transaction
calldata and registry reads are public. Store sensitive material off-chain
and use an appropriate commitment or encryption scheme if needed.
