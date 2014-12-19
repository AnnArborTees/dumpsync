require "dumpsync/version"
require 'dumpsync/railtie' if defined?(Rails::Railtie)

module Dumpsync
  Db = Struct.new(:adapter, :username,
                  :password, :host, :database,
                  :ignore_tables)

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

    "mysqldump --single-transaction -h #{db.host} "\
    "-u #{db.username} -p#{db.password} " +
    db.ignore_tables.map(&ignore_table).join(' ') +
    " #{db.database} > #{dump_file}"
  end

  def symc_cmd(db, dump_file = nil)
    dump_file ||= default_dump_file

    "mysql -u #{db.username} -p#{db.password} "\
    "#{db.database} < #{dump_file}"
  end

  def default_dump_file
    "dumpsync-#{Time.now.strftime('%F')}.sql"
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
      config['ignore_tables'] || []
    )
  end
end
