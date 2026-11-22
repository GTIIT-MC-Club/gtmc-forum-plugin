# frozen_string_literal: true

RSpec.describe DiscourseGtmc::IconsController do
  let(:png) { "\x89PNG\r\n\x1A\n".b + "pixels".b }

  before do
    SiteSetting.gtmc_enabled = true
    SiteSetting.gtmc_servers = [
      {
        server_id: "survival",
        name: "生存服",
        addresses: [{ address: "survival.gtmc.test" }],
        icon: "gtmc-bricks",
      },
    ].to_json
  end

  it "serves the cached icon as a long-lived PNG" do
    DiscourseGtmc::ServerFavicon.store("survival", png)

    get DiscourseGtmc::ServerFavicon.url("survival")

    expect(response.status).to eq(200)
    expect(response.media_type).to eq("image/png")
    expect(response.body.b).to eq(png)
    expect(response.headers["Cache-Control"]).to include("immutable")
    expect(response.headers["X-Content-Type-Options"]).to eq("nosniff")
  end

  it "returns 404 when no icon is cached" do
    get "/gtmc/servers/survival/icon.png"
    expect(response.status).to eq(404)
  end

  it "returns 404 when the server is not registered" do
    DiscourseGtmc::ServerFavicon.store("ghost", png)

    get "/gtmc/servers/ghost/icon.png"

    expect(response.status).to eq(404)
  end

  it "still serves the icon to anonymous visitors on a login-required site" do
    SiteSetting.login_required = true
    DiscourseGtmc::ServerFavicon.store("survival", png)

    get "/gtmc/servers/survival/icon.png"

    expect(response.status).to eq(200)
  end
end
