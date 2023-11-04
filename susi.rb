#!/usr/bin/env ruby

require 'optparse'
require 'socket'
require 'json'

# create a QCOW2 image
def create_qcow2(image_name, size)
  system("qemu-img create -f qcow2 #{image_name} #{size}G")
end

SSH_PORT = 7022
VNC_PORT = 7090 - 5900
QMP_PORT = 7044

def vm_running?
  begin
    socket = TCPSocket.new("localhost", QMP_PORT)
    socket.close
    true
  rescue
    false
  end
end

def start_vm(image_name, installer = false)
  args = []
  args << "-hda #{image_name}"
  args << "-boot c"
  args << "-net nic"
  args << "-net user,hostfwd=tcp::#{SSH_PORT}-:22"
  args << "-m 8G"
  args << "-rtc base=localtime"
  if installer
    args << "-cdrom debian12.iso"
  end
  args << "-display none"

  # I want to run the VM in the background
  # so I am using the -daemonize option
  args << "-daemonize"

  # I want to communicate with the VM via QMP
  # so I am using the -qmp option
  args << "-qmp tcp:localhost:#{QMP_PORT},server,nowait"

  # activate VNC
  args << "-vnc 0.0.0.0:#{VNC_PORT},password=on"

  cmd = "qemu-system-x86_64 #{args.join(" ")}"

  system(cmd)

  10.times do |i|
    sleep 1
    if vm_running?
      puts "VM is running"
      break
    else
      raise "VM is not running" if i == 9
      puts .
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
end.parse!

# check if the user has provided all the required arguments
# if not, print the help message
# Path: susi.rb
if options[:create] && options[:name] && options[:size]
  create_qcow2(options[:name], options[:size])
elsif options[:run] && options[:name]
  start_vm(options[:name])
elsif options[:quit]
  quit_vm
else
  puts "Please provide all the required arguments"
  puts "Run susi.rb -h for help"
end