# frozen_string_literal: true

RSpec.describe "gtmc_wiki_links" do
  it "has a JSON string default the core can parse" do
    links = JSON.parse(SiteSetting.defaults[:gtmc_wiki_links])
    expect(links).to all(include("label", "url"))
    expect { SvgSprite.settings_icons }.not_to raise_error
  end
end
