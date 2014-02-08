require 'thin'
require 'http_router'
require_relative 'rpi_tank_rack'

router = HttpRouter.new
router.add('/controls').to(RPiTank::SocketControlApplication.new)
router.add('/').to(RPiTank::WebApplication.new)
run router
