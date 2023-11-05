#!/usr/bin/env ruby

require 'optparse'
require 'socket'
require 'json'

unless system("which qemu-system-x86_64 > /dev/null")
  puts "Please install qemu"
  exit
end

unless system("which qemu-img > /dev/null")
  puts "Please install qemu-img"
  exit
end

# create a QCOW2 image
def create_qcow2(image_name, size)
  cmd = "qemu-img create -f qcow2 #{image_name} #{size}G"
  puts cmd
  system(cmd)
end

def clone_qcow2(image_name, clone_name)
  cmd = "qemu-img create -f qcow2 -F qcow2 -b #{image_name} #{clone_name}"
  puts cmd
  system(cmd)
end

def list_vms
  ps = `ps aux | grep qemu-system`
  ps.split("\n").each do |line|
    id = line.match(/-name\s(\w+)/)
    if id
      puts
      puts "ID: " + id[1]
      vnc_port = line.match(/-vnc\s0.0.0.0:(\d+)/)
      if vnc_port
        puts "\tvnc://localhost:#{vnc_port[1].to_i + 5900} "
      end
      qmp_port = line.match(/-qmp\stcp:localhost:(\d+)/)
      if qmp_port
        puts "\tqmp://localhost:#{qmp_port[1]} "
      end
      ssh_port = line.match(/hostfwd=tcp::(\d+)-:22/)
      if ssh_port
        puts "\tssh://localhost:#{ssh_port[1]} "
      end
      http_port = line.match(/hostfwd=tcp::(\d+)-:80/)
      if http_port
        puts "\thttp://localhost:#{http_port[1]} "
      end
      https_port = line.match(/hostfwd=tcp::(\d+)-:443/)
      if https_port
        puts "\thttps://localhost:#{https_port[1]} "
      end
    end
  end
end

def ssh_vm
  system("ssh -p #{SSH_PORT} susi@localhost")
end

SSH_PORT = 7022
VNC_PORT = 7090 - 5900
QMP_PORT = 7044

DEFAULT_QCOW = "#{Dir.home}/.susi/default.qcow2"

def vm_running?
  begin
    socket = TCPSocket.new("localhost", QMP_PORT)
    socket.close
    true
  rescue
    false
  end
end

def start_vm(image_name, installer = nil)
  args = []
  
  # storage configuration
  args << "-hda #{image_name}"
  if installer =~ /iso$/
    args << "-boot d"
    args << "-cdrom #{installer}"
  else
    args << "-boot c"
  end

  # name configuration
  folder = File.dirname(image_name)
  if File.exist?("#{folder}/id")
    id = File.read("#{folder}/id")
    args << "-name #{id}"
  end

  # network configuration
  args << "-net nic"

  net = []
  net << "-net user"
  net << ",hostfwd=tcp::#{SSH_PORT}-:22"
  net << ",hostfwd=tcp::7080-:80"
  net << ",hostfwd=tcp::7443-:443"

  args << "-qmp tcp:localhost:#{QMP_PORT},server,nowait"
  args << "-vnc 0.0.0.0:#{VNC_PORT},password=on"

  # other configuration
  args << "-m 8G"
  args << "-display none"
  args << "-rtc base=localtime"
  args << "-daemonize"

  cmd = "qemu-system-x86_64 #{args.join(" ")}"
  puts cmd
  system(cmd)

  10.times do |i|
    sleep 1
    if vm_running?
      puts "VM is running"
      break
    else
      raise "VM is not running" if i == 9
      puts "."
    end
  end

  socket = TCPSocket.new("localhost", QMP_PORT)
  socket.gets
  socket.puts('{"execute":"qmp_capabilities"}')
  response = JSON.parse(socket.gets)
  if response["return"] == {}
    puts "QMP connection established"
  else
    puts "QMP connection failed"
  end
  socket.puts('{"execute":"query-status"}')
  response = JSON.parse(socket.gets)
  if response["return"]["running"]
    puts "VM is running"
    # set VNC password
    socket.puts('{"execute":"change-vnc-password", "arguments": {"password": "susi"}}')
    response = JSON.parse(socket.gets)
    if response["return"] == {}
      puts "VNC password set"
    else
      raise "VNC password not set"
    end
  else
    raise "VM is not running"
  end
  socket.close
end

def quit_vm
  socket = TCPSocket.new("localhost", QMP_PORT)
  socket.gets
  socket.puts('{"execute":"qmp_capabilities"}')
  response = JSON.parse(socket.gets)
  if response["return"] == {}
    puts "QMP connection established"
  else
    puts "QMP connection failed"
  end
  socket.puts('{"execute":"quit"}')
  socket.close
end

# parse command line arguments
# if arguments is susi.rb -c -n <image_name> -s <size>
# then the following code will parse the arguments
# and store the values in the variables
# image_name and size
# Path: susi.rb
options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: susi.rb [options]"

  opts.on("-c", "--create", "Create a new image") do |c|
    options[:create] = c
  end

  opts.on("-n", "--name NAME", "Name of the image") do |n|
    options[:name] = n
  end

  opts.on("-s", "--size SIZE", "Size of the image") do |s|
    options[:size] = s
  end

  opts.on("-h", "--help", "Prints this help") do
    puts opts
    exit
  end

  opts.on("-r", "--run", "Run the VM") do |r|
    options[:run] = r
  end

  opts.on("-q", "--quit", "Quit the VM") do |q|
    options[:quit] = q
  end

  # add installer iso
  opts.on("-o", "--iso INSTALLER", "Installer ISO") do |i|
    options[:installer] = i
  end

  opts.on("-i", "--init", "Initialize the VM") do |init|
    options[:init] = init
  end

  opts.on("-l", "--list", "List all the VMs") do |list|
    options[:list] = list
  end

  opts.on("-s", "--ssh", "SSH into the VM") do |ssh|
    options[:ssh] = ssh
  end
end.parse!

# check if the user has provided all the required arguments
# if not, print the help message
# Path: susi.rb
if options[:create] && options[:name] && options[:size]
  create_qcow2(options[:name], options[:size])
elsif options[:run] && options[:name]
  start_vm(options[:name], options[:installer])
elsif options[:quit]
  quit_vm
elsif options[:init]
  if Dir.exist?("#{Dir.pwd}/.susi")
    puts "VM already initialized"
  else
    puts "Initializing the VM"

    pwd = Dir.pwd
    Dir.mkdir("#{pwd}/.susi")

    unique_id = (0...8).map { (65 + rand(26)).chr }.join
    File.open("#{pwd}/.susi/id", "w") do |f|
      f.write(unique_id)
    end

    clone_qcow2(DEFAULT_QCOW, "#{pwd}/.susi/disk.qcow2")
  end
elsif options[:list]
  list_vms
elsif options[:ssh]
  ssh_vm
else
  if Dir.exist?("#{Dir.pwd}/.susi")
    if File.exist?("#{Dir.pwd}/.susi/disk.qcow2")
      if vm_running?
        puts "VM is running"
      else
        # start VM
        start_vm("#{Dir.pwd}/.susi/disk.qcow2")
      end
    end
  else
    puts "Please provide all the required arguments"
    puts "Run susi.rb -h for help"
  end
end