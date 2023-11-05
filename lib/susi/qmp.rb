def qmp(command)
  socket = TCPSocket.new("localhost", QMP_PORT)
  socket.gets
  socket.puts('{"execute":"qmp_capabilities"}')
  response = JSON.parse(socket.gets)
  if response["return"] == {}
    puts "QMP connection established"
  else
    puts "QMP connection failed"
  end
  socket.puts(command)
  response = JSON.parse(socket.gets)
  socket.close
  if response["error"]
    puts command
    raise response["error"]["desc"]
  end
  response
end

def qmp_execute(command)
  qmp('{"execute":"' + command + '"}')
end