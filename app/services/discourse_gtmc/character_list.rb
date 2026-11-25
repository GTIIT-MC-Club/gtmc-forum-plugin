# frozen_string_literal: true

module DiscourseGtmc
  # 一个论坛用户在皮肤站的角色和皮肤，右栏「我的角色」面板用，GET /gtmc/characters.json 返回它。
  # 没设皮肤的角色不列。不借用 NewcomerProgress：三步都完成的人它不再问皮肤站，这里却正要显示给他们。
  class CharacterList
    # 换完皮肤回到论坛，要不了多久就能看到
    CACHE_SECONDS = 60
    # 没问全时只缓存一小会儿，很快再试
    FAILURE_CACHE_SECONDS = 15
    # 每个角色要单独问一次皮肤站，右栏也放不下更多
    MAX_CHARACTERS = 5
    # 皮肤站慢但没超时的时候，问到这么久就不再问剩下的角色
    TIME_BUDGET_SECONDS = 3
    MAX_FETCHES_PER_MINUTE = 10

    def self.for(user)
      return [] if user.nil? || SiteSetting.gtmc_skin_site_url.blank?

      cache_key = "gtmc_characters:#{user.id}"
      cached = Discourse.cache.read(cache_key)
      return cached if !cached.nil?
      # 缓存之外再限一道：同时开很多标签页时缓存还没写入
      return [] if !fetch_allowed?(user)

      characters, is_complete = fetch(user)
      ttl = is_complete ? CACHE_SECONDS : FAILURE_CACHE_SECONDS
      Discourse.cache.write(cache_key, characters, expires_in: ttl.seconds)
      characters
    end

    # 返回 [角色, 是否问全了]
    def self.fetch(user)
      deadline = now + TIME_BUDGET_SECONDS
      names = SkinSite.player_names(user.email)
      return [], false if names.nil?

      characters = []
      names
        .first(MAX_CHARACTERS)
        .each do |name|
          return characters, false if now > deadline
          skin = SkinSite.skin(name)
          return characters, false if skin.nil?
          next if skin.empty?
          characters << {
            name: name,
            slim: skin[:slim],
            skin_url: "/gtmc/skins/#{skin[:hash]}.png",
          }
        end
      [characters, true]
    end
    private_class_method :fetch

    def self.fetch_allowed?(user)
      RateLimiter.new(user, "gtmc_characters", MAX_FETCHES_PER_MINUTE, 1.minute).performed!(
        raise_error: false,
      )
    end
    private_class_method :fetch_allowed?

    def self.now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
    private_class_method :now
  end
end
