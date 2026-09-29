// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {TestBase} from "./TestBase.sol";
import {TERMS_TYPE_GENERIC_V1} from "../src/interfaces/IPAssetTypes.sol";

/// @title SchemaHashTest
/// @notice Reproduces and pins the content-addressed `termsType` of the
///         canonical generic schema JSON line embedded in ERC-8432.
contract SchemaHashTest is TestBase {
    string constant SPEC_PATH = "docs/erc-8432.md";
    bytes constant SCHEMA_PREFIX = bytes("{\"schema\":\"generic-license-v1\",");

    error InvalidSchemaLine();

    event GenericTermsType(bytes32 id);

    /// @notice Emits the computed id for recording (run with -vvvv).
    function test_RecordGenericTermsType() public {
        emit GenericTermsType(_computeSchemaId());
    }

    /// @notice The on-chain constant MUST equal the inline schema hash.
    function test_GenericTermsType_MatchesConstant() public view {
        assertEqB32(_computeSchemaId(), TERMS_TYPE_GENERIC_V1);
    }

    function test_SchemaHash_ExcludesSurroundingMarkdown() public view {
        bytes memory schema = extractSchema(bytes(vm.readFile(SPEC_PATH)));
        bytes memory document = abi.encodePacked(
            "# Revised introduction\n\n```json\n", schema, "\n```\n\nRevised explanation.\n"
        );
        assertEqB32(keccak256(extractSchema(document)), TERMS_TYPE_GENERIC_V1);
    }

    function test_SchemaHash_ExcludesCrLfLineTerminators() public view {
        bytes memory schema = extractSchema(bytes(vm.readFile(SPEC_PATH)));
        bytes memory document = abi.encodePacked("```json\r\n", schema, "\r\n```\r\n");
        assertEqB32(keccak256(extractSchema(document)), TERMS_TYPE_GENERIC_V1);
    }

    function test_SchemaHash_RejectsMissingSchema() public {
        vm.expectRevert(InvalidSchemaLine.selector);
        this.extractSchema(bytes("# No canonical schema\n"));
    }

    function test_SchemaHash_RejectsDuplicateSchema() public {
        bytes memory schema = extractSchema(bytes(vm.readFile(SPEC_PATH)));
        bytes memory document = abi.encodePacked(schema, "\n", schema, "\n");
        vm.expectRevert(InvalidSchemaLine.selector);
        this.extractSchema(document);
    }

    function test_SchemaHash_RejectsMultilineSchema() public {
        bytes memory document = abi.encodePacked(SCHEMA_PREFIX, "\n\"abi\":\"()\"}\n");
        vm.expectRevert(InvalidSchemaLine.selector);
        this.extractSchema(document);
    }

    function test_SchemaHash_RejectsSurroundingWhitespace() public {
        bytes memory schema = extractSchema(bytes(vm.readFile(SPEC_PATH)));
        vm.expectRevert(InvalidSchemaLine.selector);
        this.extractSchema(abi.encodePacked(" ", schema, "\n"));
        vm.expectRevert(InvalidSchemaLine.selector);
        this.extractSchema(abi.encodePacked(schema, " \n"));
    }

    function _computeSchemaId() internal view returns (bytes32) {
        return keccak256(extractSchema(bytes(vm.readFile(SPEC_PATH))));
    }

    function extractSchema(bytes memory document) public pure returns (bytes memory schema) {
        uint256 start = _indexOf(document, SCHEMA_PREFIX, 0);
        if (
            start == type(uint256).max
                || (start != 0 && document[start - 1] != bytes1("\n"))
                || _indexOf(document, SCHEMA_PREFIX, start + SCHEMA_PREFIX.length)
                    != type(uint256).max
        ) revert InvalidSchemaLine();

        uint256 end = start;
        while (end < document.length && document[end] != bytes1("\n") && document[end] != bytes1("\r")) {
            ++end;
        }
        if (document[end - 1] != bytes1("}")) revert InvalidSchemaLine();
        schema = new bytes(end - start);
        for (uint256 i = 0; i < schema.length; ++i) schema[i] = document[start + i];
    }

    function _indexOf(bytes memory hay, bytes memory needle, uint256 start)
        internal pure returns (uint256)
    {
        if (needle.length == 0 || needle.length > hay.length) {
            return type(uint256).max;
        }
        for (uint256 i = start; i <= hay.length - needle.length; ++i) {
            bool matched = true;
            for (uint256 j = 0; j < needle.length; ++j) {
                if (hay[i + j] != needle[j]) { matched = false; break; }
            }
            if (matched) return i;
        }
        return type(uint256).max;
    }
}
