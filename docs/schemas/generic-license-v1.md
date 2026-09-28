# generic-license-v1 — schema guide

> **Status:** non-normative companion to
> [ERC draft §1.6](../erc-draft.md#16-well-known-constants), which contains the
> complete schema and its canonical JSON hash preimage. This Markdown guide is
> not hashed. `test/SchemaHash.t.sol` reproduces the id from the draft and checks
> it against `TERMS_TYPE_GENERIC_V1` in `src/interfaces/IPAssetTypes.sol`.
>
> **Versioning:** changing the canonical schema bytes requires a new `termsType`.
> Editorial changes to this guide or to surrounding draft prose do not.

## 1. Purpose

`generic-license-v1` is the minimal, asset-type-agnostic rights schema
shipped by the core ERC. It exists so that simple registrations do not
have to pick a domain-specific schema. It captures three universally
meaningful rights flags plus an optional attribution-text template.

Domain-specific schemas (`music-license-v1`, `software-license-v1`,
`visual-license-v1`, `dataset-license-v1`, …) are illustrative
examples called out in non-normative ERC text. They are **not** part
of this schema and **not** part of the core ERC.

## 2. Solidity ABI layout

`LicenseTerms.rightsData` for `termsType == TERMS_TYPE_GENERIC_V1` is
the ABI encoding of the following Solidity struct:

```solidity
struct GenericLicenseV1Rights {
    bool   commercialUse;
    bool   derivativesAllowed;
    bool   attributionRequired;
    string attributionTemplate;
}
```

That is, `rightsData = abi.encode(GenericLicenseV1Rights(...))`.

The draft defines all fields normatively. Implementations MUST encode the
struct in the order above. Decoders MUST reject `rightsData` that is
not a valid ABI encoding of this struct.

## 3. Field semantics

### 3.1 `commercialUse` (bool)

`true` iff the licensee may use the asset for commercial purposes,
broadly defined as any use intended to generate direct or indirect
revenue.

`false` iff the licensee is restricted to non-commercial use (personal
use, educational use, research, internal evaluation, etc.).

The schema does not enumerate which specific uses count as
"commercial"; this is a jurisdiction- and context-dependent legal
question that the authoritative legal text (`LicenseTerms.uri`)
resolves.

### 3.2 `derivativesAllowed` (bool)

`true` iff the licensee may create derivative works based on the
asset.

`false` iff derivative works are prohibited.

The schema does not define what counts as a "derivative work";
jurisdiction-specific copyright law and the authoritative legal text
govern this. For domain-specific notions of derivation (software
forks, music remixes, dataset re-purposing), use a domain-specific
schema rather than this one.

Compliance and derivation hooks (`canDerive`, R26) SHOULD treat
`commercialUse == false && derivativesAllowed == true` as "non-
commercial derivatives only" and dispatch accordingly.

### 3.3 `attributionRequired` (bool)

`true` iff the licensee MUST credit the asset's author(s) when using
or distributing the asset or its derivatives.

`false` iff no attribution is required.

The exact attribution format is governed by `attributionTemplate`
(§ 3.4) when provided, and otherwise by the authoritative legal text.

### 3.4 `attributionTemplate` (string)

A free-form ASCII or UTF-8 string describing how attribution MUST be
rendered when `attributionRequired == true`. MAY contain placeholder
tokens of the form `{authorName}`, `{assetTitle}`, `{licenseName}`,
`{licenseURI}`, `{year}`. Consumers SHOULD substitute placeholders
they recognise and leave others verbatim.

When `attributionRequired == false`, `attributionTemplate` SHOULD be
the empty string. Decoders MUST NOT treat a non-empty template as
implying `attributionRequired == true`; the boolean is the authoritative
machine-readable assertion.

## 4. Interaction with the universal frame

The universal frame fields (R16a) are stored on the `LicenseTerms`
record itself, *not* in `rightsData`. They are:

- `expiry`, `duration`, `transferable`, `revocable`, `sublicensable`, `exclusive`,
  `jurisdictionScope`.

`generic-license-v1` does **not** restate these. Implementations
constructing a `LicenseTerms` value with this `termsType` MUST set
the universal-frame fields on the outer struct directly.

### 4.1 Interaction with `RightsSummary`

The three generic booleans restate the corresponding mandatory summary
dimensions and MUST match exactly:

| Summary value | Generic boolean | Conforming |
| --- | --- | --- |
| `YES` | `true` | Yes |
| `YES` | `false` | No |
| `NO` | `false` | Yes |
| `NO` | `true` | No |
| `UNSPECIFIED` | either | No |

`UNSPECIFIED` is invalid here because each generic boolean necessarily asserts
a polarity. Consumers decoding this schema MUST reject a mismatch. The core
terms registry stores `rightsData` opaquely and does not perform this semantic
validation.

## 5. Interaction with the legal text

`LicenseTerms.uri` and `LicenseTerms.contentHash` (R16b) point to
the authoritative legal document. For `generic-license-v1` the
authoritative text MAY be empty (`uri == ""`,
`contentHash == bytes32(0)`). When present, it defines detail not
expressible in the four fields above but MUST NOT contradict them or the
outer universal frame and rights summary. The booleans remain the
authoritative machine-readable assertions. A conflict is non-conforming
under R16b.1; it is not resolved by silently preferring the legal text.

## 6. Worked example

A simple non-commercial, derivatives-allowed, attribution-required
license:

```solidity
GenericLicenseV1Rights memory r = GenericLicenseV1Rights({
    commercialUse:        false,
    derivativesAllowed:   true,
    attributionRequired:  true,
    attributionTemplate:  "Based on \"{assetTitle}\" by {authorName}, {year}"
});
bytes memory rightsData = abi.encode(r);

LicenseTerms memory t = LicenseTerms({
    expiry:            0,                             // perpetual
    duration:          0,
    transferable:      false,
    revocable:         false,
    sublicensable:     false,
    exclusive:         false,
    jurisdictionScope: JURISDICTION_WORLDWIDE,
    rights: RightsSummary({
        commercialUse:       Ternary.NO,
        derivativesAllowed:  Ternary.YES,
        attributionRequired: Ternary.YES,
        feeModel:            FeeModel.UNSPECIFIED
    }),
    uri:               "",                            // no separate legal text
    contentHash:       bytes32(0),
    termsType:         TERMS_TYPE_GENERIC_V1,
    rightsData:        rightsData
});
```

## 7. Schema identifier and canonical bytes

Hash the exact single JSON line in [ERC draft §1.6](../erc-draft.md#16-well-known-constants):
UTF-8 bytes from its first `{` through its final `}`, excluding Markdown fences,
byte-order marks, surrounding whitespace, and the line terminator. Do not parse
and reserialize the JSON or normalize its bytes. This commits to the layout and
semantics, not this guide's prose or a file-dependent prefix.

```
TERMS_TYPE_GENERIC_V1 = keccak256(canonical inline JSON bytes)
                      = 0x497589298d23e3edf03354027567294825f845d9acccc3812cbb7b7b8dc3f5fa
```
