// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {TestBase} from "./TestBase.sol";
import {IPAssetRegistry} from "../src/IPAssetRegistry.sol";
import {IERC165} from "../src/interfaces/IERC165.sol";
import {IIPAssetRegistry} from "../src/interfaces/IIPAssetRegistry.sol";
import {ITermsRegistry} from "../src/interfaces/ITermsRegistry.sol";
import {
    AssetTokenization,
    AgreementTokenization,
    AgreementCreationMode,
    AgreementEvidence,
    Author,
    ParentRef,
    DerivationAttestation,
    LicenseTerms,
    RightsSummary,
    Ternary,
    FeeModel,
    RegistrationParams,
    AgreementParams,
    ASSET_TYPE_IMAGE,
    JURISDICTION_WORLDWIDE
} from "../src/interfaces/IPAssetTypes.sol";

/// @dev Extended cheatcode surface (still the canonical HEVM address) so the
///      suite needs no forge-std. Superset of `TestBase.Vm`.
interface VmExt {
    struct Log {
        bytes32[] topics;
        bytes data;
        address emitter;
    }

    function prank(address) external;
    function warp(uint256) external;
    function addr(uint256 privateKey) external pure returns (address);
    function sign(uint256 privateKey, bytes32 digest)
        external
        pure
        returns (uint8 v, bytes32 r, bytes32 s);
    function expectRevert(bytes4) external;
    function expectRevert(bytes calldata) external;
    function recordLogs() external;
    function getRecordedLogs() external returns (Log[] memory);
    function chainId(uint256 newChainId) external;
}

/// @dev Minimal ERC-721 whose `ownerOf` reverts for nonexistent/burned tokens,
///      exactly the condition the registry must survive.
contract MockERC721 {
    mapping(uint256 => address) private _owner;

    function mint(address to, uint256 id) external {
        _owner[id] = to;
    }

    function transfer(address to, uint256 id) external {
        _owner[id] = to;
    }

    function burn(uint256 id) external {
        delete _owner[id];
    }

    function ownerOf(uint256 id) external view returns (address) {
        address o = _owner[id];
        require(o != address(0), "ERC721: nonexistent");
        return o;
    }
}

contract GasGriefingERC721 {
    mapping(uint256 => address) private _owner;
    bool private _grief;

    function mint(address to, uint256 id) external {
        _owner[id] = to;
    }

    function setGrief(bool grief) external {
        _grief = grief;
    }

    function ownerOf(uint256 id) external view returns (address) {
        if (_grief) {
            assembly {
                for {} 1 {} {}
            }
        }
        return _owner[id];
    }
}

contract MockERC1271 {
    bytes32 public expectedDigest;
    bytes32 public expectedSignatureHash;
    uint8 public mode; // 0: valid; 1: invalid; 2: revert; 3: exhaust gas; 4: short return

    function configure(bytes32 digest, bytes32 signatureHash, uint8 newMode) external {
        expectedDigest = digest;
        expectedSignatureHash = signatureHash;
        mode = newMode;
    }

    function isValidSignature(bytes32 digest, bytes calldata signature) external view returns (bytes4) {
        if (mode == 2) revert("rejected");
        if (mode == 3) {
            assembly { for {} 1 {} {} }
        }
        if (mode == 4) {
            assembly {
                mstore(0, shl(224, 0x1626ba7e))
                return(0, 4)
            }
        }
        if (mode == 0 && digest == expectedDigest && keccak256(signature) == expectedSignatureHash) {
            return 0x1626ba7e;
        }
        return 0xffffffff;
    }
}

contract TransferPolicyRegistry is IPAssetRegistry {
    struct Policy {
        bytes32 argumentsHash;
        bytes32 denialReason;
    }

    Policy private _assetPolicy;
    Policy private _agreementPolicy;

    function setAssetTransferPolicy(bytes32 argumentsHash, bytes32 denialReason) external {
        _assetPolicy = Policy(argumentsHash, denialReason);
    }

    function setAgreementTransferPolicy(bytes32 argumentsHash, bytes32 denialReason) external {
        _agreementPolicy = Policy(argumentsHash, denialReason);
    }

    function canTransferAsset(bytes32 assetId, address from, address to)
        public view override returns (bool ok, bytes32 reason)
    {
        return _evaluatePolicy(_assetPolicy, assetId, from, to);
    }

    function canTransferAgreement(bytes32 agreementId, address from, address to)
        public view override returns (bool ok, bytes32 reason)
    {
        return _evaluatePolicy(_agreementPolicy, agreementId, from, to);
    }

    function _evaluatePolicy(Policy storage policy, bytes32 id, address from, address to)
        private view returns (bool ok, bytes32 reason)
    {
        if (
            policy.argumentsHash != bytes32(0)
                && policy.argumentsHash != keccak256(abi.encode(id, from, to))
        ) return (false, "unexpected-arguments");
        if (policy.denialReason != bytes32(0)) return (false, policy.denialReason);
        return _transferRecipientPolicy(to);
    }
}

