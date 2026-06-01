# Dumpsync

Tool to download production data locally. 

If you note one thing, note the ignored_tables. If your app audits activities or issues warnings, or retains task details you may want to ignore these/speed up download times. 

## Installation

Add this line to your application's Gemfile:
    
  gem 'dumpsync', git: 'git://github.com/AnnArborTees/dumpsync.git'
  
And then execute:

    $ bundle

## Usage

bundle exec rake dump:sync

It'll download data as configured in config/remote_database.yml. A read-replica database is recommended

```
development:
  adapter: mysql2
  host: database-readreplica
  database: readonly_database
  username: readonly
  password: READONLY PASSWORD HERE
  ignored_tables:
    - ar_internal_metadata
    - activities
    - warnings
    - tasks

  sanitize_tables:
    users:
      - email:
        - email: true
      - password:
        - password: true
      - phone
```

Alternative style using `sanitizable` is also supported:

```
development:
  sanitizable:
    users:
      email:
        - email: true
      password:
        - password: true
      phone: true
```

Another accepted list style:

```
development:
  sanitizable:
    - users:
      - email:
        - email: true
      - password:
        - password: true
      - phone
```

## Multi-Database Example

If your app uses multiple database keys, define each key under the environment.
Keys must exist in both config/database.yml and config/remote_database.yml.

Example for config/remote_database.yml:

```
development:
  primary:
    adapter: mysql2
    host: database-readreplica
    database: readonly_primary
    username: readonly
    password: READONLY PASSWORD HERE
    ignored_tables:
      - activities
    sanitizable:
      users:
        email:
          - email: true
        password:
          - password: true

  reporting:
    adapter: mysql2
    host: database-readreplica
    database: readonly_reporting
    username: readonly
    password: READONLY PASSWORD HERE
    only_tables:
      - monthly_rollups
      - revenue_snapshots
```

Combined example with sanitization on both keys:

```
development:
  primary:
    adapter: mysql2
    host: database-readreplica
    database: readonly_primary
    username: readonly
    password: READONLY PASSWORD HERE
    ignored_tables:
      - activities
    sanitizable:
      users:
        email:
          - email: true
        password:
          - password: true

  reporting:
    adapter: mysql2
    host: database-readreplica
    database: readonly_reporting
    username: readonly
    password: READONLY PASSWORD HERE
    only_tables:
      - monthly_rollups
      - revenue_snapshots
    sanitizable:
      report_recipients:
        recipient_email:
          - email: true
      report_credentials:
        api_password:
          - password: true
```

## Speed Tips

1. Keep `ignored_tables` focused on high-churn/audit/log tables.
2. Use `only_tables` when you need a narrow subset.
3. Sync from a read-replica instead of primary.
4. Enable fast compression mode:

```
DUMPSYNC_FAST_COMPRESSION=1 bundle exec rake dump:sync
```

When available, this uses `pigz -1` (parallel gzip); otherwise it falls back to `gzip -1`.

## Important Ignore Rule

Always include `ar_internal_metadata` in `ignored_tables`.
Rails uses this table to store internal key/value metadata for the current database, including the `environment` value.
If you import production data for this table into development, your local database may now claim it is `production`.
That causes Rails environment safety checks to fail (for example, environment mismatch errors on DB tasks like `db:drop`, `db:schema:load`, and similar commands), which makes local development workflows break.

## Progress Output

Enable stream progress with:

```
DUMPSYNC_PROGRESS=1 bundle exec rake dump:sync
```

If `pv` is installed, dumpsync shows throughput and progress bars during dump and import.

## Sanitization Behavior

After import completes, dumpsync sanitizes configured local columns:

- Columns flagged with `email: true` are set to `email_id@example.com`.
- Columns flagged with `password: true` are set to `password_<row-id>`.
- Columns with `email` in their name default to the email format.
- Other text-like columns become `column_name_id`.
- Numeric columns become `0`.
- Date/time columns use safe defaults.
- JSON columns become `{}`.
- If a configured table or column does not exist locally, dumpsync logs a skip message and continues.
