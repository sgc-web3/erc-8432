// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

/// @title Vm
/// @notice Minimal subset of the Foundry cheatcode interface used by the
///         tests. Declared locally so the suite needs no `forge-std` /
///         `forge install` — `forge test` runs with zero external deps.
interface Vm {
    function expectRevert(bytes4 revertData) external;
    function assume(bool condition) external pure;
    function readFile(string calldata path) external view returns (string memory);
}

/// @title TestBase
/// @notice Tiny dependency-free assertion harness. Foundry runs any function
///         named `test*`; assertions revert on failure, which marks the test
///         failed. Functions taking arguments are fuzzed automatically.
abstract contract TestBase {
    /// @dev Canonical Foundry cheatcode (HEVM) address.
    Vm internal constant vm = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    function assertTrue(bool c) internal pure {
        require(c, "assertTrue failed");
    }

    function assertTrue(bool c, string memory err) internal pure {
        require(c, err);
    }

    function assertFalse(bool c) internal pure {
        require(!c, "assertFalse failed");
    }

    function assertEqB4(bytes4 a, bytes4 b) internal pure {
        require(a == b, "assertEqB4 failed");
    }

    function assertEqU(uint256 a, uint256 b) internal pure {
        require(a == b, "assertEqU failed");
    }

    function assertEqA(address a, address b) internal pure {
        require(a == b, "assertEqA failed");
    }

    function assertEqB32(bytes32 a, bytes32 b) internal pure {
        require(a == b, "assertEqB32 failed");
    }

    function assertEqStr(string memory a, string memory b) internal pure {
        require(
            keccak256(bytes(a)) == keccak256(bytes(b)),
            "assertEqStr failed"
        );
    }
}



