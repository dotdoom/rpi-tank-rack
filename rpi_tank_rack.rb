require 'cgi'
require 'erb'
require 'socket'
require 'thin'
require 'rack/websocket'

module RPiTank

class VideoStreamer
	class << self

		def start(framerate = 20, resolution = '640x480')
			stop
			@child = spawn("mjpg_streamer -i '/usr/lib/input_uvc.so -f #{framerate} -r #{resolution}' -o '/usr/lib/output_http.so -w /srv/http -p 8280'")
		end

		def stop
			Process.kill(:QUIT, @child)
		end
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
		'left'        => '23',
		'right'       => '26',
		'forward'     => '26 23',
		'backward'    => '24 22',
		'tower_left'  => '21',
		'tower_right' => '19',
		'stop'        => '',
	}

	def on_open(env)
		puts 'WebSocket: Client connected'
	end

	def on_close(env)
		puts 'WebSocket: Client disconnected'
	end

	def on_message(env, msg)
		translated_message = CONTROLS[msg]
		puts "WebSocket: Message #{msg.inspect} => #{translated_message.inspect}"
		connection.puts "set_output #{translated_message}"
	rescue
		puts "WebSocket: #$!"
	end

	def on_error(env, error)
		puts "WebSocket: #{error.inspect}"
	end

	def connection
		@connection ||= TCPSocket.new 'localhost', 11700
	end
end

end # module
