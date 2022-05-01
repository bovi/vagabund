#!/usr/bin/env ruby

require 'fileutils'
require 'net/http'
require 'uri'
require 'json'
require 'open3'
require 'optparse'
require 'ostruct'

class Qemu
  def initialize(arch: nil, iso: nil, vm_id: nil, usb: nil,
                 disk: nil, edk: nil, edk_vars: nil, port_forward: [])
    raise "VM ID is not defined" if vm_id.nil?
    raise "Architecture is not defined" if arch.nil?
    @arch = arch
    @iso = iso
    @vnc_id = vm_id
    @vnc_port = 5900 + @vnc_id
    @qmp_port = 51000 + vm_id
    @ssh_port = 52000 + vm_id
    @disk = disk
    @edk = edk
    @edk_vars = edk_vars
    @accelerator_support = accelerator_support
    @usb = usb

    @port_forward = port_forward
    # add SSH port for forwarding (default)
    @port_forward << {host: @ssh_port, guest: 22}
  end

  def ssh_port
    @ssh_port
  end

  def vnc_port
    @vnc_port
  end

  def cmd
    cmd = ''
    args = []

    # machine architecture
    case @arch
    when 'x86_64'
      cmd = 'qemu-system-x86_64'
      args << '-machine type=q35'
    when 'arm64'
      cmd = 'qemu-system-aarch64'
      args << '-machine type=virt,highmem=off'
      args << "-cpu cortex-a57"
    else
      raise 'Unknown architecture'
    end

    # activate accelerator if it is supported for the selected architecture
    args << "-accel hvf" if accelerator_support == @arch

    # add memory
    args << "-m 1024"

    # mount an iso?
    unless @iso.nil?
      args << "-cdrom '#{@iso}'"
    end

    # add disk
    case @arch
    when 'x86_64'
      args << "-drive if=virtio,file=#{@disk}"
    when 'arm64'
      args << "-drive if=pflash,format=raw,file=#{@edk},readonly=on"
      args << "-drive if=pflash,format=raw,file=#{@edk_vars},discard=on"
      args << "-drive if=virtio,format=qcow2,file=#{@disk},discard=on"
    end

    # graphical interface
    case @arch
    when 'x86_64'
      args << "-vga virtio"
      args << "-display default,show-cursor=on"
    when 'arm64'
      args << '-vga none'
      args << '-device ramfb'
    end

    # enable USB
    args << "-device qemu-xhci,id=xhci"
    case @arch
    when 'x86_64'
      args << "-device usb-tablet"
    when 'arm64'
      args << "-usb"
      args << "-device usb-kbd"
      args << "-device usb-mouse"
    end

    # add passthrough USB devices
    unless @usb.nil?
      @usb.each do |x|
        args << "-device usb-host,vendorid=#{x['vendor']},productid=#{x['product']},id=#{x['name']}"
      end
    end

    # add network
    args << "-device virtio-net-pci,netdev=net0"
    hostfwd = @port_forward.map {|x| ",hostfwd=tcp::#{x[:host]}-:#{x[:guest]}"}.join
    args << "-netdev user,id=net0#{hostfwd}"

    # VNC access
    args << "-vnc localhost:#{@vnc_id},password=on"

    # QMP access
    args << "-chardev socket,id=mon0,host=localhost,port=#{@qmp_port},server=on,wait=off"
    args << "-mon chardev=mon0,mode=control,pretty=on"

    "#{cmd} #{args.join(' ')} 1> /dev/null 2> /dev/null"
  end

  # Open QMP socket and process communication
  #
  # TODO: clean-up ugly non_blocking part
  def qmp_open(&block)
    begin
      TCPSocket.open('localhost', @qmp_port) do |qmp|
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

  def qmp_single_cmd(cmd)
    qmp_open { |qmp| qmp.(cmd) }
  end

  def change_vnc_password(new_password)
    qmp_single_cmd({execute: 'change-vnc-password', arguments: {password: new_password}})
  end

  def shutdown!
    qmp_single_cmd({execute: "system_powerdown"})
  end

  def quit!
    qmp_single_cmd({execute: "quit"})
  end

  def status
    state = qmp_single_cmd({execute: "query-status"})
    if state
      JSON.parse(state)["return"]["status"]
    else
      "halt"
    end
  end

  # Which architecture is supported by the accelerator?
  #
  # Return:
  #   'x86_64'   - accelerator for x86 guests
  #   'arm64'    - accelerator for AARCH64 guests
  #   'none'     - no accelerator available
  def accelerator_support
    result_x86 = `qemu-system-x86_64 -accel help 2>&1`
    result_arm = `qemu-system-aarch64 -accel help 2>&1`

    if result_x86.include? 'hvf'
      'x86_64'
    elsif result_arm.include? 'hvf'
      'arm64'
    else
      'none'
    end
  end

  def Qemu.create_disk_cmd(file, size_in_gb, verbose: false)
    puts "Create #{file} (Size: #{size_in_gb}GB)" if verbose
    "qemu-img create -q -f qcow2 #{file} #{size_in_gb}G 2>&1"
  end
  
  def Qemu.create_disk(file, size_in_gb, verbose: false)
    result = `#{Qemu.create_disk_cmd(file, size_in_gb, verbose: verbose)}`
    unless result
      raise "ERROR: Could not create disk #{file} with size #{size}G.\nReturn: '#{result}'"
    end
  end

  def Qemu.create_linked_disk_cmd(base_file, file, verbose: false)
    puts "Create linked #{file} from #{base_file}" if verbose
    "qemu-img create -q -f qcow2 -F qcow2 -b #{base_file} #{file} 2>&1"
  end
  
  def Qemu.create_linked_disk(base_file, file, verbose: false)
    result = `#{Qemu.create_linked_disk_cmd(base_file, file, verbose: verbose)}`
    unless result
      raise "ERROR: Could not create linked disk #{file} from #{base_file}.\nReturn: '#{result}'"
    end
  end
