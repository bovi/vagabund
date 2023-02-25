require 'socket'
require 'json'
require 'timeout'

module Susi
  # encapsulating QEMU commands
  class QEMU
    # create a QEMU image file
    def self.create_img(size_in_g: 40, path: nil)
      raise ArgumentError, "Path is required" if path.nil?

      result = `qemu-img create -f qcow2 #{path} #{size_in_g}G 2>&1`

      raise "Failed to create disk image: #{result}" unless $?.success?
    end

    def initialize(qmp_port: nil,
                  name: nil, img_path: nil, ram: 1024, cpu: 1, vnc: nil, boot: nil)
      if qmp_port.nil?
        # call start_vm to create a new VM and pass all arguments to it
        start_vm(name: name, img_path: img_path, ram: ram, cpu: cpu, vnc: vnc, boot: boot)
      else
        @qmp_port = qmp_port
      end
    end

    # start a QEMU virtual machine
    def start_vm(name: nil, img_path: nil, ram: 1024, cpu: 1, vnc: nil, boot: nil)
      raise ArgumentError, "Name is required" if name.nil?
      raise ArgumentError, "Image path is required" if img_path.nil?
      raise ArgumentError, "VNC port is required" if vnc.nil?

      qemu_arguments = []
      qemu_arguments << "-name #{name}"
      qemu_arguments << "-m #{ram}"
      qemu_arguments << "-smp #{cpu}"
      qemu_arguments << "-hda #{img_path}"
      qemu_arguments << "-vnc localhost:#{vnc},password=on"
      qemu_arguments << "-boot #{boot}" unless boot.nil?

      # QMP access
      @qmp_port = 6000 + vnc
      qemu_arguments << "-chardev socket,id=mon0,host=localhost,port=#{@qmp_port},server=on,wait=off"
      qemu_arguments << "-mon chardev=mon0,mode=control,pretty=on"

      qemu_cmd = "qemu-system-x86_64 #{qemu_arguments.join(' ')} 2>&1"
      spawn(qemu_cmd)

      sleep 3

      change_vnc_password('susi')

      {state: state, qmp_port: @qmp_port}
    end

    def qmp_open(skip_parse: false, &block)
      TCPSocket.open('localhost', @qmp_port) do |qmp|
        qmp_pipe = -> (cmd) {
          qmp.puts(cmd.to_json)
          sleep 1
          msg = ''
          begin
            loop do
              IO.select([qmp], nil, nil, 0.001)
              msg << qmp.read_nonblock(1)
              sleep 0.001
            end
          rescue IO::EAGAINWaitReadable
            # blocking happened
          rescue EOFError
            # end of file
          end
          msg
        }
        qmp_pipe.({execute: "qmp_capabilities"})
        result = block.call(qmp_pipe)
        if skip_parse
          result
        else
          JSON.parse(result)
        end
      end
    end

    def qmp_single_cmd(cmd)
      result = qmp_open { |qmp| qmp.(cmd) }
      result
    end

    def qmp_single_cmd_skip_parse(cmd)
      result = qmp_open(skip_parse: true) { |qmp| qmp.(cmd) }
      result
    end

    def change_vnc_password(new_password)
      qmp_single_cmd({execute: 'change-vnc-password',
                      arguments: {password: new_password}})
    end

    def shutdown!
      qmp_single_cmd_skip_parse({execute: "system_powerdown"})
    end

    def quit!
      qmp_single_cmd_skip_parse({execute: "quit"})
    end

    def state
      qmp_single_cmd({execute: "query-status"})['return']['status']
    end

    def arch
      qmp_single_cmd({execute: "query-target"})['return']['arch']
    end

    def kvm?
      qmp_single_cmd({execute: "query-kvm"})['return']['enabled']
    end

    def kvm_present?
      qmp_single_cmd({execute: "query-kvm"})['return']['present']
    end

    def vnc_port
      qmp_single_cmd({execute: "query-vnc"})['return']['service'].to_i
    end

    def memory
      memory_in_bytes = qmp_single_cmd({execute: "query-memory-size-summary"})['return']['base-memory']
      memory_in_bytes / 1024 / 1024
    end

    def cpu_count
      qmp_single_cmd({execute: "query-cpus"})['return'].count
    end
  end
end