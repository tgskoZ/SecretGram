# Releases

## Distribution model

SecretGram uses GitHub Releases and Telegram as complementary official Stable distribution channels.

- **Canonical Stable release page and IPA asset:** [GitHub Releases](https://github.com/jerkgram/Jerkgram-iOS/releases)
- **Stable announcements and Telegram distribution:** [@SecretGramApp](https://t.me/JerkgramApp)
- **Public Stable source:** `secretgram/SecretGram-iOS`
- **Beta discussion and feedback:** [@SecretGramCommunity](https://t.me/JerkgramCommunity)
- **Product/download entry point:** [secretgram.github.io](https://jerkgram.github.io/)
- **AltStore Classic + SideStore source:** [`https://jerkgram.github.io/altstore-source.json`](https://jerkgram.github.io/altstore-source.json)
- **Canonical/mirror metadata:** [`https://jerkgram.github.io/mirrors.json`](https://jerkgram.github.io/mirrors.json)

The GitHub Release for a Stable version is the canonical public release page for that version. It should contain or link to the Stable IPA, release notes, release provenance and the corresponding public source tag/snapshot.

The SecretGram website may expose two separate actions:

- **Download IPA** — direct link to the IPA asset attached to the matching GitHub Release;
- **View on GitHub** — link to the full GitHub Release page.

Telegram remains an official release channel rather than a replacement for the GitHub release record.

AltStore Classic and SideStore are installation/update channels over the same canonical GitHub Release IPA. Both consume one `altstore-source.json`; SecretGram does not maintain a separate SideStore source. The source metadata must point to the exact GitHub Release asset rather than a copy stored in the website repository.

`mirrors.json` records GitHub Releases as canonical. A future verified mirror must serve a byte-identical IPA with the same SHA-256; third-party catalogs are not official mirrors merely because they redistribute SecretGram.

## Stable release record

Each Stable release should publish or reference:

```text
SecretGram version
Public source tag
Telegram upstream tag
Telegram upstream commit
Stable IPA filename
Stable IPA SHA-256
Source archive filename
Source archive SHA-256
Source manifest
Release notes
```

`SECRETGRAM_RELEASE.json` is the machine-readable provenance record for the current Stable source snapshot.

## Naming

Recommended release naming:

```text
Git tag          v<VERSION>
GitHub release   SecretGram <VERSION>
IPA              SecretGram-<VERSION>.ipa
Source archive   SecretGram-<VERSION>-source.tar.xz
Manifest         public-source-manifest.json
```

The IPA asset name should stay predictable within a release so the website can link directly to it without presenting GitHub's release page as an intermediate download step.

## Stable release checklist

The detailed operator checklist and copy-ready GitHub Release body live in [`RELEASE_TEMPLATE.md`](RELEASE_TEMPLATE.md).

Before a release is marked Stable:

1. freeze the exact final public source snapshot;
2. verify the source manifest;
3. compute the Stable IPA and source archive SHA-256 values;
4. complete `SECRETGRAM_RELEASE.json`;
5. create the matching public source tag;
6. create the GitHub Release for that tag;
7. attach the Stable IPA and source artifacts;
8. publish release notes and provenance;
9. update `secretgram.github.io/latest.json` with the exact version, build, release URL, IPA URL, filename, byte size, SHA-256, minimum iOS, source tag/source URL and release date;
10. populate `secretgram.github.io/altstore-source.json` from the exact final IPA metadata, including the real bundle identifier, version/build, minimum OS and complete `appPermissions`;
11. update the canonical block in `secretgram.github.io/mirrors.json` while leaving `mirrors` empty unless a mirror has actually been verified;
12. verify the website, release record, Telegram announcement and every verified mirror publish the same IPA SHA-256;
13. validate the AltStore source and test the same source in SideStore;
14. verify no `.ipa` copy exists in `secretgram.github.io`;
15. announce the same Stable version through [@SecretGramApp](https://t.me/JerkgramApp).

## Current Stable

SecretGram 1.0.2 is the current Stable release.

- **Canonical release:** [SecretGram 1.0.2](https://github.com/jerkgram/Jerkgram-iOS/releases/tag/v1.0.2)
- **Canonical source tag:** `v1.0.2`
- **Canonical IPA:** `SecretGram-1.0.2.ipa`, attached to the GitHub Release above
- **Exact artifact hashes and provenance:** [`SECRETGRAM_RELEASE.json`](../SECRETGRAM_RELEASE.json)
