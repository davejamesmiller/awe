# Awe

***Warning: This project is not yet released, and not ready to be used yet!***

Awe simplifies the building and maintenance of websites / web apps, by handling the compilation & minification of **assets**, and **deployment** to remote (live/staging) servers.

Awe is designed for web/software development agencies and freelancers managing many different websites, so:

- It relies on convention rather than configuration as much as possible, to ensure consistency
- It is installed system-wide, not per-project, to avoid the maintenance overhead of installing and upgrading it multiple times
- All features are optional, so it can be added to existing projects without major changes

**Note:** It is not a fully flexible build tool - unlike the popular tools [Grunt](http://gruntjs.com/) and [Gulp](http://gulpjs.com/) - so it won't suit everyone. However, it should be easier to set up in more complex use cases where assets must be compiled, combined and minified.

## Features

- Compiles [Sass](http://sass-lang.com/) (`.scss`) and [CoffeeScript](http://coffeescript.org/) (`.coffee`)
- Combines the files in any directory that ends with `.js` or `.css` into a single file
- Easily install external libraries with [Bower](http://bower.io/)
- Automatically rewrites relative URLs in CSS files
- Watch mode to automatically re-build assets during development
- Simple YAML configuration file
- Detailed online documentation
- Unit tests to ensure backwards-compatibility

### Coming soon

- [Autoprefixer](https://github.com/ai/autoprefixer) support
- More efficient Watch mode - only rebuild modified files
- Minify JS/CSS files
- Compress images
- [Source map](http://www.html5rocks.com/en/tutorials/developertools/sourcemaps/) support
- [LiveReload](http://livereload.com/) support
- Deploy to a live/staging server quickly and efficiently
- Growl notification of build errors
- Interactive menu for less technical frontend developers

## Documentation

### Getting started

- [Requirements](docs/start-requirements.md)
- [Installation](docs/start-installation.md)
- [Configuration - `awe.yaml`](docs/start-config.md)
- [Command-line interface - `awe`](docs/start-cli.md)
- [Cache files - `.awe/` directory](docs/start-cache.md)

### Assets

- [Introduction](docs/assets-introduction.md)
- [Tutorial](docs/assets-tutorial.md)
- [Quick reference](docs/assets-reference.md)

### Maintenance

- [Upgrading](docs/maintain-upgrade.md)
- [Uninstalling](docs/maintain-uninstall.md)

## Contributing to Awe

- [Installing Awe from Git](docs/contrib-installing-from-git.md)
- [Grunt tasks](docs/contrib-grunt.md)
- [Writing documentation](docs/contrib-writing-documentation.md)
- [Releasing new versions](docs/contrib-release.md)

## More information

- [Changelog](CHANGELOG.md)
- [MIT License](LICENSE.txt)
