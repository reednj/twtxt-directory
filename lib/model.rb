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
	one_to_many :posts

	dataset_module do
		def exist?(id)
			!self[id].nil?
		end

		def get_by_id(partial_id)
			users = User.where(Sequel.like(:user_id, partial_id + '%')).take(100)
			raise 'more than one user with that key' if users.count > 1
			return nil if users.empty?
			return users[0]
		end

		def get_by_url(url)
			id = id_for_url(url)
			User[id]
		end
		
		def for(username, url)
			user = User.new
			user.user_id = id_for_url(url)
			user.username = username
			user.update_url = url
			user.update_count = 0
			return user
		end

		def id_for_url(url)
			url.sha1
		end
	end

	def data_path
		dir = File.dirname(__FILE__)
		File.join dir, "../data/#{user_id}.txt"
	end

	def needs_update?
		self.updated_date.nil? || self.updated_date.age > 5.minutes
	end

	# the actual content of the updates are stored in a file, this will
	# tell us if it exists
	def data_exist?
		File.exist? self.data_path
	end

	def profile_url
		"/user/#{user_id[0...16]}"
	end
end

class Post < Sequel::Model
	many_to_one :user
	
	dataset_module do
		def exist?(id)
			!self[id].nil?
		end

		def from_update(update, user)
			user_id = (user.is_a? String)? user : user.user_id

			post = Post.new
			post.user_id = user_id
			post.post_text = update.text
			post.post_date = update.date
			post.post_id = post.hash
			return post
		end

		def generate_id(s)
			s.sha1
		end

		def generate_short_id
			generate_id[0..16]
		end


	end

	def text
		post_text
	end

	def date
		post_date
	end

	def html
		TwtxtUpdate.to_html(self.text)
	end
end
