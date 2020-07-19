#!/usr/bin/env ruby

# Copyright 2020 by Tom Rathborne. Licensed under:
# GNU GENERAL PUBLIC LICENSE Version 3, 29 June 2007
# See COPYING for a copy of the license.

# guillot-draw takes the output of guillot-calc
# and outputs a list of command lines required to render the layout,
# suitable for input to e.g. GNU parallel

# XXX: It's probably easier to just hack at the code
#      than to add more command line arguments!

require 'yaml'
require 'optparse'

def parse_options
  options = {
    image: true,
    border: 0,
    filename: false,
    fontsize: 120
  }

  option_parser = OptionParser.new do |args|
    args.banner = "Usage: #{$PROGRAM_NAME} [options] | parallel -j <CORES>"

    args.on('-l', '--layout FILE',
            '[Mandatory] YAML layout filename') do |l|
      options[:layoutfile] = l
    end

    args.on('-t', '--template TEMPLATE',
            '[Mandatory] Page template image or gm expression') do |t|
      options[:template] = t
    end

    args.on('-i', '--[no-]image',
            "[default: #{options[:image]}] Draw image") do |i|
      options[:image] = i
    end

    args.on('-b', '--border PIXELS',
            OptionParser::Acceptables::DecimalInteger,
            "[default: #{options[:border]}] Width of black border around images") do |b|
      options[:border] = b.to_i
    end

    args.on('-n', '--[no-]filename',
            "[default: #{options[:filename]}] Draw filename over each image") do |n|
      options[:filename] = n
    end

    args.on('-f', '--fontsize PIXELS',
            OptionParser::Acceptables::DecimalInteger,
            "[default: #{options[:fontsize]}] Font size; implies -n") do |_f|
      options[:fontsize] = b.to_i
      options[:filename] = true
    end
  end

  option_parser.parse!

  options
end

def run
  options = parse_options

  if options[:layoutfile].nil? || options[:template].nil?
    puts 'ERROR: --layout and/or --template not specified'
    exit(1)
  end

  unless File.exist?(options[:layoutfile]) && (options[:template] =~ /xc:/ || File.exist?(options[:template]))
    puts "ERROR: At least one file does not exist: #{options[:layoutfile]} and #{options[:template]}"
    exit(2)
  end

  data = YAML.load_file(options[:layoutfile])
  pages = data['pages']

  pformat = format(" page_\%%02d.png", pages.length.to_s.length) # TODO: make this configurable

  pnum = 0

  pages.each do |page|
    # Generate temporary files for rotated images
    remove = []
    page.each do |rect|
      next unless rect['r']
      r_tmpfile = "r_#{rect['file']}" # TODO: make a tmpdir option?
      printf('gm convert %s -rotate 90 %s ; ', rect['file'], r_tmpfile)
      remove.append(r_tmpfile)
    end

    # Generate gm command to render page
    printf("gm convert %s -stroke black -linewidth #{options[:border]}", options[:template])

    # XXX: If we're drawing a rectangle, then make it translucent white
    printf(" -fill '#FFF3'") unless options[:border].zero?

    page.each do |rect|
      file = if rect['r']
               "r_#{rect['file']}"
             else
               rect['file']
             end

      if options[:image]
        printf(" -draw 'image over %d,%d 0,0 %s'",
               rect['x'], rect['y'], file)
      end

      # XXX: That translucent white rectangle is drawn over the image
      unless options[:border].zero?
        printf(" -draw 'rectangle %d,%d %d,%d'", rect['x'], rect['y'], rect['x'] + rect['w'], rect['y'] + rect['h'])
      end
    end

    if options[:filename]
      printf(' -fill black -linewidth 0')

      page.each do |rect|
        printf(" -draw \"font-size %d;text %d,%d '%s'\"",
               options[:fontsize], rect['x'] + 12, rect['y'] + options[:fontsize], rect['file'])
      end
    end

    printf(pformat, pnum)
    pnum += 1

    printf(' ; rm %s', remove.join(' ')) unless remove.empty?
    printf("\n")
  end
end

run

exit(0)
