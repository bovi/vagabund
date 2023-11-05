require 'optparse'

def parse_args
  options = {}
  OptionParser.new do |opts|
    opts.banner = "Usage: susi.rb [options]"
  
    opts.on("-c", "--create", "Create a new image") do |c|
      options[:create] = c
    end
  
    opts.on("-n", "--name NAME", "Name of the image") do |n|
      options[:name] = n
    end
  
    opts.on("-s", "--size SIZE", "Size of the image") do |s|
      options[:size] = s
    end
  
    opts.on("-h", "--help", "Prints this help") do
      puts opts
      exit
    end
  
    opts.on("-r", "--run", "Run the VM") do |r|
      options[:run] = r
    end
  
    opts.on("-q", "--quit", "Quit the VM") do |q|
      options[:quit] = q
    end
  
    # add installer iso
    opts.on("-o", "--iso INSTALLER", "Installer ISO") do |i|
      options[:installer] = i
    end
  
    opts.on("-i", "--init", "Initialize the VM") do |init|
      options[:init] = init
    end
  
    opts.on("-l", "--list", "List all the VMs") do |list|
      options[:list] = list
    end
  
    opts.on("-s", "--ssh", "SSH into the VM") do |ssh|
      options[:ssh] = ssh
    end
  
    opts.on("-d", "--powerdown", "Power down the VM") do |halt|
      options[:halt] = halt
    end

    opts.on("-v", "--verbose", "Verbose output") do |v|
      options[:verbose] = v
    end
  end.parse!

  options
end