require 'test/unit'
require 'tempfile'
require_relative '../lib/susi'

class QEMU_Test < Test::Unit::TestCase
  def test_create_img
    # check if arguments are correctly checked
    assert_raise ArgumentError do
      Susi::QEMU.create_img(size: size, path: nil)
    end

    file = Tempfile.new('qemu_test_img').path
    size = 40

    Susi::QEMU.create_img(size: size, path: file)

    # is the image file created? and is the image file correct itself?
    assert File.exist?(file)
    assert_equal "qcow2", `qemu-img info #{file} | grep "file format" | awk '{print $3}'`.strip
    assert_equal size, `qemu-img info #{file} | grep "virtual size" | awk '{print $3}'`.strip.to_i
  end

  def test_create_vm
    # check if arguments are correctly checked
    assert_raise ArgumentError do
      Susi::QEMU.new(name: nil, img: nil, ram: 1024, cpu: 1, vnc: nil, boot: nil)
    end

    # setup VM and start it
    file = Tempfile.new('qemu_test_img').path
    size = 40
    Susi::QEMU.create_img(size: size, path: file)
    vm = Susi::QEMU.new(name: "test", img: file, ram: 1024, cpu: 1, vnc: 0, boot: "c")

    # is the VM correctly started?
    assert_equal "running", vm.state
    assert_equal "test", vm.name
    assert_equal 1024, vm.ram
    assert_equal 1, vm.cpu
    assert_equal 5900, vm.vnc
    assert_equal file, vm.img

    # cleanup
    vm.quit!
  end
end