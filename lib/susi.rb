require_relative "qemu.rb"

module Susi
  # handling the command line interface
  class CLI
    def self.start(argv)
      # parse arguments from command line for create image and create vm
      argv.each do |arg|
        case arg
        when "--create-img"
          Susi::QEMU.create_img(size_in_g: 40, path: "test.img")
        when "--create-vm"
          Susi::QEMU.new(name: "test", img_path: "test.img", ram: 1024, cpu: 1, vnc: 0, boot: "c")
        end
      end
    end
  end

end