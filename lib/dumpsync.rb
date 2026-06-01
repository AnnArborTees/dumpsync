require "dumpsync/version"
require 'dumpsync/railtie' if defined?(Rails::Railtie)
require 'open3'
require 'shellwords'

module Dumpsync
  Db = Struct.new(
    :adapter, :username, :password, :host, :database, :ignored_tables, :only_tables, :sanitize_tables
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
      STDOUT.puts "Sanitize tables: #{remote_db.sanitize_tables.keys}." unless remote_db.sanitize_tables.empty?
      
      file = default_dump_file(key)
      cmd = dump_cmd(remote_db, file, progress_enabled?)

      begin
        run_command!(cmd, phase: "dump #{key}")
      rescue StandardError => e
        STDOUT.puts "Failed to dump #{key}: #{e.message}"
        next
      end

      STDOUT.puts "Dump file size for #{key}: #{human_size(File.size?(file) || 0)}"
      
      STDOUT.puts "Loading data into local database..."
      
      cmd = sync_cmd(local_dbs[key], file, progress_enabled?)

      begin
        run_command!(cmd, phase: "sync #{key}")
      rescue StandardError => e
        STDOUT.puts "Failed to sync #{key}: #{e.message}"
        next
      end

      sanitize_local_data!(local_dbs[key], remote_db.sanitize_tables)
      
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

  def dump_cmd(db, dump_file = nil, show_progress = false)
    dump_file ||= default_dump_file
    
    ignore_table = lambda do |table_name|
      "--ignore-table=#{db.database}.#{table_name}"
    end

    only_tables = db.only_tables.join(" ")

    ignored_tables = db.ignored_tables.map(&ignore_table).join(' ')

    selected_tables = db.only_tables.any? ? only_tables : ignored_tables
    stream_monitor = monitor_cmd(show_progress)

    "mysqldump --single-transaction -h #{db.host} " +
      auth(db) + "#{db.database} #{selected_tables}" +
    " | #{stream_monitor} | #{compress_cmd} > #{dump_file}"
  end

  def sync_cmd(db, dump_file = nil, show_progress = false)
    dump_file ||= default_dump_file

    stream_monitor = monitor_cmd(show_progress)

    "#{decompress_cmd} < #{dump_file} | #{stream_monitor} | mysql -h #{db.host} #{auth(db)} #{db.database}"
  end

  def default_dump_file(name = nil)
    suffix = name.to_s.empty? ? '' : "-#{name}"
    "dumpsync#{suffix}-#{Time.now.strftime('%F')}.sql.gz"
  end

  def auth(db)
    a = ''
    a += "-u  #{db.username} " unless db.username.nil? || db.username.empty?
    a += "-p#{db.password}" unless db.password.nil? || db.password.empty?
    a + ' '
  end

  def run_command!(cmd, phase:)
    if progress_enabled?
      success = system(*shell_runner, cmd)
      raise "Failed to #{phase}" unless success
      return
    end

    output, status = Open3.capture2e(*shell_runner, cmd)
    return if status.success?

    raise "Failed to #{phase}: #{output}"
  end

  def sanitize_local_data!(db, sanitize_tables)
    return if sanitize_tables.nil? || sanitize_tables.empty?

    STDOUT.puts 'Running local sanitization...'

    sanitize_tables.each do |table_name, column_rules|
      unless valid_identifier?(table_name)
        STDOUT.puts "Skipping sanitize table with invalid name: #{table_name}"
        next
      end

      column_rules.each do |column_name, strategy|
        unless valid_identifier?(column_name)
          STDOUT.puts "Skipping sanitize column with invalid name: #{table_name}.#{column_name}"
          next
        end

        sql = "UPDATE #{quote_identifier(table_name)} SET #{quote_identifier(column_name)} = #{sanitizer_expression(db, table_name, column_name, strategy)}"
        run_mysql_sql!(db, sql)
        STDOUT.puts "Sanitized #{table_name}.#{column_name}"
      end
    end
  end

  def run_mysql_sql!(db, sql)
    cmd = "mysql -N -B -h #{db.host} #{auth(db)} #{db.database} -e #{Shellwords.escape(sql)}"
    output, status = Open3.capture2e(*shell_runner, cmd)
    raise "Sanitization failed: #{output}" unless status.success?
  end

  def sanitizer_expression(db, table_name, column_name, strategy = :auto)
    data_type, = column_metadata(db, table_name, column_name)
    email_expression = "CONCAT('email_', COALESCE(CAST(id AS CHAR), '0'), '@example.com')"
    generic_text_expression = "CONCAT('#{column_name}_', COALESCE(CAST(id AS CHAR), '0'))"

    return "'password123'" if strategy.to_s == 'password'
    return email_expression if strategy.to_s == 'email'

    case data_type
    when 'int', 'integer', 'smallint', 'mediumint', 'bigint', 'tinyint',
         'decimal', 'numeric', 'float', 'double', 'real', 'bit', 'bool', 'boolean'
      '0'
    when 'date'
      "'1970-01-01'"
    when 'datetime', 'timestamp'
      "'1970-01-01 00:00:00'"
    when 'time'
      "'00:00:00'"
    when 'year'
      "'1970'"
    when 'json'
      "'{}'"
    when 'char', 'varchar', 'tinytext', 'text', 'mediumtext', 'longtext', 'enum', 'set', 'binary', 'varbinary'
      column_name.to_s.downcase.include?('email') ? email_expression : generic_text_expression
    else
      column_name.to_s.downcase.include?('email') ? email_expression : generic_text_expression
    end
  end

  def column_metadata(db, table_name, column_name)
    sql = <<~SQL
      SELECT DATA_TYPE, IS_NULLABLE
      FROM INFORMATION_SCHEMA.COLUMNS
      WHERE TABLE_SCHEMA = '#{db.database}'
      AND TABLE_NAME = '#{table_name}'
      AND COLUMN_NAME = '#{column_name}'
      LIMIT 1
    SQL

    cmd = "mysql -N -B -h #{db.host} #{auth(db)} #{db.database} -e #{Shellwords.escape(sql)}"
    output, status = Open3.capture2e(*shell_runner, cmd)
    raise "Failed to inspect column metadata: #{output}" unless status.success?

    parts = output.strip.split("\t")
    return [parts[0], parts[1]] if parts.size == 2

    raise "Could not find metadata for #{table_name}.#{column_name}"
  end

  def valid_identifier?(name)
    !!(name.to_s =~ /\A[a-zA-Z0-9_]+\z/)
  end

  def quote_identifier(name)
    "`#{name}`"
  end

  def shell_runner
    ['bash', '-o', 'pipefail', '-lc']
  end

  def progress_enabled?
    ENV['DUMPSYNC_PROGRESS'].to_s == '1'
  end

  def fast_compression?
    ENV['DUMPSYNC_FAST_COMPRESSION'].to_s == '1'
  end

  def compress_cmd
    return 'pigz -1' if fast_compression? && command_available?('pigz')
    return 'gzip -1' if fast_compression?

    'gzip'
  end

  def decompress_cmd
    return 'pigz -d' if fast_compression? && command_available?('pigz')

    'gunzip'
  end

  def monitor_cmd(show_progress)
    return 'cat' unless show_progress

    return 'pv -ptebar' if command_available?('pv')

    'cat'
  end

  def command_available?(command)
    _, status = Open3.capture2e('bash', '-lc', "command -v #{command} >/dev/null 2>&1")
    status.success?
  end

  def human_size(bytes)
    return '0 B' if bytes <= 0

    units = ['B', 'KB', 'MB', 'GB']
    size = bytes.to_f
    unit = units.shift

    while size >= 1024 && !units.empty?
      size /= 1024.0
      unit = units.shift
    end

    format('%.2f %s', size, unit)
  end

  def dbs_from(config_file)
    file   = File.read(File.join('config', config_file))
    
    config = if Psych::VERSION > '4.0'
               YAML.load(ERB.new(file).result, aliases: true)[Rails.env.to_s]
             else
               YAML.load(ERB.new(file).result)[Rails.env.to_s]
             end

    if config.nil?
      raise "Could not open config/#{config_file}"
    end
    
    db_entries = extract_db_entries(config)

    dbs = {}
    db_entries.each do |key, db_config|
      sanitize_tables = normalize_sanitize_tables(
        db_config['sanitizable'] || db_config['sanitize_tables'] || config['sanitizable'] || config['sanitize_tables']
      )

      dbs[key] = Db.new(
        db_config['adapter'],
        (db_config['username'] ||= ENV['MYSQL_USER']),
        (db_config['password'] ||= ENV['MYSQL_ROOT_PASSWORD']),
        (db_config['host'] ||= ENV['MYSQL_HOST']),
        (db_config['database'] ||= ENV['MYSQL_DATABASE']),
        db_config['ignored_tables'] || config['ignored_tables'] || [],
        db_config['only_tables'] || config['only_tables'] || [],
        sanitize_tables
      )
    end

    dbs.with_indifferent_access
  end

  def extract_db_entries(config)
    return { 'primary' => config } if config['adapter'].present?

    entries = config.each_with_object({}) do |(key, value), result|
      next unless value.is_a?(Hash)
      next unless value['adapter'].present?

      result[key.to_s] = value
    end

    entries
  end

  def normalize_sanitize_tables(value)
    return {} if value.nil?
    return normalize_sanitize_table_hash(value) if value.is_a?(Hash)

    if value.is_a?(Array)
      value.each_with_object({}) do |entry, result|
        next unless entry.is_a?(Hash)

        result.merge!(normalize_sanitize_table_hash(entry))
      end
    else
      {}
    end
  end

  def normalize_sanitize_table_hash(value)
    value.each_with_object({}) do |(table_name, column_config), result|
      table_key = table_name.to_s
      result[table_key] = normalize_sanitize_columns(column_config)
    end
  end

  def normalize_sanitize_columns(value)
    case value
    when Hash
      value.each_with_object({}) do |(column_name, options), result|
        result[column_name.to_s] = sanitize_strategy_for(column_name, options)
      end
    when Array
      value.each_with_object({}) do |entry, result|
        case entry
        when Hash
          entry.each do |column_name, options|
            result[column_name.to_s] = sanitize_strategy_for(column_name, options)
          end
        when String, Symbol
          result[entry.to_s] = :auto
        end
      end
    when String, Symbol
      { value.to_s => :auto }
    else
      {}
    end
  end

  def sanitize_strategy_for(column_name, options)
    flags = normalize_sanitize_flags(options)
    return :password if flags['password']
    return :email if flags['email']

    column_name.to_s.downcase.include?('email') ? :email : :auto
  end

  def normalize_sanitize_flags(value)
    case value
    when Hash
      value.each_with_object({}) { |(key, v), result| result[key.to_s] = !!v }
    when Array
      value.each_with_object({}) do |entry, result|
        next unless entry.is_a?(Hash)

        entry.each { |(key, v)| result[key.to_s] = !!v }
      end
    when String, Symbol
      key = value.to_s
      if key == 'email' || key == 'password'
        { key => true }
      else
        {}
      end
    else
      {}
    end
  end

  extend self
end
