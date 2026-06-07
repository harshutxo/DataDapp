# DataDapp

DataDapp is a secure Solidity foundation for a decentralized private-cloud style data storage system.

The important design rule is simple: **do not put private user data on-chain**. The blockchain tokenizes and controls encrypted data references, while the actual encrypted files live in decentralized storage such as IPFS, Filecoin, Arweave, or another content-addressed storage network.

## Architecture

1. The client encrypts user data locally.
2. The encrypted blob is uploaded to decentralized storage.
3. The client stores the encrypted blob URI and integrity hash in `DataVault`.
4. The contract mints an ERC-721 compatible token representing ownership of that encrypted data object.
5. Access is granted by storing a URI/hash for an encrypted key envelope, never the plaintext key.
6. Updating or transferring a data token increments the access version, invalidating older grants.

## Security Model

- Raw user data is never stored in Solidity state or events.
- Plaintext encryption keys are never stored on-chain.
- Every content pointer has a `bytes32` integrity hash.
- Only token owners can update data pointers, freeze records, grant access, or revoke access.
- Existing access grants are invalidated when data is updated or the token is transferred.
- Frozen records cannot be changed after the owner locks them.
- ERC-721 approvals are cleared during transfer.
- `safeTransferFrom` checks ERC-721 receiver compatibility.
- A small reentrancy guard protects mint and transfer flows.

## Contract

The main contract is:

- `contracts/DataVault.sol`

It exposes these core functions:

- `createDataToken(...)`: mint a tokenized encrypted data record.
- `updateDataToken(...)`: update encrypted content and metadata pointers.
- `freezeDataToken(...)`: permanently lock the record pointers.
- `grantAccess(...)`: grant another address access to a wrapped-key envelope.
- `revokeAccess(...)`: revoke a previously granted account.
- `hasAccess(...)`: check whether an address has current access.
- `getDataRecord(...)`: read the public encrypted-data record metadata.
- `getAccessGrant(...)`: read a grant as either the token owner or the grantee.

## Install

```bash
npm install
```

## Compile

```bash
npm run compile
```

If Hardhat cannot download compiler metadata in a restricted network, use the local JavaScript compiler:

```bash
npm run compile:local
```

## Test

```bash
npm test
```

## Deploy

For a local Hardhat node:

```bash
npm run deploy
```

For a live EVM-compatible network, set `RPC_URL` and `PRIVATE_KEY`, then run:

```bash
npm run deploy -- --network target
```

Keep the private key out of git. Use a funded deployer wallet dedicated to deployment.

## Client Responsibilities

The smart contract provides ownership and authorization. A production client should also:

- Encrypt files locally with AES-GCM or XChaCha20-Poly1305.
- Generate a unique symmetric key per data object.
- Wrap the symmetric key for each grantee using the grantee's public key.
- Upload encrypted data and encrypted key envelopes to decentralized storage.
- Pin or replicate content to avoid data loss.
- Verify downloaded ciphertext against the on-chain hash before decryption.

## Production Notes

Before mainnet deployment, run a professional smart-contract audit, add deployment scripts for your target chain, and consider using audited OpenZeppelin ERC-721 contracts if your build pipeline allows external dependencies.
