require_relative 'rpi_tank_rack'

map '/controls' do
	run RPiTank::SocketControlApplication.new
end

map '/' do
	run RPiTank::WebApplication.new
end
