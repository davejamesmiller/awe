_          = require('lodash')
AssetGroup = require('../lib-build/AssetGroup')
expect     = require('chai').use(require('chai-fs')).expect
fs         = require('fs')
output     = require('../lib-build/output')
path       = require('path')
rmdir      = require('rimraf').sync

fixtures = path.resolve(__dirname, '../fixtures')

#================================================================================
# Settings
#================================================================================

# Set this to true to display only the results (this should be the default)
# Set it to false if you want to see the full build output
quiet = true


#================================================================================
# Helper
#================================================================================

build = ({root, files, config, warnings, errors, tests}) ->
  # Return a function for Mocha to run asynchronously
  (done) ->
    # Default config settings
    config = _.defaults {}, config,
      src:          'src/'
      dest:         'build/'
      bower:        false
      autoprefixer: false
      sourcemaps:   false
      warningfile:  false

    # Check all the listed files exist - this is partly to double-check the
    # directory structure, and partly a way to document it
    if files
      for file in files
        expect("#{root}/#{file}").to.be.a.path('TEST SETUP ERROR')

    # Clear the cache and build directories
    rmdir("#{root}/.awe")
    rmdir("#{root}/#{config.dest}")

    # Disable output?
    output.disable() if quiet

    # Insert a blank line to separate build output from the previous test
    output.line()
    output.building()

    # Start counting warnings & errors
    output.resetCounters()

    # Build it
    (new AssetGroup(root, config)).build (err, result) ->
      # Insert another blank line to separate build output from the test results
      output.finished()
      output.line()

      # Re-enable output
      output.enable() if quiet

      # Get us outside any try..catch blocks that interfere with assertions
      process.nextTick ->
        # Check for unhandled errors
        throw new Error(err) if err

        # Check for error/warning messages
        expect(output.counters.error || 0).to.equal(errors || 0, "Expected #{errors || 0} error(s)")
        expect(output.counters.warning || 0).to.equal(warnings || 0, "Expected #{warnings || 0} warning(s)")

        # Run tests (synchronously)
        tests() if tests

        # Tell Mocha we're done
        done()


#================================================================================
# Tests
#================================================================================

