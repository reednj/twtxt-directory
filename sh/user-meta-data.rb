#!/usr/bin/env ruby

require 'yaml'
require_relative '../lib/model'

class App
	def main
		raise 'username required' if ARGV.length == 0
		username = ARGV.first
		user = User.get_by_name(username) || raise("user @#{username} not found")
		
		puts "@#{user.username}:"
		puts user.feed_attr.to_yaml

	end
end

App.new.main
