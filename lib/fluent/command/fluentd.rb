#
# Fluentd
#
# Copyright (C) 2011 FURUHASHI Sadayuki
#
#    Licensed under the Apache License, Version 2.0 (the "License");
#    you may not use this file except in compliance with the License.
#    You may obtain a copy of the License at
#
#        http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS,
#    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#    See the License for the specific language governing permissions and
#    limitations under the License.
#

require 'optparse'
require 'fluent/log'
require 'fluent/env'
require 'fluent/version'

op = OptionParser.new

config_path = Fluent::DEFAULT_CONFIG_PATH
plugin_dirs = [Fluent::DEFAULT_PLUGIN_DIR]
log_level = Fluent::Log::LEVEL_INFO
log_file = nil
daemonize = false
libs = []
setup_path = nil

op.on('-s', "--setup [DIR=#{File.dirname(Fluent::DEFAULT_CONFIG_PATH)}]", "install sample configuration file to the directory") {|s|
  setup_path = s || File.dirname(Fluent::DEFAULT_CONFIG_PATH)
}

op.on('-c', '--config PATH', "config flie path (default: #{config_path})") {|s|
  config_path = s
}

op.on('-p', '--plugin DIR', "add plugin directory") {|s|
  plugin_dirs << s
}

op.on('-I PATH', "add library path") {|s|
  $LOAD_PATH << s
}

op.on('-r NAME', "load library") {|s|
  libs << s
}

op.on('-d', '--daemon PIDFILE', "daemonize fluent process") {|s|
  daemonize = s
}

op.on('-o', '--log PATH', "log file path") {|s|
  log_file = s
}

op.on('-v', '--verbose', "increment verbose level (-v: debug, -vv: trace)", TrueClass) {|b|
  if b
    case log_level
    when Fluent::Log::LEVEL_INFO
      log_level = Fluent::Log::LEVEL_DEBUG
    when Fluent::Log::LEVEL_DEBUG
      log_level = Fluent::Log::LEVEL_TRACE
    end
  end
}

(class<<self;self;end).module_eval do
  define_method(:usage) do |msg|
    puts op.to_s
    puts "error: #{msg}" if msg
    exit 1
  end
end

begin
  op.parse!(ARGV)

  if ARGV.length != 0
    usage nil
  end
rescue
  usage $!.to_s
end


if setup_path
  require 'fileutils'
  FileUtils.mkdir_p File.join(setup_path, "plugin")
  confpath = File.join(setup_path, "fluent.conf")
  if File.exist?(confpath)
    puts "#{confpath} already exists."
  else
    File.open(confpath, "w") {|f|
      conf = File.read File.join(File.dirname(__FILE__), "..", "..", "..", "fluent.conf")
      f.write conf
    }
    puts "Installed #{confpath}."
  end
  exit 0
end


if log_file
  log_out = File.open(log_file, "a")
else
  log_out = $stdout
end

$log = Fluent::Log.new(log_out, log_level)
if log_level <= Fluent::Log::LEVEL_DEBUG
  $log.enable_debug
end

require 'fluent/engine'
Fluent::Engine.init

libs.each {|ilb|
  require lib
}

plugin_dirs.each {|dir|
  if Dir.exist?(dir)
    Fluent::Engine.load_plugin_dir(dir)
  end
}

begin
  Fluent::Engine.read_config(config_path)
rescue Fluent::ConfigError
  $log.error "#{config_path}: #{$!}"
  $log.debug_backtrace
  exit 1
rescue
  # TODO error
  $log.error $!
  $log.debug_backtrace
  exit 1
end

if Fluent::Engine.match?($log.tag)
  $log.enable_event
end

trap :INT do
  Fluent::Engine.stop
end

trap :TERM do
  Fluent::Engine.stop
end

trap :HUP do
  if log_file
    $log.reopen(log_file, "a")
  end
end

trap :USR1 do
  $log.info "force flushing"
  Fluent::Engine.flush!
end

if daemonize
  exit!(0) if fork
  Process.setsid
  exit!(0) if fork
  File.umask(0)
  STDIN.reopen("/dev/null")
  STDOUT.reopen("/dev/null", "w")
  STDERR.reopen("/dev/null", "w")
  File.open(daemonize, "w") {|f|
    f.write Process.pid.to_s
  }
end

$log.info "running fluent-#{Fluent::VERSION}"
Fluent::Engine.run

