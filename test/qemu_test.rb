require 'test/unit'
require 'tempfile'
require_relative '../lib/susi'

class QEMU_Test < Test::Unit::TestCase
  def assert_qemu_is_gone
    # check if process is dead
    result = `ps aux | grep qemu-system-x86_64 | grep -v grep`
    assert_equal "", result, 'there are still qemu processes running'
  end

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
    iso = Tempfile.new('qemu_test_iso').path
    size = 40
    Susi::QEMU.create_img(size: size, path: file)
    vm = Susi::QEMU.new(name: "test", img: file, ram: 1024, cpu: 1, vm_id: 0, iso: iso)
    vm2 = Susi::QEMU.new(qmp_port: vm.qmp_port)

    [vm, vm2].each do |v|
      assert_equal "running", v.state
      assert_equal "test", v.name
      assert_equal 1024, v.ram
      assert_equal 1, v.cpu
      assert_equal 5900, v.vnc_port
      assert_equal 6000, v.qmp_port
      assert_equal file, v.img
      assert_equal iso, v.iso
    end

    # cleanup
    vm.quit!

    assert_qemu_is_gone
  end

  def test_load_one_service
    img_file = File.join(File.dirname(__FILE__), 'data', '00service.img')   
    size = 40
    Susi::QEMU.create_img(size: size, path: img_file)

    file = File.join(File.dirname(__FILE__), 'data', '00service.json')   
    service = Susi::Service.new(file)

    assert_equal 1, service.vms.count
    assert_equal "n", service.vms.first.name
    assert_equal "test/data/00service.img", service.vms.first.img
    assert_equal 1024, service.vms.first.ram
    assert_equal 5900, service.vms.first.vnc_port
    assert_equal 6000, service.vms.first.qmp_port

    service.vms.first.quit!

    # cleanup
    File.delete(img_file)

    assert_qemu_is_gone
  end

  def test_load_three_service
    size = 40
    0.upto(2) do |i|
      img_file = File.join(File.dirname(__FILE__), 'data', "01service#{i}.img")
      Susi::QEMU.create_img(size: size, path: img_file)
    end

    file = File.join(File.dirname(__FILE__), 'data', '01service.json')   
    service = Susi::Service.new(file)

    assert_equal 3, service.vms.count

    0.upto(2) do |i|
      assert_equal "n#{i}", service.vms[i].name
      assert_equal "test/data/01service#{i}.img", service.vms[i].img
      assert_equal 1024, service.vms[i].ram
      assert_equal 5900 + i, service.vms[i].vnc_port
      assert_equal 6000 + i, service.vms[i].qmp_port
    end

    service.quit!

    assert_qemu_is_gone

    # cleanup
    0.upto(2) do |i|
      img_file = File.join(File.dirname(__FILE__), 'data', "01service#{i}.img")
      File.delete(img_file)
    end
  end

end