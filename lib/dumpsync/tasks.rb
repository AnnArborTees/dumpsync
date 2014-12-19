namespace :dump do
  desc %(
    Transfer all data from the database defined in config/remote_database.yml
    to the database defined in config/database.yml. Dumps all data from the
    local database first.
  )
  task :sync do
    include Dumpsync
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

    dump_file = "dumpsync-#{Time.now.strftime('%F')}.sql"
    dump_cmd = "mysqldump --single-transaction -h #{remote_db.host} "\
               "-u #{remote_db.username} -p#{remote_db.password} "\
               "#{remote_db.database} > #{dump_file}"
    dump = `#{dump_cmd}`

    unless dump.strip.empty?
      raise "Failed to dump: #{dump}"
    end

    sync_cmd = "mysql -u #{local_db.username} -p#{local_db.password} "\
               "#{local_db.database} < #{dump_file}"
    sync = `#{sync_cmd}`

    STDOUT.puts "I HAVE NO IDEA IF SUCCESS: #{sync}"
  end
end
