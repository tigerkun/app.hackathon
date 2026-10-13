# SafeSphere Shared Contracts & Schemas

This directory houses the single source of truth for cross-tier data contracts between the SafeSphere backend (FastAPI), Flutter mobile client, and web preview client.

## Directory Structure
- `contracts/api_contracts.json`: Standardized OpenAPI 3.1.0 specifications for all REST endpoints, WebSocket streaming, authentication flows, and data payloads.
- `types/`: Strongly-typed schema definitions in TypeScript for web/mobile client consumers:
  - `auth.ts`: User credentials, tokens, emergency contacts, session state, biometrics, PINs.
  - `reports.ts`: Geo-tagged incident report creation, statuses, categories, queries.
  - `sos.ts`: Emergency SOS triggers, cancellation with mandatory PIN verification, live status.
  - `markers.ts`: Verified safe zones, police stations, hospitals, and Haversine distance proximity query types.
