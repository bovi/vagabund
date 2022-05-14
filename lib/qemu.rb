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
    @accelerator_support = Qemu.accelerator_support
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
    args << "-accel hvf" if Qemu.accelerator_support == @arch

    # add memory
    args << "-m 1024"

    # mount an iso?
    unless @iso.nil?
      args << "-cdrom '#{@iso}'"
    end

    # add disk
    args << "-drive if=virtio,format=qcow2,file=#{@disk},discard=on"
    case @arch
    when 'x86_64'
      # nothing else todo
    when 'arm64'
      # add firmware for the ARM platform
      args << "-drive if=pflash,format=raw,file=#{@edk},readonly=on"
      args << "-drive if=pflash,format=raw,file=#{@edk_vars},discard=on"
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
        usb_details = "vendorid=#{x['vendor']},productid=#{x['product']},id=#{x['name']}"
        args << "-device usb-host,#{usb_details}"
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

    # File access
    ## add current working directory to the system
    args << " -virtfs local,path=#{File.expand_path('.')},security_model=mapped-xattr,mount_tag=CWD"

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
    qmp_single_cmd({execute: 'change-vnc-password',
                    arguments: {password: new_password}})
  end

  def shutdown!
    qmp_single_cmd({execute: "system_powerdown"})
  end

  def quit!
    qmp_single_cmd({execute: "quit"})
  end

  def status
    state = ''
    processes = running_qemu_processes
    processes.each do |ps|
      state << "#{ps[:name]}: #{ps[:status]} (#{ps[:path]})"
    end

    state
  end

  def running_qemu_processes
    processes = []
    ps_awxx = `ps awxx | grep "qemu-system"`
    ps_awxx.each_line do |ps_with_qemu|
      next unless ps_with_qemu =~ /sh -c qemu-system/
      ps_with_qemu.strip.match(/(qemu-system-.*)$/)[1].split(/\s\-/).each do |param|
        case param
        when /drive\s/
          t = param.match(/format=(.*?)\,/)
          unless t.nil?
            case t[1]
            when 'qcow2'
              #f = param.match(/file\=(.*+).*+discard=on/)
              f = param.split(',').select {|x| x =~ /file=/}
              path = ""
              if f.count == 1
                f_split = f[0].sub('file=', '').split('/')
                f_split.each do |x|
                  if x == ".susi"
                    if path == "/Users/#{`whoami`.strip}"
                      # this is the user susi folder
                      # we should only be here if we
                      # install or modify base images
                      path = f_split.join('/')
                      name = path.split('/').last.sub('.qcow2', '')
                      processes << {'name': name, 'status': 'running',
                                    'path': path}
                      break
                    else
                      vm_file = File.join(path, "susi.json")
                      if File.exist? vm_file
                        vm_data = JSON.parse(File.read(vm_file))
                        vm_data["guests"].each do |vm|
                          if f_split[-2] == vm['name']
                            processes << {'name': vm['name'], 'status': 'running',
                                          'path': path}
                          end
                        end
                      end
                      break
                    end
                  else
                    path = File.join(path, x)
                  end
                end
              end
            else
              # ignore this kind of file format
            end
          end
        end
      end
    end

    processes
  end

  # Which architecture is supported by the accelerator?
  #
  # Return:
  #   'x86_64'   - accelerator for x86 guests
  #   'arm64'    - accelerator for AARCH64 guests
  #   'none'     - no accelerator available
  def Qemu.accelerator_support
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