describe 'AssetGroup.build()', ->
  @timeout 5000

  #----------------------------------------
  # Basic copy/compile functionality
  #----------------------------------------

  it 'should copy JavaScript, CSS and unknown files', build
    root: "#{fixtures}/build-copy"
    files: [
      'src/javascript.js'
      'src/stylesheet.css'
      'src/unknown.file'
    ]
    tests: ->
      expect("#{fixtures}/build-copy/build/javascript.js").to.have.content """
        console.log('JavaScript');\n
      """

      expect("#{fixtures}/build-copy/build/stylesheet.css").to.have.content """
        .red {
          color: red;
        }\n
      """

      expect("#{fixtures}/build-copy/build/unknown.file").to.have.content """
        Unknown\n
      """


  it 'should copy images', build
    root: "#{fixtures}/build-copy-images"
    files: [
      'src/sample.gif'
    ]
    tests: ->
      # Using hex encoding because it's the easiest way to compare two files
      # This test is necessary because the file must be copied in binary mode not UTF-8 else it is corrupted
      data1 = 'Hex encoding: ' + fs.readFileSync("#{fixtures}/build-copy-images/build/sample.gif", encoding: 'hex')
      data2 = 'Hex encoding: ' + fs.readFileSync("#{fixtures}/build-copy-images/src/sample.gif", encoding: 'hex')
      expect(data1).to.equal(data2)


  it 'should compile CoffeeScript files', build
    root: "#{fixtures}/build-coffeescript"
    files: [
      'src/coffeescript.coffee'
    ]
    tests: ->
      expect("#{fixtures}/build-coffeescript/build/coffeescript.js").to.have.content """
        (function() {
          console.log('CoffeeScript');

        }).call(this);\n
      """


  it 'should compile Sass files', build
    root: "#{fixtures}/build-sass"
    files: [
      'src/sass.scss'
    ]
    tests: ->
      expect("#{fixtures}/build-sass/build/sass.css").to.have.content """
        .main-red, .also-red {
          color: red;
        }\n
      """


  it 'should skip files starting with an underscore', build
    root: "#{fixtures}/build-underscores"
    files: [
      'src/_ignored.coffee'
      'src/_vars.scss'
    ]
    tests: ->
      expect("#{fixtures}/build-underscores/_ignored.coffee").not.to.be.a.path()
      expect("#{fixtures}/build-underscores/_ignored.js").not.to.be.a.path()
      expect("#{fixtures}/build-underscores/_vars.scss").not.to.be.a.path()
      expect("#{fixtures}/build-underscores/_vars.css").not.to.be.a.path()


  it 'should display a warning when CSS is invalid', build
    root: "#{fixtures}/build-css-invalid"
    files: [
      'src/invalid.css'
    ]
    warnings: 1


  #----------------------------------------
  # Error handling
  #----------------------------------------

  it 'should show an error if src/ does not exist', build
    root: "#{fixtures}/build-error-src"
    errors: 1


  it 'should handle errors in Sass files', build
    root: "#{fixtures}/build-error-sass"
    files: [
      'src/invalid.scss'
      'src/combined.css/invalid.scss'
    ]
    errors: 2


  it 'should handle errors in CoffeeScript files', build
    root: "#{fixtures}/build-error-coffeescript"
    files: [
      'src/invalid.coffee'
      'src/combined.js/invalid.coffee'
    ]
    errors: 2


  #----------------------------------------
  # Compass
  #----------------------------------------

  it 'should use relative paths for Compass URL helpers', build
    root: "#{fixtures}/build-compass-urls"
    files: [
      'src/subdir/urls.scss'
    ]
    tests: ->
      expect("#{fixtures}/build-compass-urls/build/subdir/urls.css").to.have.content """
        .imageUrl {
          background: url('../img/sample.gif');
        }

        @font-face {
          font-family: myfont;
          src: url('../fonts/myfont.woff');
        }\n
      """


  it 'should support the Compass inline-image() helper', build
    root: "#{fixtures}/build-compass-inline"
    files: [
      'src/img/_blank.gif'
      'src/inline.scss'
    ]
    tests: ->
      expect("#{fixtures}/build-compass-inline/build/inline.css").to.have.content """
        .inlineImage {
          background: url('data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAQAIBRAA7');
        }\n
      """


  it 'should support Compass sprites', build
    root: "#{fixtures}/build-compass-sprites"
    files: [
      'src/_sprites/icons/icon1.png'
      'src/_sprites/icons/icon2.png'
      'src/sprite.scss'
    ]
    tests: ->
      # CSS file content must match
      content = fs.readFileSync("#{fixtures}/build-compass-sprites/build/sprite.css", 'utf8')
      expect(content).to.match /\.icons-sprite, \.icons-icon1, \.icons-icon2 {/
      expect(content).to.match /background-image: url\('_generated\/icons-[^']+\.png'\);/

      # Generated sprite must exist
      sprite = content.match(/background-image: url\('_generated\/(icons-[^']+\.png)'\);/)[1]
      expect("#{fixtures}/build-compass-sprites/build/_generated/#{sprite}").to.be.a.file()


  #----------------------------------------
  # Combine directories
  #----------------------------------------

  it 'should combine the content of *.js/ directories', build
    root: "#{fixtures}/build-combine-js"
    files: [
      'src/combine.js/_ignored.coffee'
      'src/combine.js/1.js'
      'src/combine.js/2-subdir/2.coffee'
    ]
    tests: ->
      expect("#{fixtures}/build-combine-js/build/combine.js").to.have.content """
        f1();

        (function() {
          f2();

        }).call(this);\n
      """


  it 'should combine the content of *.css/ directories', build
    root: "#{fixtures}/build-combine-css"
    files: [
      'src/combine.css/_vars.scss'
      'src/combine.css/1.css'
      'src/combine.css/2-subdir/2.scss'
    ]
    tests: ->
      expect("#{fixtures}/build-combine-css/build/combine.css").to.have.content """
        .css {
          color: red;
        }

        .scss, .also-scss {
          color: green;
        }\n
      """


  it 'should not combine the content of *.other/ directories', build
    root: "#{fixtures}/build-combine-other"
    files: [
      'src/combine.other/sample.txt'
    ]
    tests: ->
      expect("#{fixtures}/build-combine-other/build/combine.other").to.be.a.directory()
      expect("#{fixtures}/build-combine-other/build/combine.other/sample.txt").to.be.a.file()


  it 'should not combine the content non-CSS files in a CSS directory', build
    root: "#{fixtures}/build-combine-invalid"
    files: [
      'src/combine.css/styles.css'
      'src/combine.css/ignore.txt'
    ]
    tests: ->
      expect("#{fixtures}/build-combine-invalid/build/combine.css").to.have.content """
        body {
          color: red;
        }\n
      """


  #----------------------------------------
  # YAML imports
  #----------------------------------------

  it 'should import JavaScript/CoffeeScript files listed in a .js.yaml file', build
    root: "#{fixtures}/build-yaml-js"
    files: [
      'src/_1.js'
      'src/_2.coffee'
      'src/import.js.yaml'
    ]
    tests: ->
      expect("#{fixtures}/build-yaml-js/build/import.js").to.have.content """
        f1();

        (function() {
          f2();

        }).call(this);\n
      """


  it 'should import CSS/Sass files listed in a .css.yaml file', build
    root: "#{fixtures}/build-yaml-css"
    files: [
      'src/_1.css'
      'src/_2.scss'
      'src/import.css.yaml'
    ]
    tests: ->
      expect("#{fixtures}/build-yaml-css/build/import.css").to.have.content """
        .css {
          color: red;
        }

        .scss, .also-scss {
          color: green;
        }\n
      """


  it 'should not attempt to import files from other .yaml files', build
    root: "#{fixtures}/build-yaml-other"
    files: [
      'src/import.txt.yaml'
    ]
    tests: ->
      expect("#{fixtures}/build-yaml-other/build/import.txt").not.to.be.a.path()
      expect("#{fixtures}/build-yaml-other/build/import.txt.yaml").to.be.have.content """
        - SHOULD NOT BE IMPORTED\n
      """


  it 'should allow imports outside the source directory in YAML files', build
    root: "#{fixtures}/build-yaml-error"
    files: [
      'outside.js'
      'src/_1.js'
      'src/_2.js'
      'src/import.js.yaml'
    ]
    tests: ->
      expect("#{fixtures}/build-yaml-error/build/import.js").to.have.content """
        f1();\n
        f2();\n
        f3();\n
      """


  it 'should import YAML files nested inside other YAML files', build
    root: "#{fixtures}/build-yaml-nested"
    files: [
      'src/_script.js'
      'src/_nested.js.yaml'
      'src/import.js.yaml'
    ]
    tests: ->
      expect("#{fixtures}/build-yaml-nested/build/import.js").to.have.content """
        console.log('JavaScript');\n
      """


  it 'should import files listed in a YAML file inside a combined directory', build
    root: "#{fixtures}/build-combine-yaml"
    files: [
      'src/combine.js/1.js'
      'src/combine.js/2-3.js.yaml'
      'src/combine.js/4.js'
      'src/_2.js'
      'src/_3.js'
    ]
    tests: ->
      expect("#{fixtures}/build-combine-yaml/build/combine.js").to.have.content """
        f1();\n
        f2();\n
        f3();\n
        f4();\n
      """


  it 'should combine files in a directory listed in a YAML file', build
    root: "#{fixtures}/build-yaml-combine"
    files: [
      'src/_1.js'
      'src/_23.js/2.js'
      'src/_23.js/3.js'
      'src/_4.js'
      'src/import.js.yaml'
    ]
    tests: ->
      expect("#{fixtures}/build-yaml-combine/build/import.js").to.have.content """
        f1();\n
        f2();\n
        f3();\n
        f4();\n
      """


  it 'should show an error if a file cannot be found', build
    root: "#{fixtures}/build-yaml-missing"
    files: [
      'src/import-error.js.yaml'
    ]
    errors: 1


  #----------------------------------------
  # Autoprefixer
  #----------------------------------------

  it 'should add cross-browser prefixes to .css files when Autoprefixer is enabled', build
    root: "#{fixtures}/build-autoprefixer-css"
    config:
      autoprefixer: true
    files: [
      'src/autoprefixer.css'
    ]
    tests: ->
      expect("#{fixtures}/build-autoprefixer-css/build/autoprefixer.css").to.have.content """
        .css {
          transition: -webkit-transform 1s;
          transition: transform 1s;
        }\n\n
      """


  it 'should add cross-browser prefixes to .scss files when Autoprefixer is enabled', build
    root: "#{fixtures}/build-autoprefixer-scss"
    config:
      autoprefixer: true
    files: [
      'src/autoprefixer.scss'
    ]
    tests: ->
      expect("#{fixtures}/build-autoprefixer-scss/build/autoprefixer.css").to.have.content """
        .scss, .also-scss {
          transition: -webkit-transform 1s;
          transition: transform 1s;
        }\n
      """


  it 'should NOT add cross-browser prefixes to non-CSS files', build
    root: "#{fixtures}/build-autoprefixer-other"
    config:
      autoprefixer: true
    files: [
      'src/autoprefixer.txt'
    ]
    tests: ->
      expect("#{fixtures}/build-autoprefixer-other/build/autoprefixer.txt").to.have.content """
        .not-css {
          transition: transform 1s;
        }\n
      """


  #----------------------------------------
  # Bower
  #----------------------------------------

  it 'should create a symlink to bower_components/', build
    root: "#{fixtures}/build-bower-symlink"
    config:
      bower: 'bower_components/'
    files: [
      'bower_components/bower.txt'
      'src/_source'
    ]
    tests: ->
      expect("#{fixtures}/build-bower-symlink/build/_bower").to.be.a.symlink()
      expect("#{fixtures}/build-bower-symlink/build/_bower").to.be.a.directory()
      expect("#{fixtures}/build-bower-symlink/build/_bower/bower.txt").to.be.a.file()


  it 'should show a warning and not create a symlink if the bower target directory does not exist', build
    root: "#{fixtures}/build-bower-missing"
    config:
      bower: 'bower_components/'
    files: [
      'src/_source'
    ]
    warnings: 1
    tests: ->
      expect("#{fixtures}/build-bower-missing/build/_bower").not.to.be.a.path()


  it 'should not create a symlink to bower_components/ if set to false', build
    root: "#{fixtures}/build-bower-disabled"
    config:
      bower: false
    files: [
      'src/_source'
    ]
    tests: ->
      expect("#{fixtures}/build-bower-disabled/build/_bower").not.to.be.a.path()


  #----------------------------------------
  # URL rewriting
  #----------------------------------------
  # For full tests see UrlRewriter.coffee - this just checks they are applied correctly

  it 'should rewrite relative URLs in directory-combined CSS files', build
    root: "#{fixtures}/build-rewrite-combined"
    config:
      bower: 'bower_components/'
    files: [
      'bower_components/sample.gif'
      'src/combine.css/styles.css'
      'src/sample.gif'
    ]
    tests: ->
      expect("#{fixtures}/build-rewrite-combined/build/combine.css").to.have.content """
        .relative {
          background: url(sample.gif);
        }
        .bower {
          background: url(_bower/sample.gif);
        }\n
      """


  it 'should rewrite relative URLs to Bower files', build
    root: "#{fixtures}/build-rewrite-bower"
    config:
      bower: 'bower_components/'
    files: [
      'bower_components/sample.gif'
      'bower_components/target.css'
      'src/subdir/bower.css.yaml'
    ]
    tests: ->
      expect("#{fixtures}/build-rewrite-bower/build/subdir/bower.css").to.have.content """
        body {
          background: url(../_bower/sample.gif);
        }\n
      """


  it 'should rewrite relative URLs to outside files', build
    root: "#{fixtures}/build-rewrite-outside"
    files: [
      'sample.gif'
      'target.css'
      'src/outside.css.yaml'
    ]
    tests: ->
      expect("#{fixtures}/build-rewrite-outside/build/outside.css").to.have.content """
        body {
          background: url(../sample.gif);
        }\n
      """


  it 'should rewrite relative URLs in YAML-imported CSS files', build
    root: "#{fixtures}/build-rewrite-yaml"
    config:
      bower: 'bower_components/'
    files: [
      'bower_components/sample.gif'
      'src/_import/styles.css'
      'src/import.css.yaml'
      'src/sample.gif'
    ]
    tests: ->
      expect("#{fixtures}/build-rewrite-yaml/build/import.css").to.have.content """
        .relative {
          background: url(sample.gif);
        }
        .bower {
          background: url(_bower/sample.gif);
        }\n
      """


  it 'should warn about invalid relative URLs in CSS, but leave them unchanged', build
    root: "#{fixtures}/build-rewrite-invalid"
    files: [
      'src/invalid-url.css'
    ]
    warnings: 1
    tests: ->
      expect("#{fixtures}/build-rewrite-invalid/build/invalid-url.css").to.have.content """
        body {
          background: url(invalid.gif);
        }\n
      """


  #----------------------------------------
  # Source maps
  #----------------------------------------

  it 'should not create a .map file if sourcemaps are disabled', build
    root: "#{fixtures}/build-sourcemap-disabled"
    files: [
      'src/coffeescript.coffee'
    ]
    tests: ->
      expect("#{fixtures}/build-sourcemap-disabled/build/coffeescript.js").to.be.a.path()
      expect("#{fixtures}/build-sourcemap-disabled/build/coffeescript.js.map").not.to.be.a.path()


  it 'should create sourcemaps for CoffeeScript', build
    root: "#{fixtures}/build-sourcemap-coffeescript"
    config:
      sourcemaps: true
    files: [
      'src/coffeescript.coffee'
    ]
    tests: ->
      expect("#{fixtures}/build-sourcemap-coffeescript/build/coffeescript.js").to.have.content """
        (function() {
          console.log('CoffeeScript 1');

          console.log('CoffeeScript 2');

          console.log('CoffeeScript 3');

        }).call(this);

        //# sourceMappingURL=coffeescript.js.map\n
      """
      expect("#{fixtures}/build-sourcemap-coffeescript/build/coffeescript.js.map").to.have.content """
        {
          "version": 3,
          "file": "coffeescript.js",
          "sourceRoot": "../src",
          "sources": [
            "coffeescript.coffee"
          ],
          "names": [],
          "mappings": "AAAA;EAAA,OAAO,CAAC,GAAR,CAAY,gBAAZ;;EACA,OAAO,CAAC,GAAR,CAAY,gBAAZ;;EACA,OAAO,CAAC,GAAR,CAAY,gBAAZ;AAFA",
          "sourcesContent": [
            "console.log 'CoffeeScript 1'\\nconsole.log 'CoffeeScript 2'\\nconsole.log 'CoffeeScript 3'\\n"
          ]
        }
      """


  it 'should create sourcemaps for CSS with Autoprefixer', build
    root: "#{fixtures}/build-sourcemap-css-autoprefixer"
    config:
      sourcemaps: true
      autoprefixer: true
    files: [
      'src/styles.css'
    ]
    tests: ->
      expect("#{fixtures}/build-sourcemap-css-autoprefixer/build/styles.css").to.have.content """
        /* This is just to make the line numbers change a bit */
        .another {
          transition: -webkit-transform 1s;
          transition: transform 1s;
        }

        .css {
          transition: -webkit-transform 1s;
          transition: transform 1s;
        }

        /*# sourceMappingURL=styles.css.map */\n
      """
      expect("#{fixtures}/build-sourcemap-css-autoprefixer/build/styles.css.map").to.have.content """
        {
          "version": 3,
          "sources": [
            "styles.css"
          ],
          "names": [],
          "mappings": "AAAA,yDAAwD;AACxD;EACE,kCAAyB;EAAzB,0BAAyB;EAC1B;;AAED;EACE,kCAAyB;EAAzB,0BAAyB;EAC1B",
          "file": "styles.css",
          "sourceRoot": "../src",
          "sourcesContent": [
            "/* This is just to make the line numbers change a bit */\\n.another {\\n  transition: transform 1s;\\n}\\n\\n.css {\\n  transition: transform 1s;\\n}\\n"
          ]
        }
      """


  it 'should create sourcemaps for Sass files', build
    root: "#{fixtures}/build-sourcemap-sass"
    config:
      sourcemaps: true
    files: [
      'src/sass.scss'
    ]
    tests: ->
      expect("#{fixtures}/build-sourcemap-sass/build/sass.css").to.have.content """
        .main-red, .also-red {
          color: red;
        }

        /*# sourceMappingURL=sass.css.map */\n
      """
      expect("#{fixtures}/build-sourcemap-sass/build/sass.css.map").to.have.content """
        {
          "version": 3,
          "sources": [
            "sass.scss"
          ],
          "names": [],
          "mappings": "AAGA;EACE,YAHO;EACR",
          "file": "sass.css",
          "sourceRoot": "../src",
          "sourcesContent": [
            "// This is just to make the line numbers change a bit\\n$red: red;\\n\\n.main-red {\\n  color: $red;\\n}\\n\\n.also-red {\\n  @extend .main-red;\\n}\\n"
          ]
        }
      """


  it 'should create sourcemaps for Sass files with sprites', build
    root: "#{fixtures}/build-sourcemap-compass-sprites"
    config:
      sourcemaps: true
    files: [
      'src/sprite.scss'
    ]
    tests: ->
      # XXX Brittle test - The Ruby version may change
      source = path.join(__dirname, '../ruby_bundle/ruby/2.5.0/gems/compass-core-1.0.1/stylesheets/compass/utilities/sprites/_base.scss')
      expect("#{fixtures}/build-sourcemap-compass-sprites/build/sprite.css.map").to.have.content """
        {
          "version": 3,
          "sources": [
            "sprite.scss",
            "_awe/ruby_bundle/ruby/2.5.0/gems/compass-core-1.0.1/stylesheets/compass/utilities/sprites/_base.scss"
          ],
          "names": [],
          "mappings": "AAAA;EACE,2DAA2E;EAC3E,8BAA6B;EAC9B;;ACgFO;EAlEN,0BACiB;EDXlB",
          "file": "sprite.css",
          "sourceRoot": "../src",
          "sourcesContent": [
            "@import 'compass/utilities/sprites';\\n@import 'icons/*.png';\\n@include all-icons-sprites;\\n",
            #{JSON.stringify(fs.readFileSync(source, 'utf8'))}
          ]
        }
      """


  it 'should create sourcemaps for combined JavaScript directories', build
    root: "#{fixtures}/build-sourcemap-combine-js"
    config:
      sourcemaps: true
    files: [
      'src/combine.js/1.js'
      'src/combine.js/2-subdir/2.coffee'
      'src/combine.js/_ignored.coffee'
    ]
    tests: ->
      expect("#{fixtures}/build-sourcemap-combine-js/build/combine.js").to.have.content """
        // This is just to move it down a line
        console.log('JavaScript');

        (function() {
          console.log('CoffeeScript');

        }).call(this);

        //# sourceMappingURL=combine.js.map\n
      """
      expect("#{fixtures}/build-sourcemap-combine-js/build/combine.js.map").to.have.content """
        {
          "version": 3,
          "sources": [
            "combine.js/1.js",
            "combine.js/2-subdir/2.coffee"
          ],
          "names": [],
          "mappings": "AAAA;AACA;AACA;ACAA;EAAA,OAAO,CAAC,GAAR,CAAY,cAAZ;AAAA",
          "file": "combine.js",
          "sourceRoot": "../src",
          "sourcesContent": [
            "// This is just to move it down a line\\nconsole.log('JavaScript');\\n",
            "# This is just to move it down a couple\\n# of lines\\nconsole.log 'CoffeeScript'\\n"
          ]
        }
      """


  it 'should create sourcemaps for combined CSS directories', build
    root: "#{fixtures}/build-sourcemap-combine-css"
    config:
      sourcemaps: true
    files: [
      'src/combine.css/_vars.scss'
      'src/combine.css/1.css'
      'src/combine.css/2-subdir/2.scss'
    ]
    tests: ->
      expect("#{fixtures}/build-sourcemap-combine-css/build/combine.css").to.have.content """
        .css {
          color: red;
        }

        .scss, .also-scss {
          font-weight: bold;
        }

        /*# sourceMappingURL=combine.css.map */\n
      """
      expect("#{fixtures}/build-sourcemap-combine-css/build/combine.css.map").to.have.content """
        {
          "version": 3,
          "sources": [
            "combine.css/1.css",
            "combine.css/2-subdir/2.scss"
          ],
          "names": [],
          "mappings": "AAAA;EACE,YAAW;EACZ;;ACDD;EACE,mBAAiB;EAAlB",
          "file": "combine.css",
          "sourceRoot": "../src",
          "sourcesContent": [
            ".css {\\n  color: red;\\n}\\n",
            "// This comment is just to change the line numbers\\n.scss {\\n  font-weight: bold;\\n}\\n\\n.also-scss {\\n  @extend .scss;\\n}\\n"
          ]
        }
      """


  it 'should create sourcemaps for YAML imports', build
    root: "#{fixtures}/build-sourcemap-yaml-combine"
    config:
      sourcemaps: true
    files: [
      'src/_1.js'
      'src/_23.js/2.js'
      'src/_23.js/3.js'
      'src/_4.js'
      'src/import.js.yaml'
    ]
    tests: ->
      expect("#{fixtures}/build-sourcemap-yaml-combine/build/import.js").to.have.content """
        console.log('File 1');

        // This is just to move it down a line
        console.log('File 2');

        // This is just to move it down 2 lines
        // This is just to move it down 2 lines
        console.log('File 3');

        // This is just to move it down 3 lines
        // This is just to move it down 3 lines
        // This is just to move it down 3 lines
        console.log('File 4');

        //# sourceMappingURL=import.js.map\n
      """
      expect("#{fixtures}/build-sourcemap-yaml-combine/build/import.js.map").to.have.content """
        {
          "version": 3,
          "sources": [
            "_1.js",
            "_23.js/2.js",
            "_23.js/3.js",
            "_4.js"
          ],
          "names": [],
          "mappings": "AAAA;AACA;ACDA;AACA;AACA;ACFA;AACA;AACA;AACA;ACHA;AACA;AACA;AACA;AACA",
          "file": "import.js",
          "sourceRoot": "../src",
          "sourcesContent": [
            "console.log('File 1');\\n",
            "// This is just to move it down a line\\nconsole.log('File 2');\\n",
            "// This is just to move it down 2 lines\\n// This is just to move it down 2 lines\\nconsole.log('File 3');\\n",
            "// This is just to move it down 3 lines\\n// This is just to move it down 3 lines\\n// This is just to move it down 3 lines\\nconsole.log('File 4');\\n"
          ]
        }
      """


  it 'should support sourcemaps for empty CSS files', build
    # This is because concat-with-sourcemaps crashes on empty CSS files -
    # probably an incompatibility with PostCSS since JS files are fine
    root: "#{fixtures}/build-sourcemap-combine-empty"
    config:
      sourcemaps: true
    files: [
      'src/dir.css/empty.css'
    ]
    tests: ->
      expect("#{fixtures}/build-sourcemap-combine-empty/build/dir.css").to.have.content """
        \n\n/*# sourceMappingURL=dir.css.map */\n
      """
      expect("#{fixtures}/build-sourcemap-combine-empty/build/dir.css.map").to.have.content """
        {
          "version": 3,
          "sources": [
            "dir.css/empty.css"
          ],
          "names": [],
          "mappings": "AAAA;AACA",
          "file": "dir.css",
          "sourceRoot": "../src",
          "sourcesContent": [
            ""
          ]
        }
      """


  it 'should support sourcemaps for empty Sass files', build
    root: "#{fixtures}/build-sourcemap-empty-sass"
    config:
      sourcemaps: true
    files: [
      'src/empty.scss'
    ]
    tests: ->
      expect("#{fixtures}/build-sourcemap-empty-sass/build/empty.css").to.have.content """
        \n\n/*# sourceMappingURL=empty.css.map */\n
      """
      # Note: Compass doesn't generate a sourcemap for an empty file, so the
      # sources list here is empty rather than showing an empty file
      expect("#{fixtures}/build-sourcemap-empty-sass/build/empty.css.map").to.have.content """
        {
          "version": 3,
          "sources": [],
          "names": [],
          "mappings": "",
          "file": "empty.css",
          "sourceRoot": "../src",
          "sourcesContent": []
        }
      """


  #----------------------------------------
  # Miscellaneous
  #----------------------------------------

  it 'should put cache files in .awe/ and create a .gitignore file', build
    root: "#{fixtures}/build-cache"
    files: [
      'src/styles.scss'
    ]
    tests: ->
      expect("#{fixtures}/build-cache/.awe/sass-cache").to.be.a.directory()
      expect("#{fixtures}/build-cache/.awe/.gitignore").to.be.a.file()


  it "should display an error and not create the build directory if the source directory doesn't exist", build
    root: "#{fixtures}/build-src-missing"
    files: [
      '.gitkeep'
    ]
    errors: 1
    tests: ->
      expect("#{fixtures}/build-src-missing/build").not.to.be.a.path()


  it 'should create _DO_NOT_EDIT.txt in the build directory', build
    root: "#{fixtures}/build-warning-file"
    config:
      warningfile: true
    files: [
      'src/_source'
    ]
    tests: ->
      expect("#{fixtures}/build-warning-file/build/_DO_NOT_EDIT.txt").to.have.content """
        *** WARNING ***

        DO NOT EDIT, CREATE OR DELETE ANY FILES IN THIS DIRECTORY

        All files in this directory were generated by Awe (http://awe.alberon.co.uk/)
        from the source files in:

            ../src

        Any changes to this directory will be lost when assets are re-built.

        To rebuild files run:

            awe build\n
      """
