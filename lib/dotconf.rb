# frozen_string_literal: true

require "logger"

require_relative "dotconf/version"
require_relative "dotconf/var"

class Dotconf
  include Enumerable

  DEFAULT_LOGGER = Logger.new(STDOUT).tap do |logger|
    logger.level = Logger::INFO
    logger.formatter = proc { |severity, _datetime, _progname, msg|
      "# [#{severity}] #{msg}\n"
    }
  end

  DEFAULT_PATH = ".env"
  DEFAULT_PREFIX = ""

  attr_accessor :logger, :path, :prefix
  attr_reader :loaded, :vars

  def initialize(path: DEFAULT_PATH, prefix: DEFAULT_PREFIX,
                 logger: DEFAULT_LOGGER, vars: nil)
    @logger = logger
    @path = path
    @prefix = prefix
    @vars = {}

    return if vars.nil?

    vars.each do |name, props|
      var! name, **props
    end
  end

  def var! name, cls: Var, **opts
    var = cls.new self, name, **opts
    vars[var.name] = var
  end

  def file?
    if File.exist? path
      return true if File.file?(path)

      logger.warn "Dotenv path `#{path}` exists but is not a regular file"
    end

    false
  end

  def load!
    unless file?
      logger.info "dotenv not found at #{path}"
      logger.info "run `rake configure` to create one"
      return self
    end

    logger.info "loading config from #{path}"
    @loaded = Dotenv.parse path

    to_set = loaded.to_h

    vars.each_value do |var|
      if (v_env = to_set.delete(var.env_name)) && !var.set?
        var.set!(v_env, path)
      end
    end

    unless to_set.empty?
      logger.warn "unknown vars found in #{path}: #{to_set.keys}"
    end

    self
  end

  def write(io)
    vars.each do |_name, var|
      var.write(io)
    end
  end

  def dump
    StringIO.open do |io|
      write io
      io.string
    end
  end

  def save!
    File.open(path, "w") do |io|
      write io
    end
  end

  def [](name)
    vars[name.to_s].get
  end

  def []=(name, value)
    vars[name.to_s].set! value, :runtime
  end

  def each
    return enum_for(:each) unless block_given?

    vars.each_value do |var|
      yield var.name, var.get
    end
  end

  def to_h
    each.to_h
  end

  def configure!
    puts "Configuring..."

    vars.each_value do |var|
      var.prompt!
    end

    save!
  end

  def explain
    {
      "path" => path,
      "prefix" => prefix,
      "loaded" => loaded,
      "vars" => vars.each_value.map do |var|
        [var.name, var.explain]
      end.to_h
    }
  end

  def readers
    mod = Module.new

    vars.each_value do |var|
      mod.send :define_method, var.reader_name do
        var.get
      end
    end

    mod
  end
end
