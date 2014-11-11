#!/usr/bin/ruby

class Interface
  
  def initialize(config);
    @config = config
  end
  
  def display(prs);
    if !@config.quiet_mode
      puts "No output to display."
    end
  end
  
end

class Terminal < Interface
  
  def initialize(config);
    @config = config
  end
  
  def display(pr_store);
    # Either automatically open all prs, or ask the user which prs they wish to open
    commands = if @config.auto_open
      puts "Automatically opening links for all found PRs."
      ['all']
    else
      authors = (@config.authors & pr_store.authors).sort
      numbers = pr_store.numbers
      commands = ['all', 'none']
      validCommands = (authors + numbers + commands).to_set

      if !@config.quiet_mode
        puts "You can specify PRs to open by;"
        puts "#{@config.indent}Author: #{authors.join(", ")}"
        puts "#{@config.indent}PR #: #{numbers.join(", ")}"
        puts "#{@config.indent}Misc: #{commands.join(", ")}"
      end
      
      get_user_input(validCommands)
    end

    open(pr_store, commands)
    
    if !@config.quiet_mode
      puts @config.seperator
      puts
    end
    
  end
  
  private
  
  def get_user_input(validCommands);

    Readline.completion_proc = proc { |s| validCommands.grep(/^#{Regexp.escape(s)}/) }

    begin
      commands = Readline.readline('> ', true).chomp.strip.split(" ").to_set
      if commands.size == 1 && !(commands < validCommands)
        puts "Unknown command #{commands.inspect} specified."
      elsif !(commands < validCommands)
        puts "Specified unknown commands: `#{commands.inspect}`."
      end
    end while !(commands < validCommands)
    
    commands
  end
  
  def open(pr_store, commands);
    # Open all requested PRs in the default browser
    browser = Browser.new()
    commands.each do |command|

      if command == 'all'
        pr_store.get_all_urls.each do |url|
          browser.open url
        end
      elsif command == 'none'
        # Nothing to do here.
      else
        pr_store.urls_for(command).each do |url|
          browser.open url
        end
      end

    end
  end
end

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
