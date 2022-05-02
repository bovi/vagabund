#!/usr/bin/env ruby

require 'json'

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
