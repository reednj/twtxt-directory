require 'sinatra'
require 'sinatra/cookies'
require 'sinatra/content_for'
require 'sinatra/json'

require 'json'
require 'erubis'
require 'rest-client'

require "sinatra/reloader" if development?

require './lib/model'
require './lib/extensions'
require './lib/sinatra-schema-backup'

use Rack::Deflater
set :erb, :escape_html => true
set :version, GitVersion.current('/home/reednj/code/twtxt.git/.git')

configure :development do
	also_reload './lib/model.rb'
	also_reload './lib/extensions.rb'
end

configure :production do

end

helpers do

	def background_task(options=nil)
		raise 'background_task needs a block' unless block_given?

		options ||= {}

		worker = Thread.new do
			begin
				yield
			rescue => e
				File.append 'error.log', "#{e.class.to_s}\t#{e.message}\n"
			end
		end

		# if the user set a timeout then we need a thread to monitor
		# the worker to make sure it doesn't run too long
		if !options[:timeout].nil?
			Thread.new do
				sleep options[:timeout].to_f
				
				if worker.status != false
					worker.kill 
					File.append 'error.log', "background_task thread timeout\n"
				end
			end
		end

		worker
	end

	# basically the same as a regular halt, but it sends the message to the 
	# client with the content type 'text/plain'. This is important, because
	# the client error handlers look for that, and will display the message
	# if it is text/plain and short enough
	def halt_with_text(code, message = nil)
		message = message.to_s if !message.nil?
		halt code, {'Content-Type' => 'text/plain'}, message
	end

	def valid_username?(username)
		return false if username.length > 64
		return username =~ /^[a-zA-Z_\-0-9]+$/
	end

end

get '/' do
	erb :home, :layout => :_layout, :locals => {
		:users => User.order_by(:username).take(500)
	}
end

post '/user/add' do 
	username = params[:username]
	url = params[:url]

	username.strip!
	url.strip!

	# validate the username + url
	halt_with_text 500, 'invalid username' if !valid_username?(username)
	halt_with_text 500, 'url required' if url.nil? || url.empty?

	# maybe we already have a user for that url? this will fail with a PK error
	# anyway, but if we catch it here, we can give a nicer message
	user = User.get_by_url(url)
	halt_with_text 500, "a user @#{user.username} already exists for that url" if !user.nil?

	# get the url to make sure it exists and is valid
	user = User.for username, url

	begin
		data = UserHelper.update_user_data(user)
		UserHelper.update_user_record(user, data)
	rescue => e
		halt_with_text 500, "could not load updates from that url (#{e.message})"
	end

	if request.xhr?
		json user 
	else
		redirect to("/user/#{user.user_id}")
	end

end

get '/user/:user_id' do |user_id|
	begin
		user = User.get_by_id user_id
		halt_with_text 404, 'user not found' if user.nil?
		halt_with_text 404, 'no data for that user' if !user.data_exist?
	rescue => e
		halt_with_text 500, "could not load user (#{e.message})"
	end

	if user.needs_update?
		background_task :timeout => 30.0 do
			# is it safe to spawn another thread using the same user object?
			# I have no idea...
			#
			# the update user call with get the data, update the file on disk
			# and update the date and count for the user record in the db
			UserHelper.update_user(user)
		end
	end

	data = File.read user.data_path
	updates = UserHelper.updates_from_data(data)

	erb :user, :layout => :_layout, :locals => {
		:user => user,
		:data => updates
	}
end

class TwtxtUpdate
	attr_accessor :date
	attr_accessor :text

	def initialize(line)
		fields = line.split("\t")
		raise 'update should have only two fields' if fields.count != 2

		begin
			self.date = Time.parse(fields[0])
			self.text = fields[1]

			if self.date > 1.day.from_now
				raise 'update is in the future'
			end
		rescue => e
			raise "could not parse update (#{e.message})"
		end
	end
end

class UserHelper
	def self.update_user_record(user, data)
		updates = UserHelper.updates_from_data(data)
		user.update_count = updates.length
		user.updated_date = Time.now
		user.save_changes
	end

	def self.update_user(user)
		# update the updated_date straight away so this doesn't keep getting
		# triggered. Still could get into a race condition here, but going to
		# live with it
		user.updated_date = Time.now
		user.save_changes

		data = update_user_data(user)
		update_user_record(user, data)
	end

	def self.update_user_data(user)
		response = RestClient.head(user.update_url)
		_check_update_headers! response.headers

		# if no exception was raised when checking the headers we
		# can continue getting the data
		data = RestClient::Request.execute({
			:method => :get, 
			:url => user.update_url, 
			:timeout => 20
		})

		File.write user.data_path, data
		return data
	end

	def self._check_update_headers!(headers)
		content_type = headers[:content_type]
		content_length = headers[:content_length]

		if !content_type.nil?
			if !content_type.include?('text/plain') && !content_type.include?('text/html')
				raise 'text/plain or text/html file required'
			end
		end

		raise 'content-length header required' if content_length.nil?
		raise 'max update size is 1mb' if content_length.to_i > 1024 * 1024
	end


	def self.updates_from_data(data)
		lines = data.split("\n")
	
		updates = lines.map do |d| 
			begin
				TwtxtUpdate.new d 
			rescue
				nil
			end
		end

		updates.compact.sort_by { |u| u.date }.reverse
	end
end
