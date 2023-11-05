require 'json'

CONFIG = "#{SUSI_PWD}/config.json"

def config_exists?
  File.exist?(CONFIG)
end

def init_config
  pwd = Dir.pwd
  Dir.mkdir(SUSI_PWD)

  unique_id = (0...8).map { (65 + rand(26)).chr }.join

  config = {}
  config['id'] = unique_id
  config['user'] = ENV['USER'] || 'susi'
  config['ram'] = 8
  config['shell'] = []

  File.open(CONFIG, "w") do |f|
    f.write(config.to_json)
  end
end

def c(key)
  raise "No .susi config" if !File.exist?(CONFIG)
  config = JSON.parse(File.read(CONFIG))
  config[key]
end