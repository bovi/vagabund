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
end