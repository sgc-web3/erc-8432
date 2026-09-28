// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {TestBase} from "./TestBase.sol";
import {IpRef} from "../src/IpRef.sol";
import {IPid} from "../src/IPid.sol";

/// @notice External wrapper so `vm.expectRevert` sees reverts one call frame
///         deeper than the cheatcode (library internals are inlined and would
///         otherwise revert at the same depth).
contract IpRefHarness {
    function encodeAsset(uint256 chainId, address registry, bytes32 id)
        external pure returns (string memory)
    {
        return IpRef.encodeAsset(chainId, registry, id);
    }

    function decodeAsset(string calldata s)
        external pure returns (uint256, address, bytes32)
    {
        return IpRef.decodeAsset(s);
    }
}

/// @title IpRefTest
/// @notice Round-trip, malformed-input, and fuzz coverage for the canonical
///         reference encoder/decoder for assets, terms, and agreements.
contract IpRefTest is TestBase {
    address constant REG = 0x00000000000000000000000000000000000000AB; // encodes to ...ab (lowercase)
    bytes32 constant ID =
        0x00000000000000000000000000000000000000000000000000000000000000ff;

    IpRefHarness internal harness = new IpRefHarness();

    // ---------------------------------------------------------------------
    // Encoding shape
    // ---------------------------------------------------------------------

    function test_EncodeAsset_CanonicalShape() public pure {
        string memory s = IpRef.encodeAsset(1, REG, ID);
        assertEqStr(
            s,
            "ipid:1:0x00000000000000000000000000000000000000ab/0x00000000000000000000000000000000000000000000000000000000000000ff"
        );
    }

    function test_EncodePrefixes_Differ() public pure {
        assertEqStr(_prefix(IpRef.encodeAsset(1, REG, ID)), "ipid:");
        assertEqStr(_prefix(IpRef.encodeTerms(1, REG, ID)), "ipterms:");
        assertEqStr(_prefix(IpRef.encodeAgreement(1, REG, ID)), "ipagreement:");
    }

    // ---------------------------------------------------------------------
    // Round trips
    // ---------------------------------------------------------------------

    function test_RoundTrip_AllKinds() public pure {
        _roundTrip(IpRef.Kind.ASSET, 1, REG, ID);
        _roundTrip(IpRef.Kind.TERMS, 8453, REG, ID);
        _roundTrip(IpRef.Kind.AGREEMENT, 137, REG, ID);
    }

    function test_IPid_BackCompat_MatchesIpRef() public pure {
        string memory viaLegacy = IPid.encode(10, REG, ID);
        string memory viaRef = IpRef.encodeAsset(10, REG, ID);
        assertEqStr(viaLegacy, viaRef);

        (bool ok, uint256 c, address r, bytes32 i) = IPid.tryDecode(viaLegacy);
        assertTrue(ok);
        assertEqU(c, 10);
        assertEqA(r, REG);
        assertEqB32(i, ID);
    }

    // ---------------------------------------------------------------------
    // Reverting decode paths
    // ---------------------------------------------------------------------

    function test_Encode_ZeroChainId_Reverts() public {
        vm.expectRevert(IpRef.ZeroChainId.selector);
        harness.encodeAsset(0, REG, ID);
    }

    function test_Decode_WrongPrefix_Reverts() public {
        vm.expectRevert(IpRef.InvalidPrefix.selector);
        harness.decodeAsset("ipterms:1:0x00000000000000000000000000000000000000ab/0x00000000000000000000000000000000000000000000000000000000000000ff");
    }

    function test_Decode_ZeroChainId_Reverts() public {
        vm.expectRevert(IpRef.InvalidChainId.selector);
        harness.decodeAsset("ipid:0:0x00000000000000000000000000000000000000ab/0x00000000000000000000000000000000000000000000000000000000000000ff");
    }

    // ---------------------------------------------------------------------
    // Non-reverting tryDecode / isValid
    // ---------------------------------------------------------------------

    function test_TryDecode_RejectsLeadingZeroChainId() public pure {
        (bool ok,,,) = IpRef.tryDecode(
            IpRef.Kind.ASSET,
            "ipid:01:0x00000000000000000000000000000000000000ab/0x00000000000000000000000000000000000000000000000000000000000000ff"
        );
        assertFalse(ok);
    }

    function test_TryDecode_RejectsUppercaseHex() public pure {
        (bool ok,,,) = IpRef.tryDecode(
            IpRef.Kind.ASSET,
            "ipid:1:0x00000000000000000000000000000000000000AB/0x00000000000000000000000000000000000000000000000000000000000000ff"
        );
        assertFalse(ok);
    }

    function test_TryDecode_RejectsShortRegistry() public pure {
        (bool ok,,,) = IpRef.tryDecode(
            IpRef.Kind.ASSET,
            "ipid:1:0xab/0x00000000000000000000000000000000000000000000000000000000000000ff"
        );
        assertFalse(ok);
    }

    function test_IsValid_KindMismatch() public pure {
        string memory terms = IpRef.encodeTerms(1, REG, ID);
        assertTrue(IpRef.isValid(IpRef.Kind.TERMS, terms));
        assertFalse(IpRef.isValid(IpRef.Kind.ASSET, terms));
    }

    // ---------------------------------------------------------------------
    // Fuzz
    // ---------------------------------------------------------------------

    function testFuzz_RoundTrip(uint256 chainId, address registry, bytes32 id) public pure {
        vm.assume(chainId != 0);
        _roundTrip(IpRef.Kind.ASSET, chainId, registry, id);
        _roundTrip(IpRef.Kind.TERMS, chainId, registry, id);
        _roundTrip(IpRef.Kind.AGREEMENT, chainId, registry, id);
    }

    // ---------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------

    function _roundTrip(IpRef.Kind k, uint256 chainId, address registry, bytes32 id) internal pure {
        string memory s = IpRef.encode(k, chainId, registry, id);
        (uint256 c, address r, bytes32 i) = IpRef.decode(k, s);
        assertEqU(c, chainId);
        assertEqA(r, registry);
        assertEqB32(i, id);
        assertTrue(IpRef.isValid(k, s));
    }

    function _prefix(string memory s) internal pure returns (string memory) {
        bytes memory b = bytes(s);
        uint256 end;
        for (uint256 i = 0; i < b.length; ++i) {
            if (b[i] == ":") { end = i + 1; break; }
        }
        bytes memory out = new bytes(end);
        for (uint256 i = 0; i < end; ++i) out[i] = b[i];
        return string(out);
    }
}







