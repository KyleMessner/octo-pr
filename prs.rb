#!/usr/bin/ruby

# ----------------------------------------------------------------------------#
# Author: Chris Salij
# Repository: https://github.com/ChrisSalij/octo-pr
# ----------------------------------------------------------------------------#

# Check that all the required modules exist
['ghee', 'launchy', 'optparse', 'yaml', 'io/console', 'readline'].each do |dependency|
  begin
    require dependency
  rescue LoadError
    puts "Failed to load dependency '#{dependency}'."
    puts "Ensure that you have installed all required gems."
    puts "HINT: `gem install #{dependency}` might work."
    puts "Exiting immediately."
    exit
  end
end

# ----------------------------------------------------------------------------#
# BEGIN: Helper Functions
# ----------------------------------------------------------------------------#

# Tuple to help with validation of required values in the yaml config file.
# Takes the name of the value, and the expected type.
Validator = Struct.new(:name, :type)

# Outputs a message to the terminal that can be replaced by calling this
# method again.
# To empty the line call this method with an empty string as a message.
#
# NOTE: Throws an error if the line is longer than ther terminal window.
def buffer(message);
  buffer = Integer(`tput co`) - message.size
  print "\r#{message}#{" " * (buffer)}"
  $stdout.flush
end

# Class which handles opening urls in the default browser.
class Browser

  def initialize;
    @already_opened_prs = Set.new()
  end

  # Open a url in the browser.
  # Automatically filters urls if they've already been opened.
  def open(url);
    if !@already_opened_prs.include? url
      # Because Launchy sometimes fails to open multiple tabs if it is called too quickly
      sleep(0.1)
      Launchy.open(url) do |exception|
        puts "Attempted to open #{url} and failed because #{exception}"
      end
      @already_opened_prs.add url
    else
      puts "filtered #{url}"
    end
  end

end

# Holds the general configuration for the app
class Configuration

  attr_accessor :username, :password, :auth_token, :org, :repos, :authors, :auto_open, :show_link, :indent, :verbose_mode, :quiet_mode, :seperator

  # Initialize the config. Takes two parameters;
  # options - The command line options
  # yaml - The configuration yaml file with default values
  def initialize(options, yaml);
    validate(yaml)

    @username = options[:username] ||= yaml['github']['username']
    @password = options[:password] ||= yaml['github']['password']
    @auth_token = options[:auth_token] ||= yaml['github']['auth_token']

    @org = options[:org] ||= yaml['github']['org']
    @repos = (options[:repos] ||= yaml['github']['repos']).sort
    @authors = (options[:authors] ||= yaml['github']['authors']).sort.map { |author| author.downcase.strip }
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

# Holds found PRs and provides some handy accessors
class PRs

  attr_accessor :author_map, :number_lookup

  def initialize;
    # A map of author name -> list of PRs (title, number, url)
    @author_map = Hash.new(Hash.new([]))
    # A map of number to -> url (for each lookup)
    @number_lookup = Hash.new([])
  end

  # Add a given pr to the list of prs
  def add(author, repo, title, number, url);
    number = number.to_s

    if !@author_map.has_key? author
      @author_map[author] = Hash.new()
    end

    if !@author_map[author].has_key? repo
      @author_map[author][repo] = Array.new()
    end

    @author_map[author][repo].push({ 'title' => title, 'number' => number, 'url' => url })
    @number_lookup["#{repo}:#{number}"] = url
  end

  # Get all the authors with an open pr
  def authors;
    @author_map.keys.sort
  end

  # Get all the open pr numbers
  def numbers;
    @number_lookup.keys.sort
  end

  # Get all the urls for a given lookup.
  # Essentially just an easy shorthand for looking up by number + author.
  def urls_for(lookup);
    urls_by_number(lookup) + urls_by_author(lookup)
  end

  def urls_by_number(number);
    @number_lookup[number]
  end

  def urls_by_author(author);
    @author_map[author].flat_map do |repos,commits|
      commits.map do |commit|
        commit['url']
      end
    end
  end

  def get_all_urls;
    @author_map.flat_map do |_,repo|
      repo.flat_map do |_,commits|
        commits.map do |commit|
          commit['url']
        end
      end
    end
  end

  # Prints a status of all prs found.
  # config - The configuration file. Used for indentation, and determining
  #          the list of expected authors.
  def print_status(config);
    @author_map.each do |author, repo|
      puts "#{author}"
      repo.each do |repo, commits|
        puts "#{config.indent}#{commits.size} PR#{(commits.size == 1) ? "" : "s" } against #{repo}"

        if !config.quiet_mode
          # We're not in quiet mode, print out the title
          commits.each do |commit|
            puts "#{config.indent * 2}#{commit['number']}: #{commit['title']}"

            # And if they want the link printed out, do that on the next line
            if config.show_link
              puts "#{config.indent * 3}#{commit['url']}"
            end
          end

        elsif config.show_link
          # We're in quiet mode, but they've said they want to see the links
          commits.each do |commit|
            puts "#{config.indent * 2}#{commit['url']}"
          end
        end
      end
    end

    if !config.quiet_mode
      noPrs = (config.authors - authors)
      puts "NOTE: #{noPrs.join(", ")} #{(noPrs.size == 1) ? "has" : "have"} no open prs"
    end
  end

