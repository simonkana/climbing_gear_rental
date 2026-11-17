# Public, unguessable identifier used in URLs instead of the numeric primary key.
# UUIDv7 is time-ordered, so inserts stay append-only in the unique index.
module HasPublicId
  extend ActiveSupport::Concern

  included do
    attr_readonly :public_id
    before_validation :assign_public_id, on: :create
  end

  def to_param
    public_id
  end

  private
    def assign_public_id
      self.public_id ||= SecureRandom.uuid_v7
    end
end
