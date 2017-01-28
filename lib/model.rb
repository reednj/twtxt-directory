require 'sequel'
require_relative '../config/app.config'

DB = Sequel.connect DB_CONFIG
PK_KEY_SALT = 'reednj.key.8Khg8Nh9UKyDadwK'

class Sequel::Model
	def to_json(args)
		self.values.to_json(args)
	end
end

if !DB[:users].columns.include? :last_modified_date
	# this column stores the last modifed date sent from the server to be used for
	# caching. You would expect that the If-Modifed-since header would use a less-then
	# comparision, so we could just use the mtime on the file of something, but thats not
	# the case - most servers do an exact match, treating the modifed date like an etag
	DB.alter_table :users do
		add_column :last_modified_date, :timestamp, :default => nil, :null => true
	end
end

if !DB[:users].columns.include? :is_local
	DB.alter_table :users do
		add_column :is_local, :boolean, {
			:default => false, 
			:null => false
		}
	end
end

class User < Sequel::Model
	one_to_many :posts, :order => :post_date

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
			url.gsub('https://', 'http://').sha1
		end

		def active
			where('last_post_date > ?', 1.day.ago)
		end
	end

	def short_id
		user_id[0..16] unless user_id.nil?
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

	def to_txt
		"@<#{username} #{update_url}>"
	end

	def posts_to_txt
		
		posts.map {|p| "#{p.date.iso8601}\t#{p.text}"}.join("\n")
	end
end

class Post < Sequel::Model
	many_to_one :user
	
	def before_create
		post_id ||= self.to_txt.sha1
	end

	dataset_module do
		def exist?(id)
			!self[id].nil?
		end

		def from_update(update, u)
			user_id = (u.is_a? String)? u : u.user_id

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

		def get_by_id(partial_id)
			posts = Post.where(Sequel.like(:post_id, partial_id + '%')).take(100)
			raise 'more than one user with that key' if posts.count > 1
			return nil if posts.empty?
			return posts[0]
		end
	end

	def text
		post_text
	end

	def date
		post_date
	end

	def html(options = nil)
		TwtxtUpdate.to_html(self.text, options)
	end

	def to_txt
		"#{user.to_txt}\t#{date.iso8601}\t#{text}"
	end

	def post_url
		"/update/#{post_id[0...16]}"
	end

end
