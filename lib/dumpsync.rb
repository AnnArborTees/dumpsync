require "dumpsync/version"
require 'dumpsync/railtie' if defined?(Rails::Railtie)

module Dumpsync
  Db = Struct.new(:adapter, :username,
                  :password, :host, :database,
                  :ignored_tables)

  def local_db
    @local_db ||= db_from('database.yml')
  end

  def remote_db
    @remote_db ||= db_from('remote_database.yml')
  end

  def dump_cmd(db, dump_file = nil)
    dump_file ||= default_dump_file

    ignore_table = lambda do |table_name|
      "--ignore-table=#{db.database}.#{table_name}"
    end

    "mysqldump --single-transaction -h #{db.host} " +
    auth(db) +
    db.ignored_tables.map(&ignore_table).join(' ') +
    " #{db.database} > #{dump_file}"
  end

  def sync_cmd(db, dump_file = nil)
    dump_file ||= default_dump_file

    "mysql #{auth(db)} "\
    "#{db.database} < #{dump_file}"
  end

  def default_dump_file
    "dumpsync-#{Time.now.strftime('%F')}.sql"
  end

  def auth(db)
    a = "-u #{db.username}"
    a += " -p#{db.password}" unless db.password.nil? || db.password.empty?
    a + ' '
  end

  def db_from(config_file)
    file   = File.read(File.join('config', config_file))
    config = YAML.load(ERB.new(file).result)[Rails.env.to_s]
    Db.new(
      config['adapter'],
      config['username'],
      config['password'],
      config['host'],
      config['database'],
      config['ignored_tables'] || []
    )
  end
end
