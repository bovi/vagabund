require 'json'

SSH_PORT = 7022
VNC_PORT = 7090 - 5900
QMP_PORT = 7044

SUSI_HOME = "#{Dir.home}/.susi"
SUSI_PWD = "#{Dir.pwd}/.susi"

def log(msg)
  puts msg if $verbose
end

require_relative 'susi/config'
require_relative 'susi/parse'
require_relative 'susi/qemu'

def execute_program(options)
  if options[:verbose]
    $verbose = true
  else
    $verbose = false
  end

  # cmd: susi -c -n <name> -s <size>
  # desc: create a new image with the given name and size
  if options[:create] && options[:name] && options[:size]
    create_qcow2(options[:name], options[:size])
  
  # cmd: susi -r -n <name>
  # desc: run the VM with the given image name
  elsif options[:run] && options[:name]
    start_vm(options[:name], options[:installer])

  # cmd: susi quit
  # desc: force quit the VM
  elsif options[:quit]
    quit_vm
  
  # cmd: susi stop
  # desc: stop the VM
  elsif options[:halt] or ARGV[0] == "stop" or ARGV[0] == "halt"
    powerdown_vm
  
  # cmd: susi init
  # desc: initialize the VM configuration and disk
  elsif options[:init] or ARGV[0] == "init"
    if Dir.exist?(SUSI_PWD)
      raise "VM already initialized"
    else
      log "Initializing the VM"
      init_vm
    end
  
  # cmd: susi (ls|list)
  # desc: list all the VMs
  elsif options[:list] or ARGV[0] == "list" or ARGV[0] == "ls"
    list_vms
  
  # cmd: susi ssh
  # desc: ssh into the VM
  elsif options[:ssh] or ARGV[0] == "ssh"
    ssh_vm

  # cmd: susi rm
  # desc: remove the VM disk and the config
  elsif ARGV[0] == "rm"
    quit_vm
    FileUtils.rm_rf(SUSI_PWD)
  
  # cmd: susi clean
  # desc: remove the VM disk but keep the config
  elsif ARGV[0] == "clean"
    quit_vm
    # delete disk
    FileUtils.rm_rf(DISK)
  
  # cmd: susi start
  # desc: start the VM (clone disk if not exists) from config
  elsif ARGV[0] == "start"
    if config_exists?
      if disk_exists?
        if vm_running?
          raise "VM is already running"
        else
          # start VM
          start_vm_with_config
        end
      else
        init_disk
      end
    else
      raise "Please initialize the VM first"
    end
  
  # HELP
  else
    log "Please provide all the required arguments"
    log "Run susi.rb -h for help"
  end
end
