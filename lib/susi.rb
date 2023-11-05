require 'json'

SSH_PORT = 7022
VNC_PORT = 7090 - 5900
QMP_PORT = 7044

SUSI_HOME = "#{Dir.home}/.susi"
SUSI_PWD = "#{Dir.pwd}/.susi"

def log(msg)
  log msg if $verbose
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

  if options[:create] && options[:name] && options[:size]
    create_qcow2(options[:name], options[:size])
  elsif options[:run] && options[:name]
    start_vm(options[:name], options[:installer])
  elsif options[:quit]
    quit_vm
  elsif options[:halt] or ARGV[0] == "stop"
    powerdown_vm
  elsif options[:init] or ARGV[0] == "init"
    if Dir.exist?(SUSI_PWD)
      raise "VM already initialized"
    else
      log "Initializing the VM"
      init_vm
    end
  elsif options[:list] or ARGV[0] == "list" or ARGV[0] == "ls"
    list_vms
  elsif options[:ssh] or ARGV[0] == "ssh"
    ssh_vm
  elsif ARGV[0] == "rm"
    quit_vm
    # delete susi folder
    FileUtils.rm_rf(SUSI_PWD)
  elsif ARGV[0] == "clean"
    quit_vm
    # delete disk
    FileUtils.rm_rf(DISK)
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
  else
    log "Please provide all the required arguments"
    log "Run susi.rb -h for help"
  end
end