contract IPAssetRegistryTest is TestBase {
    VmExt internal constant vmx = VmExt(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    IPAssetRegistry internal reg;
    MockERC721 internal nft;

    bytes32 internal constant CONTENT_HASH = keccak256("original-work");

    function setUp() public {
        reg = new IPAssetRegistry();
        nft = new MockERC721();
    }

    // ---- helpers --------------------------------------------------------

    function _emptyAttestation() internal pure returns (DerivationAttestation memory att) {
        // Every field is zero/empty => absent.
        return att;
    }

    function _noneParams(address owner, bytes32 contentHash)
        internal
        pure
        returns (RegistrationParams memory p)
    {
        p.salt = contentHash; // per-registrant content-addressed de-dup behaviour
        p.owner = owner;
        p.sharesDenominator = 0;
        p.assetType = ASSET_TYPE_IMAGE;
        p.tokenization = AssetTokenization.NONE;
        p.metadataURI = "ipfs://manifest";
        p.contentHash = contentHash;
    }

    function _registerNone(address owner, bytes32 contentHash) internal returns (bytes32) {
        RegistrationParams memory p = _noneParams(owner, contentHash);
        return reg.register(p);
    }

    function _registerTermsBasic(uint64 expiry, bool transferable) internal returns (bytes32) {
        LicenseTerms memory t;
        t.expiry = expiry;
        t.transferable = transferable;
        t.revocable = true;
        t.jurisdictionScope = JURISDICTION_WORLDWIDE;
        t.termsType = bytes32(0);
        return reg.registerTerms(t);
    }

    // ---- registration ---------------------------------------------------

    function test_ChainId_IsNonzeroAndDeploymentFrozen() public {
        vmx.chainId(12_345);
        IPAssetRegistry deployed = new IPAssetRegistry();
        assertEqU(deployed.chainId(), 12_345);

        vmx.chainId(54_321);
        assertEqU(deployed.chainId(), 12_345);
    }

    function test_DeploymentRejectsZeroChainId() public {
        vmx.chainId(0);
        vmx.expectRevert(IIPAssetRegistry.InvalidChainId.selector);
        new IPAssetRegistry();
    }

    function test_UnknownAssetReads_ReturnPinnedSentinels() public view {
        bytes32 unknown = keccak256("unknown-asset");
        assertFalse(reg.assetExists(unknown));
        assertEqA(reg.ownerOf(unknown), address(0));

        {
            (Author[] memory authors, uint256 denominator) = reg.authorsOf(unknown);
            assertEqU(authors.length, 0);
            assertEqU(denominator, 0);
        }
        {
            (AssetTokenization tokenization, address collection, uint256 tokenId) =
                reg.tokenizationOf(unknown);
            assertTrue(tokenization == AssetTokenization.NONE);
            assertEqA(collection, address(0));
            assertEqU(tokenId, 0);
        }
        assertEqB32(reg.assetTypeOf(unknown), bytes32(0));
        {
            (string memory uri, bytes32 contentHash) = reg.metadataOf(unknown);
            assertEqStr(uri, "");
            assertEqB32(contentHash, bytes32(0));
        }
        {
            DerivationAttestation memory att = reg.derivationAttestationOf(unknown);
            assertEqU(att.parents.length, 0);
            assertEqA(att.issuer, address(0));
            assertEqU(att.signature.length, 0);
            assertEqU(att.metadata.length, 0);
            assertEqB32(att.registrationHash, bytes32(0));
        }
        {
            (bytes32[] memory ids, bytes[] memory parameters) =
                reg.attachedTermsOf(unknown);
            assertEqU(ids.length, 0);
            assertEqU(parameters.length, 0);
        }
        assertEqU(reg.agreementCountOf(unknown), 0);
        assertEqB32(reg.agreementAtIndex(unknown, type(uint256).max), bytes32(0));
    }

    function test_UnknownAgreementReads_ReturnPinnedSentinels() public view {
        bytes32 unknown = keccak256("unknown-agreement");
        (
            bytes32 assetId,
            bytes32 termsId,
            address party,
            AgreementTokenization tokenization,
            address collection,
            uint256 tokenId,
            AgreementEvidence memory evidence,
            uint64 expiry,
            bool transferable,
            bool revocable
        ) = reg.agreementOf(unknown);
        assertEqB32(assetId, bytes32(0));
        assertEqB32(termsId, bytes32(0));
        assertEqA(party, address(0));
        assertTrue(tokenization == AgreementTokenization.NONE);
        assertEqA(collection, address(0));
        assertEqU(tokenId, 0);
        assertEqA(evidence.licensor, address(0));
        assertEqA(evidence.createdBy, address(0));
        assertEqA(evidence.initialLicensee, address(0));
        assertEqU(evidence.createdAt, 0);
        assertTrue(evidence.creationMode == AgreementCreationMode.GRANT);
        assertEqB32(evidence.licenseParamsHash, bytes32(0));
        assertEqB32(evidence.acceptanceHash, bytes32(0));
        assertEqU(expiry, 0);
        assertFalse(transferable);
        assertFalse(revocable);
        assertEqA(reg.getLicensee(unknown), address(0));
        assertFalse(reg.isAgreementActive(unknown));
        assertFalse(reg.isActiveAgreementHolder(unknown, bytes32(0), address(1)));
    }

    function test_UnknownClaimReads_ReturnPinnedSentinels() public view {
        bytes32 unknownAsset = keccak256("unknown-asset");
        bytes32 unknownTopic = keccak256("unknown-topic");
        address issuer = address(0x1234);
        (bytes memory data, bytes memory signature, uint64 timestamp, bool revoked) =
            reg.getClaim(unknownAsset, unknownTopic, issuer);
        assertEqU(data.length, 0);
        assertEqU(signature.length, 0);
        assertEqU(timestamp, 0);
        assertFalse(revoked);
        assertEqU(reg.getClaimIssuers(unknownAsset, unknownTopic).length, 0);
        assertFalse(reg.isTrustedIssuer(unknownTopic, issuer));
    }

    function test_RegisterNone_StoresRecord() public {
        bytes32 id = _registerNone(address(this), CONTENT_HASH);
        assertTrue(reg.assetExists(id));
        assertEqA(reg.ownerOf(id), address(this));
        assertEqB32(reg.assetTypeOf(id), ASSET_TYPE_IMAGE);
        (string memory uri, bytes32 ch) = reg.metadataOf(id);
        assertEqStr(uri, "ipfs://manifest");
        assertEqB32(ch, CONTENT_HASH);
        (AssetTokenization tk,,) = reg.tokenizationOf(id);
        assertTrue(tk == AssetTokenization.NONE);
    }

    function test_RegisterNone_EventCarriesInitialMetadataUri() public {
        RegistrationParams memory p = _noneParams(address(this), CONTENT_HASH);

        vmx.recordLogs();
        bytes32 id = reg.register(p);
        VmExt.Log[] memory logs = vmx.getRecordedLogs();

        assertEqU(logs.length, 1);
        assertEqB32(
            logs[0].topics[0],
            keccak256("AssetRegistered(bytes32,address,address,bytes32,uint8,string,bytes32)")
        );
        assertEqB32(logs[0].topics[1], id);
        assertEqB32(logs[0].topics[2], bytes32(uint256(uint160(address(this)))));
        assertEqB32(logs[0].topics[3], bytes32(uint256(uint160(address(this)))));
        (bytes32 assetType, AssetTokenization tokenization, string memory metadataURI, bytes32 ch) =
            abi.decode(logs[0].data, (bytes32, AssetTokenization, string, bytes32));
        assertEqB32(assetType, ASSET_TYPE_IMAGE);
        assertTrue(tokenization == AssetTokenization.NONE);
        assertEqStr(metadataURI, "ipfs://manifest");
        assertEqB32(ch, CONTENT_HASH);
    }

    function test_RegisterNone_AssetIdIsSaltDerived() public {
        bytes32 id = _registerNone(address(this), CONTENT_HASH);
        // salt == contentHash in _noneParams; the id also binds the caller.
        bytes32 expected = keccak256(abi.encode(reg.chainId(), address(reg), address(this), CONTENT_HASH));
        assertEqB32(id, expected);
    }

    function test_RegisterNone_SameSaltDifferentRegistrants_DistinctIds() public {
        RegistrationParams memory p = _noneParams(address(this), CONTENT_HASH);
        address other = address(0xBAD);
        bytes32 expectedOther = keccak256(abi.encode(reg.chainId(), address(reg), other, p.salt));
        RegistrationParams memory attackerParams = _noneParams(other, keccak256("other-work"));
        attackerParams.salt = p.salt; // observed pending salt, but different data and caller
        vmx.prank(other);
        bytes32 otherId = reg.register(attackerParams);
        bytes32 myId = reg.register(p);
        assertEqB32(otherId, expectedOther);
        assertEqB32(myId, keccak256(abi.encode(reg.chainId(), address(reg), address(this), p.salt)));
        assertTrue(myId != otherId);
        assertTrue(reg.assetExists(myId));
    }

    function test_RegisterNone_DistinctSalts_DistinctIds() public {
        RegistrationParams memory p1 = _noneParams(address(this), CONTENT_HASH);
        p1.salt = keccak256("salt-1");
        RegistrationParams memory p2 = _noneParams(address(this), CONTENT_HASH);
        p2.salt = keccak256("salt-2");
        bytes32 id1 = reg.register(p1);
        bytes32 id2 = reg.register(p2);
        // Same underlying work (same contentHash), different salts => distinct
        // ids coexist (no identity-squatting; supports re-registration).
        assertTrue(id1 != id2);
    }

    function test_RegisterNone_RequiresContentHash() public {
        RegistrationParams memory p = _noneParams(address(this), bytes32(0));
        vmx.expectRevert(IPAssetRegistry.ContentHashRequired.selector);
        reg.register(p);
    }

    function test_RegisterNone_RequiresOwner() public {
        RegistrationParams memory p = _noneParams(address(0), CONTENT_HASH);
        vmx.expectRevert(IPAssetRegistry.OwnerRequired.selector);
        reg.register(p);
    }

    function test_Register_DuplicateReverts() public {
        _registerNone(address(this), CONTENT_HASH);
        RegistrationParams memory p = _noneParams(address(this), CONTENT_HASH);
        vmx.expectRevert(IPAssetRegistry.AlreadyExists.selector);
        reg.register(p);
    }

    function test_Register_BadAuthorShares_Reverts() public {
        RegistrationParams memory p = _noneParams(address(this), CONTENT_HASH);
        p.sharesDenominator = 100;
        p.authors = new Author[](1);
        p.authors[0] = Author({author: address(this), shareNumerator: 99}); // != 100
        vmx.expectRevert(IPAssetRegistry.BadAuthorsShares.selector);
        reg.register(p);
    }

    function test_Register_AuthorsRequireNonzeroDenominator() public {
        RegistrationParams memory p = _noneParams(address(this), CONTENT_HASH);
        p.authors = new Author[](1);
        p.authors[0] = Author({author: address(this), shareNumerator: 0});
        vmx.expectRevert(IPAssetRegistry.BadAuthorsShares.selector);
        reg.register(p);
    }

    function test_Register_AuthorsRecorded() public {
        RegistrationParams memory p = _noneParams(address(this), CONTENT_HASH);
        p.sharesDenominator = 100;
        p.authors = new Author[](2);
        p.authors[0] = Author({author: address(0xA11CE), shareNumerator: 70});
        p.authors[1] = Author({author: address(0xB0B), shareNumerator: 30});
        bytes32 id = reg.register(p);
        (Author[] memory authors, uint256 denom) = reg.authorsOf(id);
        assertEqU(denom, 100);
        assertEqU(authors.length, 2);
        assertEqA(authors[0].author, address(0xA11CE));
        assertEqU(authors[1].shareNumerator, 30);
    }

    // ---- ownership ------------------------------------------------------

    function test_TransferOwnership_None() public {
        bytes32 id = _registerNone(address(this), CONTENT_HASH);
        reg.transferOwnership(id, address(0xBEEF));
        assertEqA(reg.ownerOf(id), address(0xBEEF));
    }

    function test_TransferOwnership_NotOwner_RevertsDespitePermissiveHook() public {
        bytes32 id = _registerNone(address(this), CONTENT_HASH);
        vmx.prank(address(0x9999));
        vmx.expectRevert(IPAssetRegistry.NotOwner.selector);
        reg.transferOwnership(id, address(0xBEEF));
        assertEqA(reg.ownerOf(id), address(this));
    }

    function test_TransferOwnership_ZeroRecipient_PreservesHookDenial() public {
        bytes32 id = _registerNone(address(this), CONTENT_HASH);
        vmx.expectRevert(
            abi.encodeWithSelector(IIPAssetRegistry.HookDenied.selector, bytes32("zero-recipient"))
        );
        reg.transferOwnership(id, address(0));
        assertEqA(reg.ownerOf(id), address(this));
    }

    function test_UpdateMetadata_MovesUriKeepsHash() public {
        bytes32 id = _registerNone(address(this), CONTENT_HASH);
        reg.updateMetadata(id, "ipfs://v2");
        (string memory uri, bytes32 ch) = reg.metadataOf(id);
        assertEqStr(uri, "ipfs://v2");
        assertEqB32(ch, CONTENT_HASH); // contentHash is immutable
    }

    function test_UpdateMetadata_NotOwner_Reverts() public {
        bytes32 id = _registerNone(address(this), CONTENT_HASH);
        vmx.prank(address(0x9999));
        vmx.expectRevert(IPAssetRegistry.NotOwner.selector);
        reg.updateMetadata(id, "ipfs://v2");
    }

    function test_TransferOwnership_Erc721_Reverts() public {
        nft.mint(address(this), 1);
        bytes32 id = _registerErc721(address(nft), 1);
        vmx.expectRevert(IPAssetRegistry.WrongTokenization.selector);
        reg.transferOwnership(id, address(0xBEEF));
    }

    function _registerErc721(address collection, uint256 tokenId) internal returns (bytes32) {
        RegistrationParams memory p;
        p.salt = keccak256(abi.encode(collection, tokenId)); // bind-derived by convention
        p.assetType = ASSET_TYPE_IMAGE;
        p.tokenization = AssetTokenization.ERC721;
        p.tokenCollection = collection;
        p.tokenId = tokenId;
        p.metadataURI = "ipfs://nft";
        return reg.register(p);
    }

    // ---- ERC721 delegation + failure safety ----------------------------

    function test_Erc721_OwnerOf_Delegates() public {
        nft.mint(address(0xCA11), 7);
        bytes32 id = _registerErc721(address(nft), 7);
        assertEqA(reg.ownerOf(id), address(0xCA11));
        nft.transfer(address(0xD00D), 7);
        assertEqA(reg.ownerOf(id), address(0xD00D));
    }

    function test_Erc721Registration_EventEmitsResolvedOwner() public {
        nft.mint(address(0xCA11), 8);
        vmx.recordLogs();
        bytes32 id = _registerErc721(address(nft), 8);
        VmExt.Log[] memory logs = vmx.getRecordedLogs();

        assertEqU(logs.length, 1);
        assertEqB32(logs[0].topics[1], id);
        assertEqB32(logs[0].topics[2], bytes32(uint256(uint160(address(this)))));
        assertEqB32(logs[0].topics[3], bytes32(uint256(uint160(address(0xCA11)))));
    }

    function test_Erc721Registration_RejectsNonzeroOwnerInput() public {
        nft.mint(address(0xCA11), 8);
        RegistrationParams memory p;
        p.salt = keccak256("erc721-owner-input");
        p.owner = address(0xCA11);
        p.assetType = ASSET_TYPE_IMAGE;
        p.tokenization = AssetTokenization.ERC721;
        p.tokenCollection = address(nft);
        p.tokenId = 8;

        vmx.expectRevert(IPAssetRegistry.OwnerMustBeZero.selector);
        reg.register(p);
    }

    function test_Erc721Registration_RejectsCollectionWithoutCode() public {
        RegistrationParams memory p;
        p.salt = keccak256("erc721-no-code");
        p.assetType = ASSET_TYPE_IMAGE;
        p.tokenization = AssetTokenization.ERC721;
        p.tokenCollection = address(0xCA11);
        p.tokenId = 8;

        vmx.expectRevert(IPAssetRegistry.TokenBindingRequired.selector);
        reg.register(p);
    }

    function test_Erc721Registration_RejectsMissingHolder() public {
        RegistrationParams memory p;
        p.salt = keccak256("erc721-no-holder");
        p.assetType = ASSET_TYPE_IMAGE;
        p.tokenization = AssetTokenization.ERC721;
        p.tokenCollection = address(nft);
        p.tokenId = 404;

        vmx.expectRevert(IPAssetRegistry.OwnerRequired.selector);
        reg.register(p);
    }

    function test_Erc721_OwnerOf_BurnedIsOwnerless_NoRevert() public {
        nft.mint(address(0xCA11), 7);
        bytes32 id = _registerErc721(address(nft), 7);
        nft.burn(7);
        // Must NOT revert; returns address(0).
        assertEqA(reg.ownerOf(id), address(0));
    }

    // ---- terms ----------------------------------------------------------

    function test_RegisterTerms_ContentAddressedDedup() public {
        bytes32 t1 = _registerTermsBasic(0, true);
        bytes32 t2 = _registerTermsBasic(0, true);
        assertEqB32(t1, t2); // identical terms => same id
        assertTrue(reg.termsExists(t1));
    }

    function test_RegisterTerms_ExistingIdIsEventFreeNoOp() public {
        LicenseTerms memory terms;
        terms.revocable = true;
        terms.jurisdictionScope = JURISDICTION_WORLDWIDE;

        vmx.recordLogs();
        bytes32 id = reg.registerTerms(terms);
        VmExt.Log[] memory firstLogs = vmx.getRecordedLogs();
        assertEqU(firstLogs.length, 1);
        assertEqB32(firstLogs[0].topics[0], keccak256("TermsRegistered(bytes32,address,bytes32)"));
        assertEqB32(firstLogs[0].topics[1], id);

        bytes32 storedBefore = keccak256(abi.encode(reg.getTerms(id)));
        vmx.recordLogs();
        vmx.prank(address(0xBEEF));
        bytes32 sameId = reg.registerTerms(terms);
        assertEqB32(sameId, id);
        assertEqU(vmx.getRecordedLogs().length, 0);
        assertEqB32(keccak256(abi.encode(reg.getTerms(id))), storedBefore);
    }

    function test_RegisterTerms_CanBeMirroredAcrossRegistries() public {
        LicenseTerms memory terms;
        terms.transferable = true;
        terms.jurisdictionScope = JURISDICTION_WORLDWIDE;

        bytes32 sourceTermsId = reg.registerTerms(terms);
        IPAssetRegistry mirror = new IPAssetRegistry();
        bytes32 mirroredTermsId = mirror.registerTerms(terms);
        assertEqB32(mirroredTermsId, sourceTermsId);

        RegistrationParams memory p =
            _noneParams(address(this), keccak256("mirrored-work"));
        bytes32 assetId = mirror.register(p);
        mirror.attachTerms(assetId, mirroredTermsId, "");
        (bytes32[] memory attachedTermsIds,) = mirror.attachedTermsOf(assetId);
        assertEqB32(attachedTermsIds[0], sourceTermsId);
    }

    function test_RegisterTerms_CanonicalEncodingVector_Default() public {
        LicenseTerms memory terms;
        bytes32 expected =
            0x6c30a113f027b95c15f0b7b763866b623f284f67fc293aada6eb6ea598397db5;
        assertEqB32(keccak256(abi.encode(terms)), expected);
        assertEqB32(reg.registerTerms(terms), expected);
    }

    function test_RegisterTerms_CanonicalEncodingVector_Populated() public {
        LicenseTerms memory terms;
        terms.expiry = 2_000_000_000;
        terms.duration = 31_536_000;
        terms.transferable = true;
        terms.revocable = true;
        terms.exclusive = true;
        terms.jurisdictionScope =
            0x1111111111111111111111111111111111111111111111111111111111111111;
        terms.rights = RightsSummary({
            commercialUse: Ternary.YES,
            derivativesAllowed: Ternary.NO,
            attributionRequired: Ternary.YES,
            feeModel: FeeModel.ONE_TIME
        });
        terms.uri = "ipfs://terms";
        terms.contentHash =
            0x2222222222222222222222222222222222222222222222222222222222222222;
        terms.termsType =
            0x3333333333333333333333333333333333333333333333333333333333333333;
        terms.rightsData = hex"010203";

        bytes32 expected =
            0x65ab60a127daf191b77e3597eabe71e4e3aab8f79852fa6169d2874cb9be322e;
        assertEqB32(keccak256(abi.encode(terms)), expected);
        assertEqB32(reg.registerTerms(terms), expected);
    }

    function test_RegisterTerms_RightsSummaryRoundTrips() public {
        LicenseTerms memory t;
        t.expiry = 0;
        t.transferable = true;
        t.termsType = bytes32(0); // summary-only, no domain schema
        t.rights = RightsSummary({
            commercialUse: Ternary.YES,
            derivativesAllowed: Ternary.NO,
            attributionRequired: Ternary.YES,
            feeModel: FeeModel.RECURRING
        });
        bytes32 id = reg.registerTerms(t);

        LicenseTerms memory got = reg.getTerms(id);
        assertEqU(uint256(uint8(got.rights.commercialUse)), uint256(uint8(Ternary.YES)));
        assertEqU(uint256(uint8(got.rights.derivativesAllowed)), uint256(uint8(Ternary.NO)));
        assertEqU(uint256(uint8(got.rights.attributionRequired)), uint256(uint8(Ternary.YES)));
        assertEqU(uint256(uint8(got.rights.feeModel)), uint256(uint8(FeeModel.RECURRING)));
    }

    function test_RegisterTerms_RightsSummaryAffectsTermsId() public {
        LicenseTerms memory a;
        a.termsType = bytes32(0);
        a.rights.feeModel = FeeModel.FREE;
        LicenseTerms memory b;
        b.termsType = bytes32(0);
        b.rights.feeModel = FeeModel.ONE_TIME;
        assertTrue(reg.registerTerms(a) != reg.registerTerms(b));
    }

    function test_RegisterTerms_RejectsUriWithoutContentHash() public {
        LicenseTerms memory terms;
        terms.uri = "ipfs://terms";

        vm.expectRevert(ITermsRegistry.IncompleteLegalWrapper.selector);
        reg.registerTerms(terms);
    }

    function test_RegisterTerms_RejectsContentHashWithoutUri() public {
        LicenseTerms memory terms;
        terms.contentHash = keccak256("legal document");

        vm.expectRevert(ITermsRegistry.IncompleteLegalWrapper.selector);
        reg.registerTerms(terms);
    }

    function test_AttachDetachTerms() public {
        bytes32 id = _registerNone(address(this), CONTENT_HASH);
        bytes32 t = _registerTermsBasic(0, true);
        reg.attachTerms(id, t, "");
        (bytes32[] memory ids,) = reg.attachedTermsOf(id);
        assertEqB32(ids[0], t);
        reg.detachTerms(id, t);
        (bytes32[] memory ids2,) = reg.attachedTermsOf(id);
        assertEqU(ids2.length, 0);
    }

    function test_AttachTerms_EventCarriesUpdatedParameters() public {
        bytes32 assetId = _registerNone(address(this), CONTENT_HASH);
        bytes32 termsId = _registerTermsBasic(0, true);
        reg.attachTerms(assetId, termsId, "initial");

        vmx.recordLogs();
        reg.attachTerms(assetId, termsId, "updated");
        VmExt.Log[] memory logs = vmx.getRecordedLogs();

        assertEqU(logs.length, 1);
        assertEqB32(
            logs[0].topics[0],
            keccak256("TermsAttached(bytes32,bytes32,bytes)")
        );
        assertEqB32(logs[0].topics[1], assetId);
        assertEqB32(logs[0].topics[2], termsId);
        bytes memory eventParameters = abi.decode(logs[0].data, (bytes));
        assertEqStr(string(eventParameters), "updated");

        (, bytes[] memory storedParameters) = reg.attachedTermsOf(assetId);
        assertEqStr(string(storedParameters[0]), "updated");
    }

    function test_AttachTerms_RejectsUnknownLocalTerms() public {
        bytes32 assetId = _registerNone(address(this), CONTENT_HASH);
        bytes32 unknownTermsId = keccak256("unknown-local-terms");

        vmx.expectRevert(IPAssetRegistry.TermsUnknown.selector);
        reg.attachTerms(assetId, unknownTermsId, "");

        (bytes32[] memory termsIds,) = reg.attachedTermsOf(assetId);
        assertEqU(termsIds.length, 0);
    }

    // ---- agreements + verification --------------------------------------

    function test_AcquireAgreement_AndVerify() public {
        bytes32 id = _registerNone(address(this), CONTENT_HASH);
        bytes32 t = _registerTermsBasic(0, true);
        reg.attachTerms(id, t, "");

        address licensee = address(0x1111);
        vmx.prank(licensee);
        bytes32 ag = reg.acquireAgreement(id, t, "", bytes32(0));

        assertTrue(reg.isAgreementActive(ag));
        assertTrue(reg.isActiveAgreementHolder(ag, id, licensee));
        assertFalse(reg.isActiveAgreementHolder(ag, id, address(0x2222)));
        assertFalse(reg.isActiveAgreementHolder(ag, keccak256("wrong-asset"), licensee));
        (bytes32[] memory mine, uint256 next) =
            reg.activeAgreementsOf(id, licensee, 0, 10);
        assertEqU(mine.length, 1);
        assertEqB32(mine[0], ag);
        assertEqU(next, 1);
        assertEqA(reg.getLicensee(ag), licensee);
    }

    function test_ActiveAgreements_DoNotImplyUsePermission() public {
        bytes32 id = _registerNone(address(this), CONTENT_HASH);
        address licensee = address(0x1111);

        LicenseTerms memory denied;
        denied.rights.commercialUse = Ternary.NO;
        denied.rights.derivativesAllowed = Ternary.NO;
        bytes32 deniedTermsId = reg.registerTerms(denied);
        reg.attachTerms(id, deniedTermsId, "");

        AgreementParams memory p;
        p.assetId = id;
        p.termsId = deniedTermsId;
        p.party = licensee;
        p.agreementTokenization = AgreementTokenization.NONE;
        bytes32 deniedAgreement = reg.createAgreement(p);

        // Activity is true even though these terms deny both contemplated uses.
        assertTrue(reg.isActiveAgreementHolder(deniedAgreement, id, licensee));
        assertTrue(reg.isAgreementActive(deniedAgreement));
        LicenseTerms memory deniedResult = reg.getTerms(deniedTermsId);
        assertEqU(uint256(uint8(deniedResult.rights.commercialUse)), uint256(uint8(Ternary.NO)));
        assertEqU(
            uint256(uint8(deniedResult.rights.derivativesAllowed)), uint256(uint8(Ternary.NO))
        );

        LicenseTerms memory allowed;
        allowed.rights.commercialUse = Ternary.YES;
        allowed.rights.derivativesAllowed = Ternary.YES;
        bytes32 allowedTermsId = reg.registerTerms(allowed);
        reg.attachTerms(id, allowedTermsId, "");
        p.termsId = allowedTermsId;
        bytes32 allowedAgreement = reg.createAgreement(p);

        (bytes32[] memory active, uint256 next) =
            reg.activeAgreementsOf(id, licensee, 0, 10);
        assertEqU(active.length, 2);
        assertEqU(next, 2);
        assertEqB32(active[0], deniedAgreement);
        assertEqB32(active[1], allowedAgreement);

        (, bytes32 boundTermsId,,,,,,,,) = reg.agreementOf(active[0]);
        assertEqB32(boundTermsId, deniedTermsId);
        LicenseTerms memory boundTerms = reg.getTerms(boundTermsId);
        assertEqU(uint256(uint8(boundTerms.rights.commercialUse)), uint256(uint8(Ternary.NO)));
    }

    function test_CanDerive_DoesNotTreatActivityAsPermission() public {
        bytes32 ag = _grant(address(0x4444), true);
        (bytes32 id,,,,,,,,,) = reg.agreementOf(ag);

        (bool ok, bytes32 reason) = reg.canDerive(id, address(0x4444));
        assertFalse(ok);
        assertEqB32(reason, bytes32("policy-not-implemented"));
    }

    function test_AcquireAgreement_ForwardsLicenseParams() public {
        bytes32 id = _registerNone(address(this), CONTENT_HASH);
        bytes32 t = _registerTermsBasic(0, true);
        reg.attachTerms(id, t, "");

        address licensee = address(0x1111);
        bytes memory licenseParams = abi.encode(uint256(100), "signed");
        bytes32 acceptanceHash = keccak256("northwind-acceptance");
        vmx.prank(licensee);
        bytes32 ag = reg.acquireAgreement(
            id, t, licenseParams, acceptanceHash
        );

        assertTrue(reg.isAgreementActive(ag));
        assertTrue(reg.isActiveAgreementHolder(ag, id, licensee));
        (,,,,,, AgreementEvidence memory evidence, uint64 expiry, bool transferable, bool revocable) =
            reg.agreementOf(ag);
        assertEqA(evidence.licensor, address(this));
        assertEqA(evidence.createdBy, licensee);
        assertEqA(evidence.initialLicensee, licensee);
        assertEqU(evidence.createdAt, block.timestamp);
        assertEqU(
            uint256(uint8(evidence.creationMode)),
            uint256(uint8(AgreementCreationMode.ACQUIRE))
        );
        assertEqB32(evidence.licenseParamsHash, keccak256(licenseParams));
        assertEqB32(evidence.acceptanceHash, acceptanceHash);
        assertEqU(expiry, 0);
        assertTrue(transferable);
        assertTrue(revocable);
    }

    function test_Hook_ReasonCodes() public {
        (bool ok, bytes32 r) =
            reg.canTransferAsset(bytes32(0), address(this), address(0));
        assertFalse(ok);
        assertEqB32(r, bytes32("zero-recipient"));

        (ok, r) = reg.canTransferAgreement(bytes32(0), address(this), address(0));
        assertFalse(ok);
        assertEqB32(r, bytes32("zero-recipient"));

        bytes32 id = _registerNone(address(this), CONTENT_HASH);
        bytes32 t = _registerTermsBasic(0, true);
        reg.attachTerms(id, t, "");

        (ok, r) = reg.canLicense(id, t, address(0), "", bytes32(0));
        assertFalse(ok);
        assertEqB32(r, bytes32("zero-acquirer"));

        (ok, r) = reg.canLicense(id, t, address(0x1), "", bytes32(0));
        assertTrue(ok);
        assertEqB32(r, bytes32(0));

        (ok, r) = reg.canRevoke(bytes32("nope"), address(this), bytes32(0));
        assertFalse(ok);
        assertEqB32(r, bytes32("agreement-unknown"));
    }

    function testFuzz_TransferHooks_DefaultPolicy(
        bytes32 unknownId, address from, address to, address observer
    ) public {
        vmx.prank(observer);
        (bool assetOk, bytes32 assetReason) = reg.canTransferAsset(unknownId, from, to);
        vmx.prank(observer);
        (bool agreementOk, bytes32 agreementReason) =
            reg.canTransferAgreement(unknownId, from, to);
        assertTrue(assetOk == (to != address(0)));
        assertTrue(agreementOk == assetOk);
        assertEqB32(assetReason, to == address(0) ? bytes32("zero-recipient") : bytes32(0));
        assertEqB32(agreementReason, assetReason);
    }

    function test_TransferHooks_IndependentPoliciesForSameId() public {
        TransferPolicyRegistry policy = _useTransferPolicyRegistry();
        bytes32 id = bytes32("same");
        policy.setAssetTransferPolicy(bytes32(0), bytes32("asset-denied"));
        (bool ok, bytes32 reason) = reg.canTransferAsset(id, address(this), address(1));
        assertFalse(ok);
        assertEqB32(reason, bytes32("asset-denied"));
        (ok, reason) = reg.canTransferAgreement(id, address(this), address(1));
        assertTrue(ok);
        assertEqB32(reason, bytes32(0));

        policy.setAssetTransferPolicy(bytes32(0), bytes32(0));
        policy.setAgreementTransferPolicy(bytes32(0), bytes32("agreement-denied"));
        (ok, reason) = reg.canTransferAsset(id, address(this), address(1));
        assertTrue(ok);
        assertEqB32(reason, bytes32(0));
        (ok, reason) = reg.canTransferAgreement(id, address(this), address(1));
        assertFalse(ok);
        assertEqB32(reason, bytes32("agreement-denied"));
    }

    function test_TransferOwnership_EnforcesCurrentAssetHook() public {
        TransferPolicyRegistry policy = _useTransferPolicyRegistry();
        bytes32 id = _registerNone(address(this), CONTENT_HASH);
        address to = address(0xBEEF);
        bytes32 argumentsHash = keccak256(abi.encode(id, address(this), to));
        policy.setAssetTransferPolicy(argumentsHash, bytes32(0));
        policy.setAgreementTransferPolicy(bytes32(0), bytes32("agreement-denied"));
        (bool ok,) = reg.canTransferAsset(id, address(this), to);
        assertTrue(ok);

        policy.setAssetTransferPolicy(argumentsHash, bytes32("asset-denied"));
        vmx.recordLogs();
        vmx.expectRevert(
            abi.encodeWithSelector(IIPAssetRegistry.HookDenied.selector, bytes32("asset-denied"))
        );
        reg.transferOwnership(id, to);
        assertEqA(reg.ownerOf(id), address(this));
        assertEqU(vmx.getRecordedLogs().length, 0);

        policy.setAssetTransferPolicy(argumentsHash, bytes32(0));
        vmx.recordLogs();
        reg.transferOwnership(id, to);
        assertEqA(reg.ownerOf(id), to);
        _assertTransferLog(
            keccak256("OwnershipTransferred(bytes32,address,address)"), id, address(this), to
        );
    }

    function test_TransferAgreement_EnforcesCurrentAgreementHook() public {
        TransferPolicyRegistry policy = _useTransferPolicyRegistry();
        address licensee = address(0x4444);
        address to = address(0x5555);
        bytes32 id = _grant(licensee, true);
        bytes32 evidenceHash = _agreementEvidenceHash(id);
        bytes32 argumentsHash = keccak256(abi.encode(id, licensee, to));
        policy.setAgreementTransferPolicy(argumentsHash, bytes32(0));
        policy.setAssetTransferPolicy(bytes32(0), bytes32("asset-denied"));
        (bool ok,) = reg.canTransferAgreement(id, licensee, to);
        assertTrue(ok);

        policy.setAgreementTransferPolicy(argumentsHash, bytes32("agreement-denied"));
        vmx.recordLogs();
        vmx.prank(licensee);
        vmx.expectRevert(
            abi.encodeWithSelector(
                IIPAssetRegistry.HookDenied.selector, bytes32("agreement-denied")
            )
        );
        reg.transferAgreement(id, to);
        assertEqA(reg.getLicensee(id), licensee);
        assertEqB32(_agreementEvidenceHash(id), evidenceHash);
        assertEqU(vmx.getRecordedLogs().length, 0);

        policy.setAgreementTransferPolicy(argumentsHash, bytes32(0));
        vmx.recordLogs();
        vmx.prank(licensee);
        reg.transferAgreement(id, to);
        assertEqA(reg.getLicensee(id), to);
        assertEqB32(_agreementEvidenceHash(id), evidenceHash);
        _assertTransferLog(
            keccak256("LicenseAgreementTransferred(bytes32,address,address)"), id, licensee, to
        );
    }

    function test_TransferHooks_DoNotGateExternalErc721Transfers() public {
        TransferPolicyRegistry policy = _useTransferPolicyRegistry();
        policy.setAssetTransferPolicy(bytes32(0), bytes32("asset-denied"));
        policy.setAgreementTransferPolicy(bytes32(0), bytes32("agreement-denied"));
        nft.mint(address(this), 1);
        bytes32 assetId = _registerErc721(address(nft), 1);
        bytes32 termsId = _registerTermsBasic(0, false);
        reg.attachTerms(assetId, termsId, "");
        nft.mint(address(0x4444), 2);
        AgreementParams memory p;
        p.assetId = assetId;
        p.termsId = termsId;
        p.agreementTokenization = AgreementTokenization.ERC721;
        p.agreementCollection = address(nft);
        p.agreementTokenId = 2;
        bytes32 agreementId = reg.createAgreement(p);

        vmx.expectRevert(IPAssetRegistry.WrongTokenization.selector);
        reg.transferOwnership(assetId, address(0xBEEF));
        vmx.prank(address(0x4444));
        vmx.expectRevert(IPAssetRegistry.WrongTokenization.selector);
        reg.transferAgreement(agreementId, address(0x5555));

        nft.transfer(address(0xBEEF), 1);
        nft.transfer(address(0x5555), 2);
        assertEqA(reg.ownerOf(assetId), address(0xBEEF));
        assertEqA(reg.getLicensee(agreementId), address(0x5555));
        assertTrue(reg.isActiveAgreementHolder(agreementId, assetId, address(0x5555)));
    }

    function test_TransferHooks_LegacySelectorIsUnsupported() public view {
        // The previous draft's generic transfer-policy selector.
        (bool ok,) = address(reg).staticcall(
            abi.encodeWithSelector(
                bytes4(0xe38adcbf), uint8(0), bytes32(0), address(this), address(1)
            )
        );
        assertFalse(ok);
    }

    function _useTransferPolicyRegistry() internal returns (TransferPolicyRegistry policy) {
        policy = new TransferPolicyRegistry();
        reg = policy;
    }

    function _agreementEvidenceHash(bytes32 agreementId) internal view returns (bytes32) {
        (,,,,,, AgreementEvidence memory evidence,,,) = reg.agreementOf(agreementId);
        return keccak256(abi.encode(evidence));
    }

    function _assertTransferLog(bytes32 eventSignature, bytes32 id, address from, address to)
        internal
    {
        VmExt.Log[] memory logs = vmx.getRecordedLogs();
        assertEqU(logs.length, 1);
        assertEqA(logs[0].emitter, address(reg));
        assertEqU(logs[0].topics.length, 4);
        assertEqB32(logs[0].topics[0], eventSignature);
        assertEqB32(logs[0].topics[1], id);
        assertEqB32(logs[0].topics[2], bytes32(uint256(uint160(from))));
        assertEqB32(logs[0].topics[3], bytes32(uint256(uint160(to))));
        assertEqU(logs[0].data.length, 0);
    }

    function test_AcquireAgreement_RequiresAttached() public {
        bytes32 id = _registerNone(address(this), CONTENT_HASH);
        bytes32 t = _registerTermsBasic(0, true);
        vmx.expectRevert(IPAssetRegistry.TermsNotAttached.selector);
        reg.acquireAgreement(id, t, "", bytes32(0));
    }

    function test_AcquireAgreement_RequiresObservableLicensor() public {
        nft.mint(address(this), 99);
        bytes32 id = _registerErc721(address(nft), 99);
        bytes32 t = _registerTermsBasic(0, true);
        reg.attachTerms(id, t, "");
        nft.burn(99);

        vmx.prank(address(0x1111));
        vmx.expectRevert(IPAssetRegistry.OwnerRequired.selector);
        reg.acquireAgreement(id, t, "", bytes32(0));
    }

    function test_CreateAgreement_ByOwner_None() public {
        bytes32 id = _registerNone(address(this), CONTENT_HASH);
        bytes32 t = _registerTermsBasic(0, true);
        reg.attachTerms(id, t, "");
        AgreementParams memory p;
        p.assetId = id;
        p.termsId = t;
        p.party = address(0x3333);
        p.agreementTokenization = AgreementTokenization.NONE;
        p.agreementCollection = address(0xDEAD);
        p.agreementTokenId = 999;
        p.licenseParams = "grant-evidence";
        p.acceptanceHash = keccak256("accepted-off-chain");
        vmx.recordLogs();
        bytes32 ag = reg.createAgreement(p);
        VmExt.Log[] memory logs = vmx.getRecordedLogs();
        assertTrue(reg.isActiveAgreementHolder(ag, id, address(0x3333)));
        assertEqA(reg.getLicensee(ag), address(0x3333));
        (
            ,,
            address storedParty,
            AgreementTokenization storedTokenization,
            address storedCollection,
            uint256 storedTokenId,
            AgreementEvidence memory evidence,,,
        ) = reg.agreementOf(ag);
        assertEqA(storedParty, address(0x3333));
        assertEqU(
            uint256(uint8(storedTokenization)), uint256(uint8(AgreementTokenization.NONE))
        );
        assertEqA(storedCollection, address(0));
        assertEqU(storedTokenId, 0);
        assertEqA(evidence.licensor, address(this));
        assertEqA(evidence.createdBy, address(this));
        assertEqA(evidence.initialLicensee, address(0x3333));
        assertEqU(evidence.createdAt, block.timestamp);
        assertEqU(
            uint256(uint8(evidence.creationMode)),
            uint256(uint8(AgreementCreationMode.GRANT))
        );
        assertEqB32(evidence.licenseParamsHash, keccak256("grant-evidence"));
        assertEqB32(evidence.acceptanceHash, p.acceptanceHash);

        assertEqU(logs.length, 1);
        assertEqA(logs[0].emitter, address(reg));
        assertEqB32(
            logs[0].topics[0],
            keccak256(
                "LicenseAgreementCreated(bytes32,bytes32,bytes32,(address,address,address,uint64,uint8,bytes32,bytes32),uint8,address,uint256,uint64,bool,bool)"
            )
        );
        assertEqB32(logs[0].topics[1], ag);
        assertEqB32(logs[0].topics[2], id);
        assertEqB32(logs[0].topics[3], t);
        (
            AgreementEvidence memory eventEvidence,
            AgreementTokenization eventTokenization,
            address eventCollection,
            uint256 eventTokenId,
            uint64 eventExpiry,
            bool eventTransferable,
            bool eventRevocable
        ) = abi.decode(
            logs[0].data,
            (AgreementEvidence, AgreementTokenization, address, uint256, uint64, bool, bool)
        );
        assertEqA(eventEvidence.licensor, evidence.licensor);
        assertEqA(eventEvidence.createdBy, evidence.createdBy);
        assertEqA(eventEvidence.initialLicensee, evidence.initialLicensee);
        assertEqU(eventEvidence.createdAt, evidence.createdAt);
        assertEqU(
            uint256(uint8(eventEvidence.creationMode)), uint256(uint8(evidence.creationMode))
        );
        assertEqB32(eventEvidence.licenseParamsHash, evidence.licenseParamsHash);
        assertEqB32(eventEvidence.acceptanceHash, evidence.acceptanceHash);
        assertEqU(uint256(uint8(eventTokenization)), uint256(uint8(AgreementTokenization.NONE)));
        assertEqA(eventCollection, address(0));
        assertEqU(eventTokenId, 0);
        assertEqU(eventExpiry, 0);
        assertTrue(eventTransferable);
        assertTrue(eventRevocable);
    }

    function test_CreateAgreement_UsesCanonicalAgreementId() public {
        bytes32 assetId = _registerNone(address(this), CONTENT_HASH);
        bytes32 termsId = _registerTermsBasic(0, true);
        reg.attachTerms(assetId, termsId, "");

        AgreementParams memory p;
        p.assetId = assetId;
        p.termsId = termsId;
        p.party = address(0x3333);
        p.agreementTokenization = AgreementTokenization.NONE;

        bytes32 expectedFirst =
            keccak256(abi.encode(reg.chainId(), address(reg), assetId, uint256(0)));
        bytes32 first = reg.createAgreement(p);
        assertEqB32(first, expectedFirst);

        bytes32 expectedSecond =
            keccak256(abi.encode(reg.chainId(), address(reg), assetId, uint256(1)));
        bytes32 second =
            reg.acquireAgreement(assetId, termsId, "", bytes32(0));
        assertEqB32(second, expectedSecond);
        assertTrue(first != second);
    }

    /// @dev Attachment regression: `createAgreement` MUST require the terms be
    ///      attached, exactly like `acquireAgreement`. Detachment blocks new
    ///      agreements. Previously `createAgreement` skipped this check entirely.
    function test_CreateAgreement_RequiresAttached() public {
        bytes32 id = _registerNone(address(this), CONTENT_HASH);
        bytes32 t = _registerTermsBasic(0, true);
        AgreementParams memory p;
        p.assetId = id;
        p.termsId = t;
        p.party = address(0x3333);
        p.agreementTokenization = AgreementTokenization.NONE;
        vmx.expectRevert(IPAssetRegistry.TermsNotAttached.selector);
        reg.createAgreement(p);
    }

    /// @dev Detachment regression: detaching terms MUST block `createAgreement` just
    ///      like it blocks `acquireAgreement`.
    function test_CreateAgreement_RevertsAfterDetach() public {
        bytes32 id = _registerNone(address(this), CONTENT_HASH);
        bytes32 t = _registerTermsBasic(0, true);
        reg.attachTerms(id, t, "");
        reg.detachTerms(id, t);
        AgreementParams memory p;
        p.assetId = id;
        p.termsId = t;
        p.party = address(0x3333);
        p.agreementTokenization = AgreementTokenization.NONE;
        vmx.expectRevert(IPAssetRegistry.TermsNotAttached.selector);
        reg.createAgreement(p);
    }

    function test_TransferAgreement_Transferable() public {
        bytes32 ag = _grant(address(0x4444), true);
        vmx.prank(address(0x4444));
        reg.transferAgreement(ag, address(0x5555));
        assertEqA(reg.getLicensee(ag), address(0x5555));
        (,,,,,, AgreementEvidence memory evidence,,,) = reg.agreementOf(ag);
        assertEqA(evidence.initialLicensee, address(0x4444));
    }

    function test_TransferAgreement_NonTransferable_Reverts() public {
        bytes32 ag = _grant(address(0x4444), false);
        vmx.prank(address(0x4444));
        vmx.expectRevert(IPAssetRegistry.NotTransferable.selector);
        reg.transferAgreement(ag, address(0x5555));
    }

    function test_TransferAgreement_NotLicensee_RevertsDespitePermissiveHook() public {
        bytes32 ag = _grant(address(0x4444), true);
        vmx.prank(address(0x9999));
        vmx.expectRevert(IPAssetRegistry.NotLicensee.selector);
        reg.transferAgreement(ag, address(0x5555));
        assertEqA(reg.getLicensee(ag), address(0x4444));
    }

    function test_TransferAgreement_ZeroRecipient_PreservesErrorOrdering() public {
        bytes32 ag = _grant(address(0x4444), true);
        vmx.prank(address(0x4444));
        vmx.expectRevert(IPAssetRegistry.PartyRequired.selector);
        reg.transferAgreement(ag, address(0));
        assertEqA(reg.getLicensee(ag), address(0x4444));
    }

    function _grant(address party, bool transferable) internal returns (bytes32) {
        bytes32 id = _registerNone(address(this), CONTENT_HASH);
        bytes32 t = _registerTermsBasic(0, transferable);
        reg.attachTerms(id, t, "");
        AgreementParams memory p;
        p.assetId = id;
        p.termsId = t;
        p.party = party;
        p.agreementTokenization = AgreementTokenization.NONE;
        return reg.createAgreement(p);
    }

    // ---- expiry / revoke / freeze ---------------------------------------

    function test_Expiry_DeactivatesAgreement() public {
        bytes32 id = _registerNone(address(this), CONTENT_HASH);
        bytes32 t = _registerTermsBasic(uint64(block.timestamp + 100), true);
        reg.attachTerms(id, t, "");
        vmx.prank(address(0x1111));
        bytes32 ag = reg.acquireAgreement(id, t, "", bytes32(0));
        assertTrue(reg.isAgreementActive(ag));
        vmx.warp(block.timestamp + 101);
        assertFalse(reg.isAgreementActive(ag));
        assertFalse(reg.isActiveAgreementHolder(ag, id, address(0x1111)));
    }

    function test_Duration_IsRelativeToEachAgreementCreation() public {
        bytes32 assetId = _registerNone(address(this), CONTENT_HASH);
        LicenseTerms memory terms;
        terms.duration = 100;
        bytes32 termsId = reg.registerTerms(terms);
        reg.attachTerms(assetId, termsId, "");

        uint64 firstCreatedAt = uint64(block.timestamp);
        vmx.prank(address(0x1111));
        bytes32 first =
            reg.acquireAgreement(assetId, termsId, "", bytes32(0));
        (,,,,,,, uint64 firstExpiry,,) = reg.agreementOf(first);
        assertEqU(firstExpiry, firstCreatedAt + 100);

        vmx.warp(block.timestamp + 25);
        uint64 secondCreatedAt = uint64(block.timestamp);
        vmx.prank(address(0x2222));
        bytes32 second =
            reg.acquireAgreement(assetId, termsId, "", bytes32(0));
        (,,,,,,, uint64 secondExpiry,,) = reg.agreementOf(second);
        assertEqU(secondExpiry, secondCreatedAt + 100);

        vmx.warp(firstExpiry);
        assertFalse(reg.isAgreementActive(first));
        assertTrue(reg.isAgreementActive(second));
    }

    function test_Duration_IsCappedByAbsoluteExpiry() public {
        bytes32 assetId = _registerNone(address(this), CONTENT_HASH);
        LicenseTerms memory terms;
        terms.expiry = uint64(block.timestamp + 50);
        terms.duration = 100;
        bytes32 termsId = reg.registerTerms(terms);
        reg.attachTerms(assetId, termsId, "");

        bytes32 agreementId =
            reg.acquireAgreement(assetId, termsId, "", bytes32(0));
        (,,,,,,, uint64 effectiveExpiry,,) = reg.agreementOf(agreementId);
        assertEqU(effectiveExpiry, terms.expiry);
    }

    function test_ExpiredAbsoluteTermsCannotCreateAgreement() public {
        bytes32 assetId = _registerNone(address(this), CONTENT_HASH);
        LicenseTerms memory terms;
        terms.expiry = uint64(block.timestamp);
        bytes32 termsId = reg.registerTerms(terms);
        reg.attachTerms(assetId, termsId, "");

        vmx.expectRevert(
            abi.encodeWithSelector(
                IIPAssetRegistry.TermsAlreadyExpired.selector,
                termsId,
                terms.expiry
            )
        );
        reg.acquireAgreement(assetId, termsId, "", bytes32(0));
    }

    function test_DurationOverflowCannotCreateAgreement() public {
        vmx.warp(1);
        bytes32 assetId = _registerNone(address(this), CONTENT_HASH);
        LicenseTerms memory terms;
        terms.duration = type(uint64).max;
        bytes32 termsId = reg.registerTerms(terms);
        reg.attachTerms(assetId, termsId, "");

        vmx.expectRevert(
            abi.encodeWithSelector(
                IIPAssetRegistry.AgreementExpiryOverflow.selector, termsId
            )
        );
        reg.acquireAgreement(assetId, termsId, "", bytes32(0));
    }

    function test_Revoke_ByOwner() public {
        bytes32 ag = _grant(address(0x4444), true);
        reg.revokeAgreement(ag, bytes32("dmca"));
        assertFalse(reg.isAgreementActive(ag));
    }

    function test_NonRevocable_BothModesAndCreationPaths() public {
        bytes32 assetId = _registerNone(address(this), CONTENT_HASH);
        LicenseTerms memory terms;
        bytes32 termsId = reg.registerTerms(terms);
        assertFalse(reg.getTerms(termsId).revocable);
        reg.attachTerms(assetId, termsId, "");
        bytes32 acquired = reg.acquireAgreement(assetId, termsId, "", bytes32(0));
        nft.mint(address(this), 42);
        AgreementParams memory p;
        p.assetId = assetId;
        p.termsId = termsId;
        p.agreementTokenization = AgreementTokenization.ERC721;
        p.agreementCollection = address(nft);
        p.agreementTokenId = 42;
        bytes32 granted = reg.createAgreement(p);
        terms.revocable = true;
        bytes32 replacement = reg.registerTerms(terms);
        assertTrue(replacement != termsId);
        assertTrue(reg.getTerms(replacement).revocable);
        reg.attachTerms(assetId, replacement, "");
        for (uint256 i; i < 2; ++i) {
            bytes32 id = i == 0 ? acquired : granted;
            (,,,,,,,,, bool revocable) = reg.agreementOf(id);
            assertFalse(revocable);
            vmx.expectRevert(IPAssetRegistry.NotRevocable.selector);
            reg.revokeAgreement(id, "ordinary");
            assertTrue(reg.isAgreementActive(id));
            vmx.prank(address(0xBAD));
            vmx.expectRevert(IPAssetRegistry.NotAdmin.selector);
            reg.forceRevokeAgreement(id, "unauthorized");
            reg.freezeAgreement(id, "hold");
            assertFalse(reg.isAgreementActive(id));
            reg.unfreezeAgreement(id, "clear");
            reg.forceRevokeAgreement(id, "exceptional");
            assertFalse(reg.isAgreementActive(id));
        }
    }

    function test_Revoke_ByStranger_Reverts() public {
        bytes32 ag = _grant(address(0x4444), true);
        vmx.prank(address(0x9999));
        vmx.expectRevert(IPAssetRegistry.NotOwner.selector);
        reg.revokeAgreement(ag, bytes32("x"));
    }

    function test_ForceRevoke_AdminOnly() public {
        bytes32 ag = _grant(address(0x4444), true);
        vmx.prank(address(0x9999));
        vmx.expectRevert(IPAssetRegistry.NotAdmin.selector);
        reg.forceRevokeAgreement(ag, bytes32("x"));
        reg.forceRevokeAgreement(ag, bytes32("ok")); // admin == this
        assertFalse(reg.isAgreementActive(ag));
    }

    function test_FreezeAsset_BlocksFutureWritesButPreservesExistingAgreement() public {
        bytes32 id = _registerNone(address(this), CONTENT_HASH);
        bytes32 t = _registerTermsBasic(0, true);
        reg.attachTerms(id, t, "");

        AgreementParams memory p;
        p.assetId = id;
        p.termsId = t;
        p.party = address(0x2222);
        p.agreementTokenization = AgreementTokenization.NONE;
        bytes32 existingAgreement = reg.createAgreement(p);

        reg.freezeAsset(id, bytes32("hold"));

        assertTrue(reg.isAgreementActive(existingAgreement));
        assertTrue(reg.isActiveAgreementHolder(existingAgreement, id, address(0x2222)));

        bytes32 otherTerms = _registerTermsBasic(0, false);
        vmx.expectRevert(IPAssetRegistry.AssetFrozenErr.selector);
        reg.attachTerms(id, otherTerms, "");

        p.party = address(0x3333);
        vmx.expectRevert(IPAssetRegistry.AssetFrozenErr.selector);
        reg.createAgreement(p);

        vmx.prank(address(0x1111));
        vmx.expectRevert(IPAssetRegistry.AssetFrozenErr.selector);
        reg.acquireAgreement(id, t, "", bytes32(0));

        reg.unfreezeAsset(id, bytes32("clear"));
        vmx.prank(address(0x1111));
        bytes32 newAgreement = reg.acquireAgreement(id, t, "", bytes32(0));
        assertTrue(reg.isAgreementActive(newAgreement));
    }

    function test_FreezeLicense_Deactivates() public {
        bytes32 ag = _grant(address(0x4444), true);
        reg.freezeAgreement(ag, bytes32("hold"));
        assertFalse(reg.isAgreementActive(ag));
        reg.unfreezeAgreement(ag, bytes32("clear"));
        assertTrue(reg.isAgreementActive(ag));
    }

    // ---- ERC721 agreement delegation ------------------------------------

    function test_Erc721Agreement_LicenseeDelegates_AndBurnDeactivates() public {
        bytes32 id = _registerNone(address(this), CONTENT_HASH);
        bytes32 t = _registerTermsBasic(0, true);
        reg.attachTerms(id, t, "");
        nft.mint(address(0x7777), 42);

        AgreementParams memory p;
        p.assetId = id;
        p.termsId = t;
        p.party = address(0xDEAD);
        p.agreementTokenization = AgreementTokenization.ERC721;
        p.agreementCollection = address(nft);
        p.agreementTokenId = 42;
        bytes32 ag = reg.createAgreement(p);

        assertEqA(reg.getLicensee(ag), address(0x7777));
        (
            ,,
            address storedParty,
            AgreementTokenization storedTokenization,
            address storedCollection,
            uint256 storedTokenId,
            AgreementEvidence memory evidence,,,
        ) = reg.agreementOf(ag);
        assertEqA(storedParty, address(0));
        assertEqU(
            uint256(uint8(storedTokenization)), uint256(uint8(AgreementTokenization.ERC721))
        );
        assertEqA(storedCollection, address(nft));
        assertEqU(storedTokenId, 42);
        assertEqA(evidence.initialLicensee, address(0x7777));
        assertTrue(reg.isActiveAgreementHolder(ag, id, address(0x7777)));
        nft.transfer(address(0x8888), 42);
        assertTrue(reg.isActiveAgreementHolder(ag, id, address(0x8888)));
        nft.burn(42);
        assertFalse(reg.isAgreementActive(ag)); // ownerless => inactive, no revert
    }

    function test_Erc721Agreement_RejectsZeroCollectionAtCreation() public {
        bytes32 id = _registerNone(address(this), CONTENT_HASH);
        bytes32 t = _registerTermsBasic(0, true);
        reg.attachTerms(id, t, "");

        AgreementParams memory p;
        p.assetId = id;
        p.termsId = t;
        p.agreementTokenization = AgreementTokenization.ERC721;
        p.agreementTokenId = 42;

        vmx.expectRevert(IPAssetRegistry.TokenBindingRequired.selector);
        reg.createAgreement(p);
    }

    function test_Erc721Agreement_RejectsMissingHolderAtCreation() public {
        bytes32 id = _registerNone(address(this), CONTENT_HASH);
        bytes32 t = _registerTermsBasic(0, true);
        reg.attachTerms(id, t, "");

        AgreementParams memory p;
        p.assetId = id;
        p.termsId = t;
        p.agreementTokenization = AgreementTokenization.ERC721;
        p.agreementCollection = address(nft);
        p.agreementTokenId = 404;

        vmx.expectRevert(IPAssetRegistry.PartyRequired.selector);
        reg.createAgreement(p);
    }

    function test_Erc721Agreement_TransferabilityRequiresTokenEnforcement() public {
        bytes32 assetId = _registerNone(address(this), CONTENT_HASH);
        bytes32 termsId = _registerTermsBasic(0, false);
        reg.attachTerms(assetId, termsId, "");
        nft.mint(address(0x7777), 43);

        AgreementParams memory p;
        p.assetId = assetId;
        p.termsId = termsId;
        p.agreementTokenization = AgreementTokenization.ERC721;
        p.agreementCollection = address(nft);
        p.agreementTokenId = 43;
        bytes32 agreementId = reg.createAgreement(p);

        (,,,,,,,, bool capturedTransferable,) = reg.agreementOf(agreementId);
        assertFalse(capturedTransferable);

        // This unrestricted token can transfer despite the captured terms. The
        // registry follows its holder and does not attest policy compliance.
        nft.transfer(address(0x8888), 43);
        assertEqA(reg.getLicensee(agreementId), address(0x8888));
        assertTrue(reg.isActiveAgreementHolder(agreementId, assetId, address(0x8888)));
        assertTrue(reg.isAgreementActive(agreementId));
    }

    // ---- pagination ----------------------------------------------------

    function test_Pagination_ExaminedNotReturned() public {
        bytes32 id = _registerNone(address(this), CONTENT_HASH);
        bytes32 t = _registerTermsBasic(0, true);
        reg.attachTerms(id, t, "");

        // Create 10 agreements; revoke the even-indexed ones.
        bytes32[] memory ags = new bytes32[](10);
        for (uint256 i; i < 10; ++i) {
            AgreementParams memory p;
            p.assetId = id;
            p.termsId = t;
            p.party = address(uint160(0x100 + i));
            p.agreementTokenization = AgreementTokenization.NONE;
            ags[i] = reg.createAgreement(p);
        }
        for (uint256 i; i < 10; i += 2) {
            reg.revokeAgreement(ags[i], bytes32("x"));
        }

        assertEqU(reg.agreementCountOf(id), 10);

        // Walk with a small limit; iterate until nextCursor == count.
        uint256 cursor;
        uint256 totalValid;
        uint256 pages;
        while (cursor < reg.agreementCountOf(id)) {
            (bytes32[] memory page, uint256 next) = reg.activeAgreementsOf(id, cursor, 3);
            totalValid += page.length;
            cursor = next;
            ++pages;
            if (pages > 100) break; // guard
        }
        assertEqU(totalValid, 5); // 5 odd-indexed survive
        assertEqU(cursor, 10);
    }

    function test_Pagination_UnknownAsset_EmptyPage() public view {
        (bytes32[] memory page, uint256 next) = reg.activeAgreementsOf(keccak256("nope"), 0, 10);
        assertEqU(page.length, 0);
        assertEqU(next, 0);
    }

    function test_PartyPagination_BoundsExaminedRecords() public {
        bytes32 id = _registerNone(address(this), CONTENT_HASH);
        bytes32 t = _registerTermsBasic(0, true);
        reg.attachTerms(id, t, "");

        AgreementParams memory p;
        p.assetId = id;
        p.termsId = t;
        p.agreementTokenization = AgreementTokenization.NONE;
        p.party = address(0x1111);
        reg.createAgreement(p);
        p.party = address(0x2222);
        bytes32 mine = reg.createAgreement(p);

        (bytes32[] memory first, uint256 next) =
            reg.activeAgreementsOf(id, address(0x2222), 0, 1);
        assertEqU(first.length, 0); // Empty page is not proof of absence.
        assertEqU(next, 1);

        (bytes32[] memory second, uint256 done) =
            reg.activeAgreementsOf(id, address(0x2222), next, 1);
        assertEqU(second.length, 1);
        assertEqB32(second[0], mine);
        assertEqU(done, 2);
    }

    function test_Pagination_MaxLimitDoesNotOverflow() public {
        bytes32 id = _registerNone(address(this), CONTENT_HASH);
        bytes32 t = _registerTermsBasic(0, true);
        reg.attachTerms(id, t, "");

        AgreementParams memory p;
        p.assetId = id;
        p.termsId = t;
        p.party = address(0x1111);
        p.agreementTokenization = AgreementTokenization.NONE;
        bytes32 ag = reg.createAgreement(p);

        (bytes32[] memory all, uint256 allNext) =
            reg.activeAgreementsOf(id, 0, type(uint256).max);
        assertEqU(all.length, 1);
        assertEqB32(all[0], ag);
        assertEqU(allNext, 1);

        (bytes32[] memory mine, uint256 mineNext) =
            reg.activeAgreementsOf(id, address(0x1111), 0, type(uint256).max);
        assertEqU(mine.length, 1);
        assertEqB32(mine[0], ag);
        assertEqU(mineNext, 1);
    }

    function test_Pagination_ZeroLimitDoesNotSkipRecords() public {
        bytes32 id = _registerNone(address(this), CONTENT_HASH);
        bytes32 t = _registerTermsBasic(0, true);
        reg.attachTerms(id, t, "");
        AgreementParams memory p;
        p.assetId = id;
        p.termsId = t;
        p.party = address(0x1111);
        p.agreementTokenization = AgreementTokenization.NONE;
        reg.createAgreement(p);

        (bytes32[] memory all, uint256 allNext) = reg.activeAgreementsOf(id, 0, 0);
        assertEqU(all.length, 0);
        assertEqU(allNext, 0);

        (bytes32[] memory mine, uint256 mineNext) =
            reg.activeAgreementsOf(id, address(0x1111), 0, 0);
        assertEqU(mine.length, 0);
        assertEqU(mineNext, 0);
    }

    function test_Pagination_SurvivesOwnerOfGasGriefing() public {
        bytes32 id = _registerNone(address(this), CONTENT_HASH);
        bytes32 t = _registerTermsBasic(0, true);
        reg.attachTerms(id, t, "");
        address licensee = address(0x1111);

        GasGriefingERC721 hostile = new GasGriefingERC721();
        hostile.mint(licensee, 1);
        AgreementParams memory p;
        p.assetId = id;
        p.termsId = t;
        p.agreementTokenization = AgreementTokenization.ERC721;
        p.agreementCollection = address(hostile);
        p.agreementTokenId = 1;
        reg.createAgreement(p);

        p.agreementTokenization = AgreementTokenization.NONE;
        p.party = licensee;
        bytes32 registryTracked = reg.createAgreement(p);
        hostile.setGrief(true);

        (bool ok, bytes memory result) = address(reg).staticcall{gas: 400_000}(
            abi.encodeWithSignature(
                "activeAgreementsOf(bytes32,address,uint256,uint256)", id, licensee, 0, 2
            )
        );
        assertTrue(ok);
        (bytes32[] memory page, uint256 next) = abi.decode(result, (bytes32[], uint256));
        assertEqU(page.length, 1);
        assertEqB32(page[0], registryTracked);
        assertEqU(next, 2);
    }

    /// @dev Enumeration regression: `agreementAtIndex` MUST NOT revert on an unknown
    ///      asset or an out-of-range index — it MUST return a sentinel
    ///      (`bytes32(0)`) like the other read-path views.
    function test_AgreementAtIndex_OutOfRange_DoesNotRevert() public {
        bytes32 id = _registerNone(address(this), CONTENT_HASH);
        assertEqB32(reg.agreementAtIndex(id, 0), bytes32(0));
        assertEqB32(reg.agreementAtIndex(keccak256("nope"), 0), bytes32(0));

        bytes32 t = _registerTermsBasic(0, true);
        reg.attachTerms(id, t, "");
        AgreementParams memory p;
        p.assetId = id;
        p.termsId = t;
        p.party = address(0x4444);
        p.agreementTokenization = AgreementTokenization.NONE;
        bytes32 ag = reg.createAgreement(p);

        assertEqB32(reg.agreementAtIndex(id, 0), ag);
        assertEqB32(reg.agreementAtIndex(id, 1), bytes32(0)); // one agreement only
    }

    // ---- asset claims --------------------------------------------------

    function test_Claim_AddGetRevoke() public {
        bytes32 id = _registerNone(address(this), CONTENT_HASH);
        bytes32 topic = keccak256("kyc");
        address issuer = address(0xC1A1);

        vmx.prank(issuer);
        reg.addClaim(id, topic, issuer, "verified", "sig");

        (bytes memory data, , , bool revoked) = reg.getClaim(id, topic, issuer);
        assertEqStr(string(data), "verified");
        assertFalse(revoked);

        address[] memory issuers = reg.getClaimIssuers(id, topic);
        assertEqU(issuers.length, 1);
        assertEqA(issuers[0], issuer);

        reg.revokeClaim(id, topic, issuer);
        (, , , bool revokedAfter) = reg.getClaim(id, topic, issuer);
        assertTrue(revokedAfter);
        assertEqU(reg.getClaimIssuers(id, topic).length, 0); // excluded once revoked
    }

    function test_ClaimWrites_EnforceReferenceAuthorization() public {
        bytes32 assetId = _registerNone(address(this), CONTENT_HASH);
        bytes32 topic = keccak256("kyc");
        address issuer = address(0xC1A1);
        address stranger = address(0xBAD);

        vmx.prank(stranger);
        vmx.expectRevert(IPAssetRegistry.NotAdmin.selector);
        reg.addClaim(assetId, topic, issuer, "forged", "invalid");

        vmx.prank(issuer);
        reg.addClaim(assetId, topic, issuer, "verified", "sig");

        vmx.prank(stranger);
        vmx.expectRevert(IPAssetRegistry.NotAdmin.selector);
        reg.revokeClaim(assetId, topic, issuer);

        vmx.prank(stranger);
        vmx.expectRevert(IPAssetRegistry.NotAdmin.selector);
        reg.setTrustedIssuer(topic, issuer, true);

        reg.setTrustedIssuer(topic, issuer, true);
        assertTrue(reg.isTrustedIssuer(topic, issuer));
        reg.revokeClaim(assetId, topic, issuer); // reference admin may revoke
        (, , , bool revoked) = reg.getClaim(assetId, topic, issuer);
        assertTrue(revoked);
    }

    function test_SetTrustedIssuer_EmitsChange() public {
        bytes32 topic = keccak256("kyc");
        address issuer = address(0xC1A1);

        vmx.recordLogs();
        reg.setTrustedIssuer(topic, issuer, true);
        VmExt.Log[] memory logs = vmx.getRecordedLogs();

        assertEqU(logs.length, 1);
        assertEqB32(
            logs[0].topics[0],
            keccak256("TrustedIssuerChanged(bytes32,address,bool,address)")
        );
        assertEqB32(logs[0].topics[1], topic);
        assertEqB32(logs[0].topics[2], bytes32(uint256(uint160(issuer))));
        assertEqB32(logs[0].topics[3], bytes32(uint256(uint160(address(this)))));
        assertTrue(abi.decode(logs[0].data, (bool)));
    }

    /// @dev Claim enumeration regression: re-adding a claim for an issuer that was
    ///      previously revoked MUST make that issuer discoverable again via
    ///      `getClaimIssuers` — a live (non-revoked) claim must never be
    ///      permanently hidden from enumeration.
    function test_Claim_ReAddAfterRevoke_ReappearsInIssuers() public {
        bytes32 id = _registerNone(address(this), CONTENT_HASH);
        bytes32 topic = keccak256("kyc");
        address issuer = address(0xC1A1);

        vmx.prank(issuer);
        reg.addClaim(id, topic, issuer, "verified", "sig");
        reg.revokeClaim(id, topic, issuer);
        assertEqU(reg.getClaimIssuers(id, topic).length, 0);

        vmx.prank(issuer);
        reg.addClaim(id, topic, issuer, "verified-again", "sig2");

        address[] memory issuers = reg.getClaimIssuers(id, topic);
        assertEqU(issuers.length, 1);
        assertEqA(issuers[0], issuer);
        (bytes memory data, , , bool revoked) = reg.getClaim(id, topic, issuer);
        assertEqStr(string(data), "verified-again");
        assertFalse(revoked);
    }

    // ---- derivation attestation signature ------------------------------

    function test_Derivation_ZeroIssuerRequiresCanonicalEmptyStruct() public {
        RegistrationParams memory p = _noneParams(address(this), CONTENT_HASH);

        p.derivationAttestation.parents = new ParentRef[](1);
        p.derivationAttestation.parents[0] =
            ParentRef({chainId: 1, registry: address(1), assetId: bytes32(uint256(1))});
        _expectMalformedAbsentDerivation(p);
        p.derivationAttestation.parents = new ParentRef[](0);

        p.derivationAttestation.signature = hex"01";
        _expectMalformedAbsentDerivation(p);
        p.derivationAttestation.signature = "";

        p.derivationAttestation.metadata = hex"01";
        _expectMalformedAbsentDerivation(p);
        p.derivationAttestation.metadata = "";

        p.derivationAttestation.registrationHash = bytes32(uint256(1));
        _expectMalformedAbsentDerivation(p);
    }

    function _expectMalformedAbsentDerivation(RegistrationParams memory p) internal {
        vmx.expectRevert(IIPAssetRegistry.MalformedDerivationAttestation.selector);
        reg.register(p);
    }

    function test_Derivation_ValidSignatureAccepted() public {
        uint256 pk = 0xA11CE;
        address issuer = vmx.addr(pk);

        ParentRef[] memory parents = new ParentRef[](1);
        parents[0] = ParentRef({chainId: reg.chainId(), registry: address(reg), assetId: keccak256("parent")});
        bytes memory metadata = hex"c0ffee";

        bytes32 expectedAssetId =
            keccak256(abi.encode(reg.chainId(), address(reg), address(this), CONTENT_HASH));
        RegistrationParams memory p = _noneParams(address(this), CONTENT_HASH);
        bytes32 digest = _derivationDigest(
            expectedAssetId, p, address(this), parents, metadata
        );
        (uint8 v, bytes32 r, bytes32 s) = vmx.sign(pk, digest);

        p.derivationAttestation = DerivationAttestation({
            parents: parents,
            issuer: issuer,
            signature: abi.encodePacked(r, s, v),
            metadata: metadata,
            registrationHash: _registrationHashForTest(p, address(this))
        });
        bytes32 id = reg.register(p);
        assertEqB32(id, expectedAssetId);
        DerivationAttestation memory got = reg.derivationAttestationOf(id);
        assertEqA(got.issuer, issuer);
        assertEqU(got.parents.length, 1);
        assertEqB32(got.registrationHash, _registrationHashForTest(p, address(this)));
    }

    function test_Derivation_BadSignatureRejected() public {
        uint256 pk = 0xA11CE; // signer; the attestation will name a *different* issuer
        ParentRef[] memory parents = new ParentRef[](0);
        bytes memory metadata = "";
        bytes32 expectedAssetId =
            keccak256(abi.encode(reg.chainId(), address(reg), address(this), CONTENT_HASH));
        RegistrationParams memory p = _noneParams(address(this), CONTENT_HASH);
        bytes32 digest = _derivationDigest(
            expectedAssetId, p, address(this), parents, metadata
        );
        (uint8 v, bytes32 r, bytes32 s) = vmx.sign(pk, digest);
        // Tamper: claim a different issuer than the signer.
        p.derivationAttestation = DerivationAttestation({
            parents: parents,
            issuer: address(0xDEAD),
            signature: abi.encodePacked(r, s, v),
            metadata: metadata,
            registrationHash: _registrationHashForTest(p, address(this))
        });
        vmx.expectRevert(IPAssetRegistry.BadDerivationSignature.selector);
        reg.register(p);
    }

    function _contractIssuerParams(MockERC1271 wallet, uint8 mode)
        internal returns (RegistrationParams memory p)
    {
        p = _noneParams(address(this), CONTENT_HASH);
        ParentRef[] memory parents = new ParentRef[](0);
        bytes memory signature = hex"c0ffee"; // ERC-1271 signatures need not be 65 bytes
        bytes32 id = keccak256(abi.encode(reg.chainId(), address(reg), address(this), p.salt));
        bytes32 digest = _derivationDigest(id, p, address(this), parents, "");
        wallet.configure(digest, keccak256(signature), mode);
        p.derivationAttestation = DerivationAttestation({
            parents: parents,
            issuer: address(wallet),
            signature: signature,
            metadata: "",
            registrationHash: _registrationHashForTest(p, address(this))
        });
    }

    function test_Derivation_ContractIssuerValidSignatureAccepted() public {
        MockERC1271 wallet = new MockERC1271();
        RegistrationParams memory p = _contractIssuerParams(wallet, 0);
        bytes32 id = reg.register(p);
        assertEqA(reg.derivationAttestationOf(id).issuer, address(wallet));
    }

    function test_Derivation_ContractIssuerInvalidSignatureRejected() public {
        MockERC1271 wallet = new MockERC1271();
        RegistrationParams memory p = _contractIssuerParams(wallet, 1);
        vmx.expectRevert(IPAssetRegistry.BadDerivationSignature.selector);
        reg.register(p);
        wallet.configure(bytes32(0), bytes32(0), 0); // wrong digest despite a magic-capable wallet
        vmx.expectRevert(IPAssetRegistry.BadDerivationSignature.selector);
        reg.register(p);
    }

    function test_Derivation_ContractIssuerRevertRejected() public {
        MockERC1271 wallet = new MockERC1271();
        RegistrationParams memory p = _contractIssuerParams(wallet, 2);
        vmx.expectRevert(IPAssetRegistry.BadDerivationSignature.selector);
        reg.register(p);
    }

    function test_Derivation_ContractIssuerGasExhaustionRejected() public {
        MockERC1271 wallet = new MockERC1271();
        RegistrationParams memory p = _contractIssuerParams(wallet, 3);
        vmx.expectRevert(IPAssetRegistry.BadDerivationSignature.selector);
        reg.register(p);
    }

    function test_Derivation_ContractIssuerMalformedReturnRejected() public {
        MockERC1271 wallet = new MockERC1271();
        RegistrationParams memory p = _contractIssuerParams(wallet, 4);
        vmx.expectRevert(IPAssetRegistry.BadDerivationSignature.selector);
        reg.register(p);
    }

    function test_Derivation_SignatureRejectsAlteredRegistration() public {
        uint256 pk = 0xA11CE;
        address issuer = vmx.addr(pk);
        ParentRef[] memory parents = new ParentRef[](0);
        bytes memory metadata = hex"c0ffee";
        RegistrationParams memory p = _noneParams(address(this), CONTENT_HASH);
        bytes32 assetId = keccak256(abi.encode(reg.chainId(), address(reg), address(this), p.salt));
        bytes32 digest = _derivationDigest(assetId, p, address(this), parents, metadata);
        (uint8 v, bytes32 r, bytes32 s) = vmx.sign(pk, digest);
        p.derivationAttestation = DerivationAttestation({
            parents: parents,
            issuer: issuer,
            signature: abi.encodePacked(r, s, v),
            metadata: metadata,
            registrationHash: _registrationHashForTest(p, address(this))
        });

        p.owner = address(0xBEEF);
        _expectBadDerivation(p);
        p.owner = address(this);

        p.authors = new Author[](1);
        p.authors[0] = Author({author: address(0xA11CE), shareNumerator: 1});
        p.sharesDenominator = 1;
        _expectBadDerivation(p);
        p.authors = new Author[](0);
        p.sharesDenominator = 0;

        p.assetType = keccak256("altered-type");
        _expectBadDerivation(p);
        p.assetType = ASSET_TYPE_IMAGE;

        p.metadataURI = "ipfs://altered";
        _expectBadDerivation(p);
        p.metadataURI = "";

        p.contentHash = keccak256("altered-content");
        _expectBadDerivation(p);
        p.contentHash = CONTENT_HASH;

        p.tokenization = AssetTokenization.ERC721;
        p.tokenCollection = address(nft);
        p.tokenId = 42;
        _expectBadDerivation(p);
    }

    function test_Derivation_SignatureRejectsDifferentRegistrant() public {
        uint256 pk = 0xA11CE;
        address issuer = vmx.addr(pk);
        ParentRef[] memory parents = new ParentRef[](0);
        bytes memory metadata = "";
        RegistrationParams memory p = _noneParams(address(this), CONTENT_HASH);
        bytes32 assetId = keccak256(abi.encode(reg.chainId(), address(reg), address(this), p.salt));
        bytes32 digest = _derivationDigest(assetId, p, address(this), parents, metadata);
        (uint8 v, bytes32 r, bytes32 s) = vmx.sign(pk, digest);
        p.derivationAttestation = DerivationAttestation({
            parents: parents,
            issuer: issuer,
            signature: abi.encodePacked(r, s, v),
            metadata: metadata,
            registrationHash: _registrationHashForTest(p, address(this))
        });

        vmx.prank(address(0xBAD));
        vmx.expectRevert(IPAssetRegistry.BadDerivationSignature.selector);
        reg.register(p);
    }

    function _expectBadDerivation(RegistrationParams memory p) internal {
        vmx.expectRevert(IPAssetRegistry.BadDerivationSignature.selector);
        reg.register(p);
    }

    function _derivationDigest(
        bytes32 assetId,
        RegistrationParams memory params,
        address registrant,
        ParentRef[] memory parents,
        bytes memory metadata
    )
        internal
        view
        returns (bytes32)
    {
        bytes32 PARENTREF_TYPEHASH =
            keccak256("ParentRef(uint256 chainId,address registry,bytes32 assetId)");
        bytes32 DERIVATION_TYPEHASH = keccak256(
            "Derivation(uint256 chainId,address registry,bytes32 assetId,bytes32 registrationHash,bytes32 parentsHash,bytes32 metadataHash)"
        );
        bytes32[] memory parentHashes = new bytes32[](parents.length);
        for (uint256 i; i < parents.length; ++i) {
            parentHashes[i] = keccak256(
                abi.encode(
                    PARENTREF_TYPEHASH,
                    parents[i].chainId,
                    parents[i].registry,
                    parents[i].assetId
                )
            );
        }
        bytes32 structHash = keccak256(
            abi.encode(
                DERIVATION_TYPEHASH,
                reg.chainId(),
                address(reg),
                assetId,
                _registrationHashForTest(params, registrant),
                keccak256(abi.encodePacked(parentHashes)),
                keccak256(metadata)
            )
        );
        bytes32 domainSeparator = keccak256(
            abi.encode(
                keccak256(
                    "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                ),
                keccak256(bytes("IPAssetRegistry")),
                keccak256(bytes("1")),
                reg.chainId(),
                address(reg)
            )
        );
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
    }

    function _registrationHashForTest(
        RegistrationParams memory params,
        address registrant
    ) internal pure returns (bytes32) {
        bytes32 AUTHOR_TYPEHASH =
            keccak256("Author(address author,uint256 shareNumerator)");
        bytes32 ASSET_DATA_TYPEHASH = keccak256(
            "AssetData(bytes32 assetType,uint8 tokenization,address tokenCollection,uint256 tokenId,bytes32 contentHash)"
        );
        bytes32 REGISTRATION_TYPEHASH = keccak256(
            "Registration(bytes32 salt,address registrant,address owner,bytes32 authorsHash,uint256 sharesDenominator,bytes32 assetDataHash,bytes32 metadataURIHash)"
        );
        bytes32[] memory authorHashes = new bytes32[](params.authors.length);
        for (uint256 i; i < params.authors.length; ++i) {
            authorHashes[i] = keccak256(
                abi.encode(
                    AUTHOR_TYPEHASH,
                    params.authors[i].author,
                    params.authors[i].shareNumerator
                )
            );
        }
        bytes32 assetDataHash = keccak256(
            abi.encode(
                ASSET_DATA_TYPEHASH,
                params.assetType,
                uint8(params.tokenization),
                params.tokenCollection,
                params.tokenId,
                params.contentHash
            )
        );
        return keccak256(
            abi.encode(
                REGISTRATION_TYPEHASH,
                params.salt,
                registrant,
                params.owner,
                keccak256(abi.encodePacked(authorHashes)),
                params.sharesDenominator,
                assetDataHash,
                keccak256(bytes(params.metadataURI))
            )
        );
    }

    // ---- ERC-165 --------------------------------------------------------

    function test_SupportsInterface() public view {
        assertTrue(reg.supportsInterface(type(IERC165).interfaceId));
        assertTrue(reg.supportsInterface(type(IIPAssetRegistry).interfaceId));
        assertTrue(reg.supportsInterface(type(ITermsRegistry).interfaceId));
        assertFalse(reg.supportsInterface(bytes4(0xb557ace8))); // Previous draft ABI.
        assertFalse(reg.supportsInterface(bytes4(0xffffffff)));
        assertFalse(reg.supportsInterface(bytes4(0xdeadbeef)));
    }
}
