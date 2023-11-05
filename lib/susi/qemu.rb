require 'json'
require 'socket'
require 'net/ssh'
require 'net/scp'
require 'fileutils'

require_relative 'qmp'

DEFAULT_QCOW = "#{SUSI_HOME}/default.qcow2"
DISK = "#{SUSI_PWD}/disk.qcow2"

unless system("which qemu-system-x86_64 > /dev/null")
  raise "Please install qemu"
end

unless system("which qemu-img > /dev/null")
  raise "Please install qemu-img"
end

def disk_exists?
  File.exist?(DISK)
end

# create a QCOW2 image
def create_qcow2(image_name, size)
  cmd = "qemu-img create -f qcow2 #{image_name} #{size}G"
  log cmd
  system(cmd)
end

def clone_qcow2(image_name, clone_name)
  cmd = "qemu-img create -f qcow2 -F qcow2 -b #{image_name} #{clone_name} 2>&1 > /dev/null"
  log cmd
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
  args << "-virtfs local,path=#{Dir.pwd},mount_tag=pwd,security_model=none,id=pwd"

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
    log "KVM is not available. Running in emulation mode."
  end

  cmd = "qemu-system-x86_64 #{args.join(" ")}"
  log cmd
  system(cmd)

  10.times do |i|
    sleep 1
    if vm_running?
      log "VM is running"
      break
    else
      raise "VM is not running" if i == 9
      log "."
    end
  end

  response = qmp_execute('query-status')
  if response["return"]["running"]
    log "VM is running"
    response = qmp('{"execute":"change-vnc-password", "arguments": {"password": "susi"}}')
    if response["return"] == {}
      log "VNC password set"
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
  begin
    qmp_execute('quit')
  rescue
    log "VM is not running"
  end
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
  init_disk
end

def init_disk
  clone_qcow2(DEFAULT_QCOW, DISK)
  start_vm(DISK)
  first_boot_init
end

def first_boot_init
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

    # add 9p filesystem to /etc/fstab
    ssh.exec!("sudo mkdir -p /mnt/pwd")
    ssh.exec!("sudo chmod 777 /mnt/pwd")

    # create systemd mount unit
    mount_unit = <<~MOUNT_UNIT
      [Unit]
      Description=9p mount

      [Mount]
      What=pwd
      Where=/mnt/pwd
      Type=9p
      Options=trans=virtio,version=9p2000.L

      [Install]
      WantedBy=multi-user.target
    MOUNT_UNIT
    ssh.exec!("echo '#{mount_unit}' | sudo tee /etc/systemd/system/mnt-pwd.mount")

    # create systemd automount unit
    automount_unit = <<~AUTOMOUNT_UNIT
      [Unit]
      Description=9p automount

      [Automount]
      Where=/mnt/pwd

      [Install]
      WantedBy=multi-user.target
    AUTOMOUNT_UNIT
    ssh.exec!("echo '#{automount_unit}' | sudo tee /etc/systemd/system/mnt-pwd.automount")

    # enable and start the automount unit
    ssh.exec!("sudo systemctl enable mnt-pwd.automount")
    ssh.exec!("sudo systemctl start mnt-pwd.automount") 

    ssh.exec!("ln -s /mnt/pwd /home/susi/pwd")
  end
end