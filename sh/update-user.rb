require 'time'
require 'yaml'

require_relative '../lib/model'
require_relative '../lib/twtxt'
require_relative '../lib/extensions'

class App
	def main
		# get the oldest updated user, and update them
		user = self.user_to_update

		if user.nil?
			puts 'no users require updates'
			return
		end

		UserHelper.update_user(user)

		puts "@#{user.username} updated"

		# now we refresh the data in the user, and check if they have any updates
		# users that still have no updates 3 days after they were created get deleted
		user.refresh
		if user.update_count == 0 && user.created_date.age > 3.days
			user.delete
			puts "@#{user.username} deleted - no updates for 3 days"
		end

	end

	def user_to_update
		User.where('updated_date < ?', 5.minutes.ago).order_by(:updated_date).first
	end
end

App.new.main
