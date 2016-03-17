
# check that DB exists - we assume that we already have a database
# connection
if !defined? DB
	raise 'constant DB required to use sequel-event-log'
end

if !DB.is_a? Sequel::Database
	raise "DB must be a Sequel::Database, but is actually #{DB.class}"
end

DB.create_table? :logged_events do
	primary_key :event_id
	String :user_id, :size => 64, :null => true
	String :event_name, :size => 64
	String :description, :null => true
	
	column :created_date, :timestamp, :default => Sequel.lit('CURRENT_TIMESTAMP')
end

class LoggedEvent < Sequel::Model
	dataset_module do
		def for_event(event_name, options = nil)
			options ||= {}
			e = LoggedEvent.new
			e.event_name = event_name
			e.user_id = options[:user_id]
			e.description = options[:description]
			return e
		end
	end
end

