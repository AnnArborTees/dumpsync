namespace :dump do
  desc %(
    Transfer all data from the database defined in config/remote_database.yml
    to the database defined in config/database.yml. Dumps all data from the
    local database first.
  )
  task :sync do
    Dumpsync.dump_sync!
  end
end
