require "json"

require "dotconf/error"

class Dotconf
  class Var
    attr_reader :name, :set_to, :set_by

    def initialize(conf, name, default: nil)
      @conf = conf
      @name = name.to_s
      @default = default
      @set_to = nil
      @set_by = nil
    end

    def default
      @default.is_a?(Proc) ? @default.call(@conf) : @default
    end

    def encode(value)
      value.to_s
    end

    def decode(string)
      string
    end

    def env_name
      if @conf.prefix.empty?
        name.upcase
      else
        "#{@conf.prefix}_#{name.upcase}"
      end
    end

    def env_value(value)
      case value
      when nil, ""
        nil
      when String
        value
      else
        encode value
      end
    end

    def reader_name
      name
    end

    def get
      return default unless set?

      decode ENV[env_name]
    end

    def set?
      case ENV[env_name]
      when nil, ""
        false
      else
        true
      end
    end

    def set!(value, by)
      @set_to = env_value(value)
      @set_by = by
      ENV[env_name] = @set_to
    end

    def src
      return :default unless set?

      if @set_by.nil? || @set_to != ENV[env_name]
        :env
      else
        @set_by
      end
    end

    def write(io)
      v_env = env_value(get)
      v_env = JSON.dump v_env if v_env.include?(%("))

      io.puts "#{env_name}=#{v_env}"
    end

    def prompt!
      current = env_value(get)

      print "Enter value for #{env_name} ("

      case src
      when :default
        print "default"
      when :env
        print "from env"
      when :runtime
        print "from runtime"
      when :prompt
        print "from this prompt"
      when String
        print "from #{src} file"
      end

      puts ": #{current.inspect})"

      v_env = STDIN.gets.chomp.then do |rsp|
        rsp.empty? ? current : rsp
      end

      set! v_env, :prompt
    end

    def explain
      value = get

      {
        "class" => self.class.name,
        "runtime" => {
          "value" => value,
          "type" => value.class.name
        },
        "env" => {
          "name" => env_name,
          "value" => env_value(value)
        },
        "src" => src
      }
    end
  end

  class Bool < Var
    def decode(str)
      case str
      when "0", "f", "F", "false", "False", "FALSE"
        false
      when "1", "t", "T", "true", "True", "TRUE"
        true
      else
        raise DecodeError, "expected bool string, given: #{str.inspect}"
      end
    end

    def reader_name
      "#{name}?"
    end
  end
end
