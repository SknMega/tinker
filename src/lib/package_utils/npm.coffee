fs = require 'fs-extra'
path = require 'path'
Queue = require 'queue-async'
rpt = require 'read-package-tree'
gitURLNormalizer = require 'github-url-from-git'

spawn = require '../spawn'
Module = require '../../module'

module.exports = class Utils extends (require './index')
  @loadModules: (pkg, callback) ->
    Module.destroy {package_id: pkg.id}, (err) ->
      return callback(err) if err

      collectModules = (data, cwd) =>
        results = []
        if cwd # skip root
          results.push new Module({name: data.package.name, cwd: cwd, base: data.path, path: path.join(data.path, 'package.json')})
        else
          cwd = data.path
        results = results.concat(collectModules(child, cwd)) for child in (data.children or [])
        return results

      rpt Utils.root(pkg), (err, data) ->
        return callback(err) if err

        queue = new Queue()
        for module in collectModules(data)
          do (module) -> queue.defer (callback) ->
            # TODO: BackboneORM - why is two-step save needed
            module.save (err, module) -> module.save {package: pkg}, callback

        queue.await (err) -> callback(err, Array::splice.call(arguments, 1))

  @install: (pkg, callback) -> spawn 'npm install', Utils.cwd(pkg), callback
  @uninstall: (pkg, callback) -> fs.remove Utils.modulesDirectory(pkg), callback

  @modulesDirectory: (pkg) -> path.join(Utils.root(pkg), 'node_modules')
  @installModule: (pkg, module, callback) -> spawn "npm install #{module.get('name')}", Utils.cwd(module), callback
  @gitURL: (pkg, module, callback) ->
    package_json = pkg.packageJSON()
    module_name = module.get('name')

    # a git url - pass raw
    return callback(null, location) if (location = package_json.dependencies?[module_name]) and gitURLNormalizer(location)

    module_package_json = module.packageJSON()
    return callback(null, location) if (location = module_package_json._resolved) and gitURLNormalizer(location)
    return callback(null, location) if (location = module_package_json.repository?.url) and gitURLNormalizer(location)
    return callback(new Error "Module not found on npm: #{module_name}")
