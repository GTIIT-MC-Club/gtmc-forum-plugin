# frozen_string_literal: true

RSpec.describe DiscourseGtmc::NewcomerGuidesController do
  fab!(:user)
  fab!(:guide_topic) do
    Fabricate(:topic, title: "新人指南：怎么进服、怎么升级、怎么发第一个帖子", pinned_at: Time.zone.now)
  end
  fab!(:first_post) { Fabricate(:post, topic: guide_topic) }

  before { SiteSetting.gtmc_enabled = true }

  def mark_read(user, topic, last_read_post_number:)
    TopicUser.create!(
      user: user,
      topic: topic,
      last_read_post_number: last_read_post_number,
      notification_level: TopicUser.notification_levels[:regular],
    )
  end

  it "returns the guide url and read false to an anonymous visitor" do
    get "/gtmc/newcomer_guide.json"

    expect(response.status).to eq(200)
    expect(response.parsed_body).to eq("topic_url" => guide_topic.relative_url, "read" => false)
  end

  it "returns read false to a logged-in user who has not opened the guide" do
    sign_in(user)

    get "/gtmc/newcomer_guide.json"

    expect(response.parsed_body).to eq("topic_url" => guide_topic.relative_url, "read" => false)
  end

  it "returns read true once the logged-in user has read the first post of the guide" do
    sign_in(user)
    mark_read(user, guide_topic, last_read_post_number: 1)

    get "/gtmc/newcomer_guide.json"

    expect(response.parsed_body["read"]).to eq(true)
  end

  it "does not count another user's reading" do
    mark_read(Fabricate(:user), guide_topic, last_read_post_number: 1)
    sign_in(user)

    get "/gtmc/newcomer_guide.json"

    expect(response.parsed_body["read"]).to eq(false)
  end

  it "returns a null url when there is no pinned topic titled as the newcomer guide" do
    guide_topic.update!(pinned_at: nil)

    get "/gtmc/newcomer_guide.json"

    expect(response.parsed_body).to eq("topic_url" => nil, "read" => false)
  end

  it "ignores a pinned topic whose title merely mentions the guide" do
    guide_topic.update!(title: "请先读完新人指南再发帖，谢谢大家的配合与理解")

    get "/gtmc/newcomer_guide.json"

    expect(response.parsed_body["topic_url"]).to be_nil
  end

  it "hides the guide from a user who cannot see its category" do
    secret_category = Fabricate(:private_category, group: Fabricate(:group))
    guide_topic.update!(category: secret_category)
    sign_in(user)
    mark_read(user, guide_topic, last_read_post_number: 1)

    get "/gtmc/newcomer_guide.json"

    expect(response.parsed_body).to eq("topic_url" => nil, "read" => false)
  end

  it "returns 404 when gtmc_enabled is off" do
    SiteSetting.gtmc_enabled = false

    get "/gtmc/newcomer_guide.json"

    expect(response.status).to eq(404)
  end
end
