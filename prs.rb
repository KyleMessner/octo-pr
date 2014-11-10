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

config_file = '~/prs.yml'

# ----------------------------------------------------------------------------#
# BEGIN: Configuration
# ----------------------------------------------------------------------------#

options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: #{__FILE__} [options]"
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
config_file = options[:config] || config_file
if File.exists? config_file
  puts "Using config file at '#{config_file}'"
else
  puts "Woah, config file '#{config_file}' doesn't exist, can't continue."
  puts "Exiting immediately."
  exit
end
config = YAML.load(File.open(config_file))

# Validate that all the required config values are present
Validator = Struct.new(:name, :type)
[
  Validator.new('org', String),
  Validator.new('repos', Array),
  Validator.new('authors', Array)
].each do |tuple|
  conf = config['github'][tuple.name]
  raise "Missing requred config param '#{tuple.name}'" unless !conf.nil?
  raise "Param '#{tuple.name}' is of the wrong type. Expected #{tuple.type}, was actually #{conf.class.name}" unless conf.is_a? tuple.type
end

if !((config['github']['username'] && config['github']['password']) || config['github']['auth_token'])
  raise "You must specify either a username/password combo or an auth token to use."
end

# Set all variables as needed. If they haven't been overwritten 
username = options[:username] ||= config['github']['username']
password = options[:password] ||= config['github']['password']
auth_token = options[:auth_token] ||= config['github']['auth_token']

org = options[:org] ||= config['github']['org']
repos = (options[:repos] ||= config['github']['repos']).sort
authors = (options[:authors] ||= config['github']['authors']).sort.map { |author| author.downcase.strip }
auto_open = options[:auto_open] ||= config['github']['auto_open'] ||= false
show_link = options[:show_link] ||= config['github']['show_link'] ||= false
indent = options[:indent] ||= config['github']['indent'] ||= "    "

verbose_mode = options[:verbose_mode] ||= config['github']['verbose_mode'] ||= false
# If verbose mode is set from config file or via the command line, override quiet mode
quiet_mode = !options[:verbose_mode] ||= !config['github']['verbose_mode'] ||= options[:quiet_mode] ||= config['github']['quiet_mode'] ||= false

# The string used to separate blocks of output
seperator = '--------------------------'

# ----------------------------------------------------------------------------#
# END: Configuration
# ----------------------------------------------------------------------------#

# ----------------------------------------------------------------------------#
# BEGIN: Helper Functions
# ----------------------------------------------------------------------------#

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

  @@already_opened_prs = Set.new()

  # Open a url in the browser.
  # Automatically filters urls if they've already been opened.
  def open(url);
    if !@@already_opened_prs.include? url
      # Because Launchy sometimes fails to open multiple tabs if it is called too quickly
      sleep(0.1)
      Launchy.open(url) do |exception|
        puts "Attempted to open #{uri} and failed because #{exception}"
      end
      @@already_opened_prs.add url
    else
      puts "filtered #{url}"
    end
  end

end

# ----------------------------------------------------------------------------#
# END: Helper Functions
# ----------------------------------------------------------------------------#

# ----------------------------------------------------------------------------#
# BEGIN: Pre-launch
# ----------------------------------------------------------------------------#

# Lets get this thing started
if !auth_token.nil?
  gh = Ghee.access_token(auth_token)
else
  gh = Ghee.basic_auth(username, password)
end

if repos.include? "all"
  repos = gh.orgs(org).repos.all.collect do |repo|
    repo.name
  end
  repos = repos.sort
end
map = Hash.new()
numbers = Hash.new()

# Pre-launch printout

if verbose_mode
  puts seperator
  if auth_token.nil?
    puts "Using Auth: username/password '#{username}'/'#{"*" * password.size}'"
  else
    puts "Using Auth: Token '#{"*" * auth_token.size}'"
  end
  if auto_open
    puts "Automatically opening PRs made by;"
  else
    puts "Finding open PRs made by;"
  end
  puts "#{indent}* #{authors.join("\n#{indent}* ")}"
  puts "In the organization '#{org}' to the following repos;"
  puts "#{indent}* #{repos.join("\n#{indent}* ")}"

  puts "Formatting;"
  if show_link
    puts "#{indent}Printing links for each PR."
  else
    puts "#{indent}Not printing links for each PR."
  end
  puts "#{indent}And using an indent of '#{indent}'."
  puts seperator
