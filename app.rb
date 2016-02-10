require 'sinatra'
require 'sinatra/cookies'
require 'sinatra/content_for'
require 'sinatra/json'

require 'json'
require 'erubis'

require "sinatra/reloader" if development?

require './lib/model'
require './lib/twtxt'
require './lib/extensions'
require './lib/sinatra-schema-backup'

use Rack::Deflater
set :erb, :escape_html => true
set :version, GitVersion.current('/home/reednj/code/twtxt.git/.git')

configure :development do
	also_reload './lib/twtxt.rb'
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

get '/recent' do
	erb :recent, :layout => :_layout, :locals => {
		:users => User.where('last_post_date is not null').reverse_order(:last_post_date).take(500)
	}
end

get '/timeline/all' do
	erb :timeline, :layout => :_layout, :locals => {
		:posts => Post.eager(:user).reverse_order(:post_date).take(256).select{|p| !p.user.nil? }
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

	# the user was added - we want to log this fact in @directory
	UpdateHelper.add_update "user @#{user.username} was added to the directory"

	if request.xhr?
		json user 
	else
		redirect to("/user/#{user.user_id}")
	end

end

get '/user/at/:username' do |username|
	user = User.where(:username => username).first
	halt_with_text 404, 'user not found' if user.nil?
	redirect to(user.profile_url)
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


