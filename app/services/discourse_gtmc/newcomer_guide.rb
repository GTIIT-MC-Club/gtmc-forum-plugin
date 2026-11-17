# frozen_string_literal: true

module DiscourseGtmc
  # 置顶的「新人指南」帖，右栏「新人进服」面板的第二步用它判断读没读过。契约见 PLAN.md 4.1。
  class NewcomerGuide
    # 与 infra/discourse/sidebar.rb 的 NEWCOMER_GUIDE_TITLE_PREFIX 是同一个约定：
    # 新人指南是标题以此开头的置顶帖（来源 infra/content/newcomer-guide.md 的一级标题）。
    # 改标题时两处一起改。
    TITLE_PREFIX = "新人指南"

    # 找不到、或 user 看不见（版块有权限限制）时返回 nil。user 为 nil 表示游客。
    def self.topic_visible_to(user)
      topic =
        Topic
          .listable_topics
          .where.not(pinned_at: nil)
          .where("title LIKE ?", "#{Topic.sanitize_sql_like(TITLE_PREFIX)}%")
          .order(:id)
          .first
      topic if topic && Guardian.new(user).can_see?(topic)
    end

    # 读过的标准是读到了第一帖：TopicUser.last_read_post_number 记录的是用户读到的最后一帖的序号，
    # 大于 0 说明至少读过帖子开头。游客没有阅读记录，恒为假。
    def self.read_by?(user, topic)
      return false if user.nil? || topic.nil?
      TopicUser.exists?(user_id: user.id, topic_id: topic.id, last_read_post_number: 1..)
    end
  end
end
