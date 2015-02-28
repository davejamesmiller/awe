<?php
namespace Alberon\Awe;

use Exception;

class AssetGroup
{
    // tmp.setGracefulCleanup()

    protected $app;
    protected $file;
    protected $output;

    protected $autoprefixer;
    protected $bower;
    protected $bowerLink;
    protected $bowerSrc;
    protected $bundlePath;
    protected $destPath;
    protected $prettyPrintSourcemaps;
    protected $rootPath;
    protected $sourcemaps;
    protected $srcPath;
    protected $warningFile;

    public function __construct($rootPath, $config, App $app, Filesystem $file, BuildOutput $output)
    {
        // Dependencies
        $this->app    = $app;
        $this->file   = $file;
        $this->output = $output;

        // Data
        $this->rootPath = rtrim($rootPath, '/\\');

        $this->autoprefixer          = $config['autoprefixer'];
        $this->bower                 = $config['bower'];
        $this->sourcemaps            = $config['sourcemaps'];
        $this->prettyPrintSourcemaps = isset($config['prettyPrintSourcemaps']) ? (bool) $config['prettyPrintSourcemaps'] : false;

        // Normalise paths
        $this->srcPath  = $this->rootPath . DIRECTORY_SEPARATOR . rtrim($config['src'], '/\\');
        $this->destPath = $this->rootPath . DIRECTORY_SEPARATOR . rtrim($config['dest'], '/\\');

        if ($config['warningfile'])
            $this->warningFile = $this->destPath . '/_DO_NOT_EDIT.txt';
        else
            $this->warningFile = false;

        // Generated paths
        if ($this->bower) {
            $this->bowerLink = $this->destPath . DIRECTORY_SEPARATOR . '_bower';
            $this->bowerSrc  = $this->rootPath . DIRECTORY_SEPARATOR . $this->bower;
        }

        // Script paths
        $this->bundlePath = dirname(__DIR__) . DIRECTORY_SEPARATOR . 'ruby_bundle';
    }

    public function build()
    {
        // Check if the source directory exists
        if (!$this->file->exists($this->srcPath)) {
            $path = $this->relDirPath($this->rootPath, $this->srcPath);
            $this->output->error($path, null, "Source directory doesn't exist");
            return;
        }

        // Create cache directory
        $this->cachePath = $this->rootPath . DIRECTORY_SEPARATOR . '.awe';
        $ignoreFile = $this->cachePath . DIRECTORY_SEPARATOR . '.gitignore';

        if (!$this->file->exists($this->cachePath))
            $this->file->makeDirectory($this->cachePath, 0777, true);

        $this->file->put($ignoreFile, "# Automatically generated by Awe - ignore all files\n*\n");

        // Need to know if the destination already exists for the output message
        $destExists = $this->file->exists($this->destPath);

        // Create/empty the destination
        $path = $this->relDirPath($this->rootPath, $this->destPath);
        if ($destExists) {
            $this->file->cleanDirectory($this->destPath);
            $this->output->emptied($path);
        } else {
            $this->file->makeDirectory($this->destPath, 0777, true);
            $this->output->created($path);
        }

        // Create a symlink to the bower_components directory
        if ($this->bower && !$this->file->exists($this->bowerSrc)) {
            // TODO: Display a warning
            // throw new Exception("Bower directory '{$this->bowerSrc}' doesn't exist");
            $this->bower     = false;
            $this->bowerLink = null;
            $this->bowerSrc  = null;
        }

        if ($this->bower)
            $this->createSymlink($this->bowerSrc, $this->bowerLink);

        // Create a file warning people not to edit the compiled files
        if ($this->warningFile) {
            $content = $this->renderTemplate('_DO_NOT_EDIT', [
                'source' => $this->relPath($this->destPath, $this->srcPath),
            ]);

            $this->write([
                'content' => $content,
                'count'   => 1,
                'action'  => 'generated',
                'dest'    => $this->warningFile,
            ]);
        }

        // Compile the directory
        $this->buildRegularDirectory($this->srcPath, $this->destPath);
    }

