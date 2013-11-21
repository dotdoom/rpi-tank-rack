require 'cgi'
require 'erb'
require 'socket'

class RPiTankRack
	ALLOWED_ACTIONS = %w(home go)
	RESPONSE_INTERNAL_SERVER_ERROR = [500, { 'Content-Type' => 'text/plain' }, ['Internal Server Error']]
	RESPONSE_FORBIDDEN = [403, { 'Content-Type' => 'text/plain' }, ['Forbidden']]
	CONTROLS = {
		'left'       => '23',
		'right'      => '26',
		'forward'    => '26 23',
		'backward'   => '24 22',
		'tower_left' => '21',
		'tower_right'=> '19',
	}

	attr_reader :params, :path, :source_ip

	def home
		[200, { 'Content-Type' => 'text/html' }, [ERB.new(File.read('home.html.erb')).result(binding)]]
	end

	def go
		connection.puts "set_output #{CONTROLS[params['action'].join]}"
		[200, { 'Content-Type' => 'text/plain' }, ['ok']]
	end

	def call(env)
		@source_ip = env['HTTP_X_REAL_IP'] || env['REMOTE_ADDR']
		@path = env['PATH_INFO'].to_s[1..-1] # strip leading '/'
		@path = ALLOWED_ACTIONS.first if @path.empty?
		@params = CGI::parse(env['QUERY_STRING'].to_s)

		raise 'Forbidden' unless ALLOWED_ACTIONS.include?(path)

		public_send(@path)
	rescue
		return RESPONSE_FORBIDDEN if $!.message == 'Forbidden'
		warn "Exception when processing #{path} with #{params} from #{source_ip}"
		warn "Error #{$!.inspect} at:\n#{$!.backtrace.join $/}"
		RESPONSE_INTERNAL_SERVER_ERROR
	end

	def connection
		@connection ||= TCPSocket.new 'localhost', 11700
	end
end
