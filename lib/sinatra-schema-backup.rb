#
# Exports the schema of the db given in config to a file. The config
# has the same structure as the db config that is used by Sequel.
#
# {
#	:user => 'linkuser',
#	:password => '',
#	:host => '127.0.0.1',
# 	:database => 'timeline'
# }
#
# By default the export will be run every time the app is started in development
# mode
#
# The only thing needed to use this script is to require it, and make sure that
# the DB_CONFIG constant is set
#
def export_db_schema(config)
	return false if Gem.win_platform?
	
	filename = "#{config[:database]}.sql"
	
	# if the config dir exists, then we put the schema in there
	# otherwise just in the root dir
	if Dir.exist? 'config'
		path = File.join 'config', filename
	else
		path = filename
	end

	schema = `mysqldump --host #{config[:host]} -u #{config[:user]} --no-data --skip-comments #{config[:database]}`
	schema.gsub!(/ AUTO_INCREMENT=[0-9]*/, '')
	File.write path, schema

	return true
end

configure :development do
	result = export_db_schema DB_CONFIG
	puts 'db schema exported' if result
end
