module Ownable
  def owned_by? entity
    return false unless entity
    owner == entity || owner&.owner == entity || owner == entity&.owner
  end

  def player
    owner.is_a?(Player) ? owner : owner&.player
  end
end
