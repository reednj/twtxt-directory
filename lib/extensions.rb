require 'digest/sha1'

class GitVersion
	def self.current(gitdir='./.git')
		gitdir = './.git' if !File.exist? gitdir
		git_exec = Gem.win_platform? ? 'git' : '/usr/bin/git'
		return (`#{git_exec} --git-dir=#{gitdir} describe --long --always --abbrev=3`).delete("\n")
	end
end

class Time
	def diff_in_words(t=nil)
		t ||= Time.now
		result = (t - self).abs.time_in_words
		return t > self ? result + ' ago' : result + ' to go'
	end

	def age
		(Time.new - self)
	end

	def age_in_words
		self.age.abs.time_in_words
	end

	def day_name
		self.strftime '%A'
	end

	def weekend?
		#self.saturday? || self.sunday? # this is nice, but only works on r1.9
		[0, 6, 7].include?(wday)
	end

	def to_date_s
		self.strftime '%Y-%m-%d'
	end

	def beginning_of_month
		Time.parse(self.strftime("%Y-%m-01"))
	end
end

class Date
	def today?
		self == Date.today
	end
end

class Numeric
	def to_pct(precision=1)
		p = "%.#{precision}f" % (self*100)
		"#{p} %"
	end

	def to_usd(precision=2)
		s = '$' + ("%.#{precision}f" % self.abs)
		s = '-' + s if self < 0
		return s
	end

	def to_s_with_delimiters
		self.round.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
	end

	def to_s_with_si
		return (self / 1000.0).round(2).to_s + 'k' if self > 1000
		return (self / (1000.0 * 1000.0)).round(2).to_s + 'm' if self > 1000 * 1000
		return self
	end

	def time_in_words
		if self < 1.minute
			number = self.round
			type = 'sec'
		elsif self < 1.hour
			number = (self / 1.minute).round
			type = 'min'
		elsif self < 1.day
			number = (self / 1.hour).round
			type = 'hour'
		elsif self < 2.weeks
			number = (self / 1.day).round
			type = 'day'
		elsif self < 5.weeks
			number = (self / 1.week).round
			type = 'week'
		elsif self < 52.weeks
			number = (self / 30.days).round 1
			type = 'month'
		else
			number = (self / 365.days).round 1
			type = 'year'
		end

		type += 's' if number != 1
		"#{number.to_s} #{type}"
	end

	# gives the time remaining in a xx hrs xx mins style (assuming self = a duration
	# in seconds)
	def time_remaining
		s = ''
		h = (self / 1.hour).floor
		m = ((self % 1.hour) / 1.minute).floor
		
		s = "#{s} #{h}hrs" if h > 0
		s = "#{s} #{m}mins" if m > 0 || s.empty?

		return s.strip

	end
end

class String
	def sha1
		Digest::SHA1.hexdigest self
	end

	def first(n=1)
		self[0...n]
	end

	def self.rand(len = 8)
		d = ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z']
		return (0..len).to_a.map { d.rand }.join ''
	end


	def truncate(max_len = 32)
		append = '...'
		return self if self.length < max_len
		return self[0...(max_len - append.length)] + append
	end

	def fix_encoding
		encode('UTF-8', 'binary', invalid: :replace, undef: :replace, replace: '')
	end
end

class Array
	def rand
		self[Object.send(:rand, self.length)]
	end

	def self.from(o)
		return o if o.kind_of? Array
		return [o]
	end
end

class Fixnum
	def from_now
		Time.now + self
	end

	def ago
		Time.now - self
	end

	def seconds
		self
	end

	def minutes
		self * 60
	end

	def hours
		self * 60.minutes
	end

	def days
		self * 24.hours
	end

	def weeks
		self * 7.days
	end

	alias minute minutes
	alias hour hours
	alias day days
	alias week weeks
end

class OpenStruct
	def self.from(o)
		return o if o.kind_of? OpenStruct
		return OpenStruct.new o
	end

	def to_json(options = nil)
		@table.to_json(options)
	end
end

class Hash
	def to_ostruct
		OpenStruct.new(self)
	end
end

class File
	def self.append(path, data)
		File.open(path, 'a:UTF-8') do |file| 
			file.write data 
		end
	end
end
