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

if !DB[:users].columns.include? :github_user
	DB.alter_table :users do
		add_column :github_user, :varchar, {
			:size => 64,
			:null => true,
			:unique => true
		}
	end
end

class User < Sequel::Model
	one_to_many :posts do |ds|
		ds.reverse_order(:post_date).limit(256)
	end

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

		def get_by_name(username)
			User.where(:username => username).first
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
			active_since(1.day.ago)
		end

		def active_since(since_date)
			where('last_post_date > ?', since_date)
		end
	end


	def replies
		simple_query = "%@#{username}%"
		long_query = "%@<#{username} %"

		@replies ||= Post.eager(:user).
			where(Sequel.like(:post_text, simple_query)).
			or(Sequel.like(:post_text, long_query)).
			reverse_order(:post_date)
	end
	
	def local?
		!!is_local
	end

	def short_id
		user_id[0..16] unless user_id.nil?
	end

	def data_path
		dir = File.dirname(__FILE__)
		File.join dir, "../data/#{user_id}.txt"
	end

	def needs_update?
		return false if local?
		self.updated_date.nil? || self.updated_date.age > 5.minutes
	end

	# the actual content of the updates are stored in a file, this will
	# tell us if it exists
	def data_exist?
		local? || File.exist?(self.data_path)
	end

	def profile_url
		"/user/#{user_id[0...16]}"
	end

	def replies_url
		"/user/#{username}/replies"
	end

	def to_txt
		"@<#{username} #{update_url}>"
	end

	def posts_to_txt
		posts.reverse.map {|p| "#{p.date.utc.iso8601}\t#{p.text}"}.join("\n")
	end

	def metadata
		{
			:nick => username, 
			:url => update_url, 
			:user_agent => 'twtxt.xyz (+http://twtxt.xyz)'
		}
	end

	def updates
		posts.map{ |p| p.to_update }
	end

	def local_update_url
		"http://twtxt.xyz/u/#{github_user || username}.txt"
	end

	def update_url
		return local_update_url if local?
		values[:update_url]
	end

	def last_post_in_db
		Post.where(:user_id => user_id).max(:post_date)
	end

	def db_update_count
		Post.where(:user_id => user_id).count
	end
end

class Post < Sequel::Model
	many_to_one :user
	
	def before_create
		post_id ||= self.to_txt.sha1
	end

	dataset_module do
		def containing(text)
			where(Sequel.like(:post_text, "%#{text}%"))
		end
		
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

	def to_update
		TwtxtUpdate.new(text, :date => date)
	end

	def to_json_feed
		{
			:id => post_id,
			:context_html => html(:root_url => 'http://twtxt.xyz/'),
			:url => "http://twtxt.xyz#{post_url}"
		}
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
