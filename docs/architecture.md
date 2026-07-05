# Architecture

PaisaTrack is organized as a local-first pipeline:

1. Native Android SMS capture filters and forwards candidate messages.
2. Dart capture code parses SMS into the normalized transaction record.
3. Intelligence enrichers resolve merchants, categories, recurring status, and insights.
4. Repositories persist records in encrypted SQLite.
5. Experience screens read only normalized/enriched records.

Raw SMS bodies are temporary capture inputs and must not appear in release logs,
network payloads, or unencrypted exports.
