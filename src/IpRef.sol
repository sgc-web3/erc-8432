// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

/// @title IpRef
/// @notice Reference parser/encoder for the canonical string form used by
///         this ERC to refer to assets, license terms, and license
///         agreements across registries and chains.
///
/// Three canonical forms are supported, all sharing identical syntax after
/// the prefix:
///
///     ipid:<chainId>:<registry>/<assetId>
///     ipterms:<chainId>:<registry>/<termsId>
///     ipagreement:<chainId>:<registry>/<agreementId>
///
/// where:
///   * `<chainId>`  is the EIP-155 chain id as a base-10 ASCII integer with
///                  no leading zeros. The value `0` is reserved and MUST
///                  NOT appear.
///   * `<registry>` is the 20-byte address of the issuing registry,
///                  encoded as a `0x`-prefixed lowercase hex string of
///                  exactly 42 characters.
///   * `<assetId>` / `<termsId>` / `<agreementId>` is the 32-byte id,
///                  encoded as a `0x`-prefixed lowercase hex string of
///                  exactly 66 characters.
///
/// The library is dependency-free and pure. The legacy `IPid.sol` library
/// is preserved as a thin back-compat wrapper around this one.
library IpRef {
    // ---------------------------------------------------------------------
    // Public surface
    // ---------------------------------------------------------------------

    /// @notice Which canonical form is being encoded or decoded.
    enum Kind { ASSET, TERMS, AGREEMENT }

    // ---------------------------------------------------------------------
    // Errors
    // ---------------------------------------------------------------------

    error InvalidPrefix();
    error MissingChainSeparator();
    error MissingIdSeparator();
    error InvalidChainId();
    error InvalidRegistry();
    error InvalidId();
    error ZeroChainId();

    // ---------------------------------------------------------------------
    // Encoding
    // ---------------------------------------------------------------------

    /// @notice Encode a canonical reference for the given kind.
    /// @dev    Reverts with `ZeroChainId` if `chainId == 0`.
    function encode(Kind k, uint256 chainId, address registry, bytes32 id)
        internal
        pure
        returns (string memory)
    {
        if (chainId == 0) revert ZeroChainId();
        return string(
            abi.encodePacked(
                _prefix(k),
                _toDecimalString(chainId),
                ":",
                _toHexString(uint160(registry), 20),
                "/",
                _toHexString(uint256(id), 32)
            )
        );
    }

    /// @notice Convenience: encode an `ipid:` (asset) reference.
    function encodeAsset(uint256 chainId, address registry, bytes32 assetId)
        internal pure returns (string memory)
    {
        return encode(Kind.ASSET, chainId, registry, assetId);
    }

    /// @notice Convenience: encode an `ipterms:` (license terms) reference.
    function encodeTerms(uint256 chainId, address registry, bytes32 termsId)
        internal pure returns (string memory)
    {
        return encode(Kind.TERMS, chainId, registry, termsId);
    }

    /// @notice Convenience: encode an `ipagreement:` (license agreement) reference.
    function encodeAgreement(uint256 chainId, address registry, bytes32 agreementId)
        internal pure returns (string memory)
    {
        return encode(Kind.AGREEMENT, chainId, registry, agreementId);
    }

    // ---------------------------------------------------------------------
    // Decoding
    // ---------------------------------------------------------------------

    /// @notice Parse a canonical reference string into its components.
    /// @dev    Reverts with a typed error on any deviation from the
    ///         canonical form. Hex characters must be lowercase.
    function decode(Kind k, string memory s)
        internal
        pure
        returns (uint256 chainId, address registry, bytes32 id)
    {
        bytes memory data = bytes(s);
        bytes memory prefix = _prefix(k);

        if (data.length < prefix.length) revert InvalidPrefix();
        for (uint256 i = 0; i < prefix.length; ++i) {
            if (data[i] != prefix[i]) revert InvalidPrefix();
        }

        uint256 colon = _indexOf(data, bytes1(":"), prefix.length);
        if (colon == type(uint256).max) revert MissingChainSeparator();

        uint256 slash = _indexOf(data, bytes1("/"), colon + 1);
        if (slash == type(uint256).max) revert MissingIdSeparator();

        chainId = _parseDecimal(data, prefix.length, colon);
        if (chainId == 0) revert InvalidChainId();

        if (slash - colon - 1 != 42) revert InvalidRegistry();
        registry = address(uint160(_parseHex(data, colon + 1, slash, 20, /*isRegistry*/ true)));

        if (data.length - slash - 1 != 66) revert InvalidId();
        id = bytes32(_parseHex(data, slash + 1, data.length, 32, /*isRegistry*/ false));
    }

    function decodeAsset(string memory s)
        internal pure returns (uint256 chainId, address registry, bytes32 assetId)
    {
        return decode(Kind.ASSET, s);
    }

    function decodeTerms(string memory s)
        internal pure returns (uint256 chainId, address registry, bytes32 termsId)
    {
        return decode(Kind.TERMS, s);
    }

    function decodeAgreement(string memory s)
        internal pure returns (uint256 chainId, address registry, bytes32 agreementId)
    {
        return decode(Kind.AGREEMENT, s);
    }

    /// @notice Non-reverting variant. Returns `(true, …)` on success and
    ///         `(false, 0, address(0), bytes32(0))` on any malformed input.
    function tryDecode(Kind k, string memory s)
        internal
        pure
        returns (bool ok, uint256 chainId, address registry, bytes32 id)
    {
        bytes memory data = bytes(s);
        bytes memory prefix = _prefix(k);

        // Minimum length: prefix + at least one chainId digit + ":" + 42 + "/" + 66.
        if (data.length < prefix.length + 1 + 1 + 42 + 1 + 66) return (false, 0, address(0), bytes32(0));
        for (uint256 i = 0; i < prefix.length; ++i) {
            if (data[i] != prefix[i]) return (false, 0, address(0), bytes32(0));
        }

        uint256 colon = _indexOf(data, bytes1(":"), prefix.length);
        if (colon == type(uint256).max) return (false, 0, address(0), bytes32(0));
        uint256 slash = _indexOf(data, bytes1("/"), colon + 1);
        if (slash == type(uint256).max) return (false, 0, address(0), bytes32(0));
        if (slash - colon - 1 != 42) return (false, 0, address(0), bytes32(0));
        if (data.length - slash - 1 != 66) return (false, 0, address(0), bytes32(0));

        (bool okChain, uint256 c) = _tryParseDecimal(data, prefix.length, colon);
        if (!okChain || c == 0) return (false, 0, address(0), bytes32(0));
        (bool okReg, uint256 r) = _tryParseHex(data, colon + 1, slash, 20);
        if (!okReg) return (false, 0, address(0), bytes32(0));
        (bool okId, uint256 v) = _tryParseHex(data, slash + 1, data.length, 32);
        if (!okId) return (false, 0, address(0), bytes32(0));

        return (true, c, address(uint160(r)), bytes32(v));
    }

    /// @notice True iff `s` is a syntactically valid canonical reference of
    ///         the given kind.
    function isValid(Kind k, string memory s) internal pure returns (bool ok) {
        (ok,,,) = tryDecode(k, s);
    }

    // ---------------------------------------------------------------------
    // Prefix table
    // ---------------------------------------------------------------------

    function _prefix(Kind k) private pure returns (bytes memory) {
        if (k == Kind.ASSET)     return bytes("ipid:");
        if (k == Kind.TERMS)     return bytes("ipterms:");
        // Kind.AGREEMENT
        return bytes("ipagreement:");
    }

    // ---------------------------------------------------------------------
    // Internal helpers
    // ---------------------------------------------------------------------

    function _indexOf(bytes memory s, bytes1 c, uint256 from)
        private pure returns (uint256)
    {
        for (uint256 i = from; i < s.length; ++i) {
            if (s[i] == c) return i;
        }
        return type(uint256).max;
    }

    function _parseDecimal(bytes memory s, uint256 start, uint256 end)
        private pure returns (uint256)
    {
        (bool ok, uint256 v) = _tryParseDecimal(s, start, end);
        if (!ok) revert InvalidChainId();
        return v;
    }

    function _tryParseDecimal(bytes memory s, uint256 start, uint256 end)
        private pure returns (bool, uint256)
    {
        if (end <= start) return (false, 0);
        // Reject leading zeros unless the value is a single "0" (which the
        // caller separately rejects as InvalidChainId).
        if (end - start > 1 && s[start] == "0") return (false, 0);
        uint256 v = 0;
        for (uint256 i = start; i < end; ++i) {
            uint8 b = uint8(s[i]);
            if (b < 0x30 || b > 0x39) return (false, 0);
            v = v * 10 + (b - 0x30);
        }
        return (true, v);
    }

    function _parseHex(bytes memory s, uint256 start, uint256 end, uint256 byteLen, bool isRegistry)
        private pure returns (uint256)
    {
        (bool ok, uint256 v) = _tryParseHex(s, start, end, byteLen);
        if (!ok) {
            if (isRegistry) revert InvalidRegistry();
            revert InvalidId();
        }
        return v;
    }

    function _tryParseHex(bytes memory s, uint256 start, uint256 end, uint256 byteLen)
        private pure returns (bool, uint256)
    {
        if (end - start != 2 + 2 * byteLen) return (false, 0);
        if (s[start] != "0" || s[start + 1] != "x") return (false, 0);
        uint256 v = 0;
        for (uint256 i = start + 2; i < end; ++i) {
            uint8 b = uint8(s[i]);
            uint256 nibble;
            if (b >= 0x30 && b <= 0x39) {
                nibble = b - 0x30;
            } else if (b >= 0x61 && b <= 0x66) {
                // lowercase a-f only (canonical form is lowercase)
                nibble = b - 0x61 + 10;
            } else {
                return (false, 0);
            }
            v = (v << 4) | nibble;
        }
        return (true, v);
    }

    function _toDecimalString(uint256 v) private pure returns (string memory) {
        if (v == 0) return "0";
        uint256 digits;
        uint256 tmp = v;
        while (tmp != 0) { ++digits; tmp /= 10; }
        bytes memory out = new bytes(digits);
        while (v != 0) {
            --digits;
            out[digits] = bytes1(uint8(48 + (v % 10)));
            v /= 10;
        }
        return string(out);
    }

    function _toHexString(uint256 value, uint256 byteLen)
        private pure returns (string memory)
    {
        bytes memory out = new bytes(2 + 2 * byteLen);
        out[0] = "0";
        out[1] = "x";
        for (uint256 i = 0; i < byteLen; ++i) {
            uint8 b = uint8(value >> (8 * (byteLen - 1 - i)));
            out[2 + 2 * i]     = _nibbleToHex(b >> 4);
            out[2 + 2 * i + 1] = _nibbleToHex(b & 0x0f);
        }
        return string(out);
    }

    function _nibbleToHex(uint8 n) private pure returns (bytes1) {
        return n < 10
            ? bytes1(uint8(48 + n))         // '0'..'9'
            : bytes1(uint8(87 + n));        // 'a'..'f' (97 - 10)
    }
}
