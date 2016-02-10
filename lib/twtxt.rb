
require 'rest-client'

#
# this contains a single Twtxt update, going to or from 
# an update file
#
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

		if !content_length.nil?
			raise 'max update size is 1mb' if content_length.to_i > 1024 * 1024
		end
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
