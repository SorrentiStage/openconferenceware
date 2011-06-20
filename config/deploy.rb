# = Capistrano deployment for OpenConferenceWare instances
#
# To deploy the application using Capistrano, you must:
#
#  1. Install Capistrano and the multistage extension on your local machine:
#       sudo gem install capistrano capistrano-ext
#
#  2. Create or use a stage file as defined in the "config/deploy/" directory.
#     Read the other files in that directory for ideas. You will need to use
#     the name of your configuration in all remote calls. E.g., if you created
#     a "config/deploy/mysite.rb" (thus "mysite"), you will run commands like
#     "cap mysite deploy" to deploy using your "mysite" configuration.
#
#  3. Setup your server if this is the first time you're deploying, e.g.,:
#       cap mysite deploy:setup
#
#  4. Create the "shared/config/secrets.yml" on your server to store secret
#     information. See the "config/secrets.yml.sample" file for details. If you
#     try deploying to a server without this file, you'll get instructions with
#     the exact path to put this file on the server.
#
#  5. Create the "shared/config/database.yml" on your server with the database
#     configuration. This file must contain absolute paths if you're using
#     SQLite. If you try deploying to a server without this file, you'll get
#     instructions with the exact path to put this file on the server.
#
#  6. Push your revision control changes and then deploy, e.g.,:
#       cap mysite deploy
#
#  7. If you have migrations that need to be applied, deploy with them, e.g.,:
#       cap mysite deploy:migrations
#
#  8. If you deployed a broken revision, you can rollback to the previous, e.g.,:
#       cap mysite deploy:rollback
#
# == Paths
#
# There are various paths used in the tasks:
# * current_path: The 'current' directory linked to the current release
# * release_path: The current release within the 'release' directory
# * shared_path: The 'shared' directory with common data, e.g., logs

# General settings
ssh_options[:compression] = false
default_run_options[:pty] = true
set :use_sudo, false

# Name
set :application, "openconferenceware"

# Load stages from config/deploy/*
set :stages, Dir["config/deploy/*.rb"].map{|t| File.basename(t, ".rb")}
require 'capistrano/ext/multistage'

# Print the command and then execute it, just like Rake
def sh(command)
  puts command
  system command
end

namespace :deploy do
  desc "Restart Passenger application"
  task :restart, :roles => :app, :except => { :no_release => true } do
    run "touch #{current_path}/tmp/restart.txt"
  end

  [:start, :stop].each do |t|
    desc "#{t.inspect} task is a no-op with Passenger"
    task t, :roles => :app do
      # Do nothing
    end
  end

  desc "Prepare shared directories"
  task :prepare_shared, :roles => :app do
    run "mkdir -p #{shared_path}/config"
    run "mkdir -p #{shared_path}/db"
    run "mkdir -p #{shared_path}/system/shared_fragments"
  end


  desc "Finish update, called by deploy"
  task :finish, :roles => :app do
    # Gems
    run "cd #{release_path} && (bundle check || bundle install) && bundle lock"

    # Theme
    put theme, "#{release_path}/config/theme.txt"

    # Secrets
    source = "#{shared_path}/config/secrets.yml"
    target = "#{release_path}/config/secrets.yml"
    begin
      run %{if test ! -f #{source}; then exit 1; fi}
      run %{ln -nsf #{source} #{target}}
    rescue Exception => e
      puts <<-HERE
ERROR!  You must have a file on your server to store secret information.
        See the "config/secrets.yml.sample" file for details on this.
        You will need to upload your completed file to your server at:
            #{source}
      HERE
      raise e
    end

    # Database
    source = "#{shared_path}/config/database.yml"
    target = "#{release_path}/config/database.yml"
    begin
      run %{if test ! -f #{source}; then exit 1; fi}
      run %{ln -nsf #{source} #{target}}
    rescue Exception => e
      puts <<-HERE
ERROR!  You must have a file on your server with the database configuration.
        This file must contain absolute paths if you're using SQLite.
        You will need to upload your completed file to your server at:
            #{source}
      HERE
      raise e
    end
  end

  desc "Clear the application's cache"
  task :clear_cache, :roles => :app do
    run "(cd #{current_path} && bundle exec rake RAILS_ENV=production clear)"
  end
end

namespace :data do
  desc "Download files and database from production, and install it locally."
  task :use, :roles => :db, :only => {:primary => true} do
    shared.download
    db.use
  end
end

namespace :shared do
  desc "Download shared content in 'system' directory from production, install locally"
  task :download, :roles => :db, :only => {:primary => true} do
    sh "rsync -vaxP --delete-after #{user}@#{host}:#{shared_path}/system public/"
  end
end

namespace :db do
  namespace :remote do
    desc "Dump database on remote server"
    task :dump, :roles => :db, :only => {:primary => true} do
      run "(cd #{current_path} && bundle exec rake RAILS_ENV=production db:raw:dump FILE=#{shared_path}/db/database.sql)"
    end
  end

  namespace :local do
    desc "Restore downloaded database on local server"
    task :restore, :roles => :db, :only => {:primary => true} do
      sh "bundle exec rake db:raw:dump FILE=database~old.sql && bundle exec rake db:raw:restore FILE=database.sql"
    end
  end

  desc "Download database from remote server"
  task :download, :roles => :db, :only => {:primary => true} do
    sh "rsync -vaxP #{user}@#{host}:#{shared_path}/db/database.sql ."
  end

  desc "Use: dump and download remote database and restore it locally"
  task :use, :roles => :db, :only => {:primary => true} do
    db.remote.dump
    db.download
    db.local.restore
  end
end

# Hooks
after "deploy:setup", "deploy:prepare_shared"
after "deploy:finalize_update", "deploy:finish"
after "deploy:symlink", "deploy:clear_cache"
