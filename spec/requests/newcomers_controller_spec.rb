# frozen_string_literal: true

RSpec.describe DiscourseGtmc::NewcomersController do
  fab!(:user) { Fabricate(:user, email: "newbie@gtiit.edu.cn") }

  let(:skin_api_url) { "https://skin.gtmc.test/api/gtmc/players" }

  before do
    SiteSetting.gtmc_enabled = true
    SiteSetting.gtmc_skin_api_url = skin_api_url
    SiteSetting.gtmc_skin_api_key = "s3cret"
    Discourse.cache.clear
  end

  def stub_skin(players: [], status: 200)
    stub_request(:post, skin_api_url).with(
      body: { "email" => "newbie@gtiit.edu.cn" },
      headers: {
        "Authorization" => "Bearer s3cret",
      },
    ).to_return(status: status, body: { players: players }.to_json)
  end

  def progress
    get "/gtmc/newcomer.json"
    expect(response.status).to eq(200)
    response.parsed_body
  end

  it "returns nothing done to a guest without asking the skin site" do
    expect(progress).to eq(
      "registered" => false,
      "has_character" => false,
      "joined_server" => false,
    )
    expect(a_request(:post, skin_api_url)).not_to have_been_made
  end

  it "marks only registering done when the user has no character yet" do
    stub_skin(players: [])
    sign_in(user)

    expect(progress).to eq(
      "registered" => true,
      "has_character" => false,
      "joined_server" => false,
    )
  end

  it "marks the character done once the skin site lists one" do
    stub_skin(players: ["Newbie"])
    sign_in(user)

    expect(progress).to include("has_character" => true, "joined_server" => false)
  end

  it "marks joining done once one of the characters has been seen online" do
    stub_skin(players: %w[Alt Newbie])
    DiscourseGtmc::SeenPlayer.record(server_id: "survival", mc_names: ["Newbie"])
    sign_in(user)

    expect(progress).to include("has_character" => true, "joined_server" => true)
  end

  it "does not count a name seen with different case" do
    stub_skin(players: ["Newbie"])
    DiscourseGtmc::SeenPlayer.record(server_id: "survival", mc_names: ["newbie"])
    sign_in(user)

    expect(progress["joined_server"]).to eq(false)
  end

  it "remembers a finished user and stops asking the skin site" do
    stub_skin(players: ["Newbie"])
    DiscourseGtmc::SeenPlayer.record(server_id: "survival", mc_names: ["Newbie"])
    sign_in(user)
    progress
    Discourse.cache.clear
    WebMock.reset!

    expect(progress).to eq(
      "registered" => true,
      "has_character" => true,
      "joined_server" => true,
    )
    expect(user.reload.custom_fields["gtmc_newcomer_completed_at"]).to be_present
  end

  it "caches the skin site's answer briefly" do
    stub_skin(players: [])
    sign_in(user)
    progress
    progress

    # 过期由 Redis 按真实时间处理，freeze_time 管不到，这里只验证短时间内不重复问
    expect(a_request(:post, skin_api_url)).to have_been_made.once
  end

  it "leaves the last two steps undone and asks again next time when the skin site fails" do
    stub_skin(status: 500)
    sign_in(user)

    expect(progress).to eq(
      "registered" => true,
      "has_character" => false,
      "joined_server" => false,
    )
    progress
    expect(a_request(:post, skin_api_url)).to have_been_made.twice
  end

  it "ignores a malformed answer from the skin site" do
    stub_request(:post, skin_api_url).to_return(status: 200, body: { players: "Newbie" }.to_json)
    sign_in(user)

    expect(progress["has_character"]).to eq(false)
  end

  it "does not ask the skin site when no key is set" do
    SiteSetting.gtmc_skin_api_key = ""
    sign_in(user)

    expect(progress["has_character"]).to eq(false)
    expect(a_request(:post, skin_api_url)).not_to have_been_made
  end

  it "returns 404 when gtmc_enabled is off" do
    SiteSetting.gtmc_enabled = false

    get "/gtmc/newcomer.json"

    expect(response.status).to eq(404)
  end
end
