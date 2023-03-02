require_relative "qemu.rb"
require 'optparse'

module Susi
  # handling the command line interface
  class CLI
    def self.start(argv)
      oparser = OptionParser.new do |opts|
        opts.on '-n', '--name=NAME', 'Set name for VM'
        opts.on '-v', '--version', 'Print version'
        opts.on '-c', '--create-img', 'Create QCOW2 Image'
        opts.on '-s', '--start-vm', 'Start VM'
        opts.on '-f', '--file=FILE', 'File name for this command'
        opts.on '--size=SIZE', 'Size of the image file'
      end

      options = {}
      oparser.parse!(into: options)
      puts options

      o = -> (opt) {
        if options.has_key? opt
          options[opt]
        else
          raise ArgumentError, "Argument '#{opt}' is missing."
        end
      }

      case options
      in "start-vm": true
        Susi::QEMU.new(name: o.(:name), img: o.(:file), ram: 1024, cpu: 1, vnc: 0, boot: "c")
      in "create-img": true
        Susi::QEMU.create_img(size: o.(:size), path: o.(:file))
      else
        puts 'unrecognized'
      end
    end
  end

  class Service
    attr_reader :vms

    def initialize file
      @file = file
      @vms = []
      init_vms
    end

    def init_vms
      json = JSON.parse(File.read(@file))
      json['vms'].each_with_index do |vm, i|
        @vms << Susi::QEMU.new(name: vm["name"], img: vm["img"], ram: vm["ram"], cpu: vm["cpu"], vm_id: i)
      end
    end

    def quit!
      @vms.each do |vm|
        vm.quit!
      end
    end
  end

  class APIclient
    attr_reader :port
    attr_reader :imgs
    attr_reader :vms

    def initialize(port)
      @port = port
      @imgs = []
      @vms = []
    end

    def create_img(size: nil)
      img = APIimg.new(size: size)
      @imgs << img
      img
    end

    def add_vm(name: nil, img: nil, ram: nil, cpu: nil)
      APIvm.new(name: name, img: img, ram: ram, cpu: ram)
    end
  end

  class APIimg
    def initialize(size: nil)
    end

    def delete!
    end
  end

  class APIvm
    def initialize(name: nil, img: nil, ram: nil, cpu: nil)
      @running_state = false
    end

    def start!
      @running_state = true
    end

    def running?
      @running_state
    end

    def quit!
      @running_state = false
    end

    def remove!
      @running_state = false
    end

    def exists?
      false
    end
  end
end