    protected function createSymlink($target, $link)
    {
        $target = $this->relPath(dirname($link), $target);
        symlink($target, $link);
    }

    protected function addSourceMapComment(&$data)
    {
        $file = strtolower($data['dest']);
        $map = basename($data['dest']) . '.map';

        if (ends_with($file, '.js'))
            $data['content'] .= "\n//# sourceMappingURL={$map}\n";
        elseif (ends_with($file, '.css'))
            $data['content'] .= "\n/*# sourceMappingURL={$map} */\n";
        else
            throw new Exception("Don't know how to add a source map comment to '{$data['dest']}'");
    }

    protected function removeSourceMapComment(&$data)
    {
        // This is for when an external library (PostCSS, Sass) adds a comment we
        // don't want (because we want to combine files and then add the comment at
        // the very end)
        $data['content'] = preg_replace('/[\r\n]*\/\*# sourceMappingURL=[^ ]+ \*\/[\r\n]*$/', "\n", $data['content']);
    }

    protected function parseSourceMap($sourcemap)
    {
        return json_decode($sourcemap, true);

        // if typeof sourcemap is 'string'
        //   sourcemap = JSON.parse(sourcemap)

        // # Ignore files with no mappings work around "Invalid mapping" and
        // # "Unsupported previous source map format" errors
        // if !sourcemap || !sourcemap.mappings
        //   return null

        // return sourcemap
    }

    protected function inlineSourceMapContent(&$data)
    {
        $data['sourcemap']['sourcesContent'] = array_map(function($file)
        {
            $content = $this->file->get($this->srcPath . DIRECTORY_SEPARATOR . $file);
            $content = str_replace("\r\n", "\n", $content); // Firefox doesn't like Windows line endings
            return $content;
        }, $data['sourcemap']['sources']);
    }

    protected function rewriteSourceMapFilenames(&$data)
    {
        foreach ($data['sourcemap']['sources'] as $i => $source)
        {
            $source = $this->resolvePath($this->srcPath, $source);

            // Compass sometimes adds its own internal files to the sourcemap which
            // results in ugly ../../../ paths - rewrite them to something readable.
            // Note: This has to be done *after* inlineSourceMapContent() is called.
            if (starts_with($source, $this->bundlePath))
                $data['sourcemap']['sources'][$i] = '_awe/ruby_bundle' . substr($source, strlen($this->bundlePath));
        }
    }

    protected function write($data)
    {
        if (!$data || $data['content'] === null)
            return;

        if ($this->sourcemaps && !empty($data['sourcemap'])) {
            $data['sourcemap']['sourceRoot'] = $this->relPath(dirname($data['dest']), $this->srcPath);
            $this->inlineSourceMapContent($data);
            $this->rewriteSourceMapFilenames($data);
            $this->addSourceMapComment($data);

            $pp = $this->prettyPrintSourcemaps ? JSON_PRETTY_PRINT : 0;
            $json = json_encode($data['sourcemap'], JSON_UNESCAPED_SLASHES | $pp);
            $this->file->put($data['dest'] . '.map', $json);
        }

        // await
        //   if @sourcemaps && data.sourcemap
        //     sourcemap = JSON.stringify(data.sourcemap, null, '  ')
        //     fs.writeFile("#{data.dest}.map", sourcemap, errTo(cb, defer()))

        $this->file->put($data['dest'], $data['content']);

        if ($action = $data['action']) {
            $path = $this->relPath($this->rootPath, $data['dest']);
            $notes = ($data['count'] > 1 ? "({$data['count']} files)" : '');
            $this->output->$action($path, $notes);
        }
    }

    protected function buildFileOrDirectory($src, $dest)
    {
        if ($this->file->isDirectory($src)) {
            $this->buildDirectory($src, $dest);
        } else {
            $data = $this->compileFile($src, $dest);
            $this->write($data);
        }
    }

    protected function buildDirectory($src, $dest)
    {
        $file = strtolower($src);

        if (ends_with($file, ['.css', '.js'])) {
            $data = $this->compileDirectory($src, $dest);
            $this->write($data);
        } else {
            $this->buildRegularDirectory($src, $dest);
        }
    }

