# frozen_string_literal: true

module DiscourseGtmc
  # 一个论坛用户在皮肤站的角色和皮肤，右栏「我的角色」面板用，GET /gtmc/characters.json 返回它。
  # 没设皮肤的角色不列。不借用 NewcomerProgress：三步都完成的人它不再问皮肤站，这里却正要显示给他们。
  class CharacterList
    # 换完皮肤回到论坛，要不了多久就能看到
    CACHE_SECONDS = 60
    # 每个角色要单独问一次皮肤站，右栏也放不下更多
    MAX_CHARACTERS = 5

    def self.for(user)
      return [] if user.nil? || SiteSetting.gtmc_skin_site_url.blank?

      cache_key = "gtmc_characters:#{user.id}"
      cached = Discourse.cache.read(cache_key)
      return cached if !cached.nil?

      names = SkinSite.player_names(user.email)
      return [] if names.nil?

      characters = []
      names
        .first(MAX_CHARACTERS)
        .each do |name|
          skin = SkinSite.skin(name)
          # 皮肤站连不上就不再问剩下的，免得一个请求等上好几次超时；也不缓存，下次再问
          return characters if skin.nil?
          next if skin.empty?
          characters << {
            name: name,
            slim: skin[:slim],
            skin_url: "/gtmc/skins/#{skin[:hash]}.png",
          }
        end

      Discourse.cache.write(cache_key, characters, expires_in: CACHE_SECONDS.seconds)
      characters
    end
  end
end