end

# ----------------------------------------------------------------------------#
# END: Pre-launch
# ----------------------------------------------------------------------------#

# ----------------------------------------------------------------------------#
# BEGIN: Core Logic
# ----------------------------------------------------------------------------#

# Go through all the repos and check for open prs
count = 0
repos.each do |repo|
  # Status printout. Useful for when you're checking a lot of repos.
  count += 1
  buffer "Getting PRs for '#{org}/#{repo}' (#{count}/#{repos.size})"

  json = gh.repos(org, repo).pulls({:state => "open"}).all

  if json.class.name != "Array"

    # Deal with any errors reported by the API.
    if json.message == "Bad credentials"
      puts "Error: Invalid #{auth_token.nil? ? "username/password combo" : "auth token"} used. Exiting immediately since future requests cannot succeed"
      exit
    elsif json.message == "Not Found"
      puts "Error: No repo called #{repo} found in #{org}"
    else
      puts "Unknown error encountered #{json.message}, while getting Prs for #{repo} in #{org}"
    end

  else

    # Iterate through all open prs (api doesn't provide a filter for author)
    json.each do |pr|
      author = pr['user']['login'].downcase

      # Where the author is in the list of requested authors
      # NOTE: We downcased & sorted the list of authors when we read them from the config
      if authors.include? author
        if !map.has_key? author
          map[author] = Hash.new()
        end

        if !map[author].has_key? repo
          map[author][repo] = Array.new()
        end

        number = pr['number'].to_s
        url = pr['_links']['html']['href']

        map[author][repo].push({ 'title' => pr['title'], 'number' => number, 'url' => url })
        numbers[number] = url
      end
    end

  end
end
buffer ""

# Printout a little stats for the user so they know what was found
puts seperator
map.each do |author, repo|
  puts "#{author}"
  repo.each { |repo, commits|
    puts "#{indent}#{commits.size} PR#{(commits.size == 1) ? "" : "s" } against #{repo}"

    if !quiet_mode
      # We're not in quiet mode, print out the title
      commits.each do |commit|
        puts "#{indent * 2}#{commit['number']}: #{commit['title']}"

        # And if they want the link printed out, do that on the next line
        if show_link
          puts "#{indent * 3}#{commit['url']}"
        end
      end

    elsif show_link
      # We're in quiet mode, but they've said they want to see the links
      commits.each do |commit|
        puts "#{indent * 2}#{commit['url']}"
      end
    end
  }
end

noPrs = (authors - map.keys)
puts "NOTE: #{noPrs.join(", ")} #{(noPrs.size == 1) ? "has" : "have"} no open prs"

puts seperator
puts
puts seperator

# Either automatically open all prs, or ask the user which prs they wish to open
if auto_open
  puts "Automatically opening links for all found PRs."
  options = Set.new("all")
else
  validAuthors = (authors & map.keys).sort
  validNumbers = numbers.keys.sort
  validCommands = ["all", "none"]
  allValid = (validAuthors + validNumbers + validCommands).to_set

  if !quiet_mode
    puts "You can specify PRs to open by;"
    puts "#{indent}Author: #{validAuthors.join(", ")}"
    puts "#{indent}PR #: #{validNumbers.join(", ")}"
    puts "#{indent}Misc: #{validCommands.join(", ")}"
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
    map.each { |_,repo|
      repo.each{ |_,commits|
        commits.each { |commit|
          browser.open commit['url']
        }
      }
    }
  elsif command == "none"
    # Nothing to do here.
  elsif map.has_key? command
    map[command].each { |_,commits|
      commits.each { |commit|
        browser.open commit['url']
      }
    }
  elsif numbers.has_key? command
    browser.open numbers[command]
  end
end

if !quiet_mode
  puts seperator
  puts
end

# Wey-hey, we're all done.
puts "Done."

# ----------------------------------------------------------------------------#
# END: Code
# ----------------------------------------------------------------------------#
