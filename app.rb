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

use Rack::Deflater
set :erb, :escape_html => true
set :version, GitVersion.current('/home/reednj/code/twtxt.git/.git')
set :short_version, settings.version.split('-').first

# when this is true, all sql queries will be dumped to the console, making
# it easier to debug exactly what the models are doing
set :log_sql, false

# these users will be hidden from the timeline, and from the user replies page
set :hidden_users, ['directory', 'soltempore', 'tiktok']

set :admin_password, ADMIN_PASSWORD

configure :development do
	set :server, :thin
	set :bind, "127.0.0.1"
	set :port, 4567

	also_reload './lib/twtxt.rb'
	also_reload './lib/model.rb'
	also_reload './lib/extensions.rb'

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
end

get '/' do
	# dont want a general redirect in nginx, in case some clients don't handle 302's
	# so we will just redirect the root to the new page. Maybe later roll it out to
	# some other pages
	if settings.production? && request.host == 'twtxt.reednj.com'
		return redirect to("http://twtxt.xyz#{request.path}")
	end

	erb :home, :layout => :_layout, :locals => {
		:users => User.order_by(:username).take(500),
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

	simple_query = "%@#{username}%"
	long_query = "%@<#{username} %"

	posts = Post.eager(:user).
		where(Sequel.like(:post_text, simple_query)).
		or(Sequel.like(:post_text, long_query)).
		reverse_order(:post_date).
		limit(256).all

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
	admin_only!

	erb :create_post, :layout => :_layout, :locals => {
		:username => 'reednj',
		:result => params[:r] || nil,
		:js => {
			:update_length => 140
		}
	}
end

post '/update/add' do
	admin_only!

	username = 'reednj'
	user = user_for_username!(username)
	text = (params[:content] || '').strip
	halt_with_text 500, 'update text requried' if text.nil? || text.empty?

	begin
		post = Post.new do |p|
			p.user_id = user.user_id
			p.post_text = text
			p.post_date = Time.now
		end

		post.post_id = post.to_txt.sha1
		post.save

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

get '/user/:user_id.txt' do  |user_id|
	user = get_user! user_id
	text user.posts_to_txt
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


