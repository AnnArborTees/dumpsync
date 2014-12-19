require "dumpsync/version"
require 'dumpsync/railtie' if defined?(Rails::Railtie)

module Dumpsync
  Db = Struct.new(:adapter, :username, :password, :host, :database)

  def local_db
    @local_db ||= db_from('database.yml')
  end

  def remote_db
    @remote_db ||= db_from('remote_database.yml')
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
    )
  end
end
