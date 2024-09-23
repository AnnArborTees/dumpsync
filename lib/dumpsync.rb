require "dumpsync/version"
require 'dumpsync/railtie' if defined?(Rails::Railtie)

module Dumpsync
  Db = Struct.new(
    :adapter, :username, :password, :host, :database, :ignored_tables, :only_tables
  )

  def self.dump_sync!
    config = ->(file) { File.join('config', file) }

    unless File.exist? config['database.yml']
      raise "Couldn't find database.yml."
    end
    unless File.exist? config['remote_database.yml']
      raise "Couldn't find remote_database.yml"
    end

    remote_dbs.each do |key, remote_db|
      next unless local_dbs[key].present?
      
      unless remote_db.adapter == "mysql2"
        STDOUT.puts "Remote db for #{key} does not have mysql2 adapter. Skipping..."
        next
      end

      unless local_dbs[key].adapter == 'mysql2'
        STDOUT.puts "Local db for #{key} does not have mysql2 adapter. Skipping..."
        next
      end

      STDOUT.puts "Running mysqldump on remote database #{key}"
      if remote_db.only_tables.any?
        STDOUT.puts "Only tables: #{remote_db.only_tables}."
      else
        STDOUT.puts "Ignored tables: #{remote_db.ignored_tables}."
      end
      
      file = default_dump_file
      cmd = dump_cmd(remote_db, file)
      puts cmd
      dump = `#{cmd}`

      unless dump.strip.empty?
        STDOUT.puts "Failed to dump: #{dump}"
        next
      end
      
      STDOUT.puts "Loading data into local database..."
      
      cmd = sync_cmd(local_dbs[key], file)
      puts cmd
      sync = `#{cmd}`

      unless sync.strip.empty?
        STDOUT.puts "Failed to sync: #{sync}"
      end
      
      begin
        File.delete(file)
      rescue StandardError => e
        STDOUT.puts "Error #{e} when trying to remove #{file}"
      end
    end

    STDOUT.puts "Finished dumping all databases"
  end

  def local_dbs
    @local_dbs ||= dbs_from('database.yml')
  end

  def remote_dbs
    @remote_dbs ||= dbs_from('remote_database.yml')
  end

  def dump_cmd(db, dump_file = nil)
    dump_file ||= default_dump_file
    
    ignore_table = lambda do |table_name|
      "--ignore-table=#{db.database}.#{table_name}"
    end

    only_tables = db.only_tables.join(" ")

    ignored_tables = db.ignored_tables.map(&ignore_table).join(' ')

    "mysqldump --single-transaction -h #{db.host} " +
      auth(db) + "#{db.database}" + " " + (db.only_tables.any? ? only_tables : ignored_tables) +
    " | gzip > #{dump_file}"
  end

  def sync_cmd(db, dump_file = nil)
    dump_file ||= default_dump_file


    "gunzip < #{dump_file} | mysql -h #{db.host} #{auth(db)} #{db.database}"
  end

  def default_dump_file
    "dumpsync-#{Time.now.strftime('%F')}.sql.gz"
  end

  def auth(db)
    a = ''
    a += "-u  #{db.username} " unless db.username.nil? || db.username.empty?
    a += "-p#{db.password}" unless db.password.nil? || db.password.empty?
    a + ' '
  end

  def dbs_from(config_file)
    file   = File.read(File.join('config', config_file))
    config = YAML.load(ERB.new(file).result)[Rails.env.to_s]
    if config.nil?
      raise "Could not open config/#{config_file}"
    end
    
    dbs = {}
    config.each do |key, db_config|
      dbs[key] = Db.new(
        db_config['adapter'],
        (db_config['username'] ||= ENV['MYSQL_USER']),
        (db_config['password'] ||= ENV['MYSQL_ROOT_PASSWORD']),
        (db_config['host'] ||= ENV['MYSQL_HOST']),
        (db_config['database'] ||= ENV['MYSQL_DATABASE']),
        db_config['ignored_tables'] || [],
        db_config['only_tables'] || []
      )
    end

    dbs.with_indifferent_access
  end

  extend self
end
