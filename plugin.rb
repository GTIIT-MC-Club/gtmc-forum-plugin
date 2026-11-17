# frozen_string_literal: true

# name: discourse-gtmc
# about: GTMC 论坛与 Minecraft 服务器的对接：服务器状态、账号绑定、进服验证
# version: 0.1.0
# authors: GTMC
# url: https://github.com/CHANGEME/gtmc-discourse/tree/main/plugins/discourse-gtmc

enabled_site_setting :gtmc_enabled

register_asset "stylesheets/gtmc-server-status.scss"

module ::DiscourseGtmc
  PLUGIN_NAME = "discourse-gtmc"
end

require_relative "lib/discourse_gtmc/engine"

after_initialize do
  # 在管理后台的 API Key 页面显示为 gtmc:server。发给 MC 插件的 Key 只勾这一个作用域，
  # Discourse 会拒绝它访问这里没列出的任何路由。第二期的 /gtmc/server/* 接口也加到这里。
  add_api_key_scope(:gtmc, { server: { actions: %w[discourse_gtmc/heartbeats#create] } })

  # 设置保存时记一次被忽略的项。不在每次读取时记：status.json 每个访客每 30 秒请求一次，会刷屏。
  on(:site_setting_changed) do |name, _old_value, _new_value|
    DiscourseGtmc::ServerRegistry.log_ignored_entries if name.to_sym == :gtmc_servers
  end
end
