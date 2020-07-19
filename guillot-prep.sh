#!/bin/bash

# Copyright 2020 by Tom Rathborne. Licensed under:
# GNU GENERAL PUBLIC LICENSE Version 3, 29 June 2007
# See COPYING for a copy of the license.

# This generates a YAML file with the dimensions of your input files
# Usage: guillot-prep.sh *.png

echo -e '---\nitems:'
gm identify -format '    "%f":\n        width: %w\n        height: %h\n' $@

