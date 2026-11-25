# frozen_string_literal: true

module DiscourseGtmc
  # 右栏「我的角色」面板用的数据，见 CharacterList。
  class CharactersController < ::ApplicationController
    requires_plugin PLUGIN_NAME

    def show
      render json: { characters: CharacterList.for(current_user) }
    end
  end
end
