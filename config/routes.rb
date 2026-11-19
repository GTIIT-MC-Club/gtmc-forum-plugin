# frozen_string_literal: true

# 接口说明见 README。
DiscourseGtmc::Engine.routes.draw do
  get "/status" => "status#show"
  get "/newcomer_guide" => "newcomer_guides#show"
  put "/servers/:server_id/heartbeat" => "heartbeats#update", :constraints => { server_id: /[a-z0-9-]{1,32}/ }
end

Discourse::Application.routes.draw { mount DiscourseGtmc::Engine, at: "/gtmc" }
