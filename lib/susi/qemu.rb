require 'json'
require 'socket'
require 'net/ssh'
require 'net/scp'

require_relative 'qmp'

DEFAULT_QCOW = "#{SUSI_HOME}/default.qcow2"
DISK = "#{SUSI_PWD}/disk.qcow2"

unless system("which qemu-system-x86_64 > /dev/null")
  puts "Please install qemu"
  exit
end

unless system("which qemu-img > /dev/null")
  puts "Please install qemu-img"
  exit
end

def disk_exists?
  File.exist?(DISK)
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
      vnc_port = line.match(/-vnc\slocalhost:(\d+)/)
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
  if config_exists?
    args << "-name #{c('id')}"
  end

  # network configuration
  args << "-net nic"

  net = []
  net << "-net user"
  net << ",hostfwd=tcp::#{SSH_PORT}-:22"
  net << ",hostfwd=tcp::7080-:80"
  net << ",hostfwd=tcp::7443-:443"
  args << net.join

  args << "-qmp tcp:localhost:#{QMP_PORT},server,nowait"
  args << "-vnc localhost:#{VNC_PORT},password=on"

  # other configuration
  args << "-m 8G"
  args << "-display none"
  args << "-rtc base=localtime"
  args << "-daemonize"

  if kvm_available?
    args << "-enable-kvm"
  else
    puts "KVM is not available. Running in emulation mode."
  end

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

  response = qmp_execute('query-status')
  if response["return"]["running"]
    puts "VM is running"
    response = qmp('{"execute":"change-vnc-password", "arguments": {"password": "susi"}}')
    if response["return"] == {}
      puts "VNC password set"
    else
      raise "VNC password not set"
    end
  else
    raise "VM is not running"
  end
end

def start_vm_with_config
  start_vm(DISK)
end

def quit_vm
  qmp_execute('quit')
end

def powerdown_vm
  qmp_execute('system_powerdown')
end

def kvm_available?
  File.exist?('/dev/kvm') && File.readable?('/dev/kvm') && File.writable?('/dev/kvm')
end

def ssh_vm
  user = c('user')
  system("ssh -p #{SSH_PORT} #{user}@localhost")
end

def init_vm
  raise 'project already initialized' if config_exists?

  init_config

  clone_qcow2(DEFAULT_QCOW, DISK)

  start_vm(DISK)

  # login with password to the VM via net-ssh
  Net::SSH.start("localhost", "susi",
                  :port => SSH_PORT, :password => "susi") do |ssh|
    # copy public key
    ssh.exec!("mkdir -p .ssh")
    ssh.exec!("chmod 700 .ssh")
    ssh.exec!("touch .ssh/authorized_keys")
    ssh.scp.upload!("#{Dir.home}/.ssh/id_ed25519.pub", ".ssh/authorized_keys")
    ssh.exec!("chmod 600 .ssh/authorized_keys")
    # copy private key
    ssh.scp.upload!("#{Dir.home}/.ssh/id_ed25519", ".ssh/id_ed25519")
    ssh.exec!("chmod 600 .ssh/id_ed25519")

    # deactivate ssh password authentication
    ssh.exec!("sudo sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/g' /etc/ssh/sshd_config")
    ssh.exec!("sudo systemctl restart sshd")
  end
end