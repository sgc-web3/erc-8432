# Onchain IP Asset and License Registry

An ERC draft for recording IP assets, reusable license terms, and verifiable
license agreements across independent registries.

## Documentation

Start at the [developer documentation](docs/index.md). It includes an
[overview](docs/erc_overview.md), [getting started](docs/getting_started.md),
[integration patterns](docs/integration_guide.md),
[design decisions](docs/design_decisions.md), and an
[implementer FAQ](docs/faq.md). The [ERC draft](docs/erc-draft.md) remains the
authoritative specification, including its canonical interface, schema,
rationale, compatibility, and security considerations.

## Solidity surface

| File | Purpose |
| --- | --- |
| `src/interfaces/IPAssetTypes.sol` | Shared types and constants |
| `src/interfaces/IIPAssetRegistry.sol` | Canonical registry interface |
| `src/interfaces/ITermsRegistry.sol` | Local terms storage interface |
| `src/interfaces/IERC165.sol` | ERC-165 interface |
| `src/IpRef.sol` | Encoder/decoder for `ipid:`, `ipterms:`, and `ipagreement:` references |
| `src/IPid.sol` | Asset-reference compatibility alias |
| `src/IPAssetRegistry.sol` | Non-normative reference implementation |

The reference implementation validates the specification and has not been
audited. Solidity builds without external dependencies.

## Status

The ERC is a draft. The interface id (`0x72117f80`) and generic schema hash
(`0x497589298d23e3edf03354027567294825f845d9acccc3812cbb7b7b8dc3f5fa`)
are checked by the test suite.

## Build and test

Install [Foundry](https://book.getfoundry.sh/) and run:

```sh
forge build
forge test
```

No `forge install` step is required. Tests cover identifiers, interface and
schema hashes, registration, terms, agreement lifecycle, pagination, and
derivation signatures.

## License

Solidity files are `CC0-1.0` under the
[CC0 license](https://creativecommons.org/publicdomain/zero/1.0/).
