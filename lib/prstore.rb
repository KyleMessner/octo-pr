#!/usr/bin/ruby

# Tuple to help with validation of required values in the yaml config file.
# Takes the name of the value, and the expected type.
Validator = Struct.new(:name, :type)

# Holds found PRs and provides some handy accessors
class PRStore

  attr_accessor :author_map, :number_lookup

  def initialize(config);
    # A map of author name -> list of PRs (title, number, url)
    @author_map = Hash.new(Hash.new([]))
    # A map of number to -> url (for each lookup)
    @number_lookup = Hash.new([])
    
    @config = config
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
  def print_status;
    @author_map.each do |author, repo|
      puts "#{author}"
      repo.each do |repo, commits|
        puts "#{@config.indent}#{commits.size} PR#{(commits.size == 1) ? "" : "s" } against #{repo}"

        if !@config.quiet_mode
          # We're not in quiet mode, print out the title
          commits.each do |commit|
            puts "#{@config.indent * 2}#{commit['number']}: #{commit['title']}"

            # And if they want the link printed out, do that on the next line
            if @config.show_link
              puts "#{@config.indent * 3}#{commit['url']}"
            end
          end

        elsif @config.show_link
          # We're in quiet mode, but they've said they want to see the links
          commits.each do |commit|
            puts "#{@config.indent * 2}#{commit['url']}"
          end
        end
      end
    end

    if !@config.quiet_mode
      noPrs = (@config.authors - authors)
      puts "NOTE: #{noPrs.join(", ")} #{(noPrs.size == 1) ? "has" : "have"} no open prs"
    end
  end

end