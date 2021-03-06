# model of open-rest
_             = require 'underscore'
utils         = require './utils'
Sequelize     = require 'sequelize'
_pageParams   = require './page-params'

# 存放 models 的定义
Models = {}

###
# 根据model名称获取model
###
model = (name = null) ->
  return Models unless name
  Models[name]

# 获取统计的条目数
statsCount = (Model, opts, dims, callback) ->
  return callback(null, 1) unless dims
  return callback(null, 1) unless dims.length
  option = {where: opts.where}
  option.include = opts.include if opts.include
  option.raw = yes
  distincts = _.map(dims, (x) -> x.split(' AS ')[0])
  option.attributes = ["COUNT(DISTINCT #{distincts.join(', ')}) AS `count`"]
  Model.findOne(option).then((res) ->
    callback(null, res and res.count)
  ).catch(callback)

###
# model的统计功能
# params的结构如下
# {
#   dimensions: 'dim1,dim2',
#   metrics: 'met1,met2',
#   filters: 'dim1==a;dim2!=b',
#   sort: '-met1',
#   startIndex: 0,
#   maxResults: 20
# }
# conf 的结构如下，conf 是可选字段
# {
#   dimensions: {} // 这个的结构参考 Model 上 stats.dimensions 的结构
#   metrics: {} // 这个的结构参考 Model 上 stats.metrics 的结构
# }
###
model.statistics = statistics = (params, where, conf, callback) ->
  Model = @
  {dimensions, metrics, filters, sort, startIndex, maxResults} = params
  return callback(Error('Forbidden statistics')) unless Model.statistics
  try
    dims = utils.stats.dimensions(Model, params, conf and conf.dimensions)
    mets = utils.stats.metrics(Model, params, conf and conf.metrics)
    limit = utils.stats.pageParams(Model, params)
    listOpts = Model.findAllOpts(params)
    ands = [
      utils.stats.filters(Model, filters, conf and conf.dimensions)
    ]

    ands.push(listOpts.where) if listOpts.where
    if where
      if _.isString(where)
        ands.push([where, ['']])
      else
        ands.push(where)
    option =
      attributes: [].concat(dims or [], mets)
      where: Sequelize.and.apply(Sequelize, ands)
      group: utils.stats.group(dims)
      order: utils.stats.sort(Model, params)
      offset: limit.offset
      limit: limit.limit
      raw: yes
    if listOpts.include
      option.include = _.map(listOpts.include, (x) ->
        x.attributes = []
        x
      )
  catch e
    console.error(e, e.stack)
    return callback(e)
  statsCount(Model, option, dims, (error, count) ->
    return callback(error) if error
    Model.findAll(option).then((results) ->
      callback(null, [results, count])
    ).catch(callback)
  )

###
# 返回列表查询的条件
###
model.findAllOpts = findAllOpts = (params, isAll = no) ->
  where = {}
  Model = @
  includes = modelInclude(params, Model.includes)
  _.each(Model.filterAttrs or _.keys(Model.rawAttributes), (name) ->
    utils.findOptFilter(params, name, where)
  )
  if Model.rawAttributes.isDelete and not params.showDelete
    where.isDelete = 'no'

  # 处理模糊搜索参数为q
  # 目前第一期先实现一个简化版的
  # q 的玩法需要配合用户model上的定义，否则是关闭的
  # q 也会作用到 includes下
  q = do ->
    return unless params.q
    return unless _.isString params.q
    params.q.trim().split(' ')[0..3] or undefined

  # 将搜索条件添加到主条件上
  searchOrs = []
  searchOrs.push utils.searchOpt(Model, params._searchs, params.q)

  # 处理关联资源的过滤条件
  # 以及关联资源允许返回的字段
  if includes
    _.each(includes, (x) ->
      includeWhere = {}
      _.each(x.model.filterAttrs or _.keys(x.model.rawAttributes), (name) ->
        utils.findOptFilter(params[x.as], name, includeWhere, name)
      )
      if x.model.rawAttributes.isDelete and not params.showDelete
        includeWhere.$or = [isDelete: 'no']
        includeWhere.$or.push id: null if x.required is no

      # 将搜索条件添加到 include 的 where 条件上
      searchOrs.push utils.searchOpt(x.model, params._searchs, params.q, x.as)

      x.where = includeWhere if _.size(includeWhere)

      # 以及关联资源允许返回的字段
      x.attributes = x.model.allowIncludeCols if x.model.allowIncludeCols
    )

  # 将 searchOrs 赋到 where 上
  searchOrs = _.filter(_.compact(searchOrs), (x) -> x.length)
  where.$or = [[utils.mergeSearchOrs(searchOrs), ['']]] if searchOrs.length

  ret =
    include: includes
    order: sort(params, Model.sort)

  ret.where = where if _.size(where)

  # 处理需要返回的字段
  do ->
    return unless params.attrs
    return unless _.isString params.attrs
    attrs = []
    _.each(params.attrs.split(','), (x) ->
      return unless Model.rawAttributes[x]
      attrs.push x
    )
    return unless attrs.length
    ret.attributes = attrs

  _.extend ret, Model.pageParams(params) unless isAll

  ret

