require "json"

require "dotconf/error"

class Dotconf
  # Base class to hold a dotconf variable declaration. An instance is
  # constructed and stored for each variable the a {Dotconf} instance manages
  # (see {Dotconf#vars}).
  #
  # This class is the default used by {Dotconf#var!}. Values are {String}, which
  # is the native type in both the system environment and dotenv files.
  #
  # This class is designed to be easily extended to facilitate encoding and
  # decoding types other than {String}. See {Dotconf::Bool} for an example.
  class Var
    # Name that identifies this variable. Should be snake-case without namespace
    # prefix.
    #
    # `#to_s` is used to normalize to a {String} wherever `name` arguments are
    # accepted so that {Symbol} representation may also be used in practice.
    #
    # @return [String]
    attr_reader :name

    # The last {#env_value} that this variable was set to _using the dotconf
    # API_ (if any). Because values are stored in the {ENV} this may not be the
    # variable's current value.
    #
    # Used to figure out what the {#src} of the current variable value is.
    #
    # @return [nil | String]
    attr_reader :set_to

    # A record of _how_ {#set_to} was set. If the variable's current value is
    # equal to the {#set_to} then this attribute is the {#src}.
    #
    # {Symbol} values represent setting methods, such as `:env` or `:runtime`,
    # while {String} values are file paths the variable was loaded from.
    #
    # @return [nil | Symbol | String]
    attr_reader :set_by

    # Construct an instance.
    #
    # @param conf [Dotconf] The {Dotconf} class this variable is attached to. It
    #   is assumed this does not change.
    #
    # @param name [#to_s] The {#name} this variable will go by.
    #
    # @param default [Object] (nil) Default value for the variable. If this is a
    #   {Proc} then it will be called with `conf` to produce the value. See
    #   {#default}.
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

    # Inspection Instance Methods
    # --------------------------------------------------------------------------

    # Where the current value of the variable came from.
    #
    # If it isn't {#set?} then `:default` is returned, as the {#default} will be
    # used.
    #
    # If {#set_by} is `nil` or the current value in {ENV} differs from {#set_to}
    # then `:env` is returned, as it must have been set by manipulating the env,
    # either before the program was started or afterwards through {ENV}.
    #
    # Otherwise, whatever was passed in the last {#set!} is returned. By
    # convention {String} values represent dotenv file paths, while {Symbol}
    # represent code paths (such as `:runtime` when {Dotconf#[]=}) is used).
    #
    # @return [Symbol | String]
    def src
      return :default unless set?

      if @set_by.nil? || @set_to != ENV[env_name]
        :env
      else
        @set_by
      end
    end

    # Construct a {Hash} showing (pretty much) everything we know about the var.
    # Useful for seeing/checking what's going on "under the hood".
    #
    # @return [Hash]
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

    # Reader Generation Instance Methods
    # --------------------------------------------------------------------------

    # Name used for "reader" methods that are generated by
    # {#define_reader_method}.
    #
    # This implementation just returns {#name}, but {Dotconf::Bool} does
    # something fancy by tacking a '?' on the end.
    #
    # @return [String]
    def reader_method_name
      name
    end

    # Define a method on `mod` that reads the current variable value. Delegated
    # to from {Dotconf#readers} so that subclasses _cloud_ customize this
    # behavior, though I'm not sure why they would need to.
    #
    # This implementation calls {Dotconf#load?} before {#get} the value. The
    # name of the generated method comes from {#reader_method_name}.
    #
    # @param mod [Module] Module to `#define_method` on.
    #
    # @return [nil]
    def define_reader_method(mod)
      # Need local variables to bind in
      conf = @conf
      var = self

      mod.send :define_method, reader_method_name do
        conf.load?
        var.get
      end

      nil
    end
  end # class Var

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

    def reader_method_name
      "#{name}?"
    end
  end # class Bool
end # class Dotconf
