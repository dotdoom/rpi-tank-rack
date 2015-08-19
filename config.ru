require './rpi_tank_rack'

use Rack::Static, urls: ['/static']

map '/controls' do
	run RPiTankRack::SocketControlApplication.new
end

map '/' do
	run RPiTankRack::WebApplication.new
end
