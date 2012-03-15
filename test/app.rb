require './load'

puts APP.map.to_s
APP.run server: :Thin, :Port => Cfg.port
