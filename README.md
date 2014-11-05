OctoPR
======

Ruby script to get a list of open PRs against a list of repositories, filtered by author. Allows found PRs to be opened in the default browser.


Configuration
======

This script assumes that there is a yaml file that lives at `~/prs.yml. See `sample-config.yml` for a sample config file.

All configurations can be overriden on launch, including the location of the config file. To see the options/help run;

> ruby prs.rb -?

Dependencies
======
This script has a dependency on `ghee` and `launchy`. It should work with the latest version of both.
If you don't have them, just run;
- `gem install ghee`
- `gem install launchy`

It also relies on 'io/console', 'readline' & 'yaml' all of which are included in Ruby 1.9.3.
