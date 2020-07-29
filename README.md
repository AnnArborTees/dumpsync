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
    - activities
    - warnings
    - tasks
```
