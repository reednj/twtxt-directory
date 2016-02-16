
helpers do
	# put this method at the top of a route to make it only accessable to the 
	# admin user. The password for this user can be set with settings.admin_password
	#
	# You can also add this to the 'before' filter for a certain path / directory
	# to avoid having to add it to every route, if there are lots of them
	def admin_only!
		if !admin_authenticated?
			headers['WWW-Authenticate'] = 'Basic realm="Restricted Area"'
			halt 401, "Not authorized\n"
		end
	end

	def admin_authenticated?
		raise 'settings.admin_password must be set to use basic authentication' if settings.admin_password.nil?
		@auth ||=  Rack::Auth::Basic::Request.new(request.env)
		@auth.provided? && @auth.basic? && @auth.credentials && @auth.credentials == ['admin', settings.admin_password]
	end
end