# frozen_string_literal: true

# 接口契约见仓库根目录 PLAN.md 第 4.1 节。
DiscourseGtmc::Engine.routes.draw do
  get "/status" => "status#show"
  post "/server/heartbeat" => "heartbeats#create"
end

Discourse::Application.routes.draw { mount DiscourseGtmc::Engine, at: "/gtmc" }
