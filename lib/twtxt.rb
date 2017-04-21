require 'uri'
require 'cgi'
require 'rest-client'

require_relative './sequel-event-log'

#
# this contains a single Twtxt update, going to or from 
# an update file
#
class TwtxtUpdate
	attr_accessor :date
	attr_accessor :text
	@max_len = 255

	def initialize(text = nil, options = {})
		self.date = options[:date] || Time.now
		self.text = text unless text.nil?
	end

	def self.from_s(line)
		update = self.new
		fields = line.split("\t")
		raise 'update should have only two fields' if fields.count != 2

		begin
			update.date = Time.parse(fields[0]).localtime.round
			raise 'update is in the future' if update.date > 1.day.from_now
			raise 'update is too far in the past' if update.date < Time.gm(1984,1,1)
			
			update.text = fields[1].force_encoding('utf-8')
		rescue => e
			raise "could not parse update (#{e.message})"
		end

		return update
	end

	def to_s
		text = self.text.gsub("\n", ' ')
		"#{self.date.utc.iso8601}\t#{text}"
	end

	def self.to_html(text, options = nil)
		options ||= {}
		post_max_length = options[:post_max_length] || @max_len

		h = text.truncate(post_max_length).escape_html
		urls = URI::extract(text).select {|u| u.start_with? 'http' }

		# find the user links. Remove those from the urls collection
		user_link = /@&lt;([a-z0-9_]+)? (http.+?)&gt;/i
		at_user = /(\W|^)@([a-z0-9_]+?)(\W|$)/i

		while h =~ at_user
			match = h.match(at_user)
			name = match.captures[1]
			h.sub! "@#{name}", "<a class='auto-link' href='/user/at/#{name}'>&commat;#{name}</a>"
		end

		while h =~ user_link
			match = h.match(user_link)
			name = match.captures[0]
			url = match.captures[1].unescape_html
			link_url = "/user/at/#{User.id_for_url(url)[0..16]}?n=#{name}"

			h.sub! user_link, " <a class='auto-link' title='#{url}' href='#{link_url}'>@#{name}</a>"
			urls.delete url
		end

		# make all the urls in the text clickable
		urls.each do |url|
			next if url == 'http://' || url == 'https://'
			url.chop! if '.,:;()[]'.to_a.any? { |c| url.end_with? c }
			h.gsub! url.escape_html, "<a class='auto-link' href='#{url}'>#{url.escape_html}</a>"
		end

		h
	end

	def html(options = nil)
		self.class.to_html(self.text, options)
	end

	# appends the update to the given path
	def save_to(path)
		File.append path, "#{self}\n"
	end
end

class UpdateHelper
	# adds an update for the directory user
	def self.add_update(text, username = 'directory')
		dir = File.dirname(__FILE__)
		path = File.join dir, "../public/twtxt/#{username}.twtxt.txt"

		update = TwtxtUpdate.new
		update.text = text
		update.save_to path
	end

end

class UserHelper
	@user_agent = 'twtxt/1.1 (+http://twtxt.xyz/u/reednj.txt, @reednj) twtxt.xyz/1.21'

	def self.update_user_record(user, data)
		updates = UserHelper.updates_from_data(data)
		prev_last_post = user.last_post_in_db || Time.gm(2000, 1, 1)

		DB.transaction do

			#
			# we generate an array of hashes that can be passed to the mulit_insert
			# method, which will do a bulk insert to the server, which is important
			# because there is 18ms latency to the db in our setup 
			#
			update_data = updates.select{ |u| u.date > prev_last_post }.map do |u|
				id = Post.generate_id "[#{user.user_id}]-[#{u.date}]-[#{u.text}]"
				
				h = {
					:post_id => id, 
					:user_id => user.user_id, 
					:post_date => u.date,
					:post_text => u.text
				}
			end
			
			DB[:posts].multi_insert update_data

			user.update_count = user.db_update_count
			user.updated_date = Time.now
			user.last_post_date = updates.map { |u| u.date }.max
			user.save_changes
		end
	end

	def self.update_user(user)
		# update the updated_date straight away so this doesn't keep getting
		# triggered. Still could get into a race condition here, but going to
		# live with it
		user.updated_date = Time.now
		user.save_changes

		begin
			data = update_user_data(user)
			update_user_record(user, data) unless data.nil?
		rescue => e
			d = "#{user.username} (#{e})"
			LoggedEvent.for_event('user_update_failed', :user_id => user.short_id, :description => d).save
		end
	end

	def self.update_user_data(user)
		response = RestClient.head(user.update_url)
		_check_update_headers! response.headers

		headers = { :user_agent => @user_agent }
		if !user.last_modified_date.nil?
			headers[:'If-Modified-Since'] = user.last_modified_date.httpdate 
		end

		# if no exception was raised when checking the headers we
		# can continue getting the data
		begin
			response = RestClient.get user.update_url, headers
		rescue RestClient::NotModified
			LoggedEvent.for_event('user_not_modified', :user_id => user.short_id, :description => user.username).save
			return nil
		end

		if response.code == 200 && !response.headers.nil? && !response.headers[:last_modified].nil?
			last_modified = Time.parse response.headers[:last_modified]
			user.last_modified_date = last_modified.localtime
			user.save_changes
		end

		data = response.to_s.force_encoding('utf-8')
		
		LoggedEvent.for_event('user_updated', {
			:user_id => user.short_id, 
			:description => "#{user.username}, #{data.length} bytes"
		}).save

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

		if !content_length.nil?
			raise 'max update size is 1mb' if content_length.to_i > 1024 * 1024
		end
	end

	def self.updates_from_data(data)
		lines = data.split("\n")
	
		updates = lines.map do |d| 
			begin
				TwtxtUpdate.from_s d 
			rescue => e
				puts e.message
				nil
			end
		end

		updates.compact.sort_by { |u| u.date }.reverse
	end
end
