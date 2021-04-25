require "dumpsync/version"
require 'dumpsync/railtie' if defined?(Rails::Railtie)

module Dumpsync
  Db = Struct.new(:adapter, :username,
                  :password, :host, :database,
                  :ignored_tables)

  def self.dump_sync!
    config = ->(file) { File.join('config', file) }

    unless File.exists? config['database.yml']
      raise "Couldn't find database.yml."
    end
    unless File.exists? config['remote_database.yml']
      raise "Couldn't find remote_database.yml"
    end

    unless local_db.adapter == 'mysql2'
      raise "Local adapter must be mysql2"
    end
    unless remote_db.adapter == 'mysql2'
      raise "Remote adapter must be mysql2"
    end

    STDOUT.puts "Running mysqldump on remote database..."
    STDOUT.puts "Ignored tables: #{remote_db.ignored_tables}."

    file = default_dump_file
    cmd = dump_cmd(remote_db, file)
    puts cmd
    dump = `#{cmd}`

    unless dump.strip.empty?
      raise "Failed to dump: #{dump}"
    end

    STDOUT.puts "Loading data into local database..."
    cmd = sync_cmd(local_db, file)
    puts cmd
    sync = `#{cmd}`

    unless sync.strip.empty?
      raise "Failed to sync: #{sync}"
    end

    begin
      File.delete(file)
    rescue StandardError => e
      STDOUT.puts "Error #{e} when trying to remove #{file}"
    end
  end

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
    " #{db.database} | gzip > #{dump_file}"
  end

  def sync_cmd(db, dump_file = nil)
    dump_file ||= default_dump_file


    "gunzip < #{dump_file} | mysql -h #{db.host} #{auth(db)} #{db.database}"
  end

  def default_dump_file
    "dumpsync-#{Time.now.strftime('%F')}.sql.gz"
  end

  def auth(db)
    a = "-u #{db.username}"
    a += " -p#{db.password}" unless db.password.nil? || db.password.empty?
    a + ' '
  end

  def db_from(config_file)
    file   = File.read(File.join('config', config_file))
    config = YAML.load(ERB.new(file).result)[Rails.env.to_s]
    if config.nil?
      raise "Could not open config/#{config_file}"
    end
    Db.new(
      config['adapter'],
      (config['username'] ||= ENV['MYSQL_USER']),
      (config['password'] ||= ENV['MYSQL_ROOT_PASSWORD']),
      (config['host'] ||= ENV['MYSQL_HOST']),
      (config['database'] ||= ENV['MYSQL_DATABASE']),
      config['ignored_tables'] || []
    )
  end

  extend self
end
