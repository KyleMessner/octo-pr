#!/usr/bin/ruby

def find_prs(github, config);
  pr_store = PRStore.new(config)
  
  # Go through all the repos and check for open prs
  count = 0
  config.repos.each do |repo|
    # Status printout. Useful for when you're checking a lot of repos.
    count += 1
    buffer "Getting PRs for '#{config.org}/#{repo}' (#{count}/#{config.repos.size})"

    json = github.repos(config.org, repo).pulls({:state => "open"}).all

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

          pr_store.add(author, repo, title, number, url)
        end
      end

    end
    
  end
  
  buffer ""
  
  pr_store
end