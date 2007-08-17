# Load the Module::Install bundled in ./inc/
use inc::Module::Install;

# Define metadata
name           'IO-Pty-Easy';
all_from       'lib/IO/Pty/Easy.pm';

requires       'IO::Pty';
requires       'Carp';

build_requires 'Test::More';

auto_install;
WriteAll;

