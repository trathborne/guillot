#!/usr/bin/env ruby

# Copyright 2020 by Tom Rathborne. Licensed under:
# GNU GENERAL PUBLIC LICENSE Version 3, 29 June 2007
# See COPYING for a copy of the license.

# TODO: - also mentioned below where changes are required.
# - generate list of cuts: lines at the ends of each guillotine cut
# - user-specified candidate-count-by-depth
# - user-specified candidate sorting

require 'yaml'
require 'optparse'

# --- Utility functions

# Command line argument parser, including mandatory argument enforcement

def parse_options
  # default options
  options = {
    verbose: false,
    rotate: false,
    spacing: 0,
    margin: 0,
    enough: 1.0
  }

  option_parser = OptionParser.new do |args|
    args.banner = "Usage: #{$PROGRAM_NAME} [options]"

    args.on('-i', '--input FILE',
            '[Mandatory] YAML input filename') do |i|
      options[:inputfile] = i
    end

    args.on('-g', '--geometry WxH',
            /^[0-9]+x[0-9]+$/,
            '[Mandatory] Page geometry in pixels') do |g|
      width, height = g.split('x')
      options[:width] = width.to_i
      options[:height] = height.to_i
    end

    args.on('-v', '--[no-]verbose',
            "[default: #{options[:verbose]}] Verbose output") do |v|
      options[:verbose] = v
    end

    args.on('-r', '--[no-]rotate',
            "[default: #{options[:rotate]}] Also try rotating each image 90'") do |r|
      options[:rotate] = r
    end

    args.on('-s', '--spacing PIXELS',
            OptionParser::Acceptables::DecimalInteger,
            "[default: #{options[:spacing]}] Space between images") do |s|
      options[:spacing] = s.to_i
    end

    args.on('-m', '--margin PIXELS',
            OptionParser::Acceptables::DecimalInteger,
            "[default: #{options[:margin]}] Page margin") do |m|
      options[:margin] = m.to_i
    end

    args.on('-e', '--enough FRACTION',
            OptionParser::Acceptables::DecimalNumeric,
            "[default: #{options[:enough]}] (0.5 to 1.0) Stop searching whenever this fraction of target area is covered") do |e|
      options[:enough] = e.to_f
    end
  end

  option_parser.parse!

  # Enforce mandatory arguments
  errors = []

  if options[:inputfile].nil?
    errors.append('Mandatory YAML input filename missing')
  end

  errors.append('Mandatory page geometry missing') if options[:width].nil?
  errors.append('Enough is not in (0.5 to 1.0)') unless options[:enough] >= 0.5 && options[:enough] <= 1.0

  unless errors.empty?
    STDERR.puts(option_parser.help)
    raise ArgumentError, errors.join("\n")
  end

  options
end

# Expensive but reliable

def deep_dup(it)
  Marshal.load(Marshal.dump(it))
end

# --- The algorithm

# filter_candidates takes a list of rectangles as interpreted from the input
# YAML and returns the first max_candidates that fit in the WxH rectangle.
# Optionally, it can also check the 90' rotated version of the image.

def filter_candidates(rects, max_candidates, width, height, rotate)
  candidates = []
  cdims = {} # Ensures that candidates have distinct geometry

  consider_candidate = lambda { |fn, dims|
    unless cdims.key?("#{dims[:w]}x#{dims[:h]}") ||
           (dims[:w] > width) ||
           (dims[:h] > height)

      candidates.push([fn, dims])
      cdims["#{dims[:w]}x#{dims[:h]}"] = true
    end
  }

  while (candidates.length < max_candidates) && !rects.empty?
    nrect = rects.shift

    fn = nrect[0]
    dims = nrect[1]

    rotate_this = dims[:r] # collect flag
    dims[:r] = false # for the non-rotated version

    consider_candidate.call(fn, dims)

    next unless rotate || rotate_this # (C)

    rotated_dims = {
      w: dims[:h],
      h: dims[:w],
      a: dims[:a],
      r: true
    }

    consider_candidate.call(fn, rotated_dims)
  end

  candidates
end

# fit_into gets a list of candidates via filter_candidates
# and for each candidate, recurses on fitting the remaining images into:
#     (A) the two possible guillotine cuts
#   X (B) the two orders in which those choices could be explored
# with the additional dimension of
#   X (C) (in filter_candidates) rotated versions, when requested
# The --rotate argument considers all rotated images, and thus doubles the
# normal maximum number of candidates. If images are individually approved for
# rotation via can_rotate in the input file, maximum candidate count is not
# increased.

