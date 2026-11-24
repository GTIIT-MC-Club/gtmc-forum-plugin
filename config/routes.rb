# frozen_string_literal: true

# 接口说明见 README。
DiscourseGtmc::Engine.routes.draw do
  get "/status" => "status#show"
  get "/newcomer" => "newcomers#show"
  put "/servers/:server_id/heartbeat" => "heartbeats#update",
      :constraints => {
        server_id: /[a-z0-9-]{1,32}/,
      }
  get "/servers/:server_id/icon" => "icons#show",
      :constraints => {
        server_id: /[a-z0-9-]{1,32}/,
        format: "png",
      },
      :defaults => {
        format: "png",
      }
end

Discourse::Application.routes.draw { mount DiscourseGtmc::Engine, at: "/gtmc" }
