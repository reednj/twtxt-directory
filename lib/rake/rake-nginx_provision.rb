def sudo?
    Process.uid == 0
end

def sudo_required!
    raise 'Must run as root' unless sudo?
end

# these steps are meant to be run from the git directory for the site
# not from the web directory like some other rake tasks, although this will
# be called if needed.
#
# Because these tasks do things to the nginx config, most of them will need
# sudo, and will throw an error without it
namespace "app" do
    SITE_NAME = "twtxt.reednj.com"

    home_dir = ENV['HOME']
    site_root = "/var/www/#{SITE_NAME}"
    site_root_link = File.join home_dir, SITE_NAME
    config_backup = File.join home_dir, "code/config_backup/twtxt"
    
    directory site_root
    directory config_backup

    def take_own(filename)
        me = `logname`.strip
        sh "chown -R #{me}:#{me} #{filename}"
    end

    file site_root do |t|
        sudo_required!
        take_own t.name
    end

    # copy the config file over into the config backup directory - obivously
    # the details will not be correct, but we will at least have a template
    # to change around afterward
    file "#{config_backup}/app.config.rb" => config_backup do |t|
        cp "config/app.config.rb", config_backup
        take_own config_backup
    end

    # there is a default config file for the testing site, so we copy that over into
    # the nginx config folder
    file "/etc/nginx/sites-available/#{SITE_NAME}" => [
        site_root,
        "config/nginx/#{SITE_NAME}.txt"
     ] do |t|
        sudo_required!
        cp "config/nginx/#{SITE_NAME}.txt", t.name
    end

    # enable the site by linking sites-enabled to sites-available
    file "/etc/nginx/sites-enabled/#{SITE_NAME}" => [
        "/etc/nginx/sites-available/#{SITE_NAME}"
    ] do |t|
        sudo_required!
        safe_unlink "/etc/nginx/sites-enabled/default"
        ln_s t.prerequisites.first, t.name
        sh "sudo service nginx restart"
    end

    # previously to make things simpler, we linked from the home directory
    # to the web folder. This is assumed in many scripts, so this task will
    # make sure the link exists
    file site_root_link => site_root do |t|
        # have to do this double trick when symlinking to directories
        # otherwise it will sometimes create a link loop
        unless File.exist? t.name
            ln_s t.prerequisites.first, t.name
        end
    end

    desc "set up nginx to host site"
    task :provision => [
        "/etc/nginx/sites-enabled/#{SITE_NAME}",
        "#{config_backup}/app.config.rb",
        site_root_link
     ] do
        puts "#{SITE_NAME} setup"
    end
end

