require 'json'
require 'rest-client'

module GitHub
	class OAuth
		attr_accessor :client_id
		attr_accessor :client_secret
		attr_accessor :access_token
		attr_accessor :scope

		def initialize(options = {})
			self.client_id = options[:client_id]
			self.client_secret = options[:client_secret]
			self.scope = options[:scope] || 'user:email'
		end
		
		def authorize_url
			"https://github.com/login/oauth/authorize?scope=#{scope}&client_id=#{client_id}"
		end

		# {
		#   access_token: "750ee4f6a3f15c0b1b99d42a463115e6e0375f91",
		#   token_type: "bearer",
		#   scope: "user:email"
		# }
		def token_from_code(session_code)
			json_text = RestClient.post('https://github.com/login/oauth/access_token', {
					:client_id => self.client_id,
					:client_secret => self.client_secret,
					:code => session_code
				},
				:accept => 'application/json'
			)
			
			result = JSON.parse json_text, :symbolize_names => true
			return result
		end

		def user
			authenticated!
			json_text = RestClient.get('https://api.github.com/user',{ 
				:params => { :access_token => access_token },
				:accept => 'application/json'
			})
			
			return JSON.parse json_text, :symbolize_names => true
		end

		def authenticated!
			raise 'access_token required' if access_token.nil?
		end
	end
end