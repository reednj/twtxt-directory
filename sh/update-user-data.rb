#!/usr/bin/env ruby

require 'time'
require 'yaml'

require_relative '../lib/model'
require_relative '../lib/twtxt'
require_relative '../lib/extensions'

class App
	def main
		raise 'user_id required' if ARGV.length == 0

		txt_data = STDIN.read
		user_id = ARGV.first
		update_single_user user_id, txt_data
	end

	def update_single_user(user_id, data)
		user = User.get_by_id user_id
		raise "No user found with id '#{user_id}'" if user.nil?

		puts "updating @#{user.username}"
		UserHelper.update_user_record user, data
		return user
	end

end

App.new.main
