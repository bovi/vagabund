require 'json'

SSH_PORT = 7022
VNC_PORT = 7090 - 5900
QMP_PORT = 7044

SUSI_HOME = "#{Dir.home}/.susi"
SUSI_PWD = "#{Dir.pwd}/.susi"

require_relative 'susi/config'
require_relative 'susi/parse'
require_relative 'susi/qemu'

def execute_program(options)
  if options[:create] && options[:name] && options[:size]
    create_qcow2(options[:name], options[:size])
  elsif options[:run] && options[:name]
    start_vm(options[:name], options[:installer])
  elsif options[:quit]
    quit_vm
  elsif options[:halt]
    powerdown_vm
  elsif options[:init]
    if Dir.exist?(SUSI_PWD)
      puts "VM already initialized"
    else
      puts "Initializing the VM"
      init_vm
    end
  elsif options[:list]
    list_vms
  elsif options[:ssh] or ARGV[0] == "ssh"
    ssh_vm
  else
    if Dir.exist?(SUSI_PWD)
      if disk_exists?
        if vm_running?
          puts "VM is running"
        else
          # start VM
          start_vm_with_config
        end
      end
    else
      puts "Please provide all the required arguments"
      puts "Run susi.rb -h for help"
    end
  end
end
