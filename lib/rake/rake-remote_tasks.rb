def remotes(a)
    a = [a] if a.is_a? String
    @remotes = a

    desc "list the rake remotes"
    task "list" do |t|
        puts @remotes
    end
end

def remote_task(local_name, options={})
    raise "no remotes set - use the 'remotes'" if @remotes.nil? || @remotes.empty?
    
    begin
        local_task = Rake::Task[local_name]
    rescue => e
        raise "Can't create remote_task because no local task found with name '#{local_name}'"
    end
    # todo: do some meta programming here to get the actual task object
    # - then we can copy the description, check if the task exists etc
    desc local_task.comment
    task "#{local_name.to_s}" do |t|
        cmds = [
            "source /usr/local/share/chruby/chruby.sh",
            "chruby 2.2.6",
            "rake #{local_name.to_s}"
        ]
        
        # if the user has specified a particular directory
        # to run this command in, then do that
        cmds.unshift("cd #{options[:dir]}") if !options[:dir].nil?

        on_remotes(cmds, options)
    end
end

def on_remotes(cmds, options={})
    cmds = [cmds] if cmds.is_a? String

    @remotes.each do |remote|
        puts "#{remote}:"

        a = remote.split(':')
        remote_host = a.first
        remote_path = a.last

        c = cmds.dup.unshift("cd #{remote_path}")
        puts remote_sh(remote_host, c)
    end
end

def remote_sh(host, cmds)
    cmds = [cmds] if cmds.is_a? String
    cmd = cmds.join(';').gsub('"', '\"')
    `ssh #{host} "#{cmd}"`
end