// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title DataVault
/// @notice Tokenizes encrypted user data as transferable ERC-721 records.
/// @dev Store only encrypted content pointers and hashes on-chain. Never store raw user data or plaintext keys.
contract DataVault {
    struct DataRecord {
        address creator;
        string contentURI;
        bytes32 contentHash;
        string metadataURI;
        bytes32 metadataHash;
        uint256 sizeBytes;
        uint64 createdAt;
        uint64 updatedAt;
        uint64 accessVersion;
        bool frozen;
    }

    struct AccessGrant {
        string keyEnvelopeURI;
        bytes32 keyEnvelopeHash;
        uint64 expiresAt;
        uint64 version;
        bool revoked;
    }

    error NotTokenOwner();
    error NotApprovedOrOwner();
    error TokenDoesNotExist();
    error TokenAlreadyExists();
    error ZeroAddress();
    error EmptyURI();
    error EmptyHash();
    error FrozenRecord();
    error InvalidExpiry();
    error TransferToNonReceiver();

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);
    event DataTokenCreated(
        uint256 indexed tokenId,
        address indexed owner,
        string contentURI,
        bytes32 contentHash,
        string metadataURI,
        bytes32 metadataHash
    );
    event DataTokenUpdated(
        uint256 indexed tokenId,
        string contentURI,
        bytes32 contentHash,
        string metadataURI,
        bytes32 metadataHash,
        uint64 accessVersion
    );
    event DataTokenFrozen(uint256 indexed tokenId);
    event AccessGranted(
        uint256 indexed tokenId,
        address indexed grantee,
        string keyEnvelopeURI,
        bytes32 keyEnvelopeHash,
        uint64 expiresAt,
        uint64 accessVersion
    );
    event AccessRevoked(uint256 indexed tokenId, address indexed grantee, uint64 accessVersion);

    string public name;
    string public symbol;

    uint256 private _nextTokenId = 1;
    uint256 private _locked = 1;

    mapping(uint256 => DataRecord) private _records;
    mapping(uint256 => address) private _owners;
    mapping(address => uint256) private _balances;
    mapping(uint256 => address) private _tokenApprovals;
    mapping(address => mapping(address => bool)) private _operatorApprovals;
    mapping(uint256 => mapping(address => AccessGrant)) private _accessGrants;

    modifier nonReentrant() {
        require(_locked == 1, "REENTRANCY");
        _locked = 2;
        _;
        _locked = 1;
    }

    modifier onlyExisting(uint256 tokenId) {
        if (!_exists(tokenId)) revert TokenDoesNotExist();
        _;
    }

    modifier onlyOwnerOf(uint256 tokenId) {
        if (ownerOf(tokenId) != msg.sender) revert NotTokenOwner();
        _;
    }

    constructor(string memory collectionName, string memory collectionSymbol) {
        name = collectionName;
        symbol = collectionSymbol;
    }

    function createDataToken(
        string calldata contentURI,
        bytes32 contentHash,
        string calldata metadataURI,
        bytes32 metadataHash,
        uint256 sizeBytes
    ) external nonReentrant returns (uint256 tokenId) {
        _validatePointer(contentURI, contentHash);
        _validatePointer(metadataURI, metadataHash);

        tokenId = _nextTokenId++;
        _mint(msg.sender, tokenId);

        _records[tokenId] = DataRecord({
            creator: msg.sender,
            contentURI: contentURI,
            contentHash: contentHash,
            metadataURI: metadataURI,
            metadataHash: metadataHash,
            sizeBytes: sizeBytes,
            createdAt: uint64(block.timestamp),
            updatedAt: uint64(block.timestamp),
            accessVersion: 1,
            frozen: false
        });

        emit DataTokenCreated(tokenId, msg.sender, contentURI, contentHash, metadataURI, metadataHash);
    }

    function updateDataToken(
        uint256 tokenId,
        string calldata contentURI,
        bytes32 contentHash,
        string calldata metadataURI,
        bytes32 metadataHash,
        uint256 sizeBytes
    ) external onlyExisting(tokenId) onlyOwnerOf(tokenId) {
        DataRecord storage record = _records[tokenId];
        if (record.frozen) revert FrozenRecord();
        _validatePointer(contentURI, contentHash);
        _validatePointer(metadataURI, metadataHash);

        record.contentURI = contentURI;
        record.contentHash = contentHash;
        record.metadataURI = metadataURI;
        record.metadataHash = metadataHash;
        record.sizeBytes = sizeBytes;
        record.updatedAt = uint64(block.timestamp);
        record.accessVersion += 1;

        emit DataTokenUpdated(tokenId, contentURI, contentHash, metadataURI, metadataHash, record.accessVersion);
    }

    function freezeDataToken(uint256 tokenId) external onlyExisting(tokenId) onlyOwnerOf(tokenId) {
        _records[tokenId].frozen = true;
        emit DataTokenFrozen(tokenId);
    }

    function grantAccess(
        uint256 tokenId,
        address grantee,
        string calldata keyEnvelopeURI,
        bytes32 keyEnvelopeHash,
        uint64 expiresAt
    ) external onlyExisting(tokenId) onlyOwnerOf(tokenId) {
        if (grantee == address(0)) revert ZeroAddress();
        if (bytes(keyEnvelopeURI).length == 0) revert EmptyURI();
        if (keyEnvelopeHash == bytes32(0)) revert EmptyHash();
        if (expiresAt != 0 && expiresAt <= block.timestamp) revert InvalidExpiry();

        uint64 version = _records[tokenId].accessVersion;
        _accessGrants[tokenId][grantee] = AccessGrant({
            keyEnvelopeURI: keyEnvelopeURI,
            keyEnvelopeHash: keyEnvelopeHash,
            expiresAt: expiresAt,
            version: version,
            revoked: false
        });

        emit AccessGranted(tokenId, grantee, keyEnvelopeURI, keyEnvelopeHash, expiresAt, version);
    }

    function revokeAccess(uint256 tokenId, address grantee) external onlyExisting(tokenId) onlyOwnerOf(tokenId) {
        AccessGrant storage grant = _accessGrants[tokenId][grantee];
        grant.revoked = true;
        emit AccessRevoked(tokenId, grantee, _records[tokenId].accessVersion);
    }

    function getDataRecord(uint256 tokenId) external view onlyExisting(tokenId) returns (DataRecord memory) {
        return _records[tokenId];
    }

    function getAccessGrant(uint256 tokenId, address grantee)
        external
        view
        onlyExisting(tokenId)
        returns (AccessGrant memory)
    {
        if (msg.sender != grantee && msg.sender != ownerOf(tokenId)) revert NotApprovedOrOwner();
        return _accessGrants[tokenId][grantee];
    }

    function hasAccess(uint256 tokenId, address account) public view onlyExisting(tokenId) returns (bool) {
        if (account == ownerOf(tokenId)) return true;

        AccessGrant memory grant = _accessGrants[tokenId][account];
        if (grant.revoked) return false;
        if (grant.version != _records[tokenId].accessVersion) return false;
        if (grant.expiresAt != 0 && grant.expiresAt <= block.timestamp) return false;

        return bytes(grant.keyEnvelopeURI).length != 0;
    }

    function tokenURI(uint256 tokenId) external view onlyExisting(tokenId) returns (string memory) {
        return _records[tokenId].metadataURI;
    }

    function balanceOf(address owner) public view returns (uint256) {
        if (owner == address(0)) revert ZeroAddress();
        return _balances[owner];
    }

    function ownerOf(uint256 tokenId) public view returns (address owner) {
        owner = _owners[tokenId];
        if (owner == address(0)) revert TokenDoesNotExist();
    }

    function approve(address to, uint256 tokenId) external onlyExisting(tokenId) {
        address owner = ownerOf(tokenId);
        if (msg.sender != owner && !isApprovedForAll(owner, msg.sender)) revert NotApprovedOrOwner();

        _tokenApprovals[tokenId] = to;
        emit Approval(owner, to, tokenId);
    }

    function getApproved(uint256 tokenId) public view onlyExisting(tokenId) returns (address) {
        return _tokenApprovals[tokenId];
    }

    function setApprovalForAll(address operator, bool approved) external {
        if (operator == address(0)) revert ZeroAddress();
        _operatorApprovals[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }

    function isApprovedForAll(address owner, address operator) public view returns (bool) {
        return _operatorApprovals[owner][operator];
    }

    function transferFrom(address from, address to, uint256 tokenId) public nonReentrant onlyExisting(tokenId) {
        if (!_isApprovedOrOwner(msg.sender, tokenId)) revert NotApprovedOrOwner();
        _transfer(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) external {
        safeTransferFrom(from, to, tokenId, "");
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data) public {
        transferFrom(from, to, tokenId);
        if (!_checkOnERC721Received(msg.sender, from, to, tokenId, data)) revert TransferToNonReceiver();
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == 0x01ffc9a7 || interfaceId == 0x80ac58cd || interfaceId == 0x5b5e139f;
    }

    function _mint(address to, uint256 tokenId) private {
        if (to == address(0)) revert ZeroAddress();
        if (_exists(tokenId)) revert TokenAlreadyExists();

        _balances[to] += 1;
        _owners[tokenId] = to;
        emit Transfer(address(0), to, tokenId);
    }

    function _transfer(address from, address to, uint256 tokenId) private {
        if (ownerOf(tokenId) != from) revert NotTokenOwner();
        if (to == address(0)) revert ZeroAddress();

        delete _tokenApprovals[tokenId];
        _balances[from] -= 1;
        _balances[to] += 1;
        _owners[tokenId] = to;

        DataRecord storage record = _records[tokenId];
        record.updatedAt = uint64(block.timestamp);
        record.accessVersion += 1;

        emit Transfer(from, to, tokenId);
    }

    function _exists(uint256 tokenId) private view returns (bool) {
        return _owners[tokenId] != address(0);
    }

    function _isApprovedOrOwner(address spender, uint256 tokenId) private view returns (bool) {
        address owner = ownerOf(tokenId);
        return spender == owner || getApproved(tokenId) == spender || isApprovedForAll(owner, spender);
    }

    function _validatePointer(string calldata uri, bytes32 hashValue) private pure {
        if (bytes(uri).length == 0) revert EmptyURI();
        if (hashValue == bytes32(0)) revert EmptyHash();
    }

    function _checkOnERC721Received(
        address operator,
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    ) private returns (bool) {
        if (to.code.length == 0) return true;

        try IERC721Receiver(to).onERC721Received(operator, from, tokenId, data) returns (bytes4 retval) {
            return retval == IERC721Receiver.onERC721Received.selector;
        } catch {
            return false;
        }
    }
}

interface IERC721Receiver {
    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data)
        external
        returns (bytes4);
}
