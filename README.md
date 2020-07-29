# Dumpsync

Tool to download production data locally. 

If you note one thing, note the ignored_tables. A lot of SoftWEAR-* Apps audit activities and warnings, both are significantly large databases with no warehousing system or deletion policies in place. 

## Installation

Add this line to your application's Gemfile:
    
  gem 'dumpsync', git: 'git://github.com/AnnArborTees/dumpsync.git'
  
And then execute:

    $ bundle

## Usage

bundle exec rake dump:sync

It'll download data as configured in config/remote_database.yml. We have a read-replica database set up, database details can be shared via LastPass. 

```
development:
  adapter: mysql2
  host: db-rr.aatshirtco.com
  database: softwear_crm
  username: readonly
  password: READONLY PASSWORD HERE
  ignored_tables:
    - activities
    - warnings
```
