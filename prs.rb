#!/usr/bin/ruby

# ----------------------------------------------------------------------------#
# Author: Chris Salij
# Repository: https://github.com/ChrisSalij/octo-pr
# ----------------------------------------------------------------------------#

# Check that all the required external dependencies exist
['ghee', 'launchy', 'optparse', 'yaml', 'io/console', 'readline'].each do |dependency|
  begin
    require dependency
  rescue LoadError
    puts "Failed to load dependency '#{dependency}'."
    puts 'Ensure that you have installed all required gems.'
    puts "HINT: `gem install #{dependency}` might work."
    puts 'Exiting immediately.'
    exit
  end
end

# Import all 
['browser', 'configuration', 'output', 'prstore', 'findprs'].each do |dependency|
  require_relative "lib/#{dependency}"
end

# Configure things from the yaml file, but override with command line options
config = configure

# Auth to github
if !config.auth_token.nil?
  github = Ghee.access_token(config.auth_token)
else
  github = Ghee.basic_auth(config.username, config.password)
end

# If the user specified "all" in the list of repos, get all the repos in the org.
if config.repos.include? "all"
  repos = github.orgs(config.org).repos.all.collect do |repo|
    repo.name
  end
  config.update_repos(repos.sort)
end

# Everything is congiture. Print out a status, and lets get this thing started.
config.print

# Go find the PRs
pr_store = find_prs(github, config)

# Printout a little status for the user so they know what was found
pr_store.print_status
puts config.seperator

# Display the results
interface = if config.interface == "terminal"
  Terminal.new(config)
else
  Interface.new()
end
interface.display(pr_store)

# Wey-hey, we're all done.
puts "Done."
