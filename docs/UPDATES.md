# Sparkle update channels

New Maspice versions use `appcast.xml` on the dedicated `codex/update-feed` branch as
their fixed HTTPS feed. Sparkle's default channel is stable. **Settings → Updates
→ Receive beta updates** is off by default, including in manually installed beta
builds. Enabling it additionally allows the `beta` channel. Changing the setting
resets Sparkle's update cycle; it does not start an installer or enable downgrades.

Maspice 0.6.1 and older retain their existing
`releases/latest/download/appcast.xml` feed. Beta releases are marked prerelease
and `latest=false`, so those installations continue to see stable updates only.
The first beta installation is a manual download.

Stable releases run on `main`; betas run on `codex/beta-X.Y.Z`.
`SIGN_IDENTITY` selects a Developer ID Application identity; `NOTARY_PROFILE`
selects a notarytool Keychain profile. With both configured, the release script
notarizes and staples the app before generating its final archive signature.

`scripts/release.sh X.Y.Z[-beta.N]` builds the archive, signs it with the existing
Sparkle Keychain account, merges its entry with the published feed, and uploads the app,
checksum and appcast to its immutable GitHub release tag. It updates that
feed branch **after** the release assets have been published. Stable and beta builds use
strictly increasing integer build numbers; the next stable release therefore also
updates beta installations. The bundle's numeric marketing version remains in
`CFBundleShortVersionString`; `MaspiceReleaseVersion` and the appcast display the
full beta label.

`scripts/update-appcast.py` rejects beta entries without a `beta` channel,
backwards build numbers, mismatched tag URLs and replacement archives for an
existing build. It preserves archive Ed25519 signatures and stable entries.
The feed itself is not signed; archives are signed and verified by Sparkle before
extraction. Do not edit or replace a published archive under an existing tag.

Run `python3 -B scripts/test-update-appcast.py` for the offline publication checks.
The Swift tests also verify default-channel behavior and persistent beta opt-in
against an unstarted Sparkle updater, without network or installer activity.
