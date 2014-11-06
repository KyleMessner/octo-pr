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

  opts.on("-q", "--quiet", "Enables quiet mode. No terminal output outside of prompts for required input, or fatal error will be printed,") do |quiet_mode|
    options[:quiet_mode] = quiet_mode
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

Validator = Struct.new(:name, :type)

# NOTE: Ordinarily you can't refer to Boolean directly. Only TrueClass or
# FalseClass. This little hack means you can refer to Boolean in the same way
# as the String or Array class
module Boolean; end
class TrueClass; include Boolean; end
class FalseClass; include Boolean; end

# Validate that all the required config values are present
[
  Validator.new('org', String),
  Validator.new('repos', Array),
  Validator.new('authors', Array),
  Validator.new('auto_open', Boolean)
].each do |tuple|
  conf = config['github'][tuple.name]
  raise "Missing requred config param '#{tuple.name}'" unless !conf.nil?
  raise "Param '#{tuple.name}' is of the wrong type. Expected #{tuple.type}, was actually #{conf.class.name}" unless conf.is_a? tuple.type
end

if !((config['github']['username'] && config['github']['password']) || config['github']['auth_token'])
  raise "You must specify either a username/password combo or an auth token to use."
end

# Set all variables as needed. If they haven't been overwritten 
username = options[:username] || config['github']['username']
password = options[:password] || config['github']['password']
auth_token = options[:auth_token] || config['github']['auth_token']

org = options[:org] || config['github']['org']
repos = (options[:repos] || config['github']['repos']).sort
authors = (options[:authors] || config['github']['authors']).sort.map { |author| author.downcase.strip }
auto_open = options[:auto_open] || config['github']['auto_open'] || false
show_link = options[:show_link] || config['github']['show_link'] || false
indent = options[:indent] || config['github']['indent'] || "    "

# Whether to supress all non-essential output
quiet_mode = options[:quiet_mode] || config['github']['quiet_mode'] || false

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

def openLink(link);
  # Because Launchy sometimes fails to open multiple tabs if it is called too quickly
  sleep(0.1) 
  Launchy.open(link) do |exception|
    puts "Attempted to open #{uri} and failed because #{exception}"
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

# Pre-launch printout
puts seperator
if auto_open
  puts "Automatically opening PRs made by;"
else
  puts "Finding open PRs made by;"
end
puts "#{indent}* #{authors.join("\n#{indent}* ")}"
puts "In the organization '#{org}' to the following repos;"
puts "#{indent}* #{repos.join("\n#{indent}* ")}"
if auth_token.nil?
  puts "Using the username/password '#{username}'/'#{"*" * password.size}'"
else
  puts "Using an auth token '#{auth_token}'"
end
if show_link
  puts "Printing the link to the PR underneath each title."
end
puts "And an indent of '#{indent}'"
puts seperator

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

        # Only extract the pertinent info
        pr = { "title" => pr["title"], "url" => pr["_links"]['html']['href'] }

        # Add each open PR to a map where;
        # Author -> [repo name -> List of PRs]
        map[author][repo].push pr
      end
    end

  end
end

buffer ""

if !quiet_mode
  # Printout a little stats for the user so they know what was found
  puts seperator
  map.each do |author, repo|
    puts "#{author}"
    repo.each { |repo, commits|
      puts "#{indent}#{repo}, #{commits.size} PR#{(commits.size == 1) ? "" : "s"};"
      commits.each { |commit|
        puts "#{indent * 2}#{commit['title']}"
        if show_link
          puts "#{indent * 3}#{commit['url']}"
        end
      }
    }
  end
  noPrs = (authors - map.keys)
  puts "NOTE: #{noPrs.join(", ")} #{(noPrs.size == 1) ? "has" : "have"} no open prs"
  puts seperator
  puts
end

# Either automatically open all prs, or ask the user which prs they wish to open
puts seperator

if auto_open
  puts "Automatically opening links for all found PRs."
  author = "all"
else
  validInputs = (authors & map.keys) + ["all", "none"]
  puts "Whose PRs do you want to open: #{validInputs.join(", ")}?"

  Readline.completion_proc = proc { |s| authors.grep(/^#{Regexp.escape(s)}/) }

  begin
    author = Readline.readline('> ', true).chomp.strip
    if !validInputs.include? author
      puts "Don't know about `#{author}`, Valid inputs are: #{validInputs.join(", ")}"
    end
  end while !validInputs.include? author
  
end

# Go through and open all requested PRs.
# TODO: Add support for specifying multiple authors
if author == "all"
  map.each { |_,repo|
    repo.each{ |_,commits|
      commits.each { |commit|
        openLink(commit['url'])
      }
    }
  }
elsif author == "none"
  # Nothing to do here.
elsif map.has_key? author
  map[author].each { |_,commits|
    commits.each { |commit|
      openLink(commit['url'])
    }
  }
else
  puts "Invalid author specified. '#{author}'"
end

puts seperator
puts

# Wey-hey, we're all done.
puts "Done."

# ----------------------------------------------------------------------------#
# END: Code
# ----------------------------------------------------------------------------#
