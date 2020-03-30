class Queries::VisibleDiscussions < Delegator
  def initialize(user:, group_ids: [], tags: [])
    @user = user || LoggedOutUser.new
    @group_ids = group_ids || []

    @relation = Discussion.
                  joins(:group).
                  where('groups.archived_at IS NULL').
                  where('discarded_at IS NULL').
                  includes(:author, :polls, {group: [:parent]})

    if tags.any?
      @relation = @relation.where("(discussions.info->'tags')::jsonb ?& ARRAY[:tags]", tags: tags)
    end


    @relation = self.class.apply_privacy_sql(user: @user, group_ids: @group_ids, relation: @relation)
    super(@relation)
  end

  def __getobj__
    @relation
  end

  def __setobj__(obj)
    @relation = obj
  end

  def unread
    return self unless @user.is_logged_in?
    @relation = @relation.
                  where('(dv.dismissed_at IS NULL) OR (dv.dismissed_at < discussions.last_activity_at)').
                  where('dv.last_read_at IS NULL OR (dv.last_read_at < discussions.last_activity_at)')
    self
  end

  def muted
    return self unless @user.is_logged_in?
    @relation = @relation.where('(dv.volume = :mute) OR (dv.volume IS NULL AND m.volume = :mute) ',
                                {mute: DiscussionReader.volumes[:mute]})
    self
  end

  def not_muted
    return self unless @user.is_logged_in?
    @relation = @relation.where('(dv.volume > :mute) OR (dv.volume IS NULL AND m.volume > :mute)',
                                {mute: DiscussionReader.volumes[:mute]})
    self
  end

  def recent
    @relation = @relation.where('last_activity_at > ?', 6.weeks.ago)
    self
  end

  def is_open
    @relation = @relation.is_open
    self
  end

  def is_closed
    @relation = @relation.is_closed
    self
  end

  def sorted_by_latest_activity
    @relation = @relation.order(last_activity_at: :desc)
    self
  end

  def sorted_by_importance
    @relation = @relation.order(importance: :desc, last_activity_at: :desc)
    self
  end

  def self.apply_privacy_sql(user: nil, group_ids: [], relation: nil)
    user ||= LoggedOutUser.new

    relation = relation.where('discussions.group_id IN (:group_ids)', group_ids: group_ids) if group_ids.any?

    if user.is_logged_in?
      # select where
      # the discussion is public
      # or they are a member of the group
      # or they are a member of the guest group
      # or user belongs to parent group and permission is inherited
      relation = relation.joins("LEFT OUTER JOIN discussion_readers dv ON dv.discussion_id = discussions.id AND dv.user_id = #{user.id}")
      relation = relation.joins("LEFT OUTER JOIN memberships m ON m.user_id = #{user.id} AND m.group_id = discussions.group_id")
      relation.where('((discussions.private = false) OR (m.id IS NOT NULL) OR (dv.id IS NOT NULL and dv.revoked_at IS NULL AND dv.inviter_id IS NOT NULL) OR
                       (groups.parent_members_can_see_discussions = TRUE AND groups.parent_id IN (:user_group_ids)))',
                     user_group_ids: user.group_ids)
    else
      relation.where('groups.is_visible_to_public': true)
              .where('discussions.private': false)
    end
  end

end
