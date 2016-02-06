require 'sinatra'
require 'sinatra/cookies'
require 'sinatra/content_for'
require 'sinatra/json'

require 'json'
require 'erubis'

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

