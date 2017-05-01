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
require './lib/sinatra-basic-auth'
require './lib/sinatra-twitter-gateway'

require './lib/github-oauth'

use Rack::Deflater
set :erb, :escape_html => true
set :version, GitVersion.current('/home/reednj/code/twtxt.git/.git')
set :short_version, settings.version.split('-').first

use Rack::Session::Cookie, 
	:key => 'rack.session',
	:expire_after => 90.days,
	:secret => GITHUB_CONFIG[:client_secret] + '.reednj'	

# when this is true, all sql queries will be dumped to the console, making
# it easier to debug exactly what the models are doing
set :log_sql, false

# these users will be hidden from the timeline, and from the user replies page
set :hidden_users, ['directory', 'soltempore', 'tiktok', 'reddit_random', 'hacker_news', 'ekch', 'caudasol']

set :admin_password, ADMIN_PASSWORD

configure :development do
	set :server, :thin
	set :bind, "127.0.0.1"
	set :port, 4567

	Dir["./lib/*.rb"].each {|f| also_reload f }

	if settings.log_sql
		DB.logger =  Logger.new(STDOUT)
	end
end

configure :production do

end

helpers do


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

	def html_user_link(username)
		"<a class='user-link' href='/user/at/#{username}'>@#{username}</a>"
	end

	def html_post_link(post)
		"<a class='post-link' href='#{post.post_url}'>#{post.date.diff_in_words}</a>"
	end

	def text(data, options = nil)
		options ||= {}

		return [
			options[:code] || 200,
			{'Content-Type' => 'text/plain; charset=utf-8'},
			data.respond_to?(:to_txt) ? data.to_txt : data.to_s
		]
	end

	def validate_format!(format)
		halt_with_text 500, "invalid format (#{format})" if !format.nil? && format != 'txt'
	end

	def user_for_username!(username)
		user = User.where(:username => username).first
		halt_with_text 404, 'user not found' if user.nil?
		return user
	end

	def get_user!(user_id)
		User.get_by_id(user_id) || halt_with_text(404, 'user not found')
	end

	def github
		@github ||=  GitHub::OAuth.new(GITHUB_CONFIG)
		@github.access_token = session[:access_token] unless session[:access_token].nil?
		@github
	end

	def authenticated?
		!session[:user_id].nil?
	end

	def authenticated!
		halt_with_text 401, 'login required' unless authenticated?
	end

	def current_user
		return nil unless authenticated?
		user_id = session[:user_id]
		User[user_id]
	end

	def current_user!
		authenticated!
		current_user || halt_with_text(404, 'user not found')
	end

	def html_user_actions(user)
		erb :_user_actions, :locals => {:user => user}
	end
end

get '/' do
	# dont want a general redirect in nginx, in case some clients don't handle 302's
	# so we will just redirect the root to the new page. Maybe later roll it out to
	# some other pages
	if settings.production? && request.host == 'twtxt.reednj.com'
		return redirect to("http://twtxt.xyz#{request.path}")
	end

	erb :home, :layout => :_layout, :locals => {
		:user => current_user,
		:users => User.order_by(:username).take(500).select{|u| !u.username.start_with? '.'},
		:user_count => User.count
	}
end

get '/recent' do
	erb :recent, :layout => :_layout, :locals => {
		:users => User.where('last_post_date is not null').reverse_order(:last_post_date).take(500)
	}
end

get '/users.txt' do
	# add a delay as a naive strategy to stop DoS...
	sleep 0.5 

	text User.take(500)
end

get '/timeline/all.?:format?' do |format|
	validate_format! format

	total_count = Post.count
	posts = Post.eager(:user).reverse_order(:post_date).limit(256).all

	posts.select! do |p|
		!(p.user.nil? || settings.hidden_users.include?(p.user.username))
	end

	# return text if requried
	return text(posts) if format == 'txt'

	erb :timeline, :layout => :_layout, :locals => {
		:post_count => total_count,
		:posts => posts,
		:target_user => nil,
		:timeline_type => :all
	}
end

get '/user/:username/replies.?:format?' do |username, format|
	validate_format! format

	user = User.get_by_name(username) || not_found('user not found')
	posts = user.replies.limit(256).all

	posts.select! do |p|
		!(p.user.nil? || settings.hidden_users.include?(p.user.username)) && p.text =~ /(@|@<)#{username}\W/
	end

	# return text if requried
	return text(posts) if format == 'txt'

	erb :timeline, :layout => :_layout, :locals => {
		:post_count => posts.length,
		:posts => posts,
		:target_user => username,
		:timeline_type => :replies
	}