    protected function readDirectory($dir)
    {
        $finder = $this->app->make('Symfony\Component\Finder\Finder');

        $files = [];
        foreach ($finder->in($dir)->depth(0) as $file) {
            $files[] = $file->getRelativePathname();
        }

        if ($files === false)
            return [];

        natcasesort($files);

        return $files;
    }

    protected function buildRegularDirectory($src, $dest)
    {
        // Create the destination directory
        if (!$this->file->exists($dest))
            $this->file->makeDirectory($dest, 0777, true);

        // Get a list of files in the source directory
        $files = $this->readDirectory($src);

        // Build each of the files/directories
        foreach ($files as $file) {
            if ($file[0] === '_')
                continue;

            $srcFile  = $src . DIRECTORY_SEPARATOR . $file;
            $destFile = $dest . DIRECTORY_SEPARATOR . $file;

            $this->buildFileOrDirectory($srcFile, $destFile);
        }
    }

    protected function getFile($src, $dest)
    {
        return [
            'content' => $this->file->get($src),
            'count'   => 1,
            'action'  => 'copied',
            'dest'    => $dest,
        ];
    }

    protected function compileCoffeeScript($src, $dest)
    {
        $script       = dirname(__DIR__) . '/node/compile-coffeescript.coffee';
        $relativeSrc  = $this->relPath($this->srcPath, $src);
        $destFilename = basename($dest);

        $exe  = dirname(__DIR__) . '/node_modules/.bin/coffee';
        $args = [$script, $relativeSrc, $destFilename];

        $compiler = $this->app->make('Alberon\Awe\ProcOpen3', [$exe, $args]);
        $compiler->redirectStandardInFromFile($src, 'r');
        $compiler->execute();

        $content   = stream_get_contents($compiler->getStandardOut());
        $error     = stream_get_contents($compiler->getStandardError());
        $sourcemap = stream_get_contents($compiler->getFD3());

        $compiler->close();

        if ($error) {
            $message = "<error>COFFEESCRIPT ERROR</error>\n{$error}";
            $path = $this->relPath($this->rootPath, $src);
            $this->output->error($path, null, $message);
            return;
        }

        return [
            'content'   => $content,
            'count'     => 1,
            'action'    => 'compiled',
            'sourcemap' => $this->parseSourceMap($sourcemap),
            'dest'      => $dest,
        ];
    }

    //   _getCss: (src, dest, cb) =>
    //     await @_getFile(src, dest, errTo(cb, defer data))
    //     @_rewriteCss(data, src, dest)
    //     cb(null, data)

