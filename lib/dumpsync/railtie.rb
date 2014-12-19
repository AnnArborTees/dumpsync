module Dumpsync
  class Railtie < ::Rails::Railtie
    rake_tasks do
      load 'dumpsync/tasks.rb'
    end
  end
end