end

get '/update/new' do
	user = current_user!

	erb :create_post, :layout => :_layout, :locals => {
		:username => user.username,
		:result => params[:r] || nil,
		:post_hint => params[:hint] || '',
		:js => {
			:update_length => 255
		}
	}
end

post '/update/save' do
	user = current_user!
	text = (params[:content] || '').strip
	halt_with_text 500, 'update text requried' if text.nil? || text.empty?

	begin
		DB.transaction do
			post = Post.new do |p|
				p.user_id = user.user_id
				p.post_text = text
				p.post_date = Time.now
			end

			post.post_id = post.to_txt.sha1
			post.save

			user.last_post_date = post.post_date
			user.last_modified_date = post.post_date
			user.update_count = user.db_update_count
			user.save_changes
		end

		redirect to('/update/new')
	rescue => e
		redirect to('/update/new?r=' + URI.encode(e.to_s))
	end
end

get '/update/:post_id' do |post_id|
	post = Post.get_by_id post_id
	halt_with_text 404, 'post not found' if post.nil?

	erb :timeline, :layout => :_layout, :locals => {
		:posts => [post],
		:target_user => post.user.username,
		:timeline_type => :single_post
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

get '/profile/update' do
	user = current_user!

	erb :edit_profile, :layout => :_layout, :locals => {
		:user => user,
		:result => params[:result]
	}
end

post '/profile/update' do
	user = current_user!

	begin
		username = params[:username].strip
		raise 'invalid username' unless valid_username?(username)
		raise 'username is already taken' unless User.get_by_name(username).nil?
		user.username = username
		user.save_changes
	rescue => e
		redirect to('/profile/update?result=' + URI.encode(e.to_s))
	end

	redirect to('/')
end

get '/user/at/:username_or_id' do |username_or_id|
	username_hint = params[:n]

	# keep querying with all the information we have until we find something
	# could do with more efficiently in a single query, but its probably not 
	# worth it atm
	user = User.get_by_id username_or_id
	user = User.where(:username => username_or_id).first if user.nil?
	user = User.where(:username => username_hint).first if user.nil? && !username_hint.nil?
	
	halt_with_text 404, 'user not found' if user.nil?
	redirect to(user.profile_url)
end

['/user/:user_id.txt', '/u/:user_id.txt'].each do |url|
	get url do  |user_id|
		user = User.get_by_id(user_id) || User.get_by_name(user_id) || not_found('user not found')
		last_modified user.last_post_date
		etag user.last_post_date.to_i.to_s
		
		text erb :"posts.txt", :locals => { :user => user }
	end
end

get '/user/:user_id' do |user_id|
	begin
		user = User.get_by_id user_id
		halt_with_text 404, 'user not found' if user.nil?
	rescue => e
		halt_with_text 500, "could not load user (#{e.message})"
	end

	if !user.local? && user.needs_update?
		WorkerThread.new.start :timeout => 30.0 do
			# is it safe to spawn another thread using the same user object?
			# I have no idea...
			#
			# the update user call with get the data, update the file on disk
			# and update the date and count for the user record in the db
			UserHelper.update_user(user)
		end
	end

	erb :user, :layout => :_layout, :locals => {
		:user => user,
		:data => user.updates.first(256)
	}
end

get '/oauth/complete' do
	code = params[:code]
	token = github.token_from_code(code)
	session[:access_token] = token[:access_token]
	session[:github_user] = github.user[:login]

	is_new_user = false
	local_user = User.where(:github_user => session[:github_user]).first
	
	if local_user.nil?
		begin
			is_new_user = true
			local_user = User.new do |u|
				u.username = session[:github_user]
				u.github_user = session[:github_user]
				u.user_id = User.id_for_url(u.local_update_url)
				u.update_url = u.local_update_url
				u.is_local = true
			end
			
			local_user.save
		rescue Sequel::UniqueConstraintViolation
			error_message = "Error: that username is already taken (#{session[:github_user]})"
			return redirect to('/?user_add_error=' + URI.encode(error_message))
		rescue => e
			return redirect to('/?user_add_error=' + URI.encode(e.to_s))
		end
	end
	
	session[:user_id] = local_user.user_id
	redirect to(is_new_user ? '/profile/update' : '/')
end

get '/oauth/logout' do
	session.clear
	redirect to('/')
end
