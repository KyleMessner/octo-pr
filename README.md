OctoPR
======

Ruby script to get a list of open PRs against a list of repositories, filtered by author. Allows found PRs to be opened in the default browser.


Running the script
======

Run the script using;
> ruby prs.rb -c /path/to/config/file

See `sample-config.yml` for a sample config file.

All configurations set in the config file can be overridden on launch. More information can be gotten from the help;
> ruby prs.rb -?

Dependencies
======
This script has a dependency on `ghee` and `launchy`. It should work with the latest version of both.
If you don't have them, just run;
- `gem install ghee`
- `gem install launchy`

It also relies on 'io/console', 'readline' & 'yaml' all of which are included in Ruby 1.9.3.
