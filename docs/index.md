# Developer documentation

Build against the [ERC draft](erc-draft.md), which defines the required ABI and
behavior. These guides explain how to use and implement it; they are
non-normative.

| Start here | If you want to… |
| --- | --- |
| [Overview](erc_overview.md) | Understand assets, terms, agreements, and their trust boundaries in a few minutes. |
| [Getting started](getting_started.md) | Build the contracts, publish an asset and offer, and acquire an agreement. |
| [Integration guide](integration_guide.md) | Implement agreement checks, pagination, terms decoding, provenance, and indexing. |
| [Design decisions](design_decisions.md) | Understand the technical trade-offs and choose tokenization, policy, and extension strategies. |
| [FAQ](faq.md) | Resolve recurring implementation questions and failure modes. |
| [ERC draft](erc-draft.md) | Consult the canonical types, rules, schema bytes, test vectors, and security considerations. |

The [Solidity interfaces](../src/interfaces/) are importable directly; the
[reference registry](../src/IPAssetRegistry.sol) illustrates one implementation.
It is a reference policy, not a prescribed governance model.
