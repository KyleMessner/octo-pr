#!/usr/bin/ruby

# Holds the general configuration for the app
class Configuration

  attr_accessor :username, :password, :auth_token, :org, :repos, :authors, :interface, :auto_open, :show_link, :indent, :verbose_mode, :quiet_mode, :seperator

  # Initialize the config. Takes two parameters;
  # options - The command line options
  # yaml - The configuration yaml file with default values
  def initialize(options, yaml);
    validate(yaml)

    # Auth
    @username = options[:username] ||= yaml['github']['username']
    @password = options[:password] ||= yaml['github']['password']
    @auth_token = options[:auth_token] ||= yaml['github']['auth_token']

    # Info to get
    @org = options[:org] ||= yaml['github']['org']
    @repos = (options[:repos] ||= yaml['github']['repos']).sort
    @authors = (options[:authors] ||= yaml['github']['authors']).sort.map { |author| author.downcase.strip }
    
    # Output
    @interface = options[:interface] ||= yaml['github']['interface'] ||= "terminal"
    
    @auto_open = options[:auto_open] ||= yaml['github']['auto_open'] ||= false
    @show_link = options[:show_link] ||= yaml['github']['show_link'] ||= false
    @indent = options[:indent] ||= yaml['github']['indent'] ||= "    "

    @verbose_mode = options[:verbose_mode] ||= yaml['github']['verbose_mode'] ||= false
    # If verbose mode is set from config file or via the command line, override quiet mode
    @quiet_mode = !options[:verbose_mode] ||= !yaml['github']['verbose_mode'] ||= options[:quiet_mode] ||= yaml['github']['quiet_mode'] ||= false

    # The string used to separate blocks of output
    @seperator = '--------------------------'

  end

  def update_repos(repos);
    @repos = repos
  end

  def print;
    if @verbose_mode
      puts @seperator
      if @auth_token.nil?
        puts "Using Auth: username/password '#{@username}'/'#{"*" * @password.size}'"
      else
        puts "Using Auth: Token '#{"*" * @auth_token.size}'"
      end
      if @auto_open
        puts "Automatically opening PRs made by;"
      else
        puts "Finding open PRs made by;"
      end
      puts "#{@indent}* #{@authors.join("\n#{@indent}* ")}"
      puts "In the organization '#{@org}' to the following repos;"
      puts "#{@indent}* #{@repos.join("\n#{@indent}* ")}"

      puts "Formatting;"
      if @show_link
        puts "#{@indent}Printing links for each PR."
      else
        puts "#{@indent}Not printing links for each PR."
      end
      puts "#{@indent}And using an indent of '#{@indent}'."
      puts @seperator
    end
  end

  private

  # Validate that all the required config values are present
  def validate(yaml);
    [
      Validator.new('org', String),
      Validator.new('repos', Array),
      Validator.new('authors', Array)
    ].each do |tuple|
      param = yaml['github'][tuple.name]
      raise "Missing requred config param '#{tuple.name}'" unless !param.nil?
      raise "Param '#{tuple.name}' is of the wrong type. Expected #{tuple.type}, was actually #{param.class.name}" unless param.is_a? tuple.type
    end

    if !((yaml['github']['username'] && yaml['github']['password']) || yaml['github']['auth_token'])
      raise "You must specify either a username/password combo or an auth token to use."
    end
  end

end

def configure
  
  options = {}
  OptionParser.new do |opts|
    opts.banner = "Usage: `#{__FILE__} -c /path/to/file.yml [options]`"
    options[:opts] = opts
  
    opts.on("-?", "--help", "Prints help and exits.") do |_|
      puts opts
      exit
    end
  
    opts.on("-c", "--config [file]", "The yaml config file to load.") do |file|
      options[:config] = file
    end

    opts.on("-q", "--quiet", "Enables quiet mode. No terminal output outside of prompts for required input, or fatal error will be printed.") do |quiet_mode|
      options[:quiet_mode] = quiet_mode
    end
  
    opts.on("-i", "--interface", "Sets the interface to use.") do |interface|
      options[:interface] = interface
    end
  
    opts.on("-v", "--verbose", "Shows all the configured options on launch. If enabled this will also set quiet_mode to false.") do |verbose_mode|
      options[:verbose_mode] = verbose_mode
    end
  
    opts.on("-b", "--auto-open", "Automatically open all PRs that were found in the default browser. No terminal prompt.") do |auto_open|
      options[:auto_open] = auto_open
    end
  
    opts.on("-l", "--show-link", "Adds links to the PR in the status printout.") do |show_link|
      options[:show_link] = show_link
    end
  
    opts.on("-i", "--indent [indent]", "Specify the how to indent lines.") do |indent|
      options[:indent] = indent
    end

    opts.on("-o", "--org [org]", String, "Organization to search in.") do |org|
      options[:org] = org
    end
  
    opts.on("-r",
      "--repos [repo1,repo2]",
      Array,
      "Repositories to search for PRs in. Setting this to 'all' will fetch all repos in the organization. NOTE: This will increase the number of api requests made several-fold.") do |repos|
      options[:repos] = repos
    end
  
    opts.on("-a", "--authors [author1,author2]", Array, "Authors to search for.") do |authors|
      options[:authors] = authors
    end
  
    opts.on("-u", "--username [username]", String, "Username to authenticate with.") do |username|
      options[:username] = username
    end
  
    opts.on("-p", "--password [password]", String, "Password to authenicate with.") do |password|
      options[:password] = password
    end
  
    opts.on("-t", "--auth-token [auth_token]", String, "Auth token to authenticate with.") do |auth_token|
      options[:auth_token] = auth_token
    end
  
  end.parse!

  # Just in case someone types `<script> help`.
  if ARGV[0] == "help"
    puts options[:opts]
    exit
  end

  # Load the config file
  if !options.has_key? :config
    puts "No config file specified. You must specify a yaml config file."
    puts options[:opts]
    exit
  end
  config_path = options[:config]
  if File.exists? config_path
    puts "Using config file at '#{config_path}'"
  else
    puts "Woah, config file '#{config_path}' doesn't exist, can't continue."
    puts "Exiting immediately."
    exit
  end
  yaml = YAML.load(File.open(config_path))

  Configuration.new(options, yaml)
end