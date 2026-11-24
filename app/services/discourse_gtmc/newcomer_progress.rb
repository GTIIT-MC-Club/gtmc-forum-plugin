# frozen_string_literal: true

module DiscourseGtmc
  # 右栏「新人进服」三步的完成情况，GET /gtmc/newcomer.json 返回它。
  #
  # - registered：登录了就算（论坛只能用 GTMC 账号登录）。
  # - has_character：皮肤站上邮箱相同的账号下至少有一个角色（SkinSite）。
  # - joined_server：这些角色名里有一个出现过在线名单里（SeenPlayer）。
  #
  # 三步都完成后在用户上记一笔（COMPLETED_FIELD），以后不再问皮肤站，面板也不再出现。
  # 皮肤站的结果只缓存一小会儿：新人建完角色回到论坛，第二步要很快变成已完成。
  # 问不到皮肤站时第二、三步按未完成算，不缓存，下次再问。
  class NewcomerProgress
    COMPLETED_FIELD = "gtmc_newcomer_completed_at"
    CACHE_SECONDS = 15

    GUEST = { registered: false, has_character: false, joined_server: false }.freeze
    COMPLETE = { registered: true, has_character: true, joined_server: true }.freeze

    def self.for(user)
      return GUEST if user.nil?
      return COMPLETE if user.custom_fields[COMPLETED_FIELD].present?

      mc_names = player_names(user) || []
      progress = {
        registered: true,
        has_character: mc_names.any?,
        joined_server: SeenPlayer.any_seen?(mc_names),
      }
      mark_completed(user) if progress == COMPLETE
      progress
    end

    def self.player_names(user)
      cache_key = "gtmc_newcomer_player_names:#{user.id}"
      cached = Discourse.cache.read(cache_key)
      return cached if !cached.nil?

      names = SkinSite.player_names(user.email)
      Discourse.cache.write(cache_key, names, expires_in: CACHE_SECONDS.seconds) if !names.nil?
      names
    end
    private_class_method :player_names

    def self.mark_completed(user)
      user.custom_fields[COMPLETED_FIELD] = Time.zone.now.iso8601
      user.save_custom_fields(true)
    end
    private_class_method :mark_completed
  end
end