end

# ----------------------------------------------------------------------------#
# END: Helper Functions
# ----------------------------------------------------------------------------#

# ----------------------------------------------------------------------------#
# BEGIN: Configuration
# ----------------------------------------------------------------------------#

options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: `#{__FILE__} -c /path/to/file.yml [options]`"
  options[:opts] = opts
  
  # Misc config
  
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

  # Search Config
  
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
  
  # Auth config
  
  opts.on("-p", "--password [password]", String, "Password to authenicate with.") do |password|
    options[:password] = password
  end
  
  opts.on("-x", "--auth-token [auth_token]", String, "Auth token to authenticate with.") do |auth_token|
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

config = Configuration.new(options, yaml)

# ----------------------------------------------------------------------------#
# END: Configuration
# ----------------------------------------------------------------------------#

# ----------------------------------------------------------------------------#
# BEGIN: Pre-launch
# ----------------------------------------------------------------------------#

# Create the gihub instance
if !config.auth_token.nil?
  gh = Ghee.access_token(config.auth_token)
else
  gh = Ghee.basic_auth(config.username, config.password)
end

# If the user specified "all" in the list of repos, get all the repos in the org.
if config.repos.include? "all"
  repos = gh.orgs(config.org).repos.all.collect do |repo|
    repo.name
  end
  config.update_repos(repos.sort)
end

# Everything is set up. Print out a status, and lets get this thing started.
config.print

# ----------------------------------------------------------------------------#
# END: Pre-launch
# ----------------------------------------------------------------------------#

# ----------------------------------------------------------------------------#
# BEGIN: Core Logic
# ----------------------------------------------------------------------------#

prs = PRs.new()

# Go through all the repos and check for open prs
count = 0
config.repos.each do |repo|
  # Status printout. Useful for when you're checking a lot of repos.
  count += 1
  buffer "Getting PRs for '#{config.org}/#{repo}' (#{count}/#{config.repos.size})"

  json = gh.repos(config.org, repo).pulls({:state => "open"}).all

  if json.class.name != "Array"

    # Deal with any errors reported by the API.
    if json.message == "Bad credentials"
      puts "Error: Invalid #{config.auth_token.nil? ? "username/password combo" : "auth token"} used. Exiting immediately since future requests cannot succeed"
      exit
    elsif json.message == "Not Found"
      puts "Error: No repo called #{repo} found in #{config.org}"
    else
      puts "Unknown error encountered #{json.message}, while getting Prs for #{config.repo} in #{config.org}"
    end

  else

    # Iterate through all open prs (api doesn't provide a filter for author)
    json.each do |pr|
      author = pr['user']['login'].downcase

      # Where the author is in the list of requested authors
      # NOTE: We downcased & sorted the list of authors when we read them from the config
      if config.authors.include? author

        title = pr['title']
        number = pr['number']
        url = pr['_links']['html']['href']

        prs.add(author, repo, title, number, url)
      end
    end

  end
end
buffer ""

# Printout a little status for the user so they know what was found
puts config.seperator
prs.print_status(config)
puts config.seperator

puts
puts config.seperator

# Either automatically open all prs, or ask the user which prs they wish to open
if config.auto_open
  puts "Automatically opening links for all found PRs."
  options = Set.new("all")
else
  validAuthors = (config.authors & prs.authors).sort
  validNumbers = prs.numbers
  validCommands = ["all", "none"]
  allValid = (validAuthors + validNumbers + validCommands).to_set

  if !config.quiet_mode
    puts "You can specify PRs to open by;"
    puts "#{config.indent}Author: #{validAuthors.join(", ")}"
    puts "#{config.indent}PR #: #{validNumbers.join(", ")}"
    puts "#{config.indent}Misc: #{validCommands.join(", ")}"
  end

  Readline.completion_proc = proc { |s| allValid.grep(/^#{Regexp.escape(s)}/) }

  begin
    commands = Readline.readline('> ', true).chomp.strip.split(" ").to_set
    if commands.size == 1 && !(commands < allValid)
      puts "Unknown command #{commands.inspect} specified."
    elsif !(commands < allValid)
      puts "Specified unknown commands: `#{commands.inspect}`."
    end
  end while !(commands < allValid)
end

# Open all requested PRs in the default browser
browser = Browser.new()
commands.each do |command|

  if command == "all"
    prs.get_all_urls.each do |url|
      browser.open url
    end
  elsif command == "none"
    # Nothing to do here.
  else
    prs.urls_for(command).each do |url|
      browser.open url
    end
  end

end

if !config.quiet_mode
  puts config.seperator
  puts
end

# Wey-hey, we're all done.
puts "Done."

# ----------------------------------------------------------------------------#
# END: Code
# ----------------------------------------------------------------------------#
