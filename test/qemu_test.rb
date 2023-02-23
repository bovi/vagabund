require 'test/unit'
require 'tempfile'
require_relative '../lib/susi'

class QEMU_Test < Test::Unit::TestCase
  def test_create_img
    file = Tempfile.new('qemu_test_img').path
    size = 40

    QEMU.create_img(size_in_g: size, path: file)

    assert File.exist?(file)
    assert_equal "qcow2", `qemu-img info #{file} | grep "file format" | awk '{print $3}'`.strip
    assert_equal size, `qemu-img info #{file} | grep "virtual size" | awk '{print $3}'`.strip.to_i

    File.delete(file)
  end

  #def test_create_vm
  #  assert_raise RuntimeError do
  #    QEMU.create_vm(name: nil, img_path: nil, ram: 1024, cpu: 1, vnc: nil, boot: nil)
  #  end
  #end
end