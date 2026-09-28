// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

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
    RegistrationParams,
    AgreementParams
} from "./interfaces/IPAssetTypes.sol";
import {IIPAssetRegistry} from "./interfaces/IIPAssetRegistry.sol";
import {ITermsRegistry} from "./interfaces/ITermsRegistry.sol";
import {IERC165} from "./interfaces/IERC165.sol";

/// @dev Minimal external ERC-721 ownership surface needed for delegation.
interface IERC721Min {
    function ownerOf(uint256 tokenId) external view returns (address);
}

/// @dev ERC-1271 signature validation surface (not part of the registry interface).
interface IERC1271Min {
    function isValidSignature(bytes32 hash, bytes calldata signature) external view returns (bytes4);
}

/// @title IPAssetRegistry
/// @notice **Reference implementation** of the ERC IP-licensing registry
///         (`IIPAssetRegistry`).
///
/// @dev    This contract exists to *validate the specification*: it is an
///         intentionally unoptimized, dependency-free implementation whose
///         purpose is to prove every normative requirement is simultaneously
///         satisfiable by one contract, and to surface design issues before
///         the ERC text freezes. It is NOT audited and NOT production code.
///
///         Authorization model (reference policy; the ERC leaves all of this
///         to the implementer):
///           - The asset *owner* may update metadata, attach/detach terms,
///             grant agreements, and transfer `NONE` ownership.
///           - A would-be licensee may `acquireAgreement` against attached terms.
///           - A claim's named issuer or the admin may add/revoke that claim;
///             only the admin may configure trusted issuers.
///           - An *admin* (the deployer) holds the break-glass paths:
///             freeze/unfreeze and force-revoke, plus `setTrustedIssuer`.
///         Hooks here apply sensible default policy rather than blanket
///         `true`, but remain `view`, permissionless, and non-reverting.
contract IPAssetRegistry is IIPAssetRegistry {
    /// @dev Reference implementation budget for each untrusted ERC-721
    ///      ownership query. Over-budget calls are treated as ownerless.
    uint256 private constant ERC721_OWNER_QUERY_GAS = 100_000;
    uint256 private constant ERC1271_SIGNATURE_QUERY_GAS = 100_000;

    // =====================================================================
    // Errors
    // =====================================================================

    error NotOwner();
    error NotAdmin();
    error NotLicensee();
    error AssetUnknown();
    error AgreementUnknown();
    error TermsUnknown();
    error AlreadyExists();
    error BadAuthorsShares();
    error ContentHashRequired();
    error OwnerRequired();
    error OwnerMustBeZero();
    error TokenBindingRequired();
    error PartyRequired();
    error TermsNotAttached();
    error WrongTokenization();
    error NotTransferable();
    error NotRevocable();
    error AssetFrozenErr();
    error BadDerivationSignature();
    error BadSignatureLength();

    // =====================================================================
    // Data model
    // =====================================================================

    struct AssetRecord {
        bool exists;
        bool frozen;
        AssetTokenization tokenization;
        address owner; // meaningful for NONE
        address tokenCollection; // ERC721
        uint256 tokenId; // ERC721
        bytes32 assetType;
        string metadataURI;
        bytes32 contentHash;
        uint256 sharesDenominator;
        Author[] authors;
        DerivationAttestation derivation; // all fields zero/empty => absent
        // Attached terms (parallel arrays + membership index)
        bytes32[] termsIds;
        bytes[] attachmentParameters;
        // Agreements created on this asset (append-only stable indices)
        bytes32[] agreementIds;
    }

    struct AgreementRecord {
        bool exists;
        bool revoked;
        bool frozen;
        bytes32 assetId;
        bytes32 termsId;
        address party; // meaningful for NONE
        AgreementTokenization tokenization;
        address collection; // ERC721
        uint256 tokenId; // ERC721
        uint64 expiry; // snapshot of terms frame
        bool transferable; // snapshot of terms frame
        bool revocable; // snapshot of terms frame
        address licensor;
        address createdBy;
        address initialLicensee;
        uint64 createdAt;
        AgreementCreationMode creationMode;
        bytes32 licenseParamsHash;
        bytes32 acceptanceHash;
    }

    struct ClaimRecord {
        bool exists;
        bool revoked;
        uint64 timestamp;
        bytes data;
        bytes signature;
    }

    // Storage-only mirror of LicenseTerms plus an explicit presence flag.
    // Fields mirror LicenseTerms (IPAssetTypes.sol) but are flattened so that
    // `registered` packs into the same slot as `expiry`/the bool flags, making
    // the existence flag free of an extra storage slot. `registered` is NOT part
    // of the content-addressed termsId, which is hashed from the pure
    // LicenseTerms passed by the caller.
    struct StoredTerms {
        bool    registered;
        uint64  expiry;
        uint64  duration;
        bool    transferable;
        bool    revocable;
        bool    sublicensable;
        bool    exclusive;
        bytes32 jurisdictionScope;
        RightsSummary rights;
        string  uri;
        bytes32 contentHash;
        bytes32 termsType;
        bytes   rightsData;
    }

    // =====================================================================
    // Storage
    // =====================================================================

    address public immutable admin;
    uint256 private immutable _chainId;
    bytes32 private immutable _domainSeparator;

    mapping(bytes32 => AssetRecord) private _assets;
    mapping(bytes32 => StoredTerms) private _terms;
    mapping(bytes32 => AgreementRecord) private _agreements;

    // assetId => termsId => (index+1) into attached arrays
    mapping(bytes32 => mapping(bytes32 => uint256)) private _attachIndex;

    // claims: assetId => topicId => issuer => record; plus issuer enumeration
    mapping(bytes32 => mapping(bytes32 => mapping(address => ClaimRecord))) private _claims;
    mapping(bytes32 => mapping(bytes32 => address[])) private _claimIssuers;
    mapping(bytes32 => mapping(bytes32 => mapping(address => uint256))) private _claimIssuerIndex;

    // trusted issuers: topicId => issuer => trusted
    mapping(bytes32 => mapping(address => bool)) private _trustedIssuer;

    // =====================================================================
    // EIP-712 constants (derivation-attestation signatures)
    // =====================================================================

    bytes32 private constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 private constant PARENTREF_TYPEHASH =
        keccak256("ParentRef(uint256 chainId,address registry,bytes32 assetId)");
    bytes32 private constant AUTHOR_TYPEHASH =
        keccak256("Author(address author,uint256 shareNumerator)");
    bytes32 private constant ASSET_DATA_TYPEHASH = keccak256(
        "AssetData(bytes32 assetType,uint8 tokenization,address tokenCollection,uint256 tokenId,bytes32 contentHash)"
    );
    bytes32 private constant REGISTRATION_TYPEHASH = keccak256(
        "Registration(bytes32 salt,address registrant,address owner,bytes32 authorsHash,uint256 sharesDenominator,bytes32 assetDataHash,bytes32 metadataURIHash)"
    );
    bytes32 private constant DERIVATION_TYPEHASH = keccak256(
        "Derivation(uint256 chainId,address registry,bytes32 assetId,bytes32 registrationHash,bytes32 parentsHash,bytes32 metadataHash)"
    );

    constructor() {
        uint256 deploymentChainId = block.chainid;
        if (deploymentChainId == 0) revert InvalidChainId();
        admin = msg.sender;
        _chainId = deploymentChainId;
        _domainSeparator = keccak256(
            abi.encode(
                DOMAIN_TYPEHASH,
                keccak256(bytes("IPAssetRegistry")),
                keccak256(bytes("1")),
                deploymentChainId,
                address(this)
            )
        );
    }

    // =====================================================================
    // Modifiers / internal guards
    // =====================================================================

    function _requireAsset(bytes32 assetId) private view returns (AssetRecord storage a) {
        a = _assets[assetId];
        if (!a.exists) revert AssetUnknown();
    }

    function _requireOwner(AssetRecord storage a) private view returns (address owner) {
        if (a.tokenization == AssetTokenization.NONE) {
            owner = a.owner;
        } else {
            owner = _erc721Owner(a.tokenCollection, a.tokenId);
        }
        if (msg.sender != owner) revert NotOwner();
    }

    // =====================================================================
    // 1. Identity & Registration
    // =====================================================================

    function register(RegistrationParams calldata params) external returns (bytes32 assetId) {
        (bool ok, bytes32 reason) = canRegister(msg.sender, params);
        if (!ok) revert HookDenied(reason);

        // Authorship invariant.
        if (params.authors.length > 0) {
            uint256 sum;
            for (uint256 i; i < params.authors.length; ++i) {
                sum += params.authors[i].shareNumerator;
            }
            if (sum != params.sharesDenominator || params.sharesDenominator == 0) {
                revert BadAuthorsShares();
            }
        }

        // Deterministic, *pre-computable* assetId (see dev-note below).
        assetId = _deriveAssetId(params);
        AssetRecord storage a = _assets[assetId];
        if (a.exists) revert AlreadyExists();
        DerivationAttestation calldata att = params.derivationAttestation;
        if (att.issuer == address(0)) {
            if (
                att.parents.length != 0 || att.signature.length != 0 || att.metadata.length != 0
                    || att.registrationHash != bytes32(0)
            ) revert MalformedDerivationAttestation();
        } else if (!_verifyDerivation(assetId, params, msg.sender)) {
            revert BadDerivationSignature();
        }

        address initialOwner;
        if (params.tokenization == AssetTokenization.NONE) {
            // contentHash REQUIRED for NONE; owner must be set.
            if (params.contentHash == bytes32(0)) revert ContentHashRequired();
            if (params.owner == address(0)) revert OwnerRequired();
            a.owner = params.owner;
            initialOwner = params.owner;
        } else {
            // ERC721: canonical owner input is zero; live ownership comes from the token.
            if (params.owner != address(0)) revert OwnerMustBeZero();
            if (
                params.tokenCollection == address(0)
                    || params.tokenCollection.code.length == 0
            ) revert TokenBindingRequired();
            initialOwner = _erc721Owner(params.tokenCollection, params.tokenId);
            if (initialOwner == address(0)) revert OwnerRequired();
            a.tokenCollection = params.tokenCollection;
            a.tokenId = params.tokenId;
        }

        a.exists = true;
        a.tokenization = params.tokenization;
        a.assetType = params.assetType;
        a.metadataURI = params.metadataURI;
        a.contentHash = params.contentHash;
        a.sharesDenominator = params.sharesDenominator;
        for (uint256 i; i < params.authors.length; ++i) {
            a.authors.push(params.authors[i]);
        }

        // Optional derivation attestation, signature verified before writes above.
        if (att.issuer != address(0)) {
            a.derivation.issuer = att.issuer;
            a.derivation.signature = att.signature;
            a.derivation.metadata = att.metadata;
            a.derivation.registrationHash = att.registrationHash;
            for (uint256 i; i < att.parents.length; ++i) {
                a.derivation.parents.push(att.parents[i]);
            }
            emit DerivationAttestationRegistered(
                assetId, att.issuer, att.parents, att.metadata, att.registrationHash
            );
        }

        emit AssetRegistered(
            assetId, msg.sender, initialOwner, params.assetType, params.tokenization,
            params.metadataURI, params.contentHash
        );
    }

    /// @dev Reference id-derivation. `assetId` is derived
    ///      from a registrant-chosen `salt`:
    ///        assetId = keccak256(abi.encode(chainId, registry, registrant, salt))
    ///      where registrant is msg.sender. Binding the caller prevents another
    ///      registrant from occupying a pending registration's id.
    ///      The salt makes the id **pre-computable** before the transaction,
    ///      which is required because the derivation attestation is signed
    ///      over `assetId` off-chain *before* `register` is called.
    ///      It also avoids content-hash identity-squatting in a permissionless
    ///      registry: the same work can be registered under different salts,
    ///      and downstream catalogs decide which is authoritative. A registry
    ///      that wants per-registrant content-addressed de-duplication has
    ///      registrants set `salt = contentHash`.
    function _deriveAssetId(RegistrationParams calldata params) private view returns (bytes32) {
        return keccak256(abi.encode(_chainId, address(this), msg.sender, params.salt));
    }

    function assetExists(bytes32 assetId) external view returns (bool) {
        return _assets[assetId].exists;
    }

    function chainId() external view returns (uint256) {
        return _chainId;
    }

    // =====================================================================
    // 2. Asset read paths
    // =====================================================================

    function ownerOf(bytes32 assetId) external view returns (address) {
        AssetRecord storage a = _assets[assetId];
        if (!a.exists) return address(0);
        return _ownerOfRecord(a);
    }

    function _ownerOfRecord(AssetRecord storage a) private view returns (address) {
        if (a.tokenization == AssetTokenization.NONE) return a.owner;
        return _erc721Owner(a.tokenCollection, a.tokenId);
    }

    /// @dev Revert- and gas-grief-safe delegation: a failed,
    ///      over-budget, or malformed query yields `address(0)`.
    function _erc721Owner(address collection, uint256 tokenId) private view returns (address) {
        bytes memory callData = abi.encodeCall(IERC721Min.ownerOf, (tokenId));
        uint256 gasLimit = ERC721_OWNER_QUERY_GAS;
        bool ok;
        uint256 returnSize;
        uint256 rawOwner;
        assembly {
            let output := mload(0x40)
            mstore(output, 0)
            ok := staticcall(
                gasLimit,
                collection,
                add(callData, 32),
                mload(callData),
                output,
                32
            )
            returnSize := returndatasize()
            rawOwner := mload(output)
        }
        if (!ok || returnSize != 32 || rawOwner > type(uint160).max) return address(0);
        return address(uint160(rawOwner));
    }

    function authorsOf(bytes32 assetId)
        external
        view
        returns (Author[] memory authors, uint256 sharesDenominator)
    {
        AssetRecord storage a = _assets[assetId];
        return (a.authors, a.sharesDenominator);
    }

    function tokenizationOf(bytes32 assetId)
        external
        view
        returns (AssetTokenization tokenization, address tokenCollection, uint256 tokenId)
    {
        AssetRecord storage a = _assets[assetId];
        return (a.tokenization, a.tokenCollection, a.tokenId);
    }

    function assetTypeOf(bytes32 assetId) external view returns (bytes32) {
        return _assets[assetId].assetType;
    }

    function metadataOf(bytes32 assetId)
        external
        view
        returns (string memory metadataURI, bytes32 contentHash)
    {
        AssetRecord storage a = _assets[assetId];
        return (a.metadataURI, a.contentHash);
    }

    function derivationAttestationOf(bytes32 assetId)
        external
        view
        returns (DerivationAttestation memory)
    {
        return _assets[assetId].derivation;
    }

    function attachedTermsOf(bytes32 assetId)
        external
        view
        returns (
            bytes32[] memory termsIds,
            bytes[] memory attachmentParameters
        )
    {
        AssetRecord storage a = _assets[assetId];
        return (a.termsIds, a.attachmentParameters);
    }

    function agreementCountOf(bytes32 assetId) external view returns (uint256) {
        return _assets[assetId].agreementIds.length;
    }

    function agreementAtIndex(bytes32 assetId, uint256 index)
        external
        view
        returns (bytes32 agreementId)
    {
        bytes32[] storage ids = _assets[assetId].agreementIds;
        if (index >= ids.length) return bytes32(0); // MUST NOT revert on unknown identifiers
        return ids[index];
    }

    function activeAgreementsOf(bytes32 assetId, uint256 cursor, uint256 limit)
        external
        view
        returns (bytes32[] memory agreementIds, uint256 nextCursor)
    {
        bytes32[] storage all = _assets[assetId].agreementIds;
        uint256 total = all.length;
        if (cursor >= total) {
            return (new bytes32[](0), total);
        }
        if (limit == 0) return (new bytes32[](0), cursor);
        uint256 remaining = total - cursor;
        uint256 end = limit >= remaining ? total : cursor + limit;

        agreementIds = new bytes32[](end - cursor);
        uint256 w;
        for (uint256 i = cursor; i < end; ++i) {
            if (_activeLicensee(all[i]) != address(0)) {
                agreementIds[w++] = all[i];
            }
        }
        assembly {
            mstore(agreementIds, w)
        }
        nextCursor = end;
    }

    // =====================================================================
    // 3. Asset mutation
    // =====================================================================

    function updateMetadata(bytes32 assetId, string calldata newURI) external {
        AssetRecord storage a = _requireAsset(assetId);
        _requireOwner(a);
        (bool ok, bytes32 reason) = canUpdateMetadata(assetId, newURI);
        if (!ok) revert HookDenied(reason);

        // Only the mutable pointer moves; `contentHash` is immutable.
        string memory oldURI = a.metadataURI;
        a.metadataURI = newURI;
        emit MetadataUpdated(assetId, msg.sender, oldURI, newURI, uint64(block.timestamp));
    }

    function transferOwnership(bytes32 assetId, address newOwner) external {
        AssetRecord storage a = _requireAsset(assetId);
        // ERC721 ownership lives in the token contract.
        if (a.tokenization == AssetTokenization.ERC721) revert WrongTokenization();
        if (msg.sender != a.owner) revert NotOwner();
        (bool ok, bytes32 reason) =
            canTransferAsset(assetId, a.owner, newOwner);
        if (!ok) revert HookDenied(reason);

        address from = a.owner;
        a.owner = newOwner;
        emit OwnershipTransferred(assetId, from, newOwner);
    }

    // =====================================================================
    // 4. Asset claims
    // =====================================================================

    function addClaim(
        bytes32 assetId,
        bytes32 topicId,
        address issuer,
        bytes calldata data,
        bytes calldata signature
    ) external {
        _requireAsset(assetId);
        // Reference policy: the named issuer attests for itself, or admin.
        if (msg.sender != issuer && msg.sender != admin) revert NotAdmin();

        ClaimRecord storage c = _claims[assetId][topicId][issuer];
        if (_claimIssuerIndex[assetId][topicId][issuer] == 0) {
            // Not currently in the enumerable issuer set — either brand new,
            // or previously revoked and removed. Re-insert so a re-added
            // (live) claim is discoverable via getClaimIssuers.
            _claimIssuerIndex[assetId][topicId][issuer] = _claimIssuers[assetId][topicId].length + 1;
            _claimIssuers[assetId][topicId].push(issuer);
        }
        c.exists = true;
        c.revoked = false;
        c.timestamp = uint64(block.timestamp);
        c.data = data;
        c.signature = signature;
        emit AssetClaimAdded(assetId, topicId, issuer, data);
    }

    function revokeClaim(bytes32 assetId, bytes32 topicId, address issuer) external {
        if (msg.sender != issuer && msg.sender != admin) revert NotAdmin();
        ClaimRecord storage c = _claims[assetId][topicId][issuer];
        if (!c.exists) return;
        c.revoked = true;
        _removeClaimIssuer(assetId, topicId, issuer);
        emit AssetClaimRevoked(assetId, topicId, issuer);
    }

    function getClaim(bytes32 assetId, bytes32 topicId, address issuer)
        external
        view
        returns (bytes memory data, bytes memory signature, uint64 timestamp, bool revoked)
    {
        ClaimRecord storage c = _claims[assetId][topicId][issuer];
        return (c.data, c.signature, c.timestamp, c.revoked);
    }

    function getClaimIssuers(bytes32 assetId, bytes32 topicId)
        external
        view
        returns (address[] memory)
    {
        return _claimIssuers[assetId][topicId];
    }

    function setTrustedIssuer(bytes32 topicId, address issuer, bool trusted) external {
        if (msg.sender != admin) revert NotAdmin();
        _trustedIssuer[topicId][issuer] = trusted;
        emit TrustedIssuerChanged(topicId, issuer, trusted, msg.sender);
    }

    function isTrustedIssuer(bytes32 topicId, address issuer) external view returns (bool) {
        return _trustedIssuer[topicId][issuer];
    }

    function _removeClaimIssuer(bytes32 assetId, bytes32 topicId, address issuer) private {
        uint256 idx1 = _claimIssuerIndex[assetId][topicId][issuer];
        if (idx1 == 0) return;
        address[] storage arr = _claimIssuers[assetId][topicId];
        uint256 i = idx1 - 1;
        uint256 last = arr.length - 1;
        if (i != last) {
            address moved = arr[last];
            arr[i] = moved;
            _claimIssuerIndex[assetId][topicId][moved] = i + 1;
        }
        arr.pop();
        _claimIssuerIndex[assetId][topicId][issuer] = 0;
    }

    // =====================================================================
    // 5. License terms
    // =====================================================================

    function registerTerms(LicenseTerms calldata terms) external returns (bytes32 termsId) {
        if ((bytes(terms.uri).length == 0) != (terms.contentHash == bytes32(0))) {
            revert IncompleteLegalWrapper();
        }
        termsId = keccak256(abi.encode(terms)); // content-addressed
        StoredTerms storage s = _terms[termsId];
        if (!s.registered) {
            s.expiry = terms.expiry;
            s.duration = terms.duration;
            s.transferable = terms.transferable;
            s.revocable = terms.revocable;
            s.sublicensable = terms.sublicensable;
            s.exclusive = terms.exclusive;
            s.registered = true;
            s.jurisdictionScope = terms.jurisdictionScope;
            s.rights = terms.rights;
            s.uri = terms.uri;
            s.contentHash = terms.contentHash;
            s.termsType = terms.termsType;
            s.rightsData = terms.rightsData;
            emit TermsRegistered(termsId, msg.sender, terms.termsType);
        }
        // Re-registration returns the same id without writing or emitting.
    }

    function termsExists(bytes32 termsId) external view returns (bool) {
        return _terms[termsId].registered;
    }

    function getTerms(bytes32 termsId) external view returns (LicenseTerms memory) {
        StoredTerms storage s = _terms[termsId];
        if (!s.registered) revert TermsUnknown();
        return _termsValue(s);
    }

    function _termsValue(StoredTerms storage s) private view returns (LicenseTerms memory) {
        return LicenseTerms({
            expiry: s.expiry,
            duration: s.duration,
            transferable: s.transferable,
            revocable: s.revocable,
            sublicensable: s.sublicensable,
            exclusive: s.exclusive,
            jurisdictionScope: s.jurisdictionScope,
            rights: s.rights,
            uri: s.uri,
            contentHash: s.contentHash,
            termsType: s.termsType,
            rightsData: s.rightsData
        });
    }

    // =====================================================================
    // 6. Terms attachment
    // =====================================================================

    function attachTerms(
        bytes32 assetId,
        bytes32 termsId,
        bytes calldata attachmentParameters
    ) external {
        AssetRecord storage a = _requireAsset(assetId);
        _requireOwner(a);
        if (a.frozen) revert AssetFrozenErr(); // frozen asset refuses new attachments
        if (!_terms[termsId].registered) revert TermsUnknown();
        (bool ok, bytes32 reason) = canAttachTerms(assetId, termsId, attachmentParameters);
        if (!ok) revert HookDenied(reason);

        if (_attachIndex[assetId][termsId] == 0) {
            a.termsIds.push(termsId);
            a.attachmentParameters.push(attachmentParameters);
            _attachIndex[assetId][termsId] = a.termsIds.length; // index+1
        } else {
            // Re-attach updates parameters in place.
            uint256 i = _attachIndex[assetId][termsId] - 1;
            a.attachmentParameters[i] = attachmentParameters;
        }
        emit TermsAttached(assetId, termsId, attachmentParameters);
    }

    function detachTerms(bytes32 assetId, bytes32 termsId) external {
        AssetRecord storage a = _requireAsset(assetId);
        _requireOwner(a);
        (bool ok, bytes32 reason) = canDetachTerms(assetId, termsId);
        if (!ok) revert HookDenied(reason);

        uint256 idx1 = _attachIndex[assetId][termsId];
        if (idx1 == 0) return; // not attached: no-op (existing agreements unaffected)
        uint256 i = idx1 - 1;
        uint256 last = a.termsIds.length - 1;
        if (i != last) {
            a.termsIds[i] = a.termsIds[last];
            a.attachmentParameters[i] = a.attachmentParameters[last];
            _attachIndex[assetId][a.termsIds[i]] = i + 1;
        }
        a.termsIds.pop();
        a.attachmentParameters.pop();
        _attachIndex[assetId][termsId] = 0;
        emit TermsDetached(assetId, termsId);
    }

    function _isAttached(bytes32 assetId, bytes32 termsId) private view returns (bool) {
        return _attachIndex[assetId][termsId] != 0;
    }

    // =====================================================================
    // 7. License agreements
    // =====================================================================

    function createAgreement(AgreementParams calldata params)
        external
        returns (bytes32 agreementId)
    {
        AssetRecord storage a = _requireAsset(params.assetId);
        address licensor = _requireOwner(a); // owner grants the license
        if (a.frozen) revert AssetFrozenErr(); // frozen asset refuses new agreements
        if (!_isAttached(params.assetId, params.termsId)) {
            revert TermsNotAttached(); // only attached terms are eligible for creation
        }
        address acquirer = params.agreementTokenization == AgreementTokenization.NONE
            ? params.party
            : _initialTokenLicensee(params.agreementCollection, params.agreementTokenId);
        (bool ok, bytes32 reason) = canLicense(
            params.assetId,
            params.termsId,
            acquirer,
            params.licenseParams,
            params.acceptanceHash
        );
        if (!ok) revert HookDenied(reason);
        agreementId = _createAgreement(
            params, licensor, msg.sender, acquirer, AgreementCreationMode.GRANT
        );
    }

    function acquireAgreement(
        bytes32 assetId,
        bytes32 termsId,
        bytes calldata licenseParams,
        bytes32 acceptanceHash
    )
        external
        returns (bytes32 agreementId)
    {
        AssetRecord storage a = _requireAsset(assetId);
        if (a.frozen) revert AssetFrozenErr();
        address licensor = _ownerOfRecord(a);
        if (licensor == address(0)) revert OwnerRequired();
        if (!_isAttached(assetId, termsId)) revert TermsNotAttached();
        (bool ok, bytes32 reason) = canLicense(
            assetId, termsId, msg.sender, licenseParams, acceptanceHash
        );
        if (!ok) revert HookDenied(reason);

        AgreementParams memory p = AgreementParams({
            assetId: assetId,
            termsId: termsId,
            party: msg.sender,
            agreementTokenization: AgreementTokenization.NONE,
            agreementCollection: address(0),
            agreementTokenId: 0,
            licenseParams: licenseParams,
            acceptanceHash: acceptanceHash
        });
        agreementId = _createAgreementMem(
            p, licensor, msg.sender, msg.sender, AgreementCreationMode.ACQUIRE
        );
    }

    function _createAgreement(
        AgreementParams calldata p,
        address licensor,
        address createdBy,
        address initialLicensee,
        AgreementCreationMode creationMode
    ) private returns (bytes32 agreementId) {
        return _createAgreementMem(
            AgreementParams({
                assetId: p.assetId,
                termsId: p.termsId,
                party: p.party,
                agreementTokenization: p.agreementTokenization,
                agreementCollection: p.agreementCollection,
                agreementTokenId: p.agreementTokenId,
                licenseParams: p.licenseParams,
                acceptanceHash: p.acceptanceHash
            }),
            licensor,
            createdBy,
            initialLicensee,
            creationMode
        );
    }

    function _createAgreementMem(
        AgreementParams memory p,
        address licensor,
        address createdBy,
        address initialLicensee,
        AgreementCreationMode creationMode
    ) private returns (bytes32 agreementId) {
        if (p.agreementTokenization == AgreementTokenization.NONE) {
            if (p.party == address(0)) revert PartyRequired();
        } else {
            if (p.agreementCollection == address(0)) revert TokenBindingRequired();
            if (initialLicensee == address(0)) revert PartyRequired();
        }

        if (block.timestamp > type(uint64).max) {
            revert AgreementExpiryOverflow(p.termsId);
        }
        uint64 createdAt = uint64(block.timestamp);
        (uint64 expiry, bool transferable, bool revocable) = _loadTermsFrame(p.termsId, createdAt);

        AssetRecord storage a = _assets[p.assetId];
        uint256 agreementIndex = a.agreementIds.length;
        agreementId = keccak256(
            abi.encode(_chainId, address(this), p.assetId, agreementIndex)
        );

        AgreementRecord storage g = _agreements[agreementId];
        if (agreementId == bytes32(0) || g.exists) revert AgreementIdCollision(agreementId);
        g.exists = true;
        g.assetId = p.assetId;
        g.termsId = p.termsId;
        g.tokenization = p.agreementTokenization;
        g.expiry = expiry;
        g.transferable = transferable;
        g.revocable = revocable;
        g.licensor = licensor;
        g.createdBy = createdBy;
        g.initialLicensee = initialLicensee;
        g.createdAt = createdAt;
        g.creationMode = creationMode;
        g.licenseParamsHash = keccak256(p.licenseParams);
        g.acceptanceHash = p.acceptanceHash;
        if (p.agreementTokenization == AgreementTokenization.NONE) {
            g.party = p.party;
        } else {
            g.collection = p.agreementCollection;
            g.tokenId = p.agreementTokenId;
        }
        a.agreementIds.push(agreementId);

        emit LicenseAgreementCreated(
            agreementId,
            p.assetId,
            p.termsId,
            _evidenceOf(g),
            g.tokenization,
            g.collection,
            g.tokenId,
            g.expiry,
            g.transferable,
            g.revocable
        );
    }

    function _initialTokenLicensee(address collection, uint256 tokenId)
        private
        view
        returns (address licensee)
    {
        if (collection == address(0)) revert TokenBindingRequired();
        licensee = _erc721Owner(collection, tokenId);
        if (licensee == address(0)) revert PartyRequired();
    }

    /// @dev Loads locally registered terms again at agreement creation.
    function _loadTermsFrame(bytes32 termsId, uint64 createdAt)
        private
        view
        returns (uint64 expiry, bool transferable, bool revocable)
    {
        StoredTerms storage terms = _terms[termsId];
        if (!terms.registered) revert TermsUnknown();
        uint64 relativeExpiry;
        if (terms.duration != 0) {
            if (terms.duration > type(uint64).max - createdAt) {
                revert AgreementExpiryOverflow(termsId);
            }
            relativeExpiry = createdAt + terms.duration;
        }

        expiry = terms.expiry;
        if (expiry == 0 || (relativeExpiry != 0 && relativeExpiry < expiry)) {
            expiry = relativeExpiry;
        }
        if (expiry != 0 && expiry <= createdAt) {
            revert TermsAlreadyExpired(termsId, expiry);
        }
        return (expiry, terms.transferable, terms.revocable);
    }

    function transferAgreement(bytes32 agreementId, address to) external {
        AgreementRecord storage g = _agreements[agreementId];
        if (!g.exists) revert AgreementUnknown();
        if (g.tokenization != AgreementTokenization.NONE) revert WrongTokenization(); // ERC721 via token
        if (msg.sender != g.party) revert NotLicensee();
        if (!g.transferable) revert NotTransferable(); // enforce captured transferability
        if (to == address(0)) revert PartyRequired();
        (bool ok, bytes32 reason) =
            canTransferAgreement(agreementId, g.party, to);
        if (!ok) revert HookDenied(reason);

        address from = g.party;
        g.party = to;
        emit LicenseAgreementTransferred(agreementId, from, to);
    }

    function agreementOf(bytes32 agreementId)
        external
        view
        returns (
            bytes32 assetId,
            bytes32 termsId,
            address party,
            AgreementTokenization agreementTokenization,
            address agreementCollection,
            uint256 agreementTokenId,
            AgreementEvidence memory evidence,
            uint64 expiry,
            bool transferable,
            bool revocable
        )
    {
        AgreementRecord storage g = _agreements[agreementId];
        return (
            g.assetId,
            g.termsId,
            g.party,
            g.tokenization,
            g.collection,
            g.tokenId,
            _evidenceOf(g),
            g.expiry,
            g.transferable,
            g.revocable
        );
    }

    function _evidenceOf(AgreementRecord storage g)
        private
        view
        returns (AgreementEvidence memory)
    {
        return AgreementEvidence({
            licensor: g.licensor,
            createdBy: g.createdBy,
            initialLicensee: g.initialLicensee,
            createdAt: g.createdAt,
            creationMode: g.creationMode,
            licenseParamsHash: g.licenseParamsHash,
            acceptanceHash: g.acceptanceHash
        });
    }

    function getLicensee(bytes32 agreementId) external view returns (address) {
        return _licenseeOf(agreementId);
    }

    function _licenseeOf(bytes32 agreementId) private view returns (address) {
        AgreementRecord storage g = _agreements[agreementId];
        if (!g.exists) return address(0);
        if (g.tokenization == AgreementTokenization.NONE) return g.party;
        return _erc721Owner(g.collection, g.tokenId);
    }

    // =====================================================================
    // 8. Agreement activity
    // =====================================================================

    function activeAgreementsOf(
        bytes32 assetId,
        address party,
        uint256 cursor,
        uint256 limit
    )
        external
        view
        returns (bytes32[] memory agreementIds, uint256 nextCursor)
    {
        bytes32[] storage all = _assets[assetId].agreementIds;
        uint256 total = all.length;
        if (cursor >= total) {
            return (new bytes32[](0), total);
        }
        if (limit == 0) return (new bytes32[](0), cursor);
        uint256 remaining = total - cursor;
        uint256 end = limit >= remaining ? total : cursor + limit;
        if (party == address(0)) return (new bytes32[](0), end);

        agreementIds = new bytes32[](end - cursor);
        uint256 w;
        for (uint256 i = cursor; i < end; ++i) {
            if (_activeLicensee(all[i]) == party) agreementIds[w++] = all[i];
        }
        assembly {
            mstore(agreementIds, w)
        }
        nextCursor = end;
    }

    function isActiveAgreementHolder(bytes32 agreementId, bytes32 assetId, address party)
        external
        view
        returns (bool)
    {
        if (party == address(0) || _agreements[agreementId].assetId != assetId) return false;
        return _activeLicensee(agreementId) == party;
    }

    function isAgreementActive(bytes32 agreementId) external view returns (bool) {
        return _activeLicensee(agreementId) != address(0);
    }

    function _activeLicensee(bytes32 agreementId) private view returns (address) {
        AgreementRecord storage g = _agreements[agreementId];
        if (!g.exists || g.revoked || g.frozen) return address(0);
        if (g.expiry != 0 && block.timestamp >= g.expiry) return address(0);
        return _licenseeOf(agreementId);
    }

    // =====================================================================
    // 9. Revocation
    // =====================================================================

    function revokeAgreement(bytes32 agreementId, bytes32 reason) external {
        AgreementRecord storage g = _agreements[agreementId];
        if (!g.exists) revert AgreementUnknown();
        _requireOwner(_assets[g.assetId]);
        if (!g.revocable) revert NotRevocable();
        (bool ok, bytes32 hookReason) = canRevoke(agreementId, msg.sender, reason);
        if (!ok) revert HookDenied(hookReason);
        g.revoked = true;
        emit LicenseAgreementRevoked(agreementId, msg.sender, reason);
    }

    function forceRevokeAgreement(bytes32 agreementId, bytes32 reason) external {
        if (msg.sender != admin) revert NotAdmin(); // break-glass
        AgreementRecord storage g = _agreements[agreementId];
        if (!g.exists) revert AgreementUnknown();
        g.revoked = true;
        emit LicenseAgreementRevoked(agreementId, msg.sender, reason);
    }

    // =====================================================================
    // 10. Pre-flight hooks — reference default policy
    // =====================================================================

    function canRegister(address, RegistrationParams calldata)
        public
        pure
        returns (bool ok, bytes32 reason)
    {
        return (true, bytes32(0)); // permissionless registry
    }

    function canUpdateMetadata(bytes32, string calldata)
        public
        pure
        returns (bool ok, bytes32 reason)
    {
        return (true, bytes32(0));
    }

    function canTransferAsset(bytes32, address, address to)
        public
        view
        virtual
        returns (bool ok, bytes32 reason)
    {
        return _transferRecipientPolicy(to);
    }

    function canTransferAgreement(bytes32, address, address to)
        public
        view
        virtual
        returns (bool ok, bytes32 reason)
    {
        return _transferRecipientPolicy(to);
    }

    function _transferRecipientPolicy(address to)
        internal
        pure
        returns (bool ok, bytes32 reason)
    {
        if (to == address(0)) return (false, "zero-recipient");
        return (true, bytes32(0));
    }

    function canAttachTerms(bytes32, bytes32, bytes calldata)
        public
        pure
        returns (bool ok, bytes32 reason)
    {
        return (true, bytes32(0));
    }

    function canDetachTerms(bytes32, bytes32)
        public
        pure
        returns (bool ok, bytes32 reason)
    {
        return (true, bytes32(0));
    }

    function canLicense(
        bytes32 assetId,
        bytes32,
        address acquirer,
        bytes calldata,
        bytes32
    )
        public
        view
        returns (bool ok, bytes32 reason)
    {
        // Non-reverting on unknown ids: a missing asset simply isn't licensable.
        if (!_assets[assetId].exists) return (false, "asset-unknown");
        if (_assets[assetId].frozen) return (false, "asset-frozen");
        if (acquirer == address(0)) return (false, "zero-acquirer");
        return (true, bytes32(0));
    }

    function canRevoke(bytes32 agreementId, address caller, bytes32)
        public
        view
        returns (bool ok, bytes32 reason)
    {
        AgreementRecord storage g = _agreements[agreementId];
        if (!g.exists) return (false, "agreement-unknown");
        // Additional ordinary-revocation policy after mandatory owner authorization.
        if (caller == _ownerOfRecord(_assets[g.assetId])) {
            return (true, bytes32(0));
        }
        return (false, "not-authorized");
    }

    function canDerive(bytes32 parentAssetId, address deriver)
        public
        view
        returns (bool ok, bytes32 reason)
    {
        if (!_assets[parentAssetId].exists) return (false, "parent-unknown");
        if (deriver == address(0)) return (false, "zero-deriver");
        // Agreement activity alone cannot establish permission to derive. A
        // deployment that understands its terms schemas should override this.
        return (false, "policy-not-implemented");
    }

    // =====================================================================
    // 11. Administrative paths — admin-gated
    // =====================================================================

    function freezeAsset(bytes32 assetId, bytes32 reason) external {
        if (msg.sender != admin) revert NotAdmin();
        AssetRecord storage a = _requireAsset(assetId);
        a.frozen = true;
        emit AssetFrozen(assetId, msg.sender, reason);
    }

    function unfreezeAsset(bytes32 assetId, bytes32 reason) external {
        if (msg.sender != admin) revert NotAdmin();
        AssetRecord storage a = _requireAsset(assetId);
        a.frozen = false;
        emit AssetUnfrozen(assetId, msg.sender, reason);
    }

    function freezeAgreement(bytes32 agreementId, bytes32 reason) external {
        if (msg.sender != admin) revert NotAdmin();
        AgreementRecord storage g = _agreements[agreementId];
        if (!g.exists) revert AgreementUnknown();
        g.frozen = true;
        emit LicenseAgreementFrozen(agreementId, msg.sender, reason);
    }

    function unfreezeAgreement(bytes32 agreementId, bytes32 reason) external {
        if (msg.sender != admin) revert NotAdmin();
        AgreementRecord storage g = _agreements[agreementId];
        if (!g.exists) revert AgreementUnknown();
        g.frozen = false;
        emit LicenseAgreementUnfrozen(agreementId, msg.sender, reason);
    }

    // =====================================================================
    // 12. ERC-165
    // =====================================================================

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IERC165).interfaceId
            || interfaceId == type(IIPAssetRegistry).interfaceId
            || interfaceId == type(ITermsRegistry).interfaceId;
    }

    // =====================================================================
    // Derivation attestation signature verification (EIP-712)
    // =====================================================================

    function _verifyDerivation(
        bytes32 assetId,
        RegistrationParams calldata params,
        address registrant
    )
        private
        view
        returns (bool)
    {
        DerivationAttestation calldata att = params.derivationAttestation;
        bytes32 registrationHash = _registrationHash(params, registrant);
        if (att.registrationHash != registrationHash) return false;
        bytes32[] memory parentHashes = new bytes32[](att.parents.length);
        for (uint256 i; i < att.parents.length; ++i) {
            parentHashes[i] = keccak256(
                abi.encode(
                    PARENTREF_TYPEHASH,
                    att.parents[i].chainId,
                    att.parents[i].registry,
                    att.parents[i].assetId
                )
            );
        }
        bytes32 structHash = keccak256(
            abi.encode(
                DERIVATION_TYPEHASH,
                _chainId,
                address(this),
                assetId,
                registrationHash,
                keccak256(abi.encodePacked(parentHashes)),
                keccak256(att.metadata)
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", _domainSeparator, structHash));
        if (att.issuer.code.length != 0) {
            return _isValidContractSignature(att.issuer, digest, att.signature);
        }
        return _recover(digest, att.signature) == att.issuer;
    }

    /// @dev A failing, over-budget, or noncanonical ERC-1271 response is invalid.
    function _isValidContractSignature(address issuer, bytes32 digest, bytes calldata signature)
        private view returns (bool)
    {
        bytes memory callData = abi.encodeCall(IERC1271Min.isValidSignature, (digest, signature));
        uint256 gasLimit = ERC1271_SIGNATURE_QUERY_GAS;
        bool ok;
        uint256 returnSize;
        bytes32 result;
        assembly {
            let output := mload(0x40)
            mstore(output, 0)
            ok := staticcall(gasLimit, issuer, add(callData, 32), mload(callData), output, 32)
            returnSize := returndatasize()
            result := mload(output)
        }
        return ok && returnSize == 32
            && result == bytes32(uint256(uint32(IERC1271Min.isValidSignature.selector)) << 224);
    }

    function _registrationHash(RegistrationParams calldata params, address registrant)
        private
        pure
        returns (bytes32)
    {
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

    function _recover(bytes32 digest, bytes calldata sig) private pure returns (address) {
        if (sig.length != 65) revert BadSignatureLength();
        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := calldataload(sig.offset)
            s := calldataload(add(sig.offset, 32))
            v := byte(0, calldataload(add(sig.offset, 64)))
        }
        if (
            uint256(s) >
                0x7fffffffffffffffffffffffffffffff5d576e7357a4501ddfe92f46681b20a0
                || (v != 27 && v != 28)
        ) return address(0);
        return ecrecover(digest, v, r, s);
    }
}
