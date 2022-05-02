#!/usr/bin/env ruby

require 'json'
require 'open3'
require_relative 'qemu'

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

    @qemu_guest = Qemu.new(vm_id: @guest_id, arch: @arch, disk: @disk,
                           iso: @iso, usb: @usb)
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

    usb_cmd = 'system_profiler SPUSBDataType -json'
    out, err, status = Open3.capture3(usb_cmd)
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
