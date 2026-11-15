# Maspice Sparkle feed

This branch hosts the shared HTTPS appcast for Maspice's stable and opt-in beta
channels. Archive URLs point to immutable GitHub release tags. Stable entries use
the default Sparkle channel; beta entries must carry `<sparkle:channel>beta</sparkle:channel>`.

The application release script updates this branch only after publishing release
assets. Keep integer build numbers increasing across both channels and preserve
archive Ed25519 signatures. The app defaults to stable updates.
