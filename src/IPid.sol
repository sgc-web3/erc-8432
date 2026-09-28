// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import { IpRef } from "./IpRef.sol";

/// @title IPid
/// @notice Thin back-compat wrapper over {IpRef} exposing the asset-specific
///         (`ipid:`) encoding and decoding API defined by the ERC.
///
/// New code SHOULD use {IpRef} directly, which generalises the same
/// canonical form to license terms (`ipterms:`) and license agreements
/// (`ipagreement:`). This wrapper exists so callers written against the
/// original `IPid` library continue to compile and behave identically.
library IPid {
    // Re-export errors for code that catches them by name. Since errors
    // cannot be aliased in Solidity, callers expecting the historic
    // `IPid.InvalidPrefix` (etc.) should migrate to `IpRef.InvalidPrefix`.
    // The semantics of the asset-specific surface below are unchanged.

    function encode(uint256 chainId, address registry, bytes32 assetId)
        internal pure returns (string memory)
    {
        return IpRef.encodeAsset(chainId, registry, assetId);
    }

    function decode(string memory ipid)
        internal pure returns (uint256 chainId, address registry, bytes32 assetId)
    {
        return IpRef.decodeAsset(ipid);
    }

    function tryDecode(string memory ipid)
        internal
        pure
        returns (bool ok, uint256 chainId, address registry, bytes32 assetId)
    {
        return IpRef.tryDecode(IpRef.Kind.ASSET, ipid);
    }

    function isValid(string memory ipid) internal pure returns (bool) {
        return IpRef.isValid(IpRef.Kind.ASSET, ipid);
    }
}
