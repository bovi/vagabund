#!/usr/bin/env ruby

require 'json'
require 'fileutils'
require 'net/http'
require 'net/ssh'
require 'net/scp'
require_relative 'guest'
require_relative 'susioptparser'

class Susi
  VERSION = '0.0.1'
  USER_FOLDER = File.expand_path("~/.susi")
  USER_DISK_FOLDER = File.join(USER_FOLDER, 'disks')
  USER_MISC_FOLDER = File.join(USER_FOLDER, 'miscs')
  ENV_FILE = 'susi.json'
  ENV_FOLDER = File.expand_path(".susi")
  DEFAULT_BASE_IMG = 'u2004server'

  def Susi.execute_action(argv, options)
    logit = -> (msg) { puts msg if options.verbose }
    case ARGV[0]

    # start guest(s) from the current environment
    when 'up'
      if File.expand_path('~') == File.expand_path('.')
        raise "Can't be done in the home directory"
      end
      unless File.exist? ENV_FILE
        raise "Environment file doesn't exist."
      end
      Susi.init_local_folder
      env = JSON.parse(File.read(ENV_FILE))
      guest_id = 0
      env['guests'].each do |vm|
        guest_id =+ 1
        Susi.init_local_machine_folder(name: vm['name'])
        disk = File.join(ENV_FOLDER, 'machines', vm['name'], 'boot.qcow2')

        qemu_processes_with_disk = `ps awxx | grep qemu`.strip.lines.count {|x|x.match /#{disk}/}
        if qemu_processes_with_disk > 0
          puts "Guest '#{vm['name']}' is already running"
          exit
        end

        base_disk = if vm['base'].nil?
          # no base image defined, using the default
          "#{DEFAULT_BASE_IMG}.qcow2"
        else
          # base image defined
          "#{vm['base']}.qcow2"
        end
        base_disk = File.join(USER_DISK_FOLDER, base_disk)
        raise "Base image doesn't exist" unless File.exist? base_disk
        guest = Guest.new(name: vm['name'], guest_id: guest_id, disk: disk, base_disk: base_disk,
                       usb: vm['usb'],
                       verbose: options.verbose, dryrun: options.dryrun)
        guest.start

        puts "Waiting until Guest is booted..."
        how_many_tries = 60
        how_many_tries.times do |x|
          begin
            Net::SSH.start('localhost', 'susi', {password: "susi", port: guest.ssh_port, timeout: 1}) do |ssh|
              puts "Guest is up!"

              hostname = ssh.exec!("hostname").strip
              if hostname == DEFAULT_BASE_IMG

                puts "Set Hostname"
                logit.("Hostname: #{hostname}")
                logit.("Change hostname to: #{vm['name']}")
                ssh.exec!("sudo hostnamectl set-hostname #{vm['name']}")
                hostname = ssh.exec!("hostname").strip
                logit.("Hostname is now: #{hostname}")

                puts "Install additional packages"
                ssh.exec!("sudo DEBIAN_FRONTEND=noninteractive apt-get install -qq zsh vim < /dev/null > /dev/null")

                puts "Create local user and environment in guest"
                local_user = `whoami`.strip
                local_user_id = `echo $UID`.strip
                ssh.exec!("sudo groupmod -g 20 staff")
                ssh.exec!("sudo useradd -u #{local_user_id} #{local_user}")
                ssh.exec!("sudo usermod -g staff #{local_user}")
                ssh.exec!("sudo mkdir /home/#{local_user}")
                # setup ZSH
                ssh.exec!("sudo usermod -s /bin/zsh #{local_user}")

                ssh_copy = -> (ssh_server, source, target) do
                  full_file_path = File.expand_path(source)
                  if File.exist? full_file_path
                    logit.("Upload #{source}...")
                    tmp_file_name = "/tmp/#{File.basename(target)}"
                    ssh_server.scp.upload(full_file_path, tmp_file_name)
                    ssh_server.exec!("sudo mv #{tmp_file_name} #{target}")
                  end
                end

                ssh_copy.(ssh, '~/.zshrc', "/home/#{local_user}/.zshrc")
                ssh_copy.(ssh, '~/.vimrc', "/home/#{local_user}/.vimrc")
                ssh_copy.(ssh, '~/.gitconfig', "/home/#{local_user}/.gitconfig")

                puts "Deploy SSH keys"
                logit.("Create .ssh folder")
                ssh.exec!("sudo mkdir /home/#{local_user}/.ssh")
                local_ssh_dir = File.expand_path("~/.ssh")
                Dir.foreach(local_ssh_dir) do |f|
                  if f =~ /\.pub$/
                    k = File.read(File.join(local_ssh_dir, f)).strip
                    logit.("Add public key '#{f}' to the guest")
                    ssh.exec!("sudo sh -c 'echo \"#{k}\" >> /home/#{local_user}/.ssh/authorized_keys'")
                  elsif f == 'id_ed25519'
                    ssh_copy.(ssh, "~/.ssh/#{f}", "/home/#{local_user}/.ssh/#{f}")
                    ssh.exec!("sudo chmod 0600 /home/#{local_user}/.ssh/#{f}")
                  end
                end

                puts "Setup mounted directories"
                ssh.exec!("sudo mkdir /home/#{local_user}/cwd")
                fstab_entry = "CWD /home/#{local_user}/cwd 9p _netdev,trans=virtio,version=9p2000.u,msize=104857600 0 0"
                ssh.exec!("sudo sh -c 'echo \"#{fstab_entry}\" >> /etc/fstab'")
                ssh.exec!("sudo mount /home/#{local_user}/cwd")

                # finalize permissions of the user
                ssh.exec!("echo \"#{local_user} ALL=(ALL:ALL) NOPASSWD: ALL\" | sudo tee -a /etc/sudoers")
                ssh.exec!("sudo chown -hR #{local_user}:staff /home/#{local_user}")
              else
                puts "Guets already deployed"
              end
            end

            break
          rescue Errno::ECONNRESET, Net::SSH::ConnectionTimeout
            # host is still not available
            if x > 5
              puts "Guest '#{vm['name']}' not yet up... (#{x+1}/#{how_many_tries})"
            elsif x >= 999
              raise "Couldn't connect to guest host"
            end
            sleep 1
          end
        end
      end
    when 'list'
      Dir.foreach(USER_DISK_FOLDER) do |e|
        next unless e =~ /qcow2$/
        puts e.gsub('.qcow2', '')
      end

    when 'vnc'
      guest_id = if options.base.nil?
        1
      else
        99
      end
      Guest.new(guest_id: guest_id).connect_vnc

    when 'ssh'
      guest_id = if options.base.nil?
        1
      else
        99
      end
      Guest.new(guest_id: guest_id).connect_ssh

    when 'quit'
      guest_id = if options.base.nil?
        1
      else
        99
      end
      Guest.new(guest_id: guest_id).quit!

    when 'status'
      guest_id = if options.base.nil?
        1
      else
        99
      end
      puts Guest.new(guest_id: guest_id).status

    # shutdown guest(s) from the current environment
    when 'down', 'shutdown'
      guest_id = if options.base.nil?
        1
      else
        99
      end
      Guest.new(guest_id: guest_id).shutdown!

    when 'usb'
      vm = if ARGV[1]
        Guest.new(name: ARGV[1])
      else
        Guest.new(guest_id: 1)
      end
      vm.add_usb(ENV_FILE)

    when 'modify'
      raise 'No base defined' if options.base.nil?
      disk = File.join(USER_DISK_FOLDER, "#{options.base}.qcow2")
      vm = Guest.new(guest_id: 99, disk: disk, verbose: options.verbose, dryrun: options.dryrun, install: true)
      vm.start
      vm.connect_vnc

    when 'destroy'
      guest_id = if options.base.nil?
        1
      else
        99
      end
      puts "Shutdown Guest"
      Guest.new(guest_id: guest_id).quit!
      loop do
        ret = `ps awxx | grep qemu`.strip
        break if ret.lines.count <= 2
        sleep 0.1
      end
      FileUtils.rm_rf(ENV_FOLDER, verbose: options.verbose)

    else
      case options.action

      # initialize guest(s) in the current environment
      when :init
        if File.exist? ENV_FILE
          puts 'Environment already initialized'
        else
          options.machines.map {|x| {name: x}}
          init_data = JSON.pretty_generate({ guests: options.machines.map { |x| { name: x } } })
          File.open(ENV_FILE, 'w+') do |f|
            f.puts init_data
          end
        end

      # install a base image for the current user
      when :install
        if options.control == :quit
          Guest.new(guest_id: 99).quit!
          exit
        end

        # prepare installation image
        img_url = options.image
        img_name = img_url.split("/").last
        iso = File.join(USER_MISC_FOLDER, img_name)
        if File.exist? iso
          puts "Image '#{img_name}' exist"
        else
          puts "Download #{img_name}"
          3.times do
            Susi.download(img_url, img_name, verbose: options.verbose)
            break unless File.size(iso).to_i == 0
            FileUtils.rm(iso, verbose: options.verbose)
            sleep 1
          end
          raise "Couldn't download" unless File.exist? iso
        end

        # start guest VM
        disk = File.join(USER_DISK_FOLDER, "#{options.base}.qcow2")
        vm = Guest.new(guest_id: 99, iso: iso, disk: disk, verbose: options.verbose, dryrun: options.dryrun, install: true)

        case options.connect
        when :vnc
          vm.connect_vnc
        when :ssh
          vm.connect_ssh
        else
          vm.start
          vm.connect_vnc
        end

      # reset the current users setup
      when :reset
        FileUtils.rm_rf(USER_FOLDER, verbose: options.verbose)

      else
        case options.connect
        when :vnc
          Guest.new(guest_id: 1).connect_vnc
        when :ssh
          Guest.new(guest_id: 1).connect_ssh
        else
          puts "Unknown action: #{options.action}"
        end
      end
    end
  end

  # check if the environment is setup
  def Susi.check_environment
    Susi.init_user_folder
  end

  def Susi.init_local_folder
    unless File.exist? ENV_FOLDER
      puts "Environment folder doesn't exist, create..."
      FileUtils.mkdir_p(ENV_FOLDER)
      FileUtils.mkdir_p(File.join(ENV_FOLDER, 'machines'))
    end
  end

  def Susi.init_local_machine_folder(name: nil)
    machine_folder = File.join(ENV_FOLDER, 'machines', name)
    unless File.exist? machine_folder
      FileUtils.mkdir_p(machine_folder)
    end
  end

  # initialize the user folder in the home directory
  def Susi.init_user_folder
    unless File.exist? USER_FOLDER
      puts "User folder doesn't exist, create..."
      FileUtils.mkdir_p(USER_FOLDER)
      FileUtils.mkdir_p(USER_DISK_FOLDER)
      FileUtils.mkdir_p(USER_MISC_FOLDER)

      # copy and un-pack firmware for ARM architecture
      %w(edk2-aarch64-code edk2-arm-vars).each do |fw|
        fw_file = "#{fw}.fd.xz"
        FileUtils.cp(File.join(File.dirname(__FILE__), fw_file), USER_MISC_FOLDER)
        `xz -d #{File.join(USER_MISC_FOLDER, fw_file)}`
      end
    end
  end

  # download a file and store in misc folder
  def Susi.download(link, name, verbose: false)
    url_path = "/" + link.split("/")[3..-1].join("/")
    Net::HTTP.start(link.split('/')[2]) do |http|
      response = http.request_head(url_path)
      total_size = response["content-length"].to_i
      download_size = 0.0
      last_time = Time.now

      # start download and write to disk
      File.open(File.join(USER_MISC_FOLDER, name), 'w+') do |file|
        http.get(url_path) do |data|
          file.write data

          # status message
          if verbose
            download_size += data.length
            percent = download_size / total_size * 100.0
            if (Time.now - last_time) >= 30
              puts "#{Time.now}: #{percent.round(1)}%"
              last_time = Time.now
            end
          end
        end
      end
    end
  end
end