    protected function compileSass($src, $dest)
    {
        // Create a temp directory for the output
        $tmpDir = $this->tempdir();

        // Create a config file for Compass
        // (Compass doesn't let us specify all options using the CLI, so we have to
        // generate a config file instead. We could use `sass --compass` instead for
        // some of them, but that doesn't support all the options either.)
        $configFile = $this->tempfile();
        $sourcemap = $this->sourcemaps ? 'true' : 'false';

        $compassConfig = "
            project_path = '{$this->rootPath}'
            cache_path   = '{$this->cachePath}/sass-cache'
            output_style = :expanded

            # Input files
            sass_path        =  '{$this->srcPath}'
            images_path      =  '{$this->srcPath}/img'
            fonts_path       =  '{$this->srcPath}/fonts'
            sprite_load_path << '{$this->srcPath}/_sprites'

            # Output to a temp directory so we can catch any generated files too
            css_path              = '{$tmpDir}'
            generated_images_path = '{$tmpDir}/_generated'
            javascripts_path      = '{$tmpDir}/_generated' # Rarely used but might as well

            # Output a placeholder for URLs - we will rewrite them into relative paths later
            # (Can't use 'relative_assets' because it generates paths like '../../../tmp/tmp-123/img')
            http_path                  = '/AWEDESTROOTPATH'
            http_stylesheets_path      = '/AWEDESTROOTPATH'
            http_images_path           = '/AWEDESTROOTPATH/img'
            http_fonts_path            = '/AWEDESTROOTPATH/fonts'
            http_generated_images_path = '/AWEDESTROOTPATH/_generated'
            http_javascripts_path      = '/AWEDESTROOTPATH/_generated'

            # Disable cache busting URLs (e.g. sample.gif?123456) - it makes unit
            # testing harder! One day I'll add cache busting URLs in a PostCSS filter
            asset_cache_buster :none

            # Disable line number comments - use sourcemaps instead
            line_comments = false
            sourcemap = {$sourcemap}
        ";

        $this->file->put($configFile, $compassConfig);

        // Compile the file using Compass
        $exe = dirname(__DIR__) . DIRECTORY_SEPARATOR . 'ruby_bundle' . DIRECTORY_SEPARATOR . 'bin' . DIRECTORY_SEPARATOR . 'compass';
        $args = ['compile', '--trace', '--config', $configFile, $src];

        $compiler = $this->app->make('fool\executor\ProcOpen', [$exe, $args]);
        $compiler->redirectStandardErrorToStandardOut();
        $compiler->execute();

        fclose($compiler->getStandardIn());

        $content = stream_get_contents($compiler->getStandardOut());
        $code = $compiler->close();

        if ($code > 0) {
            $error = preg_replace('/\n?\s*Use --trace for backtrace./', '', $content);
            $message = "<error>SASS/COMPASS ERROR</error> <grey>({$code})</grey>\n{$error}";
            $path = $this->relPath($this->rootPath, $src);
            $this->output->error($path, null, $message);
            return;
        }

        $compiler->close();

        // Copy any extra files that were generated
        $this->copyGeneratedDirectory(
            $tmpDir         . DIRECTORY_SEPARATOR . '_generated',
            $this->destPath . DIRECTORY_SEPARATOR . '_generated'
        );

        // Get the content from the CSS file
        $pathFromRoot = substr($src, strlen($this->srcPath) + 1);
        $outputFile = $tmpDir . DIRECTORY_SEPARATOR . substr($pathFromRoot, 0, -5) . '.css';
        $data = $this->getFile($outputFile, $dest);

        // Get the content from the source map
        if ($this->sourcemaps) {
            $data['sourcemap'] = $this->parseSourceMap(file_get_contents("$outputFile.map"));

            // Make the sources relative to the source directory - we'll change
            // them to be relative to the final destination file later
            foreach ($data['sourcemap']['sources'] as &$source) {
                $source = realpath(dirname($outputFile) . DIRECTORY_SEPARATOR . $source);
                $source = $this->relPath($this->srcPath, $source);
            }

            $this->removeSourceMapComment($data);
        }

        // Rewrite the URLs in the CSS
        // @_rewriteCss(data, src, dest)

        $data['action'] = 'compiled';

        return $data;
    }

    protected function copyGeneratedFileOrDirectory($src, $dest)
    {
        if (is_dir($src))
            $this->copyGeneratedDirectory($src, $dest);
        else
            $this->copyGeneratedFile($src, $dest);
    }

    protected function copyGeneratedFile($src, $dest)
    {
        $data = $this->getFile($src, $dest);
        $data['action'] = 'generated';
        $this->write($data);
    }

    protected function copyGeneratedDirectory($src, $dest)
    {
        if (!is_dir($src))
            return;

        // Get a list of files
        $files = $this->readDirectory($src);

        // Create destination directory
        mkdir($dest, 0777, true);

        // Copy the files
        foreach ($files as $file) {
            $this->copyGeneratedFileOrDirectory(
                $src  . DIRECTORY_SEPARATOR . $file,
                $dest . DIRECTORY_SEPARATOR . $file
            );
        }
    }

