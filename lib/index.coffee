path         = require 'path'
yaml         = require 'js-yaml'
marked       = require 'marked'
_            = require 'lodash'
w            = require 'when'
nodefn       = require 'when/node/function'
fs           = require 'fs'

module.exports = (options) ->
  options ||= {}
  folder = options.folder || "posts"

  class PostExtension
    constructor: (@roots) ->
      @category = "post"
      @posts = []

    frontmatter_regexp: /^---\n([^]*?)\n---\n([^]*)$/

    fs: ->
      extract: true
      ordered: true
      detect: (f) ->
        if "views/#{options.layout}.jade" == f.relative
          true
        else
          path.dirname(f.relative) == folder

    compile_hooks: ->
      extension = @

      before_pass: (ctx) ->
        f = ctx.file
        if f.file.relative == "views/#{options.layout}.jade"
          f.originalContent = f.content
          extension.layoutFile = f
        else
          locals = f.compile_options.posts ?= []
          locals.push(extension.read_file(f))
          locals.by_date = -> locals.filter (a,b) -> b.date - a.date
          locals.by_title = -> locals.filter (a,b) -> a.title.localeCompare(b.title)

      write: (ctx) ->
        false

    category_hooks: ->
      after: @after_category.bind(@)

    read_file: (f) ->
      match = f.content.match(@frontmatter_regexp);

      obj = if match then yaml.safeLoad(match[1]) else {}
      obj.body = if match then (match[2] || "").replace(/^\n+/, '') else content
      obj.body = marked(obj.body)

      name = path.basename(f.file_options.filename)
      parts = name.split("-")
      date = new Date("#{parts[0]}-#{parts[1]}-#{parts[2]}")
      obj.date = date
      obj.permalink = f.file_options._path

      obj.file_options = f.file_options
      f.file_options.post = obj

      @posts.push(obj)
      obj

    configure_options: (file, adapter) ->
      global_options  = @roots.config.locals ? {}
      adapter_options = @roots.config[adapter.name] ? {}
      file_options    = file.file_options
      compile_options = file.compile_options

      _.extend(global_options, adapter_options, file_options, compile_options)

    after_category: (ctx) ->
      adapter = @layoutFile.adapters[0]
      content = @layoutFile.originalContent
      opts = @configure_options(@layoutFile, adapter)

      results = []
      for post in @posts
        adapter.render(content, opts).then (result) ->
          output = path.join(ctx.roots.config.output_path(), post.file_options._path)
          results.push(nodefn.call(fs.writeFile, output, result.result))
      w.all(results)