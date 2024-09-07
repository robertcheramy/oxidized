#!/usr/bin/env ruby
# frozen_string_literal: true

require 'net/ssh'
require 'optparse'

# This scripts logs in a network device and outputs a yaml file that can be
# used for model unit tests in spec/model/

SSH_USER = 'oxidized'
SSH_HOST = 'localhost'
SSH_COMMANDS = [
  'printf \'\000-\0x20-\0020\'\n',
  'sleep 1 && echo "done" && echo "xx " && echo "done "',
  'sleep 5 && echo "done 5"',
  '/usr/bin/uname -a',
  'hostname',
  'logout'
].freeze
SSH_CMD_TIMEOUT = 2

options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: model-yaml.rb [options]"

  opts.on('-o', '--output file', 'Specify an output file instead of stdout') do |file|
    options[:output] = file
  end
  opts.on '-h', '--help', 'Print this help' do
    puts opts
    exit
  end
end.parse!

@output = options[:output] ? File.open(options[:output], 'w') : $stdout

def wait_and_output(prepend = '')
  @ssh_output = ''
  @ssh_output_length = @ssh_output.length
  timeslot = 0
  # Loop & wait for SSH_CMD_TIMEOUT seconds after last output
  @ssh.loop(0.1) do
    sleep 0.1
    if @ssh_output_length < @ssh_output.length
      # we got new output, wait at least 2 seconds
      timeslot = 0
      @ssh_output_length = @ssh_output.length
    end
    timeslot += 1
    # exit the loop after 20 timeslots (false = exit)
    timeslot < SSH_CMD_TIMEOUT * 10
  end

  @ssh_output.each_line(chomp: true) do |line|
    # encode line and remove first and trailing double quote
    line = line.dump[1..-2]
    # Make sure trailing white spaces are coded with \0x20
    line.gsub!(/ $/, '\x20')
    # prepend white spaces for the yaml block scalar
    line = prepend + line
    @output.puts line
  end
end

@ssh = Net::SSH.start(SSH_HOST, SSH_USER, { timeout: 10 })
@ssh_output = ''

ses = @ssh.open_channel do |ch|
  ch.on_data do |_ch, data|
    @ssh_output += data
  end
  ch.request_pty(term: 'vt100') do |_ch, success_pty|
    raise NoShell, "Can't get PTY" unless success_pty

    ch.send_channel_request 'shell' do |_ch, success_shell|
      raise NoShell, "Can't get shell" unless success_shell
    end
  end
  ch.on_extended_data do |_ch, _type, data|
    $stderr.print "Error: #{data}\n"
  end
end

# get motd and fist prompt
@output.puts '---', 'init_prompt: |-'

wait_and_output('  ')

@output.puts "commands:"

SSH_COMMANDS.each do |cmd|
  @output.puts "  #{cmd}: |-"
  ses.send_data cmd + "\n"
  wait_and_output('    ')
end

@output.puts 'oxidized_output: |-'
@output.puts '  !! needs to be written by hand or copy & paste from model output'

@output.close if @output != $stdout
