# frozen_string_literal: true

RSpec.describe SiteSetting do
  describe "gtmc_rail_visible_servers" do
    it "shows three servers by default" do
      expect(SiteSetting.gtmc_rail_visible_servers).to eq(3)
    end

    it "is sent to the browser because the rail panel does the folding" do
      expect(SiteSetting.client_settings).to include(:gtmc_rail_visible_servers)
    end

    it "accepts the lowest and the highest allowed value" do
      SiteSetting.gtmc_rail_visible_servers = 1
      expect(SiteSetting.gtmc_rail_visible_servers).to eq(1)

      SiteSetting.gtmc_rail_visible_servers = 20
      expect(SiteSetting.gtmc_rail_visible_servers).to eq(20)
    end

    it "refuses zero, because the panel would then hide every server" do
      expect { SiteSetting.gtmc_rail_visible_servers = 0 }.to raise_error(
        Discourse::InvalidParameters,
      )
    end

    it "refuses a value above the upper bound" do
      expect { SiteSetting.gtmc_rail_visible_servers = 21 }.to raise_error(
        Discourse::InvalidParameters,
      )
    end
  end
end
