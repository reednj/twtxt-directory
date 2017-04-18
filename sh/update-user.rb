require 'time'
require 'yaml'

require_relative '../lib/model'
require_relative '../lib/twtxt'
require_relative '../lib/extensions'

class App
	def main
		update_count = 3
		recent_update_count = 3

		if ARGV.length > 0
			user_id = ARGV.first
			update_single_user user_id
			return
		end

		# get the oldest updated user, and update them
		(0...update_count).each do 
			self.run_update self.user_to_update
			sleep 1.0
		end

		# get the oldest active user, and update them. This way we update users
		# who are more active more quickly
		(0...recent_update_count).each do 
			self.run_update self.active_user_to_update
			sleep 1.0
		end

		# delete old users that have no updates
		delete_if_old

	end

	def update_single_user(user_id)
		user = User.get_by_id user_id
		raise "No user found with id '#{user_id}'" if user.nil?
		run_update user
		return user
	end

	def run_update(user)
		if user.nil?
			puts 'no users require updates'
			return
		end

		update_user user
		puts "@#{user.username} updated"
		return user
	end

	def delete_if_old
		# now we refresh the data in the user, and check if they have any updates
		# users that still have no updates 3 days after they were created get deleted
		User.where(:update_count => 0).all.each do |u|
			if u.created_date.age > 30.days
				puts "@#{u.username} deleted"
				u.delete
			end
		end
	end

	def update_user(user)
		# do it inside a worker thread so we can kill it if it runs for too long - this is
		# protection against someone sneaking in a super large download
		t = WorkerThread.new.start :timeout => 30.0 do
			UserHelper.update_user(user)
		end

		t.join
		return user
	end

	def user_to_update
		User.active_since(20.weeks.ago).where('updated_date < ?', 5.minutes.ago).order_by(:updated_date).first
	end

	def active_user_to_update
		User.active.where('updated_date < ?', 5.minutes.ago).order_by(:updated_date).first
	end
end

App.new.main
