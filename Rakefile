# a test task
task :test do
  # execute all tests in test folder
  Dir.glob("test/**/*_test.rb").each do |file|
    require_relative file
  end
end