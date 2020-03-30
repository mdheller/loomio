class Queries::UsersByVolumeQuery
  def self.normal_or_loud(model)
    users_by_volume(model, '>=', DiscussionReader.volumes[:normal])
  end

  %w(mute quiet normal loud).map(&:to_sym).each do |volume|
    define_singleton_method volume, ->(model) {
      users_by_volume(model, '=', DiscussionReader.volumes[volume])
    }
  end

  private

  def self.users_by_volume(model, operator, volume)
    return User.none if model.nil?
    User.active.distinct.
      joins("LEFT OUTER JOIN discussion_readers dv ON dv.discussion_id = #{model.discussion_id || 0} AND dv.user_id = users.id").
      joins("LEFT OUTER JOIN memberships m ON m.user_id = users.id AND m.group_id = #{model.group_id || 0}").
      joins("LEFT OUTER JOIN stances s ON s.participant_id = users.id AND s.poll_id = #{model.poll_id || 0}")
      where('(m.id IS NOT NULL) OR
             (dv.id IS NOT NULL and dv.revoked_at IS NULL AND dv.inviter_id IS NOT NULL) OR
             (s.id IS NOT NULL and s.recoved_at IS NULL AND s.inviter_id IS NOT NULL)').
      where("coalesce(s.volume, dr.volume, m.volume, 2) #{operator} :volume", volume: volume)
  end
end
