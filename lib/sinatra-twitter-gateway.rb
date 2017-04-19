
require 'twitter'
require 'yaml'
require 'cgi'
require './lib/extensions'
require './config/app.config'

TWITTER_CLIENT = Twitter::REST::Client.new do |config|
	config.consumer_key = "N5FP6mMnW6cUtytBsBTLgE81s"
	config.consumer_secret = TWITTER_CONFIG[:consumer_secret]
	config.access_token = "11646642-5jJ7aL5IMEfq9ZkuiewkkN7GxrTK1v69CnlUcVy1T"
	config.access_token_secret = TWITTER_CONFIG[:access_token_secret]
end

class TextCache
	attr_accessor :path

	def initialize(path, options = nil)
		self.path = path
		@options ||= {}
		@options[:max_age] ||= (60 * 5)
	end

	def data
		return self.read if recent?

		if block_given?
			data = yield()
			text = data.to_s
			self.write text
			return text
		else 
			return nil
		end
	end

	def read
		File.read self.path
	end

	def write(data)
		File.write self.path, data
	end

	def exist?
		File.exist? self.path
	end

	def recent?
		self.exist? && File.mtime(self.path) > (Time.now - @options[:max_age])
	end
end

get '/t/:username/twtxt.txt' do |username|
	allowed_users = ['reednj', 'reddit_random', 'hn_bot_top1']
	halt_with_text 401, 'invalid user' if !allowed_users.include? username

	data_path = "./data/#{username}.twitter.txt"
	data = TextCache.new(data_path, :max_age => 5.minutes).data do
		timeline = TWITTER_CLIENT.user_timeline username, :count => 100, :trim_user => true
		updates = timeline.map do |t|
			u = TwtxtUpdate.new
			u.date = t.created_at.dup
			u.text = CGI.unescapeHTML(t.text)
			u
		end

		updates.reverse.to_txt
	end

	text data
end
