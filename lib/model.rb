require 'sequel'
require_relative '../config/app.config'

DB = Sequel.connect DB_CONFIG
PK_KEY_SALT = 'reednj.key.8Khg8Nh9UKyDadwK'

class Sequel::Model
	def to_json(args)
		self.values.to_json(args)
	end
end

class User < Sequel::Model

	dataset_module do
		def exist?(id)
			!self[id].nil?
		end

		def for(username, url)
			user = User.new
			user.user_id = url.sha1
			user.username = username
			user.update_url = url
			user.update_count = 0
			return user
		end

	end



end

