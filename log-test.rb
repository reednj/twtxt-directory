
require './lib/model'
require './lib/sequel-event-log'

class App
	def main
		LoggedEvent.for_event('test_event').save
		LoggedEvent.for_event('test_event', :user_id => 'SYSTEM').save
		LoggedEvent.for_event('test_event', :description => 'what evver').save
	end
end

App.new.main