    protected function compileFile($src, $dest)
    {
        // Compile CoffeeScript
        if (strtolower(substr($src, -7)) === '.coffee') {
            $dest = substr($dest, 0, -7) . '.js';
            return $this->compileCoffeeScript($src, $dest);
        }

        // Compile Sass
        elseif (strtolower(substr($src, -5)) === '.scss') {
            $dest = substr($dest, 0, -5) . '.css';
            return $this->compileSass($src, $dest);
        }

        // # Import files listed in a YAML file
        // else if src[-9..].toLowerCase() == '.css.yaml' || src[-8..].toLowerCase() == '.js.yaml'
        //   @_compileYamlImports(src, dest.replace(/\.yaml$/i, ''), cb)

        // # Copy CSS and replace URLs
        // else if src[-4..].toLowerCase() == '.css'
        //   @_getCss(src, dest, cb)

        // Copy all other files unchanged
        return $this->getFile($src, $dest);
    }


    //   _rewriteCss: (data, srcFile, destFile) =>
    //     urlRewriter = new UrlRewriter
    //       root:      @rootPath
    //       srcDir:    @srcPath
    //       srcFile:   srcFile
    //       destDir:   @destPath
    //       destFile:  destFile
    //       bowerSrc:  @bowerSrc
    //       bowerDest: @bowerLink

    //     rewriteUrl = (url) =>
    //       if S(url).startsWith('/AWEDESTROOTPATH/')
    //         return path.join(path.relative(path.dirname(srcFile), @srcPath), url[17..])

    //       try
    //         urlRewriter.rewrite(url)
    //       catch e
    //         file = path.relative(@rootPath, srcFile)
    //         output.warning(file, '(URL rewriter)', e.message)
    //         return url

    //     # PostCSS expects input sourcemap paths to be relative to the new source file
    //     if data.sourcemap
    //       srcDir = path.dirname(srcFile)
    //       for source, k in data.sourcemap.sources
    //         data.sourcemap.sources[k] = path.relative(srcDir, path.resolve(@srcPath, source))

    //     try
    //       result = rewriteCss(
    //         data.content,
    //         path.relative(@srcPath, srcFile),
    //         destFile,
    //         sourcemap: @sourcemaps,
    //         prevSourcemap: data.sourcemap,
    //         autoprefixer: @autoprefixer,
    //         rewriteUrls: rewriteUrl
    //       )
    //     catch e
    //       throw e unless e.source # Looks like a CSS error
    //       file = path.relative(@rootPath, srcFile)
    //       message = "Invalid CSS:\n#{e.reason} on line #{e.line} column #{e.column}"
    //       output.warning(file, '(CSS)', message)
    //       return

    //     data.content = result.css

    //     if @sourcemaps
    //       data.sourcemap = result.map.toJSON()
    //       @_removeSourceMapComment(data)

    protected function compileMultipleFiles($files, $dest)
    {
        $content = '';
        $count   = 0;

        foreach ($files as $file) {
            $data = $this->compileFileOrDirectory($file, $dest);

            // Skip files with compile errors
            if (!$data)
                continue;

            // TODO: Any need for this?
            // $data['src'] = $file;

            // TODO: Skip files of a different type (and warn the user)
            // TODO: Concat with sourcemap

            $content .= $data['content'] . "\n";
            $count   += $data['count'];
        }

        // sourcemap = @_parseSourceMap(concat.sourceMap)

        // # Convert absolute paths to relative
        // if sourcemap
        //   for source, k in sourcemap.sources
        //     # It may already be relative (I'm not sure under what circumstances but
        //     # it happens in the unit tests), in which case we can either try to work
        //     # out whether it's absolute or not, or we can convert it to always be
        //     # absolute first - I've chosen the latter. Node.js 0.11 will add
        //     # path.isAbsolute() which will make the former easier in the future.
        //     source = path.resolve(@srcPath, source)
        //     # And now we can convert it from absolute to relative
        //     sourcemap.sources[k] = path.relative(@srcPath, source)

        return [
            'content'   => $content,
            'sourcemap' => null, // TODO
            'count'     => $count,
            'action'    => 'compiled',
            'dest'      => $dest,
        ];
    }

    public function compileFileOrDirectory($src, $dest)
    {
        if (is_dir($src))
            return $this->compileDirectory($src, $dest);
        else
            return $this->compileFile($src, $dest);
    }

    protected function compileDirectory($src, $dest)
    {
        $files = [];

        foreach ($this->readDirectory($src) as $file) {
            if ($file[0] !== '_')
                $files[] = $src . DIRECTORY_SEPARATOR . $file;
        }

        return $this->compileMultipleFiles($files, $dest);
    }


