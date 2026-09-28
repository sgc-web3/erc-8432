// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {TestBase} from "./TestBase.sol";
import {IERC165} from "../src/interfaces/IERC165.sol";
import {IIPAssetRegistry} from "../src/interfaces/IIPAssetRegistry.sol";
import {ITermsRegistry} from "../src/interfaces/ITermsRegistry.sol";

/// @title InterfaceIdTest
/// @notice Pins the ERC-165 interface ids. The `IIP_ASSET_REGISTRY_ID`
///         constant below is the value to record in the ERC's
///         `supportsInterface` requirement once the surface is frozen — read
///         it with `forge inspect` or a getter call, no run required.
/// @dev    Per the Solidity convention, `type(I).interfaceId` XORs only the
///         selectors declared in `I` itself, excluding inherited ones — so
///         the registry id below does NOT include `supportsInterface`.
contract InterfaceIdTest is TestBase {
    bytes4 public constant ERC165_ID = type(IERC165).interfaceId;
    bytes4 public constant IIP_ASSET_REGISTRY_ID = type(IIPAssetRegistry).interfaceId;
    bytes4 public constant ITERMS_REGISTRY_ID = type(ITermsRegistry).interfaceId;

    function test_Erc165_CanonicalId() public pure {
        assertEqB4(type(IERC165).interfaceId, bytes4(0x01ffc9a7));
    }

    /// @notice Pins the ERC-165 ids. If any interface signature changes,
    ///         these break — re-pin here, in the docs, and in any
    ///         `supportsInterface` implementation.
    function test_PinnedInterfaceIds() public pure {
        assertEqB4(type(IIPAssetRegistry).interfaceId, bytes4(0x72117f80));
        assertEqB4(type(ITermsRegistry).interfaceId, bytes4(0x38c7f550));
    }

    /// @notice Emitted by `test_RecordInterfaceIds` so the pinned values are
    ///         visible in `forge test -vvvv` traces.
    event InterfaceIdLog(string name, bytes4 id);

    /// @notice Emits every interface id for recording in the spec / EIP.
    function test_RecordInterfaceIds() public {
        emit InterfaceIdLog("IERC165", type(IERC165).interfaceId);
        emit InterfaceIdLog("IIPAssetRegistry", type(IIPAssetRegistry).interfaceId);
        emit InterfaceIdLog("ITermsRegistry", type(ITermsRegistry).interfaceId);
    }

    function test_InterfaceIds_NonZero_AndDistinctFromErc165() public pure {
        bytes4 erc165 = type(IERC165).interfaceId;

        bytes4 reg = type(IIPAssetRegistry).interfaceId;
        bytes4 terms = type(ITermsRegistry).interfaceId;

        assertTrue(reg != bytes4(0));
        assertTrue(terms != bytes4(0));

        assertTrue(reg != erc165);
        assertTrue(terms != erc165);
    }
}
