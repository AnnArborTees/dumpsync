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

    file = default_dump_file
    dump = `#{dump_cmd(remote_db, file)}`

    unless dump.strip.empty?
      raise "Failed to dump: #{dump}"
    end

    sync = `#{sync_cmd(local_db, file)}`

    unless sync.strip.empty?
      raise "Failed to sync: #{sync}"
    end

    begin
      File.delete(file)
      STDOUT.puts "Successfully synced with remote database!"
    rescue StandardError => e
      STDOUT.puts "Successfully synced, but got #{e.inspect} "\
        "when trying to remove #{file}."
    end
  end
end
