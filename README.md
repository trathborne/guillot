Guillot
=======

A naive and greedy but occasionally clever algorithm
for placing a collection of differently-sized images
on the smallest possible number of same-sized pages,
ensuring that the images can be separated
by making only guillotine cuts, that is, all the way across the paper.

I found a lot of academic papers on the topic, but not very much working code.
The closest I got was [opcut](https://github.com/bozokopic/opcut), but it
ran for over 400 hours and never terminated on my sample input.

So, I wrote my own, and it runs in much less time, giving great results. It
worked great for my use case (576 images with 430 distinct sizes) so I stopped,
but cleaned it up for you. If I do any more, it will be to resolve the TODO
items in the code, which are points of tuning and finessing. **Pull requests
welcome!**

License
-------

Copyright 2020 by Tom Rathborne <tom.rathborne@gmail.com>.
**Licensed under GNU GENERAL PUBLIC LICENSE Version 3, 29 June 2007.**
See file LICENSE for a copy of the license.

Requirements
------------

- Ruby ... not sure of the minimum version, since this is my first Ruby program!
  I used `ruby 2.7.0p0 (2019-12-25 revision 647ee6f091) [x86_64-linux-gnu]` as
  found in Ubuntu 20.04.
- Ruby's `yaml` and `optparse` modules which seem to be part of libruby.
- GraphicsMagick, in particular the `gm` program
  `GraphicsMagick 1.3.35 2020-02-23 Q16` as found in Ubuntu 20.04.
- (optional) GNU parallel, in case you want to parallelize the `gm` work.

Caveats
-------

- All dimensions are in pixels.
- If you use rotation, the image directory must be writable, and slashes in
  your filenames will break the temporary-rotated-image mechanism.
- It might break if you have spaces or quotes in your filenames. Don't do that.
- The drawing process might break if the command lines get too long, but the gm
  draw commands can be put into a text file, so it would be an easy fix.

Usage
-----

There are 3 basic steps:

1. Generate a YAML description of the dimensions of each input file. This is a
simple shell wrapper around `gm identify`. The input files are structured just
like input to `opcut`, but `guillot-calc` only pays attention to the `items`
section.

```
    $ guillot-prep.sh *.png > input.yaml
```

2. Fit these images into some fixed page size. Could take a very long time.
The verbose output is mostly useful for knowing that it is still working and
making a guess as to when it will finish.

```
    $ guillot-calc.rb --help
    Usage: guillot-calc.rb [options]
        -i, --input FILE                 [Mandatory] YAML input filename
        -g, --geometry WxH               [Mandatory] Page geometry in pixels
        -v, --[no-]verbose               [default: false] Verbose output
        -r, --[no-]rotate                [default: false] Also try rotating each image 90'
        -s, --spacing PIXELS             [default: 0] Space between images
        -m, --margin PIXELS              [default: 0] Page margin
        -e, --enough FRACTION            [default: 1.0] (0.5 to 1.0) Stop searching whenever this fraction of target area is covered

    $ guillot-calc.rb -i input.yaml -g 8000x6000 -v > layout.yaml
```

3. Render the images on top of a template page. `guillot-draw` outputs command
lines which you can run with e.g. GNU parallel.

```
    $ guillot-draw.rb --help
    Usage: guillot-draw.rb [options] | parallel -j <CORES>
        -l, --layout FILE                [Mandatory] YAML layout filename
        -t, --template TEMPLATE          [Mandatory] Page template image or gm expression
        -i, --[no-]image                 [default: true] Draw image
        -b, --border PIXELS              [default: 0] Width of black border around images
        -n, --[no-]filename              [default: false] Draw filename over each image
        -f, --fontsize PIXELS            [default: 120] Font size; implies -n

    $ guillot-draw.rb -l layout.yaml -t base_8000x6000.png | parallel -j 4
```

That's it! The output will be in `page_*.png`

Instead of a template filename, you could theoretically use a GraphicsMagick
xc: input, e.g. `-t '-size 8000x6000 -type Grayscale xc:white'`, but my
GraphicsMagick doesn't seem to support xc:.
