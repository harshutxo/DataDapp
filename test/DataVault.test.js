const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("DataVault", function () {
  const contentURI = "ipfs://bafy-encrypted-content";
  const metadataURI = "ipfs://bafy-encrypted-metadata";
  const contentHash = ethers.keccak256(ethers.toUtf8Bytes("ciphertext"));
  const metadataHash = ethers.keccak256(ethers.toUtf8Bytes("metadata"));
  const keyEnvelopeURI = "ipfs://bafy-key-envelope-for-alice";
  const keyEnvelopeHash = ethers.keccak256(ethers.toUtf8Bytes("wrapped-key"));

  async function deployVault() {
    const [owner, alice, bob] = await ethers.getSigners();
    const DataVault = await ethers.getContractFactory("DataVault");
    const vault = await DataVault.deploy("Private Data Vault", "PDV");
    await vault.waitForDeployment();
    return { vault, owner, alice, bob };
  }

  async function mintRecord(vault) {
    await vault.createDataToken(contentURI, contentHash, metadataURI, metadataHash, 1024);
    return 1n;
  }

  it("tokenizes encrypted data pointers", async function () {
    const { vault, owner } = await deployVault();

    await expect(vault.createDataToken(contentURI, contentHash, metadataURI, metadataHash, 1024))
      .to.emit(vault, "DataTokenCreated")
      .withArgs(1, owner.address, contentURI, contentHash, metadataURI, metadataHash);

    expect(await vault.ownerOf(1)).to.equal(owner.address);
    expect(await vault.tokenURI(1)).to.equal(metadataURI);
  });

  it("lets the owner grant and revoke access", async function () {
    const { vault, alice } = await deployVault();
    const tokenId = await mintRecord(vault);
    const expiresAt = BigInt((await ethers.provider.getBlock("latest")).timestamp + 3600);

    await vault.grantAccess(tokenId, alice.address, keyEnvelopeURI, keyEnvelopeHash, expiresAt);
    expect(await vault.hasAccess(tokenId, alice.address)).to.equal(true);

    const grant = await vault.connect(alice).getAccessGrant(tokenId, alice.address);
    expect(grant.keyEnvelopeURI).to.equal(keyEnvelopeURI);
    expect(grant.keyEnvelopeHash).to.equal(keyEnvelopeHash);

    await vault.revokeAccess(tokenId, alice.address);
    expect(await vault.hasAccess(tokenId, alice.address)).to.equal(false);
  });

  it("invalidates old grants when data is updated", async function () {
    const { vault, alice } = await deployVault();
    const tokenId = await mintRecord(vault);

    await vault.grantAccess(tokenId, alice.address, keyEnvelopeURI, keyEnvelopeHash, 0);
    expect(await vault.hasAccess(tokenId, alice.address)).to.equal(true);

    await vault.updateDataToken(
      tokenId,
      "ipfs://bafy-new-content",
      ethers.keccak256(ethers.toUtf8Bytes("new-ciphertext")),
      "ipfs://bafy-new-metadata",
      ethers.keccak256(ethers.toUtf8Bytes("new-metadata")),
      2048
    );

    expect(await vault.hasAccess(tokenId, alice.address)).to.equal(false);
  });

  it("invalidates grants when ownership transfers", async function () {
    const { vault, owner, alice, bob } = await deployVault();
    const tokenId = await mintRecord(vault);

    await vault.grantAccess(tokenId, alice.address, keyEnvelopeURI, keyEnvelopeHash, 0);
    expect(await vault.hasAccess(tokenId, alice.address)).to.equal(true);

    await vault.transferFrom(owner.address, bob.address, tokenId);

    expect(await vault.ownerOf(tokenId)).to.equal(bob.address);
    expect(await vault.hasAccess(tokenId, owner.address)).to.equal(false);
    expect(await vault.hasAccess(tokenId, alice.address)).to.equal(false);
    expect(await vault.hasAccess(tokenId, bob.address)).to.equal(true);
  });

  it("prevents non-owners from mutating data and access", async function () {
    const { vault, alice } = await deployVault();
    const tokenId = await mintRecord(vault);

    await expect(
      vault.connect(alice).updateDataToken(tokenId, contentURI, contentHash, metadataURI, metadataHash, 1)
    ).to.be.revertedWithCustomError(vault, "NotTokenOwner");

    await expect(
      vault.connect(alice).grantAccess(tokenId, alice.address, keyEnvelopeURI, keyEnvelopeHash, 0)
    ).to.be.revertedWithCustomError(vault, "NotTokenOwner");
  });

  it("freezes records against future pointer changes", async function () {
    const { vault } = await deployVault();
    const tokenId = await mintRecord(vault);

    await vault.freezeDataToken(tokenId);

    await expect(
      vault.updateDataToken(tokenId, contentURI, contentHash, metadataURI, metadataHash, 1)
    ).to.be.revertedWithCustomError(vault, "FrozenRecord");
  });
});
