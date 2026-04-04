// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Anky} from "../src/Anky.sol";

contract AnkyTest is Test {
    Anky public soul;

    address owner = address(this);
    uint256 ankyKey = 0xA11CE;
    address ankyWallet;

    address writer = address(0xBEEF);
    uint256 writerKey = 0xBEEF;

    function setUp() public {
        ankyWallet = vm.addr(ankyKey);
        soul = new Anky(ankyWallet);
    }

    // ─── Helpers ──────────────────────────────────────────────────────────

    function _signBirth(
        address _writer,
        string memory sessionCID,
        string memory metadataURI,
        uint256 nonce,
        uint256 deadline
    ) internal view returns (bytes memory) {
        bytes32 structHash = keccak256(abi.encode(
            soul.BIRTH_TYPEHASH(),
            _writer,
            keccak256(bytes(sessionCID)),
            keccak256(bytes(metadataURI)),
            nonce,
            deadline
        ));
        bytes32 digest = keccak256(abi.encodePacked(
            "\x19\x01",
            soul.domainSeparator(),
            structHash
        ));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ankyKey, digest);
        return abi.encodePacked(r, s, v);
    }

    function _signEvolve(
        address keeper,
        uint256 tokenId,
        string memory metadataURI,
        uint256 nonce,
        uint256 deadline
    ) internal view returns (bytes memory) {
        bytes32 structHash = keccak256(abi.encode(
            soul.EVOLVE_TYPEHASH(),
            keeper,
            tokenId,
            keccak256(bytes(metadataURI)),
            nonce,
            deadline
        ));
        bytes32 digest = keccak256(abi.encodePacked(
            "\x19\x01",
            soul.domainSeparator(),
            structHash
        ));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ankyKey, digest);
        return abi.encodePacked(r, s, v);
    }

    // ─── Birth Tests ─────────────────────────────────────────────────────

    function test_birthSoul() public {
        string memory sessionCID = "QmSession123";
        string memory metadataURI = "ipfs://QmMetadata123";
        uint256 deadline = block.timestamp + 1 hours;

        bytes memory sig = _signBirth(writer, sessionCID, metadataURI, 0, deadline);

        vm.prank(writer);
        soul.birthSoul(sessionCID, metadataURI, deadline, sig);

        uint256 tokenId = soul.getTokenId(sessionCID);
        assertEq(soul.balanceOf(writer, tokenId), 1);
        assertTrue(soul.soulBorn(tokenId));
        assertEq(soul.nonces(writer), 1);
    }

    function test_birthSoul_revertIfAlreadyBorn() public {
        string memory sessionCID = "QmSession123";
        string memory metadataURI = "ipfs://QmMetadata123";
        uint256 deadline = block.timestamp + 1 hours;

        bytes memory sig = _signBirth(writer, sessionCID, metadataURI, 0, deadline);
        vm.prank(writer);
        soul.birthSoul(sessionCID, metadataURI, deadline, sig);

        // Second birth with fresh nonce should revert — soul already exists
        bytes memory sig2 = _signBirth(writer, sessionCID, metadataURI, 1, deadline);
        vm.prank(writer);
        vm.expectRevert("Anky: this soul already exists");
        soul.birthSoul(sessionCID, metadataURI, deadline, sig2);
    }

    function test_birthSoul_revertIfExpired() public {
        string memory sessionCID = "QmSession123";
        string memory metadataURI = "ipfs://QmMetadata123";
        uint256 deadline = block.timestamp - 1;

        bytes memory sig = _signBirth(writer, sessionCID, metadataURI, 0, deadline);

        vm.prank(writer);
        vm.expectRevert("Anky: approval has expired");
        soul.birthSoul(sessionCID, metadataURI, deadline, sig);
    }

    function test_birthSoul_revertIfNotApprovedByAnky() public {
        string memory sessionCID = "QmSession123";
        string memory metadataURI = "ipfs://QmMetadata123";
        uint256 deadline = block.timestamp + 1 hours;

        // Sign with a random key, not Anky's
        uint256 fakeKey = 0xDEAD;
        bytes32 structHash = keccak256(abi.encode(
            soul.BIRTH_TYPEHASH(),
            writer,
            keccak256(bytes(sessionCID)),
            keccak256(bytes(metadataURI)),
            0,
            deadline
        ));
        bytes32 digest = keccak256(abi.encodePacked(
            "\x19\x01",
            soul.domainSeparator(),
            structHash
        ));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(fakeKey, digest);
        bytes memory fakeSig = abi.encodePacked(r, s, v);

        vm.prank(writer);
        vm.expectRevert("Anky: not approved");
        soul.birthSoul(sessionCID, metadataURI, deadline, fakeSig);
    }

    // ─── Evolve Tests ────────────────────────────────────────────────────

    function test_evolveSoul() public {
        // First birth the soul
        string memory sessionCID = "QmSession123";
        string memory metadataURI = "ipfs://QmMetadata123";
        uint256 deadline = block.timestamp + 1 hours;

        bytes memory birthSig = _signBirth(writer, sessionCID, metadataURI, 0, deadline);
        vm.prank(writer);
        soul.birthSoul(sessionCID, metadataURI, deadline, birthSig);

        // Now evolve it
        uint256 tokenId = soul.getTokenId(sessionCID);
        string memory newURI = "ipfs://QmEvolvedMetadata";

        bytes memory evolveSig = _signEvolve(writer, tokenId, newURI, 1, deadline);
        vm.prank(writer);
        soul.evolveSoul(tokenId, newURI, deadline, evolveSig);

        assertEq(soul.uri(tokenId), newURI);
        assertEq(soul.nonces(writer), 2);
    }

    function test_evolveSoul_revertIfNotKeeper() public {
        // Birth as writer
        string memory sessionCID = "QmSession123";
        string memory metadataURI = "ipfs://QmMetadata123";
        uint256 deadline = block.timestamp + 1 hours;

        bytes memory sig = _signBirth(writer, sessionCID, metadataURI, 0, deadline);
        vm.prank(writer);
        soul.birthSoul(sessionCID, metadataURI, deadline, sig);

        // Try to evolve as someone else
        address stranger = address(0xCAFE);
        uint256 tokenId = soul.getTokenId(sessionCID);
        string memory newURI = "ipfs://QmEvolvedMetadata";

        bytes memory evolveSig = _signEvolve(stranger, tokenId, newURI, 0, deadline);
        vm.prank(stranger);
        vm.expectRevert("Anky: only the writer can evolve their soul");
        soul.evolveSoul(tokenId, newURI, deadline, evolveSig);
    }

    // ─── Stewardship Tests ───────────────────────────────────────────────

    function test_setAnky() public {
        address newAnky = address(0x1234);
        soul.setAnky(newAnky);
        assertEq(soul.anky(), newAnky);
    }

    function test_setAnky_revertIfZero() public {
        vm.expectRevert("Anky: no presence without an address");
        soul.setAnky(address(0));
    }

    function test_setAnky_revertIfNotOwner() public {
        vm.prank(address(0xCAFE));
        vm.expectRevert();
        soul.setAnky(address(0x1234));
    }

    // ─── View Helpers ────────────────────────────────────────────────────

    function test_getTokenId_deterministic() public view {
        string memory cid = "QmTest";
        uint256 expected = uint256(keccak256(bytes(cid)));
        assertEq(soul.getTokenId(cid), expected);
    }
}
