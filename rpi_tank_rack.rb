require 'cgi'
require 'erb'
require 'socket'
require 'thin'
require 'rack/websocket'

module RPiTank

class VideoStreamer
	def kill_if_exists
		Process.kill(:QUIT, @child)
	end
end

class WebApplication
	RESPONSE_INTERNAL_SERVER_ERROR = [500, { 'Content-Type' => 'text/plain' }, ['Internal Server Error']]

	attr_reader :params, :source_ip, :request_host_with_port, :request_host

	def call(env)
		@source_ip = env['HTTP_X_REAL_IP'] || env['REMOTE_ADDR']
		@params = CGI::parse(env['QUERY_STRING'].to_s)
		@request_host_with_port = env['HTTP_HOST']
		@request_host = @request_host_with_port.split(':', 2).first

		[200, { 'Content-Type' => 'text/html' }, [ERB.new(File.read('index.html.erb')).result(binding)]]
	rescue
		warn "Exception when processing with #{params} from #{source_ip}"
		warn "Error #{$!.inspect} at:\n#{$!.backtrace.join $/}"
		RESPONSE_INTERNAL_SERVER_ERROR
	end
end

class SocketControlApplication < Rack::WebSocket::Application
	CONTROLS = {
		'left'       => '23',
		'right'      => '26',
		'forward'    => '26 23',
		'backward'   => '24 22',
		'tower_left' => '21',
		'tower_right'=> '19',
	}

	def on_open(env)
		puts 'opened'
	end

	def on_close(env)
		puts 'closed'
	end

	def on_message(env, msg)
		connection.puts "set_output #{CONTROLS[msg]}"
	end

	def on_error(env, error)
		puts "error: #{error.inspect}"
	end

	def connection
		@connection ||= TCPSocket.new 'localhost', 11700
	end
end

end # module
