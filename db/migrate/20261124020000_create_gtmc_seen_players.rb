# frozen_string_literal: true

# 每个在线名单里出现过的游戏名一行，记第一次出现的时间和服。
# 「新人进服」第三步（进一次服）按它判断，见 DiscourseGtmc::SeenPlayer。
class CreateGtmcSeenPlayers < ActiveRecord::Migration[8.0]
  def change
    create_table :gtmc_seen_players do |t|
      # 原样保存、区分大小写：服务器按名字算 UUID，大小写不同就是两个号
      t.string :mc_name, null: false, limit: 16
      t.datetime :first_seen_at, null: false
      t.string :first_server_id, null: false, limit: 32
    end
    add_index :gtmc_seen_players, :mc_name, unique: true
  end
end
