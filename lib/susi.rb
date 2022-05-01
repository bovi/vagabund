require 'json'
require 'securerandom'
require 'fileutils'
require 'socket'
require 'open3'

USER_FOLDER = "~/.susi"
LOCAL_FOLDER = "./.susi"
ENV_FILE = "susi.json"
DEFAULT_USER = 'susi'
DEFAULT_PASSWORD = 'susi'

class Qemu
  def initialize(name: nil, arch: nil, memory: 1024, base: false, iso: nil,
                 network_card: 'virtio-net-pci', port_forward: nil,
                 usb: nil, vnc_id: nil, qmp_port: nil, disk_size: 40)
    @guest_name = if name.nil?
      SecureRandom.uuid
    else
      unless name.match /^[\s\-\_\+\.\=0-9a-zA-Z]+$/
        raise "Invalid guest name (allowed characters: a-z A-Z 0-9 + - = _ . )" 
      end
      name
    end
    @arch = arch || accelerator_support
    @memory = memory
    @base = base
    @iso = iso
    @network_card = network_card
    @port_forward = port_forward || []
    @usb = usb
    @vnc_id = vnc_id
    @qmp_port = qmp_port
    @disk_size = disk_size
  end

  def cmd
    args = []

    # qemu executable based on architecture
    executable = case @arch
    when :x86
      'qemu-system-x86_64'
    when :arm64
      'qemu-system-aarch64'
    else
      raise "Unknown architecture: #{@arch}"
    end

    # architeccture of virtual machine guest
    machine = case @arch
    when :x86
      'q35'
    when :arm64
      'virt,highmem=off'
    end
    args << "-machine type=#{machine}"

    if @arch == :arm64
      args << "-cpu cortex-a57"
      args << "-device intel-hda"
      args << "-device hda-output"
    end

    # use accelerator if the architecture is correct
    args << "-accel hvf" if accelerator_support == @arch

    # add RAM (in MB)
    args << "-m #{@memory}"

    # add boot drive
    file = if @base
      # create base image if it doesn't yet exist
      unless File.exist? default_boot_disk_file
        FileUtils.mkdir_p(File.dirname(default_boot_disk_file))
        Qemu.create_disk(default_boot_disk_file, @disk_size)
      end
      default_boot_disk_file
    else
      boot_disk_file
    end
    if @arch == :arm64
      edk = "#{File.expand_path(USER_FOLDER)}/arm64/edk2-aarch64-code.fd"
      ovmf = "#{File.expand_path(USER_FOLDER)}/arm64/edk2-arm-vars.fd"
      args << "-drive if=pflash,format=raw,file=#{edk},readonly=on"
      args << "-drive if=pflash,format=raw,file=#{ovmf},discard=on"
      args << "-drive if=virtio,format=qcow2,file=#{file},discard=on"
    elsif @arch == :x86
      args << "-drive file=#{file},if=virtio"
    else
      raise 'Could not add drive for this architecture'
    end

    # add CDROM
    unless @iso.nil?
      raise "No valid iso image given: '#{@iso}'" unless File.exists? @iso.to_s
      args << "-cdrom #{@iso}"
    end

    # add network capability
    unless @network_card.nil?
      args << "-device #{@network_card},netdev=net0"
      hostfwd = @port_forward.map {|x| ",hostfwd=tcp::#{x[:host]}-:#{x[:guest]}"}.join
      args << "-netdev user,id=net0#{hostfwd}"
    end

    # enable VNC
    args << "-vnc localhost:#{@vnc_id},password=on" unless @vnc_id.nil?

    unless @qmp_port.nil?
      # activate QMP
      args << "-chardev socket,id=mon0,host=localhost,port=#{@qmp_port},server=on,wait=off"
      args << "-mon chardev=mon0,mode=control,pretty=on"
    end

    # configurate screen and devices
    case @arch
    when :arm64
      args << '-vga none -device ramfb'
    when :x86
      args << "-vga virtio"
      args << "-display default,show-cursor=on"
    else
      raise 'Could not add video for this architecture'
    end

    # enable USB
    args << "-device qemu-xhci,id=xhci"
    case @arch
    when :x86
      args << "-device usb-tablet"
    when :arm64
      args << '-device usb-kbd'
      args << '-device usb-mouse'
      args << '-usb'
    end

    unless @usb.nil?
      @usb.each do |x|
        args << "-device usb-host,vendorid=#{x['vendor']},productid=#{x['product']},id=#{x['name']}"
      end
    end

    # redirect everything to /dev/null (we don't want to see anything)
    "#{executable} #{args.join(' ')} 1> /dev/null 2> /dev/null"
  end

  def start
    # apparantly we can't fork or daemonize when we use USB
    # TODO: we should figure out why and fix it, afterwards use -daemonize in QEMU
    spawn cmd
  end

  # Create a QCOW2 image
  #
  # Arguments:
  #   file:   location of the image
  #   size:   size of the image (in GB)
  def Qemu.create_disk(file, size)
    puts "Create #{file} (Size: #{size}GB)"
    cmd = "qemu-img create -q -f qcow2 #{file} #{size}G 2>&1"
    result = `#{cmd}`
    unless result
      raise "ERROR: Could not create disk #{file} with size #{size}G.\nReturn: '#{result}'"  
    end
  end

  def Qemu.link_disk(file, base_file)
    puts "Create #{file} linked clone of #{base_file}"
    cmd = "qemu-img create -q -f qcow2 -F qcow2 -b #{base_file} #{file}"
    result = `#{cmd}`
    unless result
      raise "ERROR: Could not create disk #{file} as a link cloned from #{base_file}.\nReturn: '#{result}'"
    end
  end

  def hostname
    @guest_name.gsub(/\s/, "").downcase
  end

  def default_boot_disk_file
    default_boot_file = []
    default_boot_file << File.expand_path(USER_FOLDER)
    default_boot_file << 'disks'
    default_boot_file << 'ubuntu-22.04-server'
    default_boot_file << @arch.to_s
    default_boot_file << "ubuntu-22.04-server-#{@arch}.qcow2"

    File.join(default_boot_file)
  end

  def boot_disk_file
    file = "#{File.expand_path(LOCAL_FOLDER)}/guests/#{hostname}/boot.qcow2"
    unless File.exists? file
      FileUtils.mkdir_p(File.dirname(file))
      unless File.exist? default_boot_disk_file
        raise "Default boot image doesn't exist\n\t#{default_boot_disk_file}"
      end
      Qemu.link_disk(file, default_boot_disk_file)
    end

    file
  end

  # Open QMP socket and process communication
  #
  # TODO: clean-up ugly non_blocking part
  def Qemu.QMP_open(&block)
    begin
      TCPSocket.open('localhost', 24444) do |qmp|
        qmp_pipe = -> (cmd) {
          qmp.print(cmd.to_json)
          msg = ''
          while true
            begin
              sleep 0.01
              msg << qmp.read_nonblock(100)
            rescue IO::EAGAINWaitReadable
              break
            end
          end
          msg
        }
        qmp_pipe.({execute: "qmp_capabilities"})
        block.call(qmp_pipe)
      end
    rescue Errno::ECONNREFUSED
      false
    rescue EOFError
      false
    end
  end

  def Qemu.QMP_single_cmd(cmd)
    Qemu.QMP_open { |qmp| qmp.(cmd) }
  end

  def Qemu.change_vnc_password(new_password)
    Qemu.QMP_single_cmd({execute: 'change-vnc-password', arguments: {password: new_password}})
  end

  def Qemu.shutdown
    Qemu.QMP_single_cmd({execute: "system_powerdown"})
  end

  def Qemu.quit
    Qemu.QMP_single_cmd({execute: "quit"})
  end

  def Qemu.status
    state = Qemu.QMP_single_cmd({execute: "query-status"})
    if state
      JSON.parse(state)["return"]["status"]
    else
      "halt"
    end
  end

  private

  # Which architecture is supported by the accelerator?
  #
  # Return:
  #   :x86      - accelerator for x86 guests
  #   :arm64    - accelerator for AARCH64 guests
  #   :none     - no accelerator available
  def accelerator_support
    result_x86 = `qemu-system-x86_64 -accel help 2>&1`
    result_arm = `qemu-system-aarch64 -accel help 2>&1`
    if result_x86.include? 'hvf'
      :x86
    elsif result_arm.include? 'hvf'
      :arm64
    else
      :none
    end
  end
end

def usb
  parse = -> (i) {
    if i['vendor_id'] == 'apple_vendor_id'
      vendor_name = "Apple"
      vendor_id = nil
    else
      _tmp = i['vendor_id'].match(/([0-9a-z]*)\s*\((.*?)\)/)
      _tmp = [] if _tmp.nil?
      vendor_name = _tmp[2] || nil
      vendor_id = _tmp[1] || nil
    end
    product_id = i['product_id'] || nil
    {
      name: i['_name'],
      vendor_name: vendor_name,
      vendor_id: vendor_id,
      product_id: product_id
    }
  }

  out, err, status = Open3.capture3('system_profiler SPUSBDataType -json')
  usb_devices = []
  JSON.parse(out)['SPUSBDataType'].first['_items'].each do |dev|
    usb_devices << parse.(dev)
    if dev.has_key? '_items'
      dev['_items'].each do |hub_item|
        usb_devices << parse.(hub_item)
      end
    end
  end

  usb_devices
end