end

class Guest
  def initialize(iso: nil, disk: nil, size: 100, verbose: false,
                 arch: 'x86_64', dryrun: false, guest_id: nil,
                 name: nil, install: false, base_disk: nil,
                 usb: nil)
    @iso = iso
    @disk = disk
    @size = size
    @arch = arch
    @dryrun = dryrun
    @verbose = verbose
    @guest_id = guest_id
    @name = name
    @install = install
    @base_disk = base_disk
    @usb = usb

    unless @disk.nil?
      # no disk is defined
      unless @install
        unless File.exist? @disk
          if @dryrun
            puts Qemu.create_linked_disk_cmd(@base_disk, @disk, verbose: verbose)
          else
            Qemu.create_linked_disk(@base_disk, @disk, verbose: verbose)
          end
        end
      else
        unless File.exist? @disk
          if @dryrun
            puts Qemu.create_disk_cmd(@disk, @size, verbose: verbose)
          else
            Qemu.create_disk(@disk, @size, verbose: verbose)
          end
        end
      end
    end

    @qemu_guest = Qemu.new(vm_id: @guest_id, arch: @arch, disk: @disk, iso: @iso, usb: @usb)
  end

  def quit!
    @qemu_guest.quit!
  end

  def shutdown!
    @qemu_guest.shutdown!
  end

  def status
    @qemu_guest.status
  end

  def connect_ssh
    cmd = "open ssh://susi@localhost:#{@qemu_guest.ssh_port}"

    if @dryrun
      puts cmd
    else
      `#{cmd}`
    end
  end

  def connect_vnc
    @qemu_guest.change_vnc_password('susi')
    cmd = "open vnc://susi:susi@localhost:#{@qemu_guest.vnc_port}"
    if @dryrun
      puts cmd
    else
      `#{cmd}`
    end
  end

  def start
    if @dryrun or @verbose
      puts @qemu_guest.cmd
    end

    unless @dryrun
      spawn(@qemu_guest.cmd)
      sleep 3
      @qemu_guest.change_vnc_password('susi')
    end
  end

  # perform scanning to identify which USB device
  # should be added to the virtual machine guest
  def add_usb(env_file)
    env_data = JSON.parse(File.open(env_file).read)
    if @name
      guest_id = env_data['guests'].index {|x| x['name'] == @name}
    else
      guest_id = 0
      @name = env_data['guests'][guest_id]['name']
    end
    puts "Adding a USB device to the '#{@name}' VM"
    puts
    puts "Please ensure that the USB device(s) you want to add are not connected"
    puts "...press ENTER to continue"
    STDIN.gets("\n")
    puts "Scanning..."
    puts
    scan_1 = usb
    puts "Please insert the USB device(s) you want to add"
    puts "...press ENTER to continue"
    STDIN.gets("\n")
    puts "Scanning..."
    puts
    scan_2 = usb

    # identify the new USB devices
    new_devices = (scan_2 - scan_1)
    # add the new USB devices to the VM configuration file
    new_devices.each do |dev|
      n = dev[:name]
      v = dev[:vendor_name]
      puts "Adding '#{n}' from '#{v}' to the '#{@name}' VM"
      puts "...press ENTER to permanent add it to your configuration (CTRL-C to cancel)"
      STDIN.gets("\n")

      env_data['guests'][guest_id]['usb'] = [] if env_data['guests'][guest_id]['usb'].nil?
      env_data['guests'][guest_id]['usb'] << {
        name: n.gsub(/[^a-zA-Z0-9]/, ''),
        vendor: dev[:vendor_id],
        product: dev[:product_id]
      }
    end
    File.open(env_file, 'w+').puts(env_data.to_json)
  end

  # scan the USB system and return all USB devices
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
end

