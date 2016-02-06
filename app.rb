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
set :version, 'v0.1'

configure :development do
	also_reload './lib/model.rb'
	also_reload './lib/extensions.rb'
end

configure :production do

end

helpers do

	def background_task
		raise 'background_task needs a block' unless block_given?

		Thread.new do
			begin
				yield
			rescue => e
				File.append 'error.log', "#{e.class.to_s}\t#{e.message}\n"
			end
		end
	end

	# basically the same as a regular halt, but it sends the message to the 
	# client with the content type 'text/plain'. This is important, because
	# the client error handlers look for that, and will display the message
	# if it is text/plain and short enough
	def halt_with_text(code, message = nil)
		message = message.to_s if !message.nil?
		halt code, {'Content-Type' => 'text/plain'}, message
	end

end

get '/' do
	erb :home, :layout => :_layout, :locals => {
		:users => User.order_by(:username).take(500)
	}
end

get '/user/:user_id' do |user_id|
	user = User[user_id]
	halt_with_text 404, 'user not found' if user.nil?
	halt_with_text 404, 'no data for that user' if !user.data_exist?

	if user.needs_update?
		background_task do 
			# is it safe to spawn another thread with the same user object?
			# I have no idea...
			#
			# update the updated_date straight away so this doesn't keep getting
			# triggered. Still could get into a race condition here, but going to
			# live with it
			user.updated_date = Time.now
			user.save_changes

			UserHelper.update_user_data(user)
			user.update_count = updates.length
			user.save_changes
		end
	end

	data = File.read user.data_path
	updates = UserHelper.updates_from_data(data)

	erb :user, :layout => :_layout, :locals => {
		:user => user,
		:data => updates
	}
end

get '/add' do
	# later this will add all the users, but for now just add the default set

	User.for('benaiah', 'http://benaiah.me/twtxt.txt').save
	User.for('buckket', 'http://buckket.org/twtxt.txt').save
	User.for('erlehmann', 'http://daten.dieweltistgarnichtso.net/tmp/docs/twtxt.txt').save
	User.for('parteigaenger', 'http://vigintitres.eu/twtxt.txt').save
	User.for('plom', 'http://test.plomlompom.com/twtxt/plom.txt').save
	User.for('zrolaps', 'http://test.plomlompom.com/twtxt/zrolaps.txt').save
	
	'ok'
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
	def self.update_user_data(user)
		data = RestClient.get user.update_urls
		File.write user.data_path, data
		return data
	end

	def self.updates_from_data(data)
		lines = data.split("\n").reverse
	
		updates = lines.map do |d| 
			begin
				TwtxtUpdate.new d 
			rescue
				nil
			end
		end

		updates.compact
	end
end
