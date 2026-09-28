# Getting started for implementers

This walkthrough uses the dependency-free Solidity interface and the reference
registry. The [ERC draft](erc-draft.md) is authoritative when implementing a
different registry.

## Build and locate the interfaces

From the repository root, with [Foundry](https://book.getfoundry.sh/) installed:

```sh
forge build
forge test
```

Import [`IIPAssetRegistry`](../src/interfaces/IIPAssetRegistry.sol) for the
registry API, [`IPAssetTypes`](../src/interfaces/IPAssetTypes.sol) for the
file-level enums, structs, and constants, and
[`ITermsRegistry`](../src/interfaces/ITermsRegistry.sol) for the inherited
terms-storage API. A conforming registry reports ERC-165 support for
`IIPAssetRegistry` (`0x72117f80`) and `ITermsRegistry` (`0x38c7f550`).
Interface detection identifies a claim of support, not trustworthy records.

## Publish a registry-tracked work and an offer

This example registers an off-chain work with one declared author and publishes
summary-only terms. The `Publisher` contract is the *registrant* and
administrative owner because it calls `register` and supplies `address(this)`;
the external caller is the declared author. A production publisher must define
its own authorization for who can call `publish`.

```solidity
// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {IIPAssetRegistry} from "../src/interfaces/IIPAssetRegistry.sol";
import {
    AssetTokenization, Author, ParentRef, DerivationAttestation, RegistrationParams,
    LicenseTerms, RightsSummary, Ternary, FeeModel,
    ASSET_TYPE_SOFTWARE, JURISDICTION_WORLDWIDE
} from "../src/interfaces/IPAssetTypes.sol";

contract Publisher {
    IIPAssetRegistry public immutable registry;

    constructor(IIPAssetRegistry registry_) { registry = registry_; }

    function publish(bytes32 salt, bytes calldata work, string calldata metadataURI)
        external returns (bytes32 assetId, bytes32 termsId)
    {
        Author[] memory authors = new Author[](1);
        authors[0] = Author(msg.sender, 1);
        DerivationAttestation memory noDerivation = DerivationAttestation({
            parents: new ParentRef[](0),
            issuer: address(0),
            signature: "",
            metadata: "",
            registrationHash: bytes32(0)
        });

        RegistrationParams memory params = RegistrationParams({
            salt: salt,
            owner: address(this),
            authors: authors,
            sharesDenominator: 1,
            assetType: ASSET_TYPE_SOFTWARE,
            tokenization: AssetTokenization.NONE,
            tokenCollection: address(0),
            tokenId: 0,
            metadataURI: metadataURI,
            contentHash: keccak256(work),
            derivationAttestation: noDerivation
        });
        (bool ok, ) = registry.canRegister(address(this), params);
        require(ok, "registration policy denied");
        assetId = registry.register(params);

        LicenseTerms memory terms = LicenseTerms({
            expiry: 0,
            duration: 30 days,
            transferable: false,
            revocable: true,
            sublicensable: false,
            exclusive: false,
            jurisdictionScope: JURISDICTION_WORLDWIDE,
            rights: RightsSummary({
                commercialUse: Ternary.NO,
                derivativesAllowed: Ternary.NO,
                attributionRequired: Ternary.YES,
                feeModel: FeeModel.FREE
            }),
            uri: "",
            contentHash: bytes32(0),
            termsType: bytes32(0), // summary is the complete machine-readable expression
            rightsData: ""
        });
        termsId = registry.registerTerms(terms);
        registry.attachTerms(assetId, termsId, "");
    }
}
```

Choose a fresh `salt` for each registration by the same publisher. The asset ID
is `keccak256(abi.encode(registry.chainId(), address(registry),
address(publisher), salt))`. The asset's `contentHash` hashes the exact work
bytes, **not** the document at `metadataURI`. Supplying bytes to this demo
means those bytes also appear in transaction calldata; for large or private
works, compute the hash off-chain and pass only the commitment in your own
registration flow.

The empty legal wrapper above is permitted, but summary-only terms are not a
substitute for specifying all legally relevant conditions. To attach a legal
document, populate *both* `uri` and `contentHash = keccak256(documentBytes)`.
To use the generic schema instead, set `termsType` to
`TERMS_TYPE_GENERIC_V1`, ABI-encode its four-field payload, and make all three
boolean assertions match the outer rights summary. See
[terms decoding](integration_guide.md#terms-and-content-integrity).

## Acquire and inspect

After `publish`, a licensee checks
`canLicense(assetId, termsId, licensee, licenseParams, acceptanceHash)` and
calls `acquireAgreement(assetId, termsId, licenseParams, acceptanceHash)` **from
the licensee's own address**. The returned `agreementId` is their witness.
Acquisition creates a `NONE` agreement held by `msg.sender`; passing a licensee
argument to the pre-flight hook does not change who acquires it.

Then call `isActiveAgreementHolder(agreementId, assetId, licensee)` to verify
the current holder and lifecycle. Fetch `agreementOf(agreementId)` to obtain
its `termsId`, then `getTerms(termsId)` to evaluate the **same agreement's**
rights. A true activity result alone does not authorize a particular use.

## Implementing a different registry

Use the [draft's Specification](erc-draft.md#specification) as the conformance
checklist. In particular:

- Implement the exact types, selectors, events, and unknown-ID read behavior;
  preserve deterministic asset and agreement IDs and exact terms ABI encoding.
- Enforce owner/licensee/issuer/administrator authorization independently of
  pre-flight hook results. Document your delegation and governance policy.
- Keep terms local and immutable, author shares and derivation immutable,
  agreements indexed append-only, and activity reads non-reverting.
- For ERC-721 bindings, resolve the live holder using the specified bounded,
  canonical `ownerOf` read; do not cache a holder or claim to police external
  token transfers.
- Test permissionless reads, authorization, expired/revoked/frozen agreements,
  malformed token responses, cursor edge cases, and EIP-712 / ERC-1271
  derivation signatures. The [reference tests](../test/IPAssetRegistry.t.sol)
  show representative cases.

Next: [integration patterns](integration_guide.md) and
[why the interfaces work this way](design_decisions.md).
