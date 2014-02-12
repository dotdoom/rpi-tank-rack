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
	class PowerState
		class Directionable
			attr_reader :direction

			# Protect against double directioning
			def direction=(new_dir)
				if @direction && new_dir
					# Lockout
					@direction = false
				elsif @direction != false
					@direction = new_dir
				end
				new_dir
			end

			def reset
				@direction = nil
			end

			def to_pin
				@pins[@direction]
			end
		end

		class Track < Directionable
			def initialize(forward_pin, reverse_pin)
				@pins = {
					forward: forward_pin,
					reverse: reverse_pin,
				}
			end
		end

		attr_reader :track_left, :track_right

		class Tower < Directionable
			def initialize(left_pin, right_pin)
				@pins = {
					left: left_pin,
					right: right_pin,
				}
			end
		end

		attr_reader :tower

		def initialize
			@track_left = Track.new(26, nil) # TODO: 24?
			@track_right = Track.new(23, nil) # TODO: 22?
			@tower = Tower.new(21, 19)
		end

		def reset
			[@track_left, @track_right, @tower].each(&:reset)
		end

		def to_pin
			[@track_left, @track_right, @tower].map(&:to_pin).compact.join(' ')
		end

		def to_s
			[@track_left, @track_right, @tower].zip(%w(LEFT RIGHT TOWER)).map { |object, name|
				"#{name}: #{object.direction}" if object.direction
			}.compact.join(', ')
		end
	end

	CONTROLS = {
		'engine_left'        => -> ps { ps.track_right.direction = :forward },
		'engine_right'       => -> ps { ps.track_left.direction = :forward },
		'engine_forward'     => -> ps { ps.track_left.direction = ps.track_right.direction = :forward },
		'engine_reverse'     => -> ps { ps.track_left.direction = ps.track_right.direction = :reverse },
		'tower_left'         => -> ps { ps.tower.direction = :left },
		'tower_right'        => -> ps { ps.tower.direction = :right },
		'trackleft_forward'  => -> ps { ps.track_left.direction = :forward },
		'trackright_forward' => -> ps { ps.track_right.direction = :reverse },
		'trackleft_reverse'  => -> ps { ps.track_left.direction = :forward },
		'trackright_reverse' => -> ps { ps.track_right.direction = :reverse },
		'stop'               => -> ps {},
	}

	def on_open(env)
		puts 'WebSocket: Client connected'
	end

	def on_close(env)
		puts 'WebSocket: Client disconnected'
		connection.puts "quit"
	end

	def on_message(env, msg)
		power_state.reset
		msg.split.each { |control| CONTROLS[control].call(power_state) } rescue false
		puts "WebSocket: message #{msg.inspect} => #{power_state.to_s.inspect}"
		connection.puts "set_output #{power_state.to_pin}"
	rescue
		puts "WebSocket: #$!"
	end

	def on_error(env, error)
		puts "WebSocket: #{error.inspect}"
	end

	def connection
		@connection ||= TCPSocket.new 'localhost', 11700
	end

	def power_state
		@power_state ||= PowerState.new
	end
end

end # module
