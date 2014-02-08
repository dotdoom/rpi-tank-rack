require_relative 'rpi_tank_rack'

map '/controls' do
	run RPiTank::SocketControlApplication.new(:backend => { :debug => true })
end

map '/' do
	run RPiTank::WebApplication.new
end
