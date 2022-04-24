#!/usr/bin/env ruby

class Qemu
  def initialize(arch: :x86, memory: 1024, image: nil, iso: nil,
                 network_card: 'virtio-net-pci', port_forward: nil,
                 headless: true)
    @arch = arch
    @memory = memory
    @image = image
    @iso = iso
    @network_card = network_card
    @port_forward = port_forward || []
    @headless = headless
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
    args << "-device qemu-xhci,id=xhci"

    # add HDD
    raise "No valid disk image given: '#{@image}'" unless File.exists? @image.to_s
    args << "-drive file=#{@image},if=virtio"

    # add CDROM
    unless @iso.nil?
      raise "No valid iso image given: '#{@iso}'" unless File.exists? @iso.to_s
      args << "-cdrom #{@iso}"
    end

    # add network capability
    unless @network_card.nil?
      args << "-device #{@network_card},netdev=net0"
      hostfwd = @port_forward.map {|x| ",hostfwd=tcp:localhost:#{x[:host]}-localhost:#{x[:guest]}"}.join
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

case ARGV[0]
when 'create'
  f = ARGV[1]
  s = ARGV[2]
  Qemu.create_disk(f, s)
when 'start'
  f = ARGV[1]
  vm = Qemu.new(image: f, port_forward: [{host: 51822, guest: 22}])
  puts vm.cmd
when 'install'
  f = ARGV[1]
  iso = ARGV[2]
  vm = Qemu.new(image: f, iso: iso, port_forward: [{host: 51822, guest: 22}], headless: false)
  puts vm.cmd
end
