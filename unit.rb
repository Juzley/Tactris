require_relative 'util.rb'

class Unit
  attr_accessor :tile
  attr_reader :fire_pattern, :move_pattern
  attr_reader :place_ap, :move_ap

  def initialize(type, tile=nil)
    @type = type
    @tile = tile
    @place_ap = 0
    @move_ap = 0
    @state = :idle

    # TODO: Each unit will have separate media eventually
    @animation = Chingu::Animation.new(file: "droid_11x15.bmp")
    @animation.frame_names = { dead: 0..5, fire: 6..7, idle: 8..9  }
    @animation[:dead].loop = false
    @animation[:fire].loop = false
    @image = @animation[:idle].first
  end

  def draw(x, y, width, height)
    @image.draw_size(x, y, ZOrder::UNIT, width, height)
  end

  def friendly?
    @type == :friendly
  end

  def enemy?
    @type == :enemy
  end

  def self.ground_unit?
    true
  end

  def self.air_unit?
    return !self.ground_unit?
  end

  def ground_unit?
    return self.class.ground_unit?
  end

  def air_unit?
    return self.class.air_unit?
  end

  def hits_ground?
    true
  end

  def hits_air?
    false
  end

  def dead?
    @state == :dead
  end

  def update
    @image = @animation[@state].next

    # If this unit is dead, unlink it from the board once the
    # death animation is finished
    if @state == :dead && @animation[@state].last_frame?
      @tile.ground_unit = nil if self.ground_unit?
      @tile.air_unit = nil if self.air_unit?
    end
    @state = :idle if @state == :fire && @animation[@state].last_frame?
  end

  def viable_target(unit)
    if unit.nil? || unit.dead?
      false
    elsif unit.enemy? == self.enemy?
      false
    elsif unit.ground_unit? && !self.hits_ground?
      false
    elsif unit.air_unit? && !self.hits_air
      false
    else
      true
    end
  end

  def run
    orientation = if enemy? then :down else :up end
    @tile.walk_surrounding(fire_pattern, orientation) do |tile|
      tile.each_unit do |unit|
        if viable_target(unit)
          @state = :fire
          unit.damage()
          break 2
        end
      end
    end
  end

  def damage
    @state = :dead
  end

  def to_s
    if enemy? then 'Enemy ' else 'Friendly ' end + self.class.to_s
  end
end

class Infantry < Unit
  def initialize(type, tile=nil)
    super(tile, type)
    @fire_pattern = [[0, 1]]
    @move_pattern = [[0, 1,], [1, 0], [0, -1], [-1, 0]]
    @place_ap = 10
    @move_ap = 10
  end
end

class Tank < Unit
  def initialize(type, tile=nil)
    super(tile, type)
    @fire_pattern = [[-1, 1], [0, 1], [1, 1]]
    @move_pattern = [[0, 1], [0, 2]]
    @place_ap = 20
    @move_ap = 20
  end

  def draw(x, y, width, height)
    @image.draw_size(x, y, ZOrder::UNIT, width, height, color=0xffff0000)
  end
end

class Artillery < Unit
  def initialize(type, tile=nil)
    super(tile, type)
    @fire_pattern = [[0, 2], [0, 3]]
    @move_pattern = [[0, 1], [1, 0], [-1, 0]]
    @place_ap = 20
    @move_ap = 40
  end

  def draw(x, y, width, height)
    @image.draw_size(x, y, ZOrder::UNIT, width, height, color = 0xff00ff00)
  end
end

class Bomber < Unit
  def initialize(type, tile=nil)
    super(tile, type)
    @fire_pattern = [[0, 0]]
    @move_pattern = [[0, 1], [0, 2], [0, 3], [0, 4]]
  end

  def ground_unit?
    false
  end

  def draw(x, y, width, height)
    @image.draw_size(x, y, ZOrder::UNIT, width, height, color = 0xff0000ff)
  end
end
