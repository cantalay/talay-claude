---
name: talay-database
description: Talay platformunda bir uygulama için PostgreSQL database + owner role ve Redis DB index tahsisi yapar, bağlantı bilgilerini Vault'a (apps/<project>/<component>) yazar ve uygulama migration stratejisini belirler. "veritabanı oluştur", "DB lazım", "redis ekle", "tablo/migration", "DATABASE_URL" isteklerinde kullan.
---

# talay-database

Bağlam: `${CLAUDE_PLUGIN_ROOT}/PLATFORM.md` §6–§7. Script: `$TALAY_INFRA_DIR/talay-data/scripts/provision-app-database.sh`.

## Model
- Paylaşımlı PostgreSQL 18 (`postgresql.data.svc.cluster.local:5432`). App başına bir database ve aynı adlı **owner** login role.
  `PUBLIC`'in database'e CONNECT yetkisi kaldırılır; app role yalnız kendi DB'sine bağlanır.
- Paylaşımlı Redis (`redis-master.data.svc.cluster.local:6379`), tek parola. App başına **DB index** (0–15) ve key prefix.
- Tablolar/indeksler **app migration'ı** ile (talay-app-standards). Platform şemaya dokunmaz.

## Ön koşullar
- `vault login -method=oidc` (VAULT_ADDR=https://vault.cantalay.com) — `vault token lookup` çalışmalı.
- `ssh root@45.87.80.10` erişimi (script `kubectl exec` için SSH kullanır).

## Akış
1. `talay.yaml` → `data.postgres.database`, `consumers`; `data.redis.db`, `consumers`.
2. Redis index'i `talay-data/README.md` §Redis DB index tahsisi tablosundan boş olanı seç; tabloyu güncelleyen commit hazırla.
3. **Dry-run** (varsayılan; hiçbir şey yazmaz, secret basmaz):
   ```bash
   cd $TALAY_INFRA_DIR/talay-data
   ./scripts/provision-app-database.sh --project <project> --database <db> \
     --consumer api --consumer worker [--redis-db <n>]
   ```
4. Çıktıyı kullanıcıya göster (oluşturulacak role/DB, yazılacak Vault path'leri ve key adları), onay al.
5. Uygula: aynı komut başına `APPLY=true`. Script idempotenttir:
   - Role + DB yoksa oluşturur; Vault'ta parola zaten varsa ve role varsa dokunmaz.
   - `--rotate` verilirse yeni parola üretir, `ALTER ROLE` + Vault günceller (pod restart gerekir).
6. Doğrula: `vault kv get -mount=kv -field=DB_NAME apps/<project>/<component>`; values'ta
   `externalSecret.enabled: true`, `remoteKey: apps/<project>/<component>`.

## Uygulamaya giden env'ler
`DATABASE_URL`, `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`, `DB_PASSWORD`, `SPRING_DATASOURCE_URL`,
`SPRING_DATASOURCE_USERNAME`, `SPRING_DATASOURCE_PASSWORD`; Redis ile `REDIS_URL`, `REDIS_HOST`, `REDIS_PORT`,
`REDIS_DB`, `REDIS_PASSWORD`, `REDIS_KEY_PREFIX`.

## Migration stratejisi
- Java: Flyway `db/migration/V<n>__*.sql`, `ddl-auto: validate`.
- Node: `db/migrations/NNNN_*.sql` + advisory-lock'lu runner (talay-app-standards/references/node.md).
- API ve worker aynı DB'yi kullanıyorsa migration'ı yalnız API çalıştırır.
- Geriye uyumluluk: expand (yeni kolon/tablo, nullable) → kod deploy → contract (eski kolonu sonraki sürümde sil).
- Seed/rol verisi gerekiyorsa idempotent migration (`insert … on conflict do nothing`).

## Sorun giderme / inceleme (salt-okunur, onayla)
- Bağlantı testi pod içinden: uygulama `/health/ready` 503 → `talay-status` ile log'a bak (`password authentication failed`
  → Vault değeri ile role parolası uyuşmuyor → `--rotate`).
- DB listesi: `ssh root@45.87.80.10 "kubectl exec -n data postgresql-0 -c postgresql -- sh -c 'PGPASSWORD=\$(cat /opt/bitnami/postgresql/secrets/postgres-password) psql -U postgres -Atc \"select datname from pg_database\"'"`
  — prod veri okumasıdır, kullanıcıdan izin iste.

## Yapma
- Admin (`postgres`) parolasını uygulamaya verme; app role'üne SUPERUSER/CREATEDB/CREATEROLE verme.
- DB silme (`DROP DATABASE`) — yalnız kullanıcı açıkça isterse, önce `pg_dump` yedeği alınarak.
