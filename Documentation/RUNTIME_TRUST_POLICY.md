# Automatic runtime trust policy

Automatic integrations: PCSX2 (PCSX2/pcsx2), RPCS3 (RPCS3/rpcs3-binaries-mac-arm64), shadPS4 (shadps4-emu/shadPS4), Vita3K (Vita3K/Vita3K), Azahar (azahar-emu/azahar), Cemu (cemu-project/Cemu), xemu (xemu-project/xemu), Flycast (flyinghead/flycast). Other catalog integrations have no automatic third-party/mirror download route. The executable policy is Sources/AkitoStationCore/RuntimeTrust.swift and catalog definitions, not arbitrary user repository input.

Each automatic request must match the catalog repository, exact release page/tag, listed asset object/ID/URL/name/size, macOS filename policy and ZIP format. HTTPS redirects allow only github.com, release-assets.githubusercontent.com and objects.githubusercontent.com; credentials/ports are rejected. Metadata redirects are refused. Native/Universal app architecture and recognized catalog identity are verified before activation. Download bytes, disk staging, archive CRC/size and complete app fingerprints are checked; failed activation retains the previous selection. Ad-hoc signatures establish no publisher identity.

Official SHA-256 API digests are verified when supplied. If absent, recognized official .sha256/.sha256sum/SHA256SUMS/checksums.txt sidecars are downloaded through the same repository/domain policy, bounded to 1 MiB, and must identify exactly one matching filename/digest. Ambiguous, malformed or mismatched checksums fail closed. This does not authenticate a publisher independently of a compromised upstream account. Unsupported checksum/signature formats still require an explicitly reviewed provider policy before claiming they are covered.

Status meanings:

* Verified Publisher: strict deep signature plus independently established pinned Team ID.
* Verified Checksum: bytes match an official SHA-256 digest. This is not publisher-signature certification.
* Official Source / Unsigned: approved upstream transport/asset with no trusted publisher signature, including ad-hoc-only signing. Legitimate unsigned projects remain supported.
* Official Source / Publisher Unverified: signature verifies but no trusted publisher baseline is pinned.
* User Imported: user-selected catalog installation. Signature details remain visible without implying Akito trusts its publisher.
* Custom External: user-owned custom registration.
* Unverified: legacy/no recorded trust state. Relink to refresh it.

No Team IDs were invented or pinned from a random installed app. Stable signed publisher baselines for these integrations remain to be independently established/reviewed. Until then **Verified Publisher is not shown for automatic releases**. PCSX2’s official release announcement says macOS releases now open normally, but supplies no Team ID baseline: [upstream announcement](https://pcsx2.net/blog/2025/pcsx2-2.4_2.2/). Upstream identity evidence and current real assets must be reviewed before clearing B8. GitHub commit signatures are not executable publisher signatures.

Source policy, checksum/tampering tests and full nested fingerprints improve enforcement; they do not resolve compromised-official-account provenance without independently trusted publisher/signature evidence. B8 remains PARTIAL.
