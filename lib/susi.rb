class QEMU
  def self.create_img(size_in_g: 40, path: nil)
    result = `qemu-img create -f qcow2 #{path} #{size_in_g}G 2>&1`
    raise "Failed to create disk image: #{result}" unless $?.success?
  end

  def self.create_vm(name: nil, img_path: nil, ram: 1024, cpu: 1, vnc: nil, boot: nil)
    raise "Name is required" if name.nil?
    raise "Image path is required" if img_path.nil?
    raise "VNC port is required" if vnc.nil?

    result = `qemu-system-x86_64 -name #{name} -m #{ram} -smp #{cpu} -hda #{img_path} -vnc :#{vnc} -boot #{boot} 2>&1`
    raise "Failed to create VM: #{result}" unless $?.success?
  end
end

module Susi
  class CLI
    def self.start(argv)
      QEMU.create_img(size_in_g: 40, path: "test.img")
    end
  end
end