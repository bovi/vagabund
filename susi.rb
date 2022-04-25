#!/usr/bin/env ruby

require 'json'
require 'securerandom'

USER_FOLDER = "~/.susi"
LOCAL_FOLDER = "./.susi"
ENV_FILE = "susi.json"

class Qemu
  def initialize(name: nil, arch: :x86, memory: 1024, image: nil, iso: nil,
                 network_card: 'virtio-net-pci', port_forward: nil,
                 headless: true, usb: nil)
    @guest_name = if name.nil?
      SecureRandom.uuid
    else
      unless name.match /^[\s\-\_\+\.\=0-9a-zA-Z]+$/
        raise "Invalid guest name (allowed characters: a-z A-Z 0-9 + - = _ . )" 
      end
      name
    end
    @arch = arch
    @memory = memory
    @image = image
    @iso = iso
    @network_card = network_card
    @port_forward = port_forward || []
    @headless = headless
    @usb = usb
  end

  def hostname
    @guest_name.gsub(/\s/, "").downcase
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
      'virt'
    end
    args << "-machine type=#{machine}"

    # use accelerator if the architecture is correct
    args << "-accel hvf" if accelerator_support == @arch

    # add RAM (in MB)
    args << "-m #{@memory}"

    # enable USB
    unless @usb.nil?
      args << "-device qemu-xhci,id=xhci"
      @usb.each do |x|
        args << "-device usb-host,vendorid=#{x['vendor']},productid=#{x['product']},id=#{x['name']}"
      end
    end

    # add boot drive
    @image = "#{LOCAL_FOLDER}/guests/#{hostname}/boot.qcow2" if @image.nil?
    raise "No valid disk image available: '#{@image}'" unless File.exists? @image.to_s
    args << "-drive file=#{@image},if=virtio"

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

    # add video graphic card support (headless or not?)
    if @headless
      args << "-vga none"
      args << "-nographic"
    else
      args << "-vga virtio"
      args << "-display default,show-cursor=on"
      args << "-device usb-tablet,bus=xhci.0"
    end

    # activate VNC
    args << "-vnc :99,password=on"

    # activate QMP
    args << "-chardev socket,id=mon0,host=localhost,port=4444,server=on,wait=off"
    args << "-mon chardev=mon0,mode=control,pretty=on"

    "#{executable} #{args.join(' ')}"
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

env = if File.exists? ENV_FILE
  JSON.parse(File.read(ENV_FILE))
else
  {"guests" => []}
end

case ARGV[0]
when 'up'
  env['guests'].each do |guest|
    vm = Qemu.new(**guest.transform_keys(&:to_sym))
    puts vm.cmd
  end
when 'down'
  # TODO: implement shutdown of the VM
when 'create'
  Qemu.create_disk(ARGV[1], ARGV[2])
end