    //   _compileYamlImports: (yamlFile, dest, cb) =>
    //     await yamlMap(yamlFile, @bowerSrc, errTo(cb, defer files))

    //     await @_compileMultipleFiles(files, dest, defer(err, data))

    //     if !err
    //       cb(null, data)
    //     else if err.code == 'ENOENT'
    //       file = path.relative(@srcPath, yamlFile)
    //       output.error(file, '(YAML import map)', 'File not found: ' + err.path)
    //       cb()
    //     else
    //       cb(err)


    /**
     * Find the relative file system path between two file system paths
     *
     * Source: https://gist.github.com/ohaal/2936041
     *
     * @param  string  $frompath  Path to start from
     * @param  string  $topath    Path we want to end up in
     *
     * @return string             Path leading from $frompath to $topath
     */
    protected function relPath( $frompath, $topath ) {
        $from = explode( DIRECTORY_SEPARATOR, $frompath ); // Folders/File
        $to = explode( DIRECTORY_SEPARATOR, $topath ); // Folders/File
        $relpath = '';

        $i = 0;
        // Find how far the path is the same
        while ( isset($from[$i]) && isset($to[$i]) ) {
            if ( $from[$i] != $to[$i] ) break;
            $i++;
        }
        $j = count( $from ) - 1;
        // Add '..' until the path is the same
        while ( $i <= $j ) {
            if ( !empty($from[$j]) ) $relpath .= '..'.DIRECTORY_SEPARATOR;
            $j--;
        }
        // Go to folder from where it starts differing
        while ( isset($to[$i]) ) {
            if ( !empty($to[$i]) ) $relpath .= $to[$i].DIRECTORY_SEPARATOR;
            $i++;
        }

        // Strip last separator
        return substr($relpath, 0, -1);
    }

    protected function relDirPath($frompath, $topath)
    {
        return str_finish($this->relPath($frompath, $topath), DIRECTORY_SEPARATOR);
    }

    /**
     * Create a temporary directory
     *
     * Based on http://php.net/manual/en/function.tempnam.php#61436
     */
    protected function tempdir($mode=0700)
    {
        $dir = rtrim(sys_get_temp_dir(), '/\\');

        do
        {
            $path = $dir . DIRECTORY_SEPARATOR . 'awe-' . str_pad(mt_rand(0, 9999999999), 10, 0, STR_PAD_RIGHT);
        } while (!@mkdir($path, $mode));

        return $path;
    }

    protected function tempfile()
    {
        return tempnam(sys_get_temp_dir(), 'awe-');
    }

    /**
     * Normalize path
     *
     * http://stackoverflow.com/a/20545583/167815
     *
     * @param   string  $path
     * @param   string  $separator
     * @return  string  normalized path
     */
    protected function normalizePath($path, $separator = '\\/')
    {
        // Remove any kind of funky unicode whitespace
        $normalized = preg_replace('#\p{C}+|^\./#u', '', $path);

        // Path remove self referring paths ("/./").
        $normalized = preg_replace('#/\.(?=/)|^\./|\./$#', '', $normalized);

        // Regex for resolving relative paths
        $regex = '#\/*[^/\.]+/\.\.#Uu';

        while (preg_match($regex, $normalized)) {
            $normalized = preg_replace($regex, '', $normalized);
        }

        if (preg_match('#/\.{2}|\.{2}/#', $normalized)) {
            throw new LogicException('Path is outside of the defined root, path: [' . $path . '], resolved: [' . $normalized . ']');
        }

        return trim($normalized, $separator);
    }

    protected function resolvePath($dir, $file)
    {
        return $this->normalizePath($dir . DIRECTORY_SEPARATOR . $file);
    }

    protected function renderTemplate($__template, $__vars)
    {
        extract($__vars);
        ob_start();
        require dirname(__DIR__) . DIRECTORY_SEPARATOR . 'templates' . DIRECTORY_SEPARATOR . $__template . '.php';
        return ob_get_clean();
    }
}