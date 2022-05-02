#!/usr/bin/env ruby

require 'optparse'
require_relative 'susi'

class SusiOptParser
  class ScriptOptions
    attr_accessor :action, :verbose, :machines, :image, :base, :dryrun, :connect, :control

    def initialize
      self.verbose = false
      self.dryrun = false
    end

    def define_options(parser)
      parser.banner = "Usage: susi [options]"
      parser.separator ""
      parser.separator "Specific options:"

      define_init(parser)
      define_install(parser)
      define_base(parser)
      define_factory_reset(parser)
      define_dryrun(parser)
      define_connect(parser)
      define_control(parser)

      parser.separator ""
      parser.separator "Common options:"

      parser.on_tail("-h", "--help", "Show this message") do
        puts parser
        exit
      end
      parser.on_tail("-v", "--version", "Show version") do
        puts Susi::VERSION
        exit
      end
      parser.on_tail("--verbose", "Verbose output") do
        self.verbose = true
      end
    end

    def define_init(parser)
      parser.on("--init vm1,vm2,vm3", Array, "Initialize Guest(s)") do |vms|
        raise "Action already defined" unless self.action.nil?
        self.action = :init
        self.machines = vms
      end
    end

    def define_factory_reset(parser)
      parser.on("--reset", Array, "Factory reset the user environment") do |vms|
        raise "Action already defined" unless self.action.nil?
        self.action = :reset
      end
    end

    def define_install(parser)
      parser.on("--install [image]", "Install image") do |img|
        raise "Action already defined" unless self.action.nil?
        self.action = :install
        self.image = img || 'https://mirrors.tuna.tsinghua.edu.cn/ubuntu-releases/20.04.4/ubuntu-20.04.4-live-server-amd64.iso'
        # 'https://mirrors.tuna.tsinghua.edu.cn/ubuntu-cdimage/ubuntu/releases/20.04.4/release/ubuntu-20.04.4-live-server-arm64.iso'
        # 'https://mirrors.tuna.tsinghua.edu.cn/ubuntu-releases/20.04.4/ubuntu-20.04.4-live-server-amd64.iso'
        self.base = self.base || 'u2004server'
        self.machines = [self.image.split("/").last.split('.')[0..-2].join('.')]
      end
    end

    def define_base(parser)
      parser.on("--base [name]", "Define base name") do |base|
        self.base = base
      end
    end

    def define_dryrun(parser)
      parser.on("--dryrun", "Do not execute just show what you would do") do
        self.dryrun = true
      end
    end

    def define_connect(parser)
      parser.on("--ssh", "Connect via SSH to the guest") do
        raise 'Connect issue. Choose SSH or VNC, not both!' unless self.connect.nil?
        self.connect = :ssh
      end
      parser.on("--vnc", "Connect via VNC to the guest") do
        raise 'Connect issue. Choose SSH or VNC, not both!' unless self.connect.nil?
        self.connect = :vnc
      end
    end

    def define_control(parser)
      parser.on("--quit", "Quit the guest process") do
        self.control = :quit
      end
    end
  end

  def parse(args)
    @options = ScriptOptions.new
    @args = OptionParser.new do |parser|
      @options.define_options(parser)
      parser.parse!(args)
    end
    @options
  end

  attr_reader :parser, :options
end