# 处理关联包含
# 返回
# [Model1, Model2]
# 或者 undefined
model.modelInclude = modelInclude = (params, includes) ->
  return unless includes
  return unless _.isString(params.includes)
  ret = _.filter(params.includes.split(','), (x) -> includes[x])
  return if ret.length is 0
  _.map(ret, (x) -> _.clone(includes[x]))

###
# 处理分页参数
# 返回 {
#   limit: xxx,
#   offset: xxx
# }
###
model.pageParams = pageParams = (params) ->
  _pageParams(@pagination, params)

###
# 处理排序参数
###
model.sort = sort = (params, conf) ->
  return null unless (params.sort or conf.default)
  order = conf.default
  direction = conf.defaultDirection or 'ASC'

  return [[order, direction]] unless params.sort

  if params.sort[0] is '-'
    direction = 'DESC'
    order = params.sort.substring(1)
  else
    direction = 'ASC'
    order = params.sort

  # 如果请求的排序方式不允许，则返回null
  return null if not conf.allow or order not in conf.allow

  [[order, direction]]

###
# 初始化 models
# params
#   sequelize Sequelize 的实例
#   path models的存放路径
###
model.init = (opt, path) ->

  # 初始化db
  opt.define = {} unless opt.define
  opt.define.classMethods = {findAllOpts, pageParams, statistics}
  sequelize = new Sequelize(opt.name, opt.user, opt.pass, opt)
  sequelize.query "SET time_zone='+0:00'"

  _.each(utils.getModules(path, ['coffee', 'js'], ['index', 'base']), (v, k) ->
    Models[k] = v(sequelize)
  )

  # model 之间关系的定义
  # 未来代码模块化更好，每个文件尽可能独立
  # 这里按照资源的紧密程度来分别设定资源的结合关系
  # 否则所有的结合关系都写在一起会很乱
  _.each(utils.getModules("#{path}/associations", ['coffee', 'js']), (v) ->
    v(Models)
  )

  # 处理 model 定义的 includes
  _.each(Models, (Model, name) ->
    return unless Model.includes
    if _.isArray Model.includes
      includes = {}
      _.each Model.includes, (include) -> includes[include] = include
      Model.includes = includes
    _.each(Model.includes, (v, k) ->
      [modelName, required] = _.isArray(v) and v or [v, yes]
      Model.includes[k] =
        model: Models[modelName]
        as: k
        required: required
    )
  )

  # 处理 model 定义的 searchCols
  _.each(Models, (Model, name) ->
    return unless Model.searchCols
    _.each(Model.searchCols, (v, k) ->
      v.match = [v.match] if _.isString(v.match)
    )
  )

  # 判断如果是 development 模式下 sync 表结构
  # 同时满足两个条件 development 模式, process.argv 包含 table-sync
  if (process.env.NODE_ENV is 'development') and ('table-sync' in process.argv)
    _.each(Models, (Model) ->
      Model
        .sync()
        .then(console.log.bind(console, "Synced"))
        .catch(console.error.bind(console))
    )

module.exports = model
