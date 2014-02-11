require 'cgi'
require 'erb'
require 'socket'
require 'thin'
require 'rack/websocket'
require 'shellwords'

module RPiTankRack

class VideoStreamer
	class << self
		PIDFILE = 'mjpg_stream.pid'

		def start(options = {})
			stop
			command = "mjpg_streamer -i #{
				("/usr/lib/input_uvc.so " <<
					"-f #{(options[:framerate] || 20).to_s.shellescape} " <<
					"-r #{(options[:resolution] || '640x480').to_s.shellescape}"
				).shellescape} -o '/usr/lib/output_http.so -w /srv/http -p 8280'"
			puts "Running: #{command}"

			pid = Process.spawn command
			Process.detach(pid)
			File.write(PIDFILE, pid)
		end

		def stop
			pid = self.pid

			5.times do
				Process.kill(:QUIT, pid)
				sleep 1
			end

			Process.kill(:KILL, pid)
		rescue
			puts "Kill #{pid}: #$!"
		end

		def pid
			pid = File.read(PIDFILE).to_i rescue return
			Process.kill(0, pid)
			pid
		rescue
			File.unlink(PIDFILE)
			nil
		end

		alias_method :running?, :pid
	end
end

class WebApplication
	RESPONSE_INTERNAL_SERVER_ERROR = [500, { 'Content-Type' => 'text/plain' }, ['Internal Server Error']]
	RESPONSE_NOT_FOUND = [404, { 'Content-Type' => 'text/plain' }, ['Not Found']]

	attr_reader :params, :source_ip, :request_host_with_port, :request_host

	def call(env)
		return RESPONSE_NOT_FOUND unless env['PATH_INFO'] == '/'

		@source_ip = env['HTTP_X_REAL_IP'] || env['REMOTE_ADDR']
		@params = CGI::parse(env['QUERY_STRING'].to_s)
		@request_host_with_port = env['HTTP_HOST']
		@request_host = @request_host_with_port.split(':', 2).first

		if (res = @params['res']) && res.any?
			VideoStreamer.start(resolution: res.first)
		elsif !VideoStreamer.running?
			VideoStreamer.start
		end

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
