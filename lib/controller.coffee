# 此模块提供默认控制器方法，共有五个
# list 获取某个资源的列表
# detail 获取某个资源详情
# modify 修改某个资源
# add 添加某个资源
# del 删除某个资源
# 此功能仅仅为了快速开发，没有任何的权限判断，生产环境慎用

_       = require 'underscore'
utils   = require './utils'
helper  = require './helper'
model   = require './model'

module.exports =

  # 获取资源列表的通用方法
  list: (ctl) ->
    Model = model(ctl)
    [
      helper.rest.list(Model)
    ]

  # 获取单个资源详情的方法
  detail: (ctl) ->
    Model = model(ctl)
    [
      helper.getter(Model, Model.name)
      helper.assert.exists(Model.name)
      helper.rest.detail(Model.name)
    ]

  # 修改某个资源描述的方法
  modify: (ctl) ->
    Model = model(ctl)
    [
      helper.getter(Model, Model.name)
      helper.assert.exists(Model.name)
      helper.rest.modify(Model, Model.name)
    ]

  # 根据资源描述添加资源到集合上的方法
  add: (ctl) ->
    Model = model(ctl)
    [
      helper.rest.add(Model)
    ]

  # 删除某个资源
  remove: (ctl) ->
    Model = model(ctl)
    [
      helper.getter(Model, Model.name)
      helper.assert.exists(Model.name)
      helper.rest.remove(Model.name)
    ]
