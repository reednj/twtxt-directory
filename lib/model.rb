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
	end

end