class Susi
  USER_FOLDER = File.expand_path("~/.susi")
  USER_DISK_FOLDER = File.join(USER_FOLDER, 'disks')
  USER_MISC_FOLDER = File.join(USER_FOLDER, 'miscs')
  ENV_FILE = 'susi.json'
  ENV_FOLDER = File.expand_path(".susi")

  def Susi.execute_action(argv, options)
    case ARGV[0]

    # start guest(s) from the current environment
    when 'up'
      if File.expand_path('~') == File.expand_path('.')
        raise "Can't be done in the home directory"
      end
      unless File.exist? ENV_FILE
        raise "Environment file doesn't exist."
      end
      Susi.init_local_folder
      env = JSON.parse(File.read(ENV_FILE))
      guest_id = 0
      env['guests'].each do |vm|
        guest_id =+ 1
        Susi.init_local_machine_folder(name: vm['name'])
        disk = File.join(ENV_FOLDER, 'machines', vm['name'], 'boot.qcow2')
        base_disk = if vm['base'].nil?
          # no base image defined, using the default
          'u2004server.qcow2'
        else
          # base image defined
          "#{vm['base']}.qcow2"
        end
        base_disk = File.join(USER_DISK_FOLDER, base_disk)
        raise "Base image doesn't exist" unless File.exist? base_disk
        vm = Guest.new(name: vm['name'], guest_id: guest_id, disk: disk, base_disk: base_disk,
                       usb: vm['usb'],
                       verbose: options.verbose, dryrun: options.dryrun)
        vm.start
      end

    when 'vnc'
      Guest.new(guest_id: 1).connect_vnc

    when 'ssh'
      Guest.new(guest_id: 1).connect_ssh

    when 'quit'
      Guest.new(guest_id: 1).quit!

    when 'status'
      puts Guest.new(guest_id: 1).status

    # shutdown guest(s) from the current environment
    when 'down'
      Guest.new(guest_id: 1).shutdown!

    when 'usb'
      vm = if ARGV[1]
        Guest.new(name: ARGV[1])
      else
        Guest.new(guest_id: 1)
      end
      vm.add_usb(ENV_FILE)

    else
      case options.action

      # initialize guest(s) in the current environment
      when :init
        if File.exist? ENV_FILE
          puts 'Environment already initialized'
        else
          options.machines.map {|x| {name: x}}
          init_data = { guests: options.machines.map { |x| { name: x } } }.to_json
          File.open(ENV_FILE, 'w+') do |f|
            f.puts init_data
          end
        end

      # install a base image for the current user
      when :install
        if options.control == :quit
          Guest.new(guest_id: 99).quit!
          exit
        end

        # prepare installation image
        img_url = options.image
        img_name = img_url.split("/").last
        iso = File.join(USER_MISC_FOLDER, img_name)
        if File.exist? iso
          puts "Image '#{img_name}' exist"
        else
          puts "Download #{img_name}"
          3.times do
            Susi.download(img_url, img_name, verbose: options.verbose)
            break unless File.size(iso).to_i == 0
            FileUtils.rm(iso, verbose: options.verbose)
            sleep 1
          end
          raise "Couldn't download" unless File.exist? iso
        end

        # start guest VM
        disk = File.join(USER_DISK_FOLDER, "#{options.base}.qcow2")
        vm = Guest.new(guest_id: 99, iso: iso, disk: disk, verbose: options.verbose, dryrun: options.dryrun, install: true)

        case options.connect
        when :vnc
          vm.connect_vnc
        when :ssh
          vm.connect_ssh
        else
          vm.start
          vm.connect_vnc
        end

      # reset the current users setup
      when :reset
        FileUtils.rm_rf(USER_FOLDER, verbose: options.verbose)

      else
        case options.connect
        when :vnc
          Guest.new(guest_id: 1).connect_vnc
        when :ssh
          Guest.new(guest_id: 1).connect_ssh
        else
          puts "Unknown action: #{options.action}"
        end
      end
    end
  end

  # check if the environment is setup
  def Susi.check_environment
    Susi.init_user_folder
  end

  def Susi.init_local_folder
    unless File.exist? ENV_FOLDER
      puts "Environment folder doesn't exist, create..."
      FileUtils.mkdir_p(ENV_FOLDER)
      FileUtils.mkdir_p(File.join(ENV_FOLDER, 'machines'))
    end
  end

  def Susi.init_local_machine_folder(name: nil)
    machine_folder = File.join(ENV_FOLDER, 'machines', name)
    unless File.exist? machine_folder
      FileUtils.mkdir_p(machine_folder)
    end
  end

  # initialize the user folder in the home directory
  def Susi.init_user_folder
    unless File.exist? USER_FOLDER
      puts "User folder doesn't exist, create..."
      FileUtils.mkdir_p(USER_FOLDER)
      FileUtils.mkdir_p(USER_DISK_FOLDER)
      FileUtils.mkdir_p(USER_MISC_FOLDER)

      # copy and un-pack firmware for ARM architecture
      %w(edk2-aarch64-code edk2-arm-vars).each do |fw|
        fw_file = "#{fw}.fd.xz"
        FileUtils.cp(File.join(File.dirname(__FILE__), fw_file), USER_MISC_FOLDER)
        `xz -d #{File.join(USER_MISC_FOLDER, fw_file)}`
      end
    end
  end

  # download a file and store in misc folder
  def Susi.download(link, name, verbose: false)
    url_path = "/" + link.split("/")[3..-1].join("/")
    Net::HTTP.start(link.split('/')[2]) do |http|
      response = http.request_head(url_path)
      total_size = response["content-length"].to_i
      download_size = 0.0
      last_time = Time.now

      # start download and write to disk
      File.open(File.join(USER_MISC_FOLDER, name), 'w+') do |file|
        http.get(url_path) do |data|
          file.write data

          # status message
          if verbose
            download_size += data.length
            percent = download_size / total_size * 100.0
            if (Time.now - last_time) >= 30
              puts "#{Time.now}: #{percent.round(1)}%"
              last_time = Time.now
            end
          end
        end
      end
    end
  end
