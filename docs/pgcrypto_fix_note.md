# pgcrypto 修正說明

本版已修正 Supabase 中 `gen_salt()` 找不到的問題。

原因：Supabase 的 `pgcrypto` extension 常位於 `extensions` schema，而不是 `public` search_path 內，因此 SQL function 中直接呼叫 `gen_salt()`、`crypt()`、`digest()`、`gen_random_bytes()` 可能會失敗。

本版已改成 schema-qualified 寫法：

- `extensions.crypt(...)`
- `extensions.gen_salt('bf')`
- `extensions.digest(...)`
- `extensions.gen_random_bytes(...)`
- `extensions.gen_random_uuid()`

若您已執行過舊版 schema，請直接重新執行：

1. `sql/p112_schema.sql`
2. `sql/p112_bootstrap_example.sql`，或手動執行 `select public.p112_bootstrap_sysadmin(...)`

