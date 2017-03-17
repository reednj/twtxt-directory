require './lib/rake/rake-remote_tasks'
require './lib/rake/rake-nginx_provision'

task :default do
    sh 'rake -T'
end

desc "release to production"
task :release => "deploy_to:prod"

namespace 'deploy_to' do
    desc "deploy to github"
    task :github do
        sh "git push origin master"
    end

    desc "deploy to prod after running tests"
    task :prod => ["github", "remote:version"] do
        remote = "prod"
        sh "git push #{remote} master"
        sh "url-status twtxt.reednj.com"
    end
end

namespace "app" do
    task "install" do
        me = `logname`.strip
        sh "sudo -u #{me} ./deploy.sh"
    end

    namespace 'installed' do
        directory 'tmp'
        directory 'data'
        
        task 'restart' => 'tmp' do
            sh 'touch tmp/restart.txt'
        end

        task 'build' => ['tmp', 'data', 'restart'] do
        end
    end
end

desc "show the current git version"
task :version do
    puts `git describe`
end


# tasks wanted:
# - install:app[version]
# - app:restart
#
namespace :remote do
    remotes [
        "reednj@rs-1.reddit-stream.com:code/twtxt.git"
    ]

    remote_task "version"
    #remote_task "app:restart", :dir => '~/reddit-stream.com'
end
