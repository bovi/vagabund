#!/usr/bin/env ruby

# Create a QCOW2 image
#
# Arguments:
#   file:   location of the image
#   size:   size of the image (in GB)
def create_disk(file, size)
  puts "Create #{file} (Size: #{size}GB)"
  cmd = "qemu-img create -q -f qcow2 #{file} #{size}G 2>&1"
  result = system(cmd)
  unless result
    raise "ERROR: Could not create disk #{file} with size #{size}G.\nReturn: '#{result}'"  
  end
end

def start_vm(disk, memory, iso: nil, headless: false)
  raise "VM Disk Image is wrong" unless File.exists? disk.to_s
  raise "VM Memory setting is wrong" unless memory.is_a? Numeric and memory > 0
  # if iso is given, we add it to the VM
  cd_args = if iso.nil?
    ''
  else
    raise "ISO Image is wrong" unless File.exists? iso.to_s
    "-cdrom #{iso}"
  end
  #
  io_args = if headless
    "-nographic"
  else
    "-vga virtio -display default,show-cursor=on -device usb-tablet"
  end
  cmd = <<CMD
qemu-system-x86_64 \
-m #{memory}G \
#{io_args} \
-usb \
-machine type=q35,accel=hvf \
-smp 2 \
#{cd_args} \
-drive file=#{disk},if=virtio \
-cpu Nehalem \
-device e1000,netdev=net0 -netdev user,id=net0,hostfwd=tcp::5555-:22
CMD

  puts cmd
end

case ARGV[0]
when 'create'
  f = ARGV[1]
  s = ARGV[2]
  create_disk(f, s)
when 'start'
  f = ARGV[1]
  m = ARGV[2].to_i
  i = ARGV[3]
  start_vm(f, m, iso: i, headless: false)
end
