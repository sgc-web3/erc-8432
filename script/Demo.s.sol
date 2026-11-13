// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

/// ERC-8432 workshop demo: the full licensing lifecycle in one script.
///
///   anvil                                   # terminal 1
///   forge script script/Demo.s.sol --rpc-url http://127.0.0.1:8545 --broadcast   # terminal 2
///
/// Without --rpc-url/--broadcast it runs as a local simulation.
/// Default keys are anvil's public test accounts #0 (Alice) and #1 (Bob);
/// override with ALICE_KEY / BOB_KEY. Never use real keys in a demo.

import {
    AssetTokenization,
    AgreementTokenization,
    Author,
    LicenseTerms,
    RightsSummary,
    Ternary,
    FeeModel,
    RegistrationParams
} from "../src/interfaces/IPAssetTypes.sol";
import {IPAssetRegistry} from "../src/IPAssetRegistry.sol";
import {IpRef} from "../src/IpRef.sol";

/// Minimal cheatcode subset, so the script needs no forge-std.
interface Vm {
    function addr(uint256 pk) external pure returns (address);
    function envOr(string calldata name, uint256 defaultValue) external view returns (uint256);
    function startBroadcast(uint256 pk) external;
    function stopBroadcast() external;
}

contract Demo {
    Vm internal constant vm = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
    address internal constant CONSOLE = 0x000000000000000000636F6e736F6c652e6c6f67;

    bytes32 internal constant ASSET_TYPE_AUDIO = keccak256("audio");
    bytes32 internal constant JURISDICTION_WORLDWIDE = keccak256("worldwide");
    bytes32 internal constant TERMS_TYPE_GENERIC_V1 =
        0x497589298d23e3edf03354027567294825f845d9acccc3812cbb7b7b8dc3f5fa;

    function run() external {
        uint256 aliceKey = vm.envOr(
            "ALICE_KEY", 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
        );
        uint256 bobKey = vm.envOr(
            "BOB_KEY", 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d
        );
        address alice = vm.addr(aliceKey);
        address bob = vm.addr(bobKey);

        // ---- 0. Deploy a registry (Alice is also its admin here) --------
        vm.startBroadcast(aliceKey);
        IPAssetRegistry reg = new IPAssetRegistry();

        // ---- 1. Alice registers her song ---------------------------------
        RegistrationParams memory p;
        p.salt = keccak256("tokyo-nights");
        p.owner = alice;
        p.authors = new Author[](1);
        p.authors[0] = Author({author: alice, shareNumerator: 1});
        p.sharesDenominator = 1;
        p.assetType = ASSET_TYPE_AUDIO;
        p.tokenization = AssetTokenization.NONE; // registry-tracked, no NFT needed
        p.metadataURI = "ipfs://bafy.../tokyo-nights.json";
        p.contentHash = keccak256("<audio file bytes>");
        // p.derivationAttestation left empty = canonical "absent" encoding
        bytes32 assetId = reg.register(p);

        // ---- 2. Register reusable, content-addressed terms ---------------
        LicenseTerms memory t;
        t.duration = 30 days; // each agreement lasts 30 days
        t.revocable = true;
        t.jurisdictionScope = JURISDICTION_WORLDWIDE;
        t.rights = RightsSummary({
            commercialUse: Ternary.YES,
            derivativesAllowed: Ternary.NO,
            attributionRequired: Ternary.YES,
            feeModel: FeeModel.FREE
        });
        t.termsType = TERMS_TYPE_GENERIC_V1;
        t.rightsData = abi.encode(true, false, true, "Music: {assetTitle} by {authorName}");
        bytes32 termsId = reg.registerTerms(t); // == keccak256(abi.encode(t))

        // ---- 3. Attach terms = publish a standing offer ------------------
        reg.attachTerms(assetId, termsId, "");
        vm.stopBroadcast();

        _log("asset ", IpRef.encodeAsset(block.chainid, address(reg), assetId));
        _log("terms ", IpRef.encodeTerms(block.chainid, address(reg), termsId));

        // ---- 4. Bob (e.g. a video agent) pre-flights, then acquires ------
        (bool ok, bytes32 reason) = reg.canLicense(assetId, termsId, bob, "", bytes32(0));
        _log("canLicense(bob) ok", ok);
        require(ok, string(abi.encodePacked(reason)));

        vm.startBroadcast(bobKey);
        bytes32 agreementId = reg.acquireAgreement(
            assetId, termsId, "", keccak256("bob accepted ipfs://.../terms")
        );
        vm.stopBroadcast();
        _log("agreement ", IpRef.encodeAgreement(block.chainid, address(reg), agreementId));

        // ---- 5. An app verifies with the witness (constant work) ---------
        _log("isActiveAgreementHolder(bob)", reg.isActiveAgreementHolder(agreementId, assetId, bob));
        _log("isActiveAgreementHolder(alice)", reg.isActiveAgreementHolder(agreementId, assetId, alice));

        // ---- 6. Discovery without a witness: bounded, paged --------------
        (bytes32[] memory found, uint256 next) = reg.activeAgreementsOf(assetId, bob, 0, 10);
        _log("activeAgreementsOf(bob) matches", found.length);
        _log("  nextCursor", next);
        _log("  scan complete (nextCursor == agreementCountOf)", next == reg.agreementCountOf(assetId));

        // ---- 7. Alice revokes; the record stays, activity flips ----------
        vm.startBroadcast(aliceKey);
        reg.revokeAgreement(agreementId, keccak256("demo"));
        vm.stopBroadcast();
        _log("after revoke: isAgreementActive", reg.isAgreementActive(agreementId));
        _log("after revoke: getLicensee == bob", reg.getLicensee(agreementId) == bob);
    }

    // ---- console.log without forge-std ----------------------------------
    function _log(string memory a, string memory b) internal view {
        _send(abi.encodeWithSignature("log(string,string)", a, b));
    }

    function _log(string memory a, bool b) internal view {
        _send(abi.encodeWithSignature("log(string,bool)", a, b));
    }

    function _log(string memory a, uint256 b) internal view {
        _send(abi.encodeWithSignature("log(string,uint256)", a, b));
    }

    function _send(bytes memory payload) internal view {
        (bool s,) = CONSOLE.staticcall(payload);
        s;
    }
}
