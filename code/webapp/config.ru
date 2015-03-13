webapp = Proc.new do |env|
  ['200', {'Content-Type' => 'text/html'}, ['Hello Docker!']]
end

run webapp
