# frozen_string_literal: true

RSpec.describe "GTMC characters" do
  fab!(:user) { Fabricate(:user, email: "player@gtiit.edu.cn") }

  let(:api_url) { "https://skin.gtmc.test/api/gtmc/players" }
  let(:skin_hash) { "a" * 64 }
  let(:texture_url) { "https://skin.gtmc.test/textures/#{skin_hash}" }
  let(:png) { "\x89PNG\r\n\x1A\n".b + "pixels".b }

  before do
    SiteSetting.gtmc_enabled = true
    SiteSetting.gtmc_skin_api_url = api_url
    SiteSetting.gtmc_skin_api_key = "s3cret"
    SiteSetting.gtmc_skin_site_url = "https://skin.gtmc.test"
    Discourse.cache.clear
  end

  def stub_names(*names)
    stub_request(:post, api_url).to_return(body: { players: names }.to_json)
  end

  def stub_skin(name, skins, status: 200)
    stub_request(:get, "https://skin.gtmc.test/csl/#{ERB::Util.url_encode(name)}.json").to_return(
      status: status,
      body: { username: name, skins: skins }.to_json,
    )
  end

  def characters
    get "/gtmc/characters.json"
    expect(response.status).to eq(200)
    response.parsed_body["characters"]
  end

  it "lists nothing for a guest without asking the skin site" do
    expect(characters).to eq([])
  end

  it "lists characters with their model, also after the newcomer steps are done" do
    user.custom_fields[DiscourseGtmc::NewcomerProgress::COMPLETED_FIELD] = Time.zone.now.iso8601
    user.save_custom_fields(true)
    stub_names("Steve", "小明", "Bare", "Gone")
    stub_skin("Steve", { default: skin_hash })
    stub_skin("小明", { slim: skin_hash })
    stub_skin("Bare", [])
    stub_skin("Gone", {}, status: 404)
    sign_in(user)

    skin_url = "/gtmc/skins/#{skin_hash}.png"
    expect(characters).to eq(
      [
        { "name" => "Steve", "slim" => false, "skin_url" => skin_url },
        { "name" => "小明", "slim" => true, "skin_url" => skin_url },
      ],
    )
    characters
    expect(a_request(:post, api_url)).to have_been_made.once
  end

  it "stops at the first failure and does not cache it" do
    stub_names("Steve", "Alex")
    failing = stub_request(:get, "https://skin.gtmc.test/csl/Steve.json").to_timeout
    sign_in(user)

    expect(characters).to eq([])
    characters
    expect(failing).to have_been_requested.twice
  end

  it "lists nothing when the skin site URL is empty" do
    SiteSetting.gtmc_skin_site_url = ""
    sign_in(user)
    expect(characters).to eq([])
  end

  describe "skins" do
    it "serves the texture long-lived and fetches it once" do
      texture = stub_request(:get, texture_url).to_return(body: png)
      sign_in(user)

      2.times { get "/gtmc/skins/#{skin_hash}.png" }

      expect(response.status).to eq(200)
      expect(response.media_type).to eq("image/png")
      expect(response.body.b).to eq(png)
      expect(response.headers["Cache-Control"]).to include("immutable")
      expect(texture).to have_been_requested.once
    end

    it "returns 404 to guests, for bad hashes and for anything but a PNG" do
      get "/gtmc/skins/#{skin_hash}.png"
      expect(response.status).to eq(404)

      sign_in(user)
      get "/gtmc/skins/#{"z" * 64}.png"
      expect(response.status).to eq(404)

      stub_request(:get, texture_url).to_return(body: "<html>")
      get "/gtmc/skins/#{skin_hash}.png"
      expect(response.status).to eq(404)
    end
  end
end
