require 'time'
require 'yaml'

require_relative '../lib/model'
require_relative '../lib/twtxt'
require_relative '../lib/extensions'

class App
	def main
		#puts Time.now.iso8601

		# get the oldest updated user, and update them
		user = self.user_to_update

		if user.nil?
			puts 'no users require updates'
			return
		end

		UserHelper.update_user(user)

		puts "@#{user.username} updated"
	end

	def user_to_update
		User.where('updated_date < ?', 5.minutes.ago).order_by(:updated_date).first
	end
end

App.new.main
