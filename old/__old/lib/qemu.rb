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

    def vm_id
      @vm_id
    end

    def qmp_port
      6000 + vm_id
    end

    def vnc_port
      5900 + vm_id
    end

    def initialize(qmp_port: nil,
                  name: nil, img: nil, ram: 1024, cpu: 1, vm_id: nil, iso: nil)
      if qmp_port.nil?
        @vm_id = vm_id
        start_vm(name: name, img: img, ram: ram, cpu: cpu, iso: iso)
      else
        @vm_id = qmp_port - 6000
      end
    end

    # start a QEMU virtual machine
    def start_vm(name: nil, img: nil, ram: 1024, cpu: 1, iso: nil)
      raise ArgumentError, "Name is required" if name.nil?
      raise ArgumentError, "Image path is required" if img.nil?
      raise ArgumentError, "VM ID is required" if vm_id.nil?

      qemu_arguments = []
      qemu_arguments << "-name #{name}"
      qemu_arguments << "-m #{ram}"
      qemu_arguments << "-smp #{cpu}"
      qemu_arguments << "-vnc localhost:#{vnc_port},password=on"
      qemu_arguments << "-cdrom #{iso}" unless iso.nil?

      # disk configuration
      qemu_arguments << "-drive if=virtio,format=qcow2,file=#{img},discard=on"

      # QMP access
      qemu_arguments << "-chardev socket,id=mon0,host=localhost,port=#{qmp_port},server=on,wait=off"
      qemu_arguments << "-mon chardev=mon0,mode=control"

      qemu_arguments << "-daemonize"

      cmd = "qemu-system-x86_64 #{qemu_arguments.join(' ')} 2>&1"
      result = `#{cmd}`

      change_vnc_password('susi')
    end

    def qmp_open(skip_parse: false, &block)
      TCPSocket.open('localhost', qmp_port) do |qmp|
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

    def qmp_single_cmd_raw(cmd)
      result = qmp_open { |qmp| qmp.(cmd) }
      result.each do |r|
        if r.has_key? 'return'
          next if r['return'].empty?
          return r['return']
        end
      end

      {}
    end

    def qmp_single_cmd(cmd)
      result = {}
      # this is kind of a hack
      # if the QMP doesn't return something we just try again
      5.times do
        result = qmp_single_cmd_raw(cmd)
        break unless result.empty?
        sleep 0.1
      end
      raise RuntimeError, "QMP command failed: #{cmd}" if result.empty?
      result
    end

    def change_vnc_password(new_password)
      qmp_single_cmd_raw({execute: 'change-vnc-password',
                         arguments: {password: new_password}})
    end

    def shutdown!
      qmp_single_cmd_raw({execute: "system_powerdown"})
    end

    def quit!
      n = self.name
      qmp_single_cmd_raw({execute: "quit"})

      # wait for QEMU to quit
      Timeout.timeout(5) do
        loop do
          result = `ps -ef | grep qemu-system | grep -v "grep" | grep "\\-name #{n}"`
          break if result.empty?
          sleep 0.1
        end
      end
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