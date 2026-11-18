# frozen_string_literal: true

# 接口契约见 gtmc-forum-infra 的 PLAN.md 4.1。
DiscourseGtmc::Engine.routes.draw do
  get "/status" => "status#show"
  get "/newcomer_guide" => "newcomer_guides#show"
  post "/server/heartbeat" => "heartbeats#create"
end

Discourse::Application.routes.draw { mount DiscourseGtmc::Engine, at: "/gtmc" }
