# SafeSphere Documentation Hub

Welcome to the SafeSphere Technical Documentation Hub. This directory contains the complete architectural, product, and API specifications for the SafeSphere enterprise monorepo.

---

## Document Index

1. **[Master PRD (`PRD.md`)](../PRD.md)** / **[Docs PRD (`docs/PRD.md`)](./PRD.md)**
   - The authoritative Product Requirements Document covering:
     - Section 1: Executive Summary & Core Mission
     - Section 2: User Personas & Detailed Use Cases (P1–P4, UC-1 to UC-9)
     - Section 3: Functional Specifications (SOS Siren, Live GPS, AI Copilot, Routing, Decay, Contacts)
     - Section 4: Non-Functional Specifications (Security, E2EE, Latency SLAs, WCAG AA, Offline)
     - Section 5: System Architecture & Component Diagrams (Mermaid architecture, Auth, SOS telemetry)
     - Section 6: OpenAPI 3.0.3 REST API Specifications & WebSocket Protocol
     - Section 7: Database Schemas (Mermaid ERD & Comprehensive Data Dictionary)
     - Section 8: Release Roadmap (Phases 1–4)

2. **[System Architecture (`docs/ARCHITECTURE.md`)](./ARCHITECTURE.md)**
   - Comprehensive technical architecture documentation detailing:
     - High-level multi-tier architecture and monorepo topology
     - Frontend Flutter structure, state management, and route guards
     - Backend Node.js Express layered architecture and middleware
     - Real-time WebSocket telemetry pipeline and Redis pub/sub
     - Spatial engine and Haversine distance calculations
     - Root monorepo automation scripts (`npm run dev`, `npm test`, `npm run clean`)

3. **[API Specification (`docs/API_SPEC.md`)](./API_SPEC.md)**
   - Detailed endpoint contracts for:
     - Authentication (`/api/v1/auth/*`)
     - Emergency SOS Alerts (`/api/v1/sos/*`)
     - Incident Reports (`/api/v1/reports/*`)
     - Safety Markers (`/api/v1/markers/*`)
     - Real-Time WebSocket Channel (`/ws/sos`)

4. **[Shared Contracts (`shared/contracts/api_contracts.json`)](../shared/contracts/api_contracts.json)**
   - Machine-readable OpenAPI 3.0/3.1 contract schema for cross-tier consumption.

---
*SafeSphere Documentation Hub — Maintained by the SafeSphere Engineering Team.*
