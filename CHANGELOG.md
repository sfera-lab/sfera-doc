# Changelog

## Unrelease

## Test
- added the following test for `SferaDoc.Cache.ParsedTemplate`
    - `get/2 returns :miss without crashing`
    - `put/3 is a no-op and returns :ok`
    - `invalidate/2 is a no-op and returns :ok`
    - `worker_spec/0 returns nil`
    - `worker_spec/0 returns a valid child spec`
    - `get/2 returns :miss for unknown key`
    - `put/3 and get/2 round-trip`
    - `put/3 overwrites existing entry for the same key`
    - `get/2 distinguishes different versions of the same template`
    - `get/2 distinguishes different template names with same version`
    - `invalidate/2 removes a specific entry`
    - `invalidate/2 is idempotent for missing keys`
    - `invalidate/2 does not affect other entries`
    - `get/2 returns :miss after TTL expires`
    - `get/2 returns hit when entry is within TTL`
    - `cache stores arbitrary term as AST`

### Refactored
- refactored `SferaDoc.Cache.ParsedTemplate`, deleting unecessary documentation, streamlining logic into seperate private functions

## [0.0.1] 2026-02-27

### Added
- Initial release of SferaDoc, a PDF generation library for Elixir
- Versioned Liquid template management with create, update, list, activate, and delete operations
- Template parsing with `solid` and ETS-based parsed template caching
- Chrome-based PDF rendering via `chromic_pdf`
- Pluggable template storage adapters: Ecto, Redis, and ETS
- Optional two-tier PDF storage: hot cache (Redis or ETS) plus durable object store (S3, Azure Blob, or file system)
- Required variable schema validation before rendering
- Telemetry events for render start, stop, and exception
