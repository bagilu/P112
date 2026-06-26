# Supabase Functions Reference

P112 V1 does not require Supabase Edge Functions.

All required server-side logic is implemented as SQL RPC functions in:

```text
sql/p112_schema.sql
```

This folder is intentionally left as a reference placeholder for future V2/V3 extensions.

Potential future functions:

- Gmail/Drive integration for photo confirmation
- Display-device token registration
- Scheduled absence detection
- Standby replacement notification

The user requested Dashboard/manual code deployment rather than CLI or `npx deploy`; therefore no deployable Edge Function is included in V1.
