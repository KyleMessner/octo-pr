#!/usr/bin/ruby

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