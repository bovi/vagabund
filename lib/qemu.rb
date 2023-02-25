require 'socket'
require 'json'
require 'timeout'

module Susi
  # encapsulating QEMU commands
  class QEMU
    # create a QEMU image file
    def self.create_img(size: 40, path: nil)
      raise ArgumentError, "Path is required" if path.nil?

      result = `qemu-img create -f qcow2 #{path} #{size}G 2>&1`

      raise "Failed to create disk image: #{result}" unless $?.success?
    end

    def qmp_port
      @qmp_port
    end

    def initialize(qmp_port: nil,
                  name: nil, img: nil, ram: 1024, cpu: 1, vnc: nil, iso: nil)
      if qmp_port.nil?
        # call start_vm to create a new VM and pass all arguments to it
        start_vm(name: name, img: img, ram: ram, cpu: cpu, vnc: vnc, iso: iso)
      else
        @qmp_port = qmp_port
      end
    end

    # start a QEMU virtual machine
    def start_vm(name: nil, img: nil, ram: 1024, cpu: 1, vnc: nil, iso: nil)
      raise ArgumentError, "Name is required" if name.nil?
      raise ArgumentError, "Image path is required" if img.nil?
      raise ArgumentError, "VNC port is required" if vnc.nil?

      qemu_arguments = []
      qemu_arguments << "-name #{name}"
      qemu_arguments << "-m #{ram}"
      qemu_arguments << "-smp #{cpu}"
      qemu_arguments << "-drive if=virtio,format=qcow2,file=#{img},discard=on"
      qemu_arguments << "-vnc localhost:#{vnc},password=on"
      qemu_arguments << "-cdrom #{iso}" unless iso.nil?

      # QMP access
      @qmp_port = 6000 + vnc
      qemu_arguments << "-chardev socket,id=mon0,host=localhost,port=#{@qmp_port},server=on,wait=off"
      qemu_arguments << "-mon chardev=mon0,mode=control"

      qemu_cmd = "qemu-system-x86_64 #{qemu_arguments.join(' ')} 2>&1"
      spawn(qemu_cmd)

      sleep 3

      change_vnc_password('susi')
    end

    def qmp_open(skip_parse: false, &block)
      TCPSocket.open('localhost', @qmp_port) do |qmp|
        qmp_pipe = -> (cmd) {
          qmp.puts(cmd.to_json)
          msg = ''
          begin
            loop do
              IO.select([qmp], nil, nil, 0.001)
              msg << qmp.read_nonblock(1)
            end
          rescue IO::EAGAINWaitReadable
            # blocking happened
          rescue EOFError
            # end of file
          end
          msg
        }
        qmp_pipe.({execute: "qmp_capabilities"})
        result = block.call(qmp_pipe).split("\r\n")
        result.map {|r| JSON.parse(r)}
      end
    end

    def qmp_single_cmd(cmd)
      result = qmp_open { |qmp| qmp.(cmd) }
      result.each do |r|
        if r.has_key? 'return'
          next if r['return'].empty?
          return r['return']
        end
      end
      {}
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

    def name
      qmp_single_cmd({execute: "query-name"})['name']
    end

    def state
      qmp_single_cmd({execute: "query-status"})['status']
    end

    def arch
      qmp_single_cmd({execute: "query-target"})['arch']
    end

    def kvm?
      qmp_single_cmd({execute: "query-kvm"})['enabled']
    end

    def kvm_present?
      qmp_single_cmd({execute: "query-kvm"})['present']
    end

    def vnc
      qmp_single_cmd({execute: "query-vnc"})['service'].to_i
    end

    def ram
      ram_in_bytes = qmp_single_cmd({execute: "query-memory-size-summary"})['base-memory']
      ram_in_bytes / 1024 / 1024
    end

    def cpu
      qmp_single_cmd({execute: "query-cpus-fast"}).count
    end

    def img
      qmp_single_cmd({execute: "query-block"}).each do |bd|
        if bd['device'] == 'virtio0'
          return bd['inserted']['file']
        end
      end

      raise RuntimeError, "Couldn't find virtio0 disk"
    end

    def iso
      qmp_single_cmd({execute: "query-block"}).each do |bd|
        if bd['device'] == 'ide1-cd0'
          return bd['inserted']['file']
        end
      end

      nil
    end
  end
end