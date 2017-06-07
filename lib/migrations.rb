
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

if !DB[:users].columns.include? :feed_attr
	DB.alter_table :users do
		add_column :feed_attr, 'TEXT', {
			:null => true
		}
	end
end