end

class SusiOptParser
  VERSION = "0.0.1"
  class ScriptOptions
    attr_accessor :action, :verbose, :machines, :image, :base, :dryrun, :connect, :control

    def initialize
      self.verbose = false
      self.dryrun = false
    end

    def define_options(parser)
      parser.banner = "Usage: susi [options]"
      parser.separator ""
      parser.separator "Specific options:"

      define_init(parser)
      define_install(parser)
      define_base(parser)
      define_factory_reset(parser)
      define_dryrun(parser)
      define_connect(parser)
      define_control(parser)

      parser.separator ""
      parser.separator "Common options:"

      parser.on_tail("-h", "--help", "Show this message") do
        puts parser
        exit
      end
      parser.on_tail("--version", "Show version") do
        puts VERSION
        exit
      end
      parser.on_tail("--verbose", "Verbose output") do
        self.verbose = true
      end
    end

    def define_init(parser)
      parser.on("--init vm1,vm2,vm3", Array, "Initialize Guest(s)") do |vms|
        raise "Action already defined" unless self.action.nil?
        self.action = :init
        self.machines = vms
      end
    end

    def define_factory_reset(parser)
      parser.on("--reset", Array, "Factory reset the user environment") do |vms|
        raise "Action already defined" unless self.action.nil?
        self.action = :reset
      end
    end

    def define_install(parser)
      parser.on("--install [image]", "Install image") do |img|
        raise "Action already defined" unless self.action.nil?
        self.action = :install
        self.image = img || 'https://mirrors.tuna.tsinghua.edu.cn/ubuntu-releases/20.04.4/ubuntu-20.04.4-live-server-amd64.iso'
        # 'https://mirrors.tuna.tsinghua.edu.cn/ubuntu-cdimage/ubuntu/releases/20.04.4/release/ubuntu-20.04.4-live-server-arm64.iso'
        # 'https://mirrors.tuna.tsinghua.edu.cn/ubuntu-releases/20.04.4/ubuntu-20.04.4-live-server-amd64.iso'
        self.base = self.base || 'u2004server'
        self.machines = [self.image.split("/").last.split('.')[0..-2].join('.')]
      end
    end

    def define_base(parser)
      parser.on("--base [name]", "Define base name") do |base|
        self.base = base
      end
    end

    def define_dryrun(parser)
      parser.on("--dryrun", "Do not execute just show what you would do") do
        self.dryrun = true
      end
    end

    def define_connect(parser)
      parser.on("--ssh", "Connect via SSH to the guest") do
        raise 'Connect issue. Choose SSH or VNC, not both!' unless self.connect.nil?
        self.connect = :ssh
      end
      parser.on("--vnc", "Connect via VNC to the guest") do
        raise 'Connect issue. Choose SSH or VNC, not both!' unless self.connect.nil?
        self.connect = :vnc
      end
    end

    def define_control(parser)
      parser.on("--quit", "Quit the guest process") do
        self.control = :quit
      end
    end
  end

  def parse(args)
    @options = ScriptOptions.new
    @args = OptionParser.new do |parser|
      @options.define_options(parser)
      parser.parse!(args)
    end
    @options
  end

  attr_reader :parser, :options
end