def fit_into(options, depth, width, height, rectangles)
  if options[:verbose]
    # print something once per second
    @last ||= 0
    now = Time.now.to_i
    if @last < now
      @last = now
      STDERR.printf("\rDepth: %2d", depth) # at least you know it's running
    end
  end

  # TODO: make maxc_by_depth configurable
  maxc_by_depth = [1, 3, 2, 1] # XXX Makes everything expensive
  max_candidates = maxc_by_depth[[depth, maxc_by_depth.length - 1].min]
  max_candidates *= 2 if options[:rotate] # XXX Makes --rotate expensive

  # TODO: make sorting configurable
  # This is Area at depth 0, then Height and Width alternating
  sorting = depth.zero? ? :a : %i[w h][depth % 2]
  s_rects = rectangles.sort_by { |_fn, dims| dims[sorting] } .reverse

  # XXX: It would be more efficient to filter first, then sort.

  # Filter s_rects for sub-candidates: [ filename, { Width, Height, Area, Rotate } ]
  candidates = filter_candidates(s_rects, max_candidates, width, height, options[:rotate])

  # The default result is only returned if candidates is empty.
  # Proof of this is an exercise left to the reader.
  result = {
    page: [],
    remaining: rectangles,
    covered: 0
  }

  spacing = options[:spacing]
  target = options[:enough] < 1.0 ? (options[:enough] * width.to_f * height.to_f).to_i : nil

  candidates.each do |candidate|
    fn = candidate[0]
    dims = candidate[1]

    # TODO: add cuts for each dimset (?)
    # (A) subdimsets are pairs of [width, height, x-offset, y-offset] sub-searches
    subdimsets = [
      [
        [
          width - dims[:w] - spacing,
          height - spacing,
          dims[:w] + spacing,
          0
        ],
        [
          dims[:w] - spacing,
          height - dims[:h] - spacing,
          0,
          dims[:h] + spacing
        ]
      ],
      [
        [
          width - spacing,
          height - dims[:h] - spacing,
          0,
          dims[:h] + spacing
        ],
        [
          width - dims[:w] - spacing,
          dims[:h] - spacing,
          dims[:w] + spacing,
          0
        ]
      ]
    ]

    # (B) Clone both subdimsets in opposite order, so we search 4 sub-options
    [subdimsets[0], subdimsets[1]].each do |dimset|
      # Don't need deep_dup because the dimsets are never changes
      subdimsets.push([dimset[1], dimset[0]])
    end

    rects = deep_dup(rectangles)
    rects.delete(fn)

    candidate_result = {
      page: [{
        'file'  => fn,
        'x'     => 0,
        'y'     => 0,
        'w'     => dims[:w],
        'h'     => dims[:h],
        'r'     => dims[:r]
      }],
      # cuts: [[x1,y1,x2,y2],[x3,y3,x4,y4]], # TODO
      remaining: rects,
      covered: dims[:a]
    }

    subdimsets.each do |dimset|
      remaining = deep_dup(rects)

      this_result = deep_dup(candidate_result)
      dimset.each do |ds|
        inner = fit_into(options, depth + 1, ds[0], ds[1], remaining)
        next unless inner[:covered] > 0
        this_result[:covered] += inner[:covered]

        # Transform inner[:page] coordinates
        inner[:page].each do |rect|
          rect['x'] += ds[2]
          rect['y'] += ds[3]
        end

        this_result[:page] += inner[:page]

        # TODO: transform inner[:cuts] coordinates
        # TODO: this_result[:cuts] += inner[:cuts]

        remaining = inner[:remaining]
        break if remaining.empty?
      end

      # Keep only the best result
      if this_result[:covered] > result[:covered]
        this_result[:remaining] = remaining
        result = this_result
      end
    end

    # If we have placed all the images, we're done!
    break if result[:remaining].empty?
    break if !target.nil? && result[:covered] > target
  end

  result
end

# multi_fit accumulates the best fit_into until we run out of rectangles

def multi_fit(options, rectangles)
  pages = []
  remaining = rectangles

  until remaining.keys.empty?
    if options[:verbose]
      before = Time.now.to_i
      STDERR.printf("Packing page %<page>d, %<images>d images remaining\n",
                    page: pages.length + 1,
                    images: remaining.keys.length)
    end

    result = fit_into(options, 0, options[:width], options[:height], remaining)

    unless options[:margin].zero?
      result[:page].each do |rect|
        rect['x'] += options[:margin]
        rect['y'] += options[:margin]
      end
    end
    pages.push(result[:page])

    remaining = result[:remaining]

    next unless options[:verbose]
    STDERR.printf("\nPage %<page>d contains %<images>d images, took %<time>ds\n",
                  page: pages.length,
                  images: result[:page].length,
                  time: Time.now.to_i - before)
  end

  pages
end

# --- Parse options and input file and feed it all to the algorithm

def run
  options = parse_options

  # The input format is like this because I swas trying to make
  # https://github.com/bozokopic/opcut work. It never terminated.
  params = YAML.load_file(options[:inputfile])
  items = params['items']

  default_rotate = options[:rotate]

  # Subtract twice the margin from the page size.
  # (In multi_fit we add it once to each image.)
  unless options[:margin].zero?
    options[:width] -= 2 * options[:margin]
    options[:height] -= 2 * options[:margin]
  end

  rects = {} # filename => { Width, Height, Area, Rotate? }

  items.each do |fn, details|
    w = details['width'].to_i
    h = details['height'].to_i
    a = w * h
    r = details['can_rotate'].nil? ? default_rotate : !!details['can_rotate']

    if (w > options[:width] || h > options[:height]) && (!r || w > options[:height] || h > options[:width])
      STDERR.printf("File %s (%dx%d) will not fit in (%dx%d)\n", fn, w, h, options[:width], options[:height])
      exit(1)
    end

    rects[fn] = {
      w: w,
      h: h,
      a: a,
      r: r
    }
  end

  pages = multi_fit(options, rects)
  print({ 'pages' => pages }.to_yaml)
end

run

exit(0)
