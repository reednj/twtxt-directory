require 'uri'
require 'cgi'
require 'rest-client'

#
# this contains a single Twtxt update, going to or from 
# an update file
#
class TwtxtUpdate
	attr_accessor :date
	attr_accessor :text

	def initialize()
		@max_len = 140
		self.date = Time.now
	end

	def self.from_s(line)
		update = self.new
		fields = line.split("\t")
		raise 'update should have only two fields' if fields.count != 2

		begin
			update.date = Time.parse(fields[0]).localtime
			raise 'update is in the future' if update.date > 1.day.from_now
			
			update.text = fields[1]			
		rescue => e
			raise "could not parse update (#{e.message})"
		end

		return update
	end

	def to_s
		"#{self.date.utc.iso8601}\t#{self.text}"
	end

	def html
		h = self.text.truncate(@max_len).escape_html
		urls = URI::extract(self.text).select {|u| u.start_with? 'http' }

		# find the user links. Remove those from the urls collection
		user_link = /( |^)@&lt;([a-z0-9_]+)? (http.+?)&gt;( |$)/i
		at_user = /( |^)@([a-z0-9_]+)?( |$)/i

		while h =~ at_user
			match = h.match(at_user)
			name = match.captures[1]
			h.sub! at_user, " <a class='auto-link' href='/user/at/#{name}'>&commat;#{name}</a> "
		end

		while h =~ user_link
			match = h.match(user_link)
			name = match.captures[1]
			url = match.captures[2].unescape_html

			h.sub! user_link, " <a class='auto-link' title='#{url}' href='#{User.id_for_url(url)[0..16]}'>@#{name}</a> "
			urls.delete url
		end

		# make all the urls in the text clickable
		urls.each do |url|
			h.gsub! url.escape_html, "<a class='auto-link' href='#{url}'>#{url.escape_html}</a>"
		end

		h
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
	def self.update_user_record(user, data)
		updates = UserHelper.updates_from_data(data)
		new_update_count = updates.length - user.update_count 

		user.update_count = updates.length
		user.updated_date = Time.now
		user.last_post_date = updates.map { |u| u.date }.max
		user.save_changes

		if new_update_count > 0 && user.username != 'directory'
			UpdateHelper.add_update "#{new_update_count} update(s) were added for @#{user.username}"
		end

		DB.transaction do
			# in the db we just delete everything, and reinsert the last 100 posts
			# this is not really the best way to do things, but this simple way will
			# work better until a faster / more complete way to syncing the data files
			# to the db is required
			DB[:posts].where(:user_id => user.user_id).delete()

			#
			# we generate an array of hashes that can be passed to the mulit_insert
			# method, which will do a bulk insert to the server, which is important
			# because there is 18ms latency to the db in our setup 
			#
			update_data = updates.first(100).map do |u|
				id = Post.generate_id "[#{user.user_id}]-[#{u.date}]-[#{u.text}]"
				
				h = {
					:post_id => id, 
					:user_id => user.user_id, 
					:post_date => u.date, 
					:post_text => u.text
				}
			end

			DB[:posts].multi_insert update_data
		end
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

		if !content_length.nil?
			raise 'max update size is 1mb' if content_length.to_i > 1024 * 1024
		end
	end

	def self.updates_from_data(data)
		lines = data.split("\n")
	
		updates = lines.map do |d| 
			begin
				TwtxtUpdate.from_s d 
			rescue
				nil
			end
		end

		updates.compact.sort_by { |u| u.date }.reverse
	end
end